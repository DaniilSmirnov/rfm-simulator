extends Node
# Room transport: a WebSocket to the room's Durable Object when the engine has
# the module and the network keeps the socket alive; HTTP polling otherwise.
# It only moves messages and keeps the server clock. What the messages mean is
# decided by room.gd through the `room` callbacks:
#   room._on_reply(kind, data)       a successful response or a socket reply/push
#   room._on_failure(kind, code, message, data)
#   room._on_rate_limited(retry_seconds)
#   room._on_left()
const NetProtocol = preload("res://scripts/net_protocol.gd")
# WebSocket ready states, kept numeric so the script parses without the module.
const SOCKET_OPEN = 1
const SOCKET_CLOSED = 3
const SOCKET_CONNECT_TIMEOUT = 6.0
const SOCKET_RETRY = 5.0
const SOCKET_MAX_FAILURES = 3

var room
var http: HTTPRequest
var server = "http://127.0.0.1:8787"
var busy = false
var request_kind = ""
var request_sent_at = 0.0
var errors = 0
# Server clock (NTP-style: offset estimated from the fastest round trips).
var server_offset = 0.0
var clock_initialized = false
var best_round_trip = INF
var round_trip_ms = 0.0
var network_jitter_ms = 0.0
var previous_round_trip = -1.0
# WebSocket state.
var socket = null
var socket_url = ""
var socket_enabled = true
var socket_open = false
var socket_hello = false
var socket_retry = 0.0
var socket_failures = 0
var socket_started_at = 0.0
var socket_opened_at = 0.0
var message_id = 0
var message_times: Dictionary = {}

# In browser builds the Worker serves /api/rooms on the same origin as /vk/.
# Never attempt to connect to the user's 127.0.0.1 or downgrade HTTPS to HTTP.
# Native development still uses the localhost Worker unless overridden.
static func default_server(is_web: bool) -> String:
	return "" if is_web else "http://127.0.0.1:8787"

func _ready() -> void:
	server = default_server(OS.has_feature("web"))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--room-server="):
			server = arg.trim_prefix("--room-server=").trim_suffix("/")
		if arg == "--room-transport=http":
			socket_enabled = false
	http = HTTPRequest.new()
	http.timeout = 8
	# Browser fetch already decompresses response bodies.
	http.accept_gzip = not OS.has_feature("web")
	http.body_size_limit = NetProtocol.max_message_bytes() * 2
	add_child(http)
	http.request_completed.connect(handle_http)

func endpoint(kind: String, room_id: String) -> String:
	return server + ("/api/rooms" if kind == "create" else "/api/rooms/%s/%s" % [room_id, kind])

