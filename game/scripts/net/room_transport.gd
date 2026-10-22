extends Node
# Room transport: a WebSocket to the room's Durable Object when the engine has
# the module and the network keeps the socket alive; HTTP polling otherwise.
# It only moves messages and keeps the server clock. What the messages mean is
# decided by room.gd through the `room` callbacks:
#   room._on_reply(kind, data)       a successful response or a socket reply/push
#   room._on_failure(kind, code, message, data)
#   room._on_rate_limited(retry_seconds)
#   room._on_left()
const WorldValidation = preload("res://scripts/net/world_validation.gd")
const NetProtocol = preload("res://scripts/net/net_protocol.gd")
# WebSocket ready states, kept numeric so the script parses without the module.
const SOCKET_OPEN = 1
const SOCKET_CLOSED = 3
const SOCKET_CONNECT_TIMEOUT = 6.0
const SOCKET_RETRY = 5.0
const SOCKET_MAX_FAILURES = 3
# Leave time for an 8s HTTP request and capped backoff before membership's 90s TTL.
const RECOVERY_SECONDS = 45.0
# Host syncs in a row the server may refuse before the room is given up.
const MAX_REFUSED_SYNCS = 3
const SOCKET_REPLY_TIMEOUT = 8.0

var room
var http: HTTPRequest
var beacon: HTTPRequest
var server = "http://127.0.0.1:8787"
var busy = false
var request_kind = ""
var request_sent_at = 0.0
var errors = 0
var refused_syncs = 0
var recovery_started_at = -INF
var suspended_at = -INF
var socket_waiting_since = -INF
# Server clock (NTP-style: offset estimated from the fastest round trips).
var server_offset = 0.0
# The server clock as this frame shows it (advance_view_clock).
var view_clock = -INF
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
# Exported native builds (macOS, Android) talk to the production Worker; running
# from the editor still uses the localhost Worker. --room-server overrides both.
const PRODUCTION_SERVER = "https://rally-fans-simulator.di-719.workers.dev"

static func default_server(is_web: bool, is_export: bool = false) -> String:
	if is_web:
		return ""
	return PRODUCTION_SERVER if is_export else "http://127.0.0.1:8787"

func _ready() -> void:
	server = default_server(OS.has_feature("web"), OS.has_feature("template"))
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

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and suspended_at == -INF:
		suspended_at = now()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and suspended_at != -INF:
		if recovery_started_at != -INF:
			recovery_started_at += now() - maxf(suspended_at, recovery_started_at)
		if socket_waiting_since != -INF:
			socket_waiting_since += now() - maxf(suspended_at, socket_waiting_since)
		suspended_at = -INF
	# A phone stops the engine in the background, so a native host reports it
	# before sleeping and the server keeps the room (web: room-session.js).
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_RESUMED:
		report_background(what == NOTIFICATION_APPLICATION_PAUSED)

# Sent on its own threaded request: the engine may stop polling right after.
func report_background(background: bool) -> void:
	if OS.has_feature("web") or room == null or not room.connected or not room.is_host:
		return
	if beacon == null:
		beacon = HTTPRequest.new()
		beacon.use_threads = true
		beacon.timeout = 8
		add_child(beacon)
	beacon.cancel_request()
	beacon.request(endpoint("heartbeat", room.room_id), ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify({"token": room.token, "background": background}))

func endpoint(kind: String, room_id: String) -> String:
	return server + ("/api/rooms" if kind == "create" else "/api/rooms/%s/%s" % [room_id, kind])

