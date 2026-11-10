class_name P2PRooms
extends Node
## Rooms with direct WebRTC links between players, on the Rally Fans
## Simulator room server (Cloudflare Worker + Durable Objects).
##
## The server keeps who is in a room and relays the WebRTC setup (offer,
## answer, ICE candidates) over the room WebSocket. Everything the game sends
## goes over WebRTC data channels between the host and each guest (a star:
## guests talk to the host, the host talks to everyone).
##
## Each link has two negotiated data channels:
##   reliable: ordered, retransmitted (chat, commands, events)
##   fast:     unordered, no retransmits (positions, inputs; the next packet
##             supersedes a lost one)
##
## Web builds use the browser's WebRTC. Desktop and mobile builds need the
## official webrtc-native GDExtension (see README).

## Emitted once the room socket is up after create_room() or join_room().
signal room_joined(room_id: String, player_id: String, is_host: bool)
## create_room() or join_room() failed. status is the HTTP status (0: no reply).
signal room_failed(error: String, status: int)
## The room is gone for this player: the host left, the player was dropped,
## or the server could not be reached for too long. Not emitted by leave_room().
signal room_closed(reason: String)
## The member list changed. Each entry: {id, name, slot, host}.
signal members_changed(members: Array)
## The WebRTC link to a member opened (a guest only ever links to the host).
signal peer_connected(peer_id: String)
## The WebRTC link to a member closed or failed.
signal peer_disconnected(peer_id: String)
## A packet from a member. data is the Variant the sender passed to send().
signal message_received(peer_id: String, data: Variant, reliable: bool)

const DEFAULT_SERVER = "https://rally-fans-simulator.di-719.workers.dev"
## Minimal player state the room server requires in every membership sync.
const MEMBERSHIP_STATE = {"pos": [0, 0, 0], "car": [0, 0, 0], "heading": 0, "yaw": 0, "pitch": 0, "in_car": false}
# WebSocketPeer / WebRTC enums kept numeric so the script parses without the module.
const SOCKET_OPEN = 1
const SOCKET_CLOSED = 3
const PEER_FAILED = 4
const PEER_CLOSED = 5
const CHANNEL_OPEN = 1
const CHANNEL_CLOSED = 3
const RELIABLE_ID = 1
const FAST_ID = 2

## Room server origin, without a trailing slash.
@export var server_url := DEFAULT_SERVER
## Your game's protocol number. Players only join rooms created with the same
## number, so pick one far from the rally game's (which uses small numbers)
## and bump it when your packets change incompatibly.
@export var app_protocol := 1_000_001
## STUN (and TURN) servers for WebRTC.
@export var ice_servers: Array = ["stun:stun.cloudflare.com:3478", "stun:stun.l.google.com:19302"]
## How often this player tells the server it is still in the room. The server
## drops a member after 90 s of silence; a host's silence closes the room.
@export var membership_interval := 1.0
## Seconds a link may take to open before it is retried.
@export var connect_timeout := 8.0
## Attempts in a row before the guest waits retry_delay * 5 between attempts.
@export var max_attempts := 3
@export var retry_delay := 2.0
## Seconds the room socket may stay down (network switch) before room_closed.
@export var reconnect_window := 45.0
## Largest packet send() accepts, in bytes.
@export var max_packet := 16000

## Optional: returns a WebRTCPeerConnection-like object. Tests and custom
## native backends replace it; by default the engine class is used.
var connection_factory: Callable

var room_id := ""
var player_id := ""
var host_id := ""
var is_host := false
var joined := false
## id -> {id, name, slot, host}
var members: Dictionary = {}
## Server clock in seconds, estimated from sync replies.
var server_time_offset := 0.0