func request(kind: String, room_id: String, body: Dictionary) -> void:
	request_kind = kind
	request_sent_at = now()
	busy = true
	var err = http.request(endpoint(kind, room_id), ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		handle_http(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())

func cancel() -> void:
	if busy:
		http.cancel_request()
		busy = false

static func now() -> float:
	return Time.get_ticks_usec() / 1000000.0

func handle_http(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
	busy = false
	var parser = JSON.new()
	var data = parser.data if parser.parse(bytes.get_string_from_utf8()) == OK else null
	if request_kind == "leave":
		room._on_left()
		return
	if result == HTTPRequest.RESULT_SUCCESS and code == 429 and room.connected:
		room._on_rate_limited(clampf(float(data.get("retry_after", 10)) if data is Dictionary else 10.0, 1.0, 60.0))
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not data is Dictionary:
		var message = str(data.get("error", "Нет связи с сервером комнаты.")) if data is Dictionary else "Нет связи с сервером комнаты."
		room._on_failure(request_kind, code, message, data)
		return
	errors = 0
	if data.has("server_time"):
		update_server_clock(float(data.server_time))
	room._on_reply(request_kind, data)

# ---------------------------------------------------------------- clock

func update_server_clock(server_msec: float, sent_at: float = -1.0) -> void:
	var t = now()
	var round_trip = clampf(t - (request_sent_at if sent_at < 0 else sent_at), 0, 2.0)
	round_trip_ms = round_trip * 1000.0
	if previous_round_trip >= 0:
		network_jitter_ms = lerpf(network_jitter_ms, absf(round_trip - previous_round_trip) * 1000.0, 0.2)
	previous_round_trip = round_trip
	var estimate = server_msec / 1000.0 - t + round_trip * 0.5
	best_round_trip = minf(best_round_trip, round_trip)
	if not clock_initialized:
		server_offset = estimate
		clock_initialized = true
	elif round_trip <= best_round_trip + 0.05:
		# A slow first response must not leave the room clock permanently behind.
		# Slow outliers cannot move a clock calibrated by faster round trips.
		if absf(estimate - server_offset) > 0.2:
			server_offset = estimate
		else:
			server_offset += clampf((estimate - server_offset) * 0.1, -0.01, 0.01)

func server_clock() -> float:
	return now() + server_offset

# ---------------------------------------------------------------- socket

# The socket carries the same sync bodies and replies as HTTP. The server also
# pushes fresh snapshots as soon as the host or a guest reports, so a guest's
# input reaches the host without waiting for the host's next poll.
func open_socket(url: String) -> void:
	socket_url = url
	socket_failures = 0
	close_socket()
	_open_socket()

func _open_socket() -> void:
	if not socket_enabled or not room.connected or socket_url == "" or not ClassDB.class_exists("WebSocketPeer"):
		return
	socket = ClassDB.instantiate("WebSocketPeer")
	socket.inbound_buffer_size = NetProtocol.max_message_bytes() * 4
	socket.outbound_buffer_size = NetProtocol.max_message_bytes() * 4
	socket_open = false
	socket_hello = false
	socket_started_at = now()
	if socket.connect_to_url(socket_url) != OK:
		_socket_failed()

func close_socket() -> void:
	if socket != null:
		socket.close()
	socket = null
	socket_open = false
	socket_hello = false
	message_times.clear()

func _socket_failed() -> void:
	var was_open = socket_open
	var lived = now() - (socket_opened_at if was_open else socket_started_at)
	close_socket()
	if not room.connected:
		return
	# A socket that dies right after opening (filtered networks often cut long
	# connections) counts as a failure; a long healthy session resets the count.
	socket_failures = 1 if was_open and lived > 60.0 else socket_failures + 1
	if socket_failures >= SOCKET_MAX_FAILURES:
		socket_enabled = false
		print("ROOM_SOCKET disabled, using HTTP")
	else:
		socket_retry = SOCKET_RETRY * socket_failures
		print("ROOM_SOCKET closed, HTTP until retry in %.0fs" % socket_retry)
	# Continue on HTTP right away.
	room.sync_now()

func poll(delta: float) -> void:
	if socket == null:
		if socket_retry > 0 and room.connected:
			socket_retry -= delta
			if socket_retry <= 0:
				_open_socket()
		return
	socket.poll()
	var state = socket.get_ready_state()
	if state == SOCKET_CLOSED:
		_socket_failed()
		return
	if state != SOCKET_OPEN:
		if now() - socket_started_at > SOCKET_CONNECT_TIMEOUT:
			_socket_failed()
		return
	if not socket_hello:
		socket_hello = true
		socket.send_text(JSON.stringify({"type": "hello", "id": 0, "token": room.token, "protocol": NetProtocol.version(), "cold_revs": room.world_sync.cold_revs}))
	while socket != null and socket.get_available_packet_count() > 0:
		_socket_message(socket.get_packet().get_string_from_utf8())

# Sends a sync body over the open socket or, without one, as an HTTP request.
# Returns false when nothing could be sent now (a request is still in flight).
func send_sync(body: Dictionary, room_id: String) -> bool:
	if socket_open:
		_send_socket(body)
		return true
	if busy:
		return false
	request("sync", room_id, body)
	return true

func ready_to_sync() -> bool:
	return socket_open or not busy

func transport_name() -> String:
	return "ws" if socket_open else "http"

func _send_socket(body: Dictionary) -> void:
	# Back off instead of queueing when the browser cannot drain the socket.
	if socket.get_current_outbound_buffered_amount() > NetProtocol.max_message_bytes():
		return
	message_id += 1
	body.erase("token")
	body.type = "sync"
	body.id = message_id
	message_times[message_id] = now()
	for id in message_times.keys():
		if id < message_id - 32:
			message_times.erase(id)
	if socket.send_text(JSON.stringify(body)) != OK:
		_socket_failed()

func _socket_message(text: String) -> void:
	var data = JSON.parse_string(text)
	if not data is Dictionary or not room.connected:
		return
	match str(data.get("type", "")):
		"hello":
			socket_open = true
			socket_opened_at = now()
			print("ROOM_SOCKET open")
		"reply":
			errors = 0
			var id = int(data.get("id", -1))
			if message_times.has(id) and data.has("server_time"):
				update_server_clock(float(data.server_time), message_times[id])
				message_times.erase(id)
			room._on_reply("sync", data)
		"push":
			room._on_reply("sync", data)
		"error":
			var status = int(data.get("status", 500))
			var message = str(data.get("error", "Нет связи с сервером комнаты."))
			if status == 429:
				room._on_rate_limited(clampf(float(data.get("retry_after", 10)), 1.0, 60.0))
			elif status in [401, 404, 410]:
				room._on_failure("sync", status, message, data)