func request(kind: String, room_id: String, body: Dictionary) -> void:
	request_kind = kind
	request_sent_at = now()
	busy = true
	var err = http.request(endpoint(kind, room_id), ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		handle_http(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())

# Giving up on a room (recovery_delay() < 0): a last leave, in case the server can be reached again,
# so the others do not see this member for the rest of its membership TTL.
# It goes on its own request and its answer is ignored: the room screen
# already says the room is closed.
func abandon(room_id: String, token: String) -> void:
	var leave = HTTPRequest.new()
	leave.timeout = 8
	add_child(leave)
	leave.request_completed.connect(func(_result, _code, _headers, _body): leave.queue_free())
	if leave.request(endpoint("leave", room_id), ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify({"token": token})) != OK:
		leave.queue_free()

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
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not data is Dictionary or (request_kind == "sync" and not valid_sync_reply(data)):
		var message = str(data.get("error", "Нет связи с сервером комнаты.")) if data is Dictionary else "Нет связи с сервером комнаты."
		room._on_failure(request_kind, code, message, data)
		return
	if data.get("world") != null and not WorldValidation.valid(data.world):
		room._on_failure(request_kind, 400, "Некорректный снимок мира.", data)
		return
	reset_recovery()
	if data.has("server_time"):
		update_server_clock(float(data.server_time))
	room._on_reply(request_kind, data)

# HTTP and socket failures share one bounded episode, without changing identity
# or discarding commands and driving inputs waiting for server acknowledgement.
func recovery_delay() -> float:
	var active_now = now() if suspended_at == -INF else suspended_at
	if recovery_started_at == -INF:
		recovery_started_at = active_now
	errors += 1
	if active_now - recovery_started_at >= RECOVERY_SECONDS:
		abandon(room.room_id, room.token)
		return -1.0
	return minf(5.0, pow(2.0, mini(errors - 1, 3)))

func reset_recovery() -> void:
	errors = 0
	recovery_started_at = -INF
	refused_syncs = 0

# The host's sync refused as too large or malformed (413, 400) is one bad
# snapshot, not a closed room: the cold sections are offered again from
# scratch. Only a run of refusals with no good reply in between is terminal.
func tolerate_refused_sync(code: int) -> bool:
	if not room.is_host or code not in [400, 413] or refused_syncs >= MAX_REFUSED_SYNCS:
		return false
	refused_syncs += 1
	room.world_sync.reset()
	return true

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

# Everything drawn from snapshots, and the host's world stamp, read one clock
# per frame. It advances with the frame and only slews toward the server clock:
# reading the wall clock mid-frame, or a 10 ms clock correction, would
# otherwise jerk every remote car by its speed times that error.
func advance_view_clock(delta: float) -> void:
	view_clock = next_view_clock(view_clock, server_clock(), delta)

static func next_view_clock(view: float, target: float, delta: float) -> float:
	if view == -INF or absf(target - view) > 0.25:
		return target
	# Averaged over frames and at most 2 % faster or slower than real time:
	# the wall clock read mid-frame wobbles by the frame's own work.
	return view + delta + clampf((target - view) * 0.05, -delta * 0.02, delta * 0.02)

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
	socket_waiting_since = -INF

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
	advance_view_clock(delta)
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
	if socket_open and suspended_at == -INF and socket_waiting_since != -INF and now() - socket_waiting_since >= SOCKET_REPLY_TIMEOUT:
		_socket_failed()
		room._on_failure("sync", 0, "Нет связи с сервером комнаты.", null)

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
	if socket_waiting_since == -INF:
		socket_waiting_since = now()
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

# Connection setup for a direct link, relayed by the room server to one member.
func send_signal(to: String, data: Dictionary) -> bool:
	if not socket_open or socket == null:
		return false
	return socket.send_text(JSON.stringify({"type": "signal", "to": to, "data": data})) == OK

static func _finite_number(value) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and absf(float(value)) <= 9007199254740991.0

func valid_sync_reply(data: Dictionary) -> bool:
	for key in ["server_time", "world_time"]:
		if data.has(key) and not _finite_number(data[key]): return false
	if not data.get("players") is Array or data.players.size() > NetProtocol.max_players(): return false
	for player in data.players:
		if not player is Dictionary or not player.get("id") is String: return false
	if data.get("world") != null and not data.world is Dictionary: return false
	if room.is_host:
		return data.get("commands") is Array
	var accepted = data.get("accepted")
	return (accepted is int or accepted is float) and is_finite(float(accepted)) and accepted >= 0 and float(accepted) == floorf(float(accepted))

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
			var raw_id = data.get("id")
			if not valid_sync_reply(data) or not _finite_number(raw_id) or raw_id < 0 or float(raw_id) != floorf(float(raw_id)): return
			if data.get("world") != null and not WorldValidation.valid(data.world):
				room._on_failure("sync", 400, "Некорректный снимок мира.", data)
				return
			reset_recovery()
			var id = int(raw_id)
			if message_times.has(id):
				socket_waiting_since = -INF
				if data.has("server_time"):
					update_server_clock(float(data.server_time), message_times[id])
				message_times.erase(id)
			room._on_reply("sync", data)
		"push":
			if not valid_sync_reply(data): return
			if data.get("world") != null and not WorldValidation.valid(data.world):
				room._on_failure("sync", 400, "Некорректный снимок мира.", data)
				return
			reset_recovery()
			room._on_reply("sync", data)
		"signal":
			if data.get("data") is Dictionary:
				if data.data.get("space", "") == "voice": room.voice.on_signal(str(data.get("from", "")), data.data)
				else: room.direct.on_signal(str(data.get("from", "")), data.data)
		"error":
			var status = int(data.get("status", 500))
			var message = str(data.get("error", "Нет связи с сервером комнаты."))
			if status == 429:
				room._on_rate_limited(clampf(float(data.get("retry_after", 10)), 1.0, 60.0))
			else:
				if status >= 500:
					_socket_failed()
				room._on_failure("sync", status, message, data)