var _token := ""
var _socket_url := ""
var _socket: WebSocketPeer
var _socket_was_open := false
var _socket_lost_at := -INF
var _socket_retry_at := 0.0
var _hello_sent := false
var _message_id := 0
var _sync_sent_at := {}
var _sync_clock := 0.0
var _http: HTTPRequest
var _pending := false
# peer id -> {"pc", "reliable", "fast", "session", "open", "started", "attempts", "retry_at", "initiator"}
var _links: Dictionary = {}
var _session_counter := 0


func _ready() -> void:
	_ensure_http()


func _ensure_http() -> void:
	if _http != null:
		return
	_http = HTTPRequest.new()
	_http.timeout = 10
	add_child(_http)
	_http.request_completed.connect(_on_http)


static func now() -> float:
	return Time.get_ticks_usec() / 1000000.0


## True when this build can open WebRTC links (browser, or webrtc-native installed).
func webrtc_available() -> bool:
	if connection_factory.is_valid():
		return true
	if not ClassDB.class_exists("WebRTCPeerConnection"):
		return false
	var pc = ClassDB.instantiate("WebRTCPeerConnection")
	var ok = pc != null and pc.initialize({}) == OK
	if pc != null:
		pc.close()
	return ok


# ------------------------------------------------------------------ room API

## Creates a room; this player becomes its host. Emits room_joined or room_failed.
func create_room(player_name: String) -> void:
	_enter("", "/api/rooms", {"name": player_name, "protocol": app_protocol})


## Joins a room by its 6-character ID. Emits room_joined or room_failed.
func join_room(id: String, player_name: String) -> void:
	var room := id.strip_edges().to_upper()
	_enter(room, "/api/rooms/%s/join" % room.uri_encode(), {"name": player_name, "protocol": app_protocol})


## Leaves the room. A host leaving closes it for everyone.
func leave_room() -> void:
	if _token != "" and room_id != "":
		# Fire and forget: the server forgets a silent member anyway.
		var beacon = HTTPRequest.new()
		add_child(beacon)
		beacon.request_completed.connect(func(_r, _c, _h, _b): beacon.queue_free())
		beacon.request(server_url + "/api/rooms/%s/leave" % room_id, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify({"token": _token}))
	_reset()


## Sends a Variant (no Objects) to one member. Guests can only reach the host.
## Returns false when the link is not open or the packet is too big.
func send(peer_id: String, data: Variant, reliable := true) -> bool:
	return _send_packet(peer_id, 0, var_to_bytes(data), reliable)


## Sends raw bytes; the receiver gets them as a PackedByteArray in message_received.
func send_bytes(peer_id: String, bytes: PackedByteArray, reliable := true) -> bool:
	return _send_packet(peer_id, 1, bytes, reliable)


func _send_packet(peer_id: String, kind: int, bytes: PackedByteArray, reliable: bool) -> bool:
	var link: Dictionary = _links.get(peer_id, {})
	if link.is_empty() or not link.open or bytes.size() + 1 > max_packet:
		return false
	var packet := PackedByteArray([kind])
	packet.append_array(bytes)
	var channel = link.reliable if reliable else link.fast
	return channel.put_packet(packet) == OK


## Sends to every open link: the host reaches all guests, a guest the host.
func broadcast(data: Variant, reliable := true) -> void:
	for id in connected_peers():
		send(id, data, reliable)


## A guest's shortcut for send(host_id, ...).
func send_to_host(data: Variant, reliable := true) -> bool:
	return send(host_id, data, reliable)


## Members with an open link.
func connected_peers() -> Array:
	var result: Array = []
	for id in _links:
		if _links[id].open:
			result.append(id)
	return result


func is_peer_connected(peer_id: String) -> bool:
	return _links.has(peer_id) and _links[peer_id].open


## The server's clock in seconds (Unix time), for shared timers.
func server_time() -> float:
	return Time.get_unix_time_from_system() + server_time_offset


# ------------------------------------------------------------------ HTTP

# room: the room to join, "" to create one.
func _enter(room: String, path: String, body: Dictionary) -> void:
	if _pending or _token != "":
		room_failed.emit("Already in a room or joining one.", 0)
		return
	if not webrtc_available():
		room_failed.emit("WebRTC is not available: install the webrtc-native GDExtension.", 0)
		return
	_pending = true
	room_id = room
	_ensure_http()
	var error = _http.request(server_url + path, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	if error != OK:
		_pending = false
		room_id = ""
		room_failed.emit("Request failed (%d)." % error, 0)


func _on_http(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_pending = false
	var data = JSON.parse_string(body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS else null
	if code != 200 or not data is Dictionary or not data.get("token") is String:
		room_id = ""
		var message = data.get("error", "") if data is Dictionary else ""
		room_failed.emit(str(message) if message != "" else "Room server unreachable.", code)
		return
	room_id = str(data.get("room", room_id))
	player_id = str(data.player)
	_token = str(data.token)
	is_host = data.get("host") == true
	host_id = player_id if is_host else ""
	_socket_url = str(data.socket)
	_open_socket()


# ------------------------------------------------------------------ room socket

func _open_socket() -> void:
	_socket = WebSocketPeer.new()
	_socket.inbound_buffer_size = 1 << 20
	_socket.outbound_buffer_size = 1 << 20
	_hello_sent = false
	_socket_was_open = false
	if _socket.connect_to_url(_socket_url) != OK:
		_socket_lost()


func _socket_send(message: Dictionary) -> bool:
	if _socket == null or _socket.get_ready_state() != SOCKET_OPEN:
		return false
	return _socket.send_text(JSON.stringify(message)) == OK


func _socket_lost() -> void:
	_socket = null
	if _token == "":
		return
	if _socket_lost_at == -INF:
		_socket_lost_at = now()
	if now() - _socket_lost_at > reconnect_window:
		_close("Lost connection to the room server.")
	else:
		_socket_retry_at = now() + 2.0


func _poll_socket(delta: float) -> void:
	if _socket == null:
		if _token != "" and now() >= _socket_retry_at:
			_open_socket()
		return
	_socket.poll()
	var state = _socket.get_ready_state()
	if state == SOCKET_OPEN:
		if not _hello_sent:
			_hello_sent = true
			_message_id += 1
			_socket_send({"type": "hello", "id": _message_id, "token": _token})
		while _socket != null and _socket.get_available_packet_count() > 0:
			var message = JSON.parse_string(_socket.get_packet().get_string_from_utf8())
			if message is Dictionary:
				_on_socket_message(message)
		if _socket_was_open:
			_sync_clock += delta
			if _sync_clock >= membership_interval:
				_send_sync()
	elif state == SOCKET_CLOSED:
		var code = _socket.get_close_code()
		_socket = null
		if code in [4401, 4404, 4410]:
			_close("The room is closed.")
		else:
			_socket_lost()


func _send_sync() -> void:
	_sync_clock = 0.0
	_message_id += 1
	if _socket_send({"type": "sync", "id": _message_id, "state": MEMBERSHIP_STATE}):
		_sync_sent_at[_message_id] = now()


func _on_socket_message(message: Dictionary) -> void:
	match str(message.get("type", "")):
		"hello":
			_socket_was_open = true
			_socket_lost_at = -INF
			_send_sync()
			if not joined:
				joined = true
				room_joined.emit(room_id, player_id, is_host)
		"reply", "push":
			_clock(message)
			_apply_view(message)
		"signal":
			_on_signal(str(message.get("from", "")), message.get("data"))
		"signal_error":
			push_warning("P2PRooms: signal refused: " + str(message.get("error", "")))
		"error":
			var status = int(message.get("status", 0))
			if status in [401, 404, 410]:
				_close(str(message.get("error", "The room is closed.")))
			elif status == 429:
				_sync_clock = -float(message.get("retry_after", 5))
			else:
				push_warning("P2PRooms: " + str(message.get("error", "")))


func _clock(message: Dictionary) -> void:
	var sent = _sync_sent_at.get(message.get("id"), -1.0)
	_sync_sent_at.erase(message.get("id"))
	var server_ms = message.get("server_time")
	if (server_ms is float or server_ms is int) and sent >= 0.0:
		var half_trip = (now() - sent) / 2.0
		server_time_offset = float(server_ms) / 1000.0 + half_trip - Time.get_unix_time_from_system()


func _apply_view(view: Dictionary) -> void:
	if not view.get("players") is Array:
		return
	var host = str(view.get("host", host_id))
	var next := {}
	for entry in view.players:
		if entry is Dictionary and entry.get("id") is String:
			next[entry.id] = {"id": entry.id, "name": str(entry.get("name", "")), "slot": int(entry.get("slot", 0)), "host": entry.id == host}
	var changed = host != host_id or next.keys() != members.keys()
	if not changed:
		for id in next:
			if next[id].name != members[id].name:
				changed = true
	host_id = host
	members = next
	for id in _links.keys():
		if not members.has(id):
			_close_link(id, true)
	if changed:
		var list = members.values()
		list.sort_custom(func(a, b): return a.slot < b.slot)
		members_changed.emit(list)
	# A guest calls the host; the host answers whoever calls.
	if not is_host and host_id != "" and members.has(host_id):
		var link: Dictionary = _links.get(host_id, {})
		if link.is_empty() or (link.pc == null and now() >= float(link.retry_at)):
			_offer(host_id, int(link.get("attempts", 0)))


# ------------------------------------------------------------------ WebRTC links

func _new_peer():
	if connection_factory.is_valid():
		return connection_factory.call()
	return ClassDB.instantiate("WebRTCPeerConnection")


func _new_link(id: String, session: int, initiator: bool, attempts: int) -> Dictionary:
	var pc = _new_peer()
	if pc == null:
		return {}
	var servers: Array = []
	for url in ice_servers:
		servers.append({"urls": [str(url)]})
	if pc.initialize({"iceServers": servers}) != OK:
		return {}
	# Both sides create the same negotiated channels: no in-band setup.
	var reliable = pc.create_data_channel("reliable", {"negotiated": true, "id": RELIABLE_ID, "ordered": true})
	var fast = pc.create_data_channel("fast", {"negotiated": true, "id": FAST_ID, "ordered": false, "maxRetransmits": 0})
	if reliable == null or fast == null:
		pc.close()
		return {}
	reliable.write_mode = WebRTCDataChannel.WRITE_MODE_BINARY
	fast.write_mode = WebRTCDataChannel.WRITE_MODE_BINARY
	var link = {"pc": pc, "reliable": reliable, "fast": fast, "session": session, "open": false, "started": now(), "attempts": attempts, "retry_at": INF, "initiator": initiator}
	pc.session_description_created.connect(func(type: String, sdp: String) -> void:
		if _links.get(id, {}).get("pc") != pc:
			return
		pc.set_local_description(type, sdp)
		_signal(id, {"kind": type, "sdp": sdp, "session": session}))
	pc.ice_candidate_created.connect(func(media: String, index: int, candidate: String) -> void:
		if _links.get(id, {}).get("pc") != pc:
			return
		_signal(id, {"kind": "candidate", "media": media, "index": index, "name": candidate, "session": session}))
	_links[id] = link
	return link


func _signal(to: String, data: Dictionary) -> void:
	_socket_send({"type": "signal", "to": to, "data": data})


func _offer(id: String, attempts: int) -> void:
	_session_counter += 1
	var session = int(Time.get_ticks_msec()) * 16 + _session_counter % 16
	_close_link(id, false)
	var link = _new_link(id, session, true, attempts + 1)
	if link.is_empty():
		push_error("P2PRooms: could not create a WebRTC connection.")
		return
	link.pc.create_offer()


func _on_signal(from: String, data) -> void:
	if not data is Dictionary:
		return
	var session = int(data.get("session", 0))
	var kind = str(data.get("kind", ""))
	if kind == "offer":
		if not is_host:
			return
		_close_link(from, false)
		var created = _new_link(from, session, false, 0)
		if not created.is_empty():
			created.pc.set_remote_description("offer", str(data.get("sdp", "")))
		return
	var link: Dictionary = _links.get(from, {})
	if link.is_empty() or link.pc == null or int(link.session) != session:
		return
	if kind == "answer" and link.initiator:
		link.pc.set_remote_description("answer", str(data.get("sdp", "")))
	elif kind == "candidate":
		link.pc.add_ice_candidate(str(data.get("media", "")), int(data.get("index", 0)), str(data.get("name", "")))


func _poll_links() -> void:
	var t = now()
	for id in _links.keys():
		var link: Dictionary = _links.get(id, {})
		if link.is_empty() or link.pc == null:
			continue
		link.pc.poll()
		var opened = link.reliable.get_ready_state() == CHANNEL_OPEN and link.fast.get_ready_state() == CHANNEL_OPEN
		if opened and not link.open:
			link.open = true
			link.attempts = 0
			peer_connected.emit(id)
		for pair in [[link.reliable, true], [link.fast, false]]:
			var channel = pair[0]
			while _links.get(id) == link and channel.get_available_packet_count() > 0:
				_receive(id, channel.get_packet(), pair[1])
		if _links.get(id) != link:
			continue
		var state = int(link.pc.get_connection_state())
		var failed = state in [PEER_FAILED, PEER_CLOSED] or link.reliable.get_ready_state() == CHANNEL_CLOSED
		if failed or (not link.open and t - float(link.started) > connect_timeout):
			_link_failed(id, link)


func _receive(from: String, packet: PackedByteArray, reliable: bool) -> void:
	if packet.is_empty():
		return
	var body = packet.slice(1)
	if packet[0] == 1:
		message_received.emit(from, body, reliable)
		return
	var value = bytes_to_var(body)
	message_received.emit(from, value, reliable)


func _link_failed(id: String, link: Dictionary) -> void:
	var attempts = int(link.attempts)
	var initiator = bool(link.initiator)
	_close_link(id, true)
	if initiator and members.has(id):
		# A placeholder makes the guest call again after a pause.
		var wait = retry_delay * (5.0 if attempts >= max_attempts else 1.0)
		_links[id] = {"pc": null, "reliable": null, "fast": null, "session": 0, "open": false, "started": now(), "attempts": attempts, "retry_at": now() + wait, "initiator": true}


func _close_link(id: String, notify: bool) -> void:
	var link: Dictionary = _links.get(id, {})
	if link.is_empty():
		return
	_links.erase(id)
	for key in ["reliable", "fast"]:
		if link[key] != null:
			link[key].close()
	if link.pc != null:
		link.pc.close()
	if link.open and notify:
		peer_disconnected.emit(id)


# ------------------------------------------------------------------ lifecycle

func _process(delta: float) -> void:
	if _token == "":
		return
	_poll_socket(delta)
	_poll_links()
	# A guest whose host link waits for a retry calls again.
	if not is_host and _links.has(host_id) and _links[host_id].pc == null and now() >= float(_links[host_id].retry_at):
		_offer(host_id, int(_links[host_id].attempts))


func _close(reason: String) -> void:
	var was = _token != ""
	_reset()
	if was:
		room_closed.emit(reason)


func _reset() -> void:
	for id in _links.keys():
		_close_link(id, true)
	_links.clear()
	if _socket != null:
		_socket.close(1000, "leave")
	_socket = null
	_token = ""
	room_id = ""
	player_id = ""
	host_id = ""
	is_host = false
	joined = false
	members.clear()
	_sync_sent_at.clear()
	_socket_lost_at = -INF


func _exit_tree() -> void:
	# The server drops a silent member after 90 s; call leave_room() to go at once.
	_reset()
