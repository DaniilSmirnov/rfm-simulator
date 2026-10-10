extends Node
# Direct links: one WebRTC data channel between the host and each guest.
#
# The room server stays the source of truth for membership, commands and slow
# world sections, and it relays the connection setup (offer, answer, ICE
# candidates) over the room socket. Once a link is open, the latency-critical
# traffic goes straight between the two browsers on an unordered channel
# without retransmits: a lost packet is simply superseded by the next one.
#   guest -> host  the guest's state with its unacknowledged driving input
#   host -> guest  the hot world, authoritative cars and everyone's state
# A link that does not open, or goes quiet, falls back to the server path.
#
# Only browser builds have a WebRTC implementation; native builds keep using
# the server. Tests replace `connection_factory` with an in-process pair.
const NetProtocol = preload("res://scripts/net_protocol.gd")
# Numeric engine enums, so the script parses without the WebRTC module.
const PEER_CONNECTED = 2
const PEER_FAILED = 4
const PEER_CLOSED = 5
const CHANNEL_OPEN = 1
const CHANNEL_CLOSED = 3
const CHANNEL_BINARY = 1

var room
# Creates a peer connection; the default uses the engine's WebRTC class.
var connection_factory: Callable
# Delivers setup messages to another member; the default uses the room socket.
var signal_sender: Callable
var enabled = false
# Peer id -> link: {"pc", "channel", "session", "started", "open",
#                   "last_received", "attempts", "retry_at", "initiator"}
var links: Dictionary = {}
var session_counter = 0
# Send timers: guest state upstream, host world downstream.
var state_clock = 0.0
var world_clock = 0.0

func setup(owner_room) -> void:
	room = owner_room
	if not connection_factory.is_valid():
		connection_factory = _engine_connection
	if not signal_sender.is_valid():
		signal_sender = func(to: String, data: Dictionary) -> bool: return room.transport.send_signal(to, data)
	enabled = OS.has_feature("web") and ClassDB.class_exists("WebRTCPeerConnection") and not "--room-direct=off" in OS.get_cmdline_user_args()

static func _engine_connection():
	return ClassDB.instantiate("WebRTCPeerConnection")

static func now() -> float:
	return Time.get_ticks_usec() / 1000000.0

# ---------------------------------------------------------------- membership

# Called with the room members after every server sync. A guest links to the
# host; the host answers whoever calls. Links to departed members close.
func sync_members(host_id: String, member_ids: Array) -> void:
	if not enabled:
		return
	for id in links.keys():
		if not id in member_ids:
			close_link(id)
	if room.is_host or host_id == "" or host_id == room.player_id:
		return
	if not room.transport.socket_open:
		return
	var link: Dictionary = links.get(host_id, {})
	if link.is_empty():
		_offer(host_id, 0)
	elif link.pc == null and int(link.attempts) < int(NetProtocol.direct("max_attempts", 3)) and now() >= float(link.retry_at):
		_offer(host_id, int(link.attempts))

func close_all() -> void:
	for id in links.keys():
		close_link(id)
	links.clear()

func close_link(id: String) -> void:
	var link: Dictionary = links.get(id, {})
	if link.is_empty():
		return
	if link.channel != null:
		link.channel.close()
	if link.pc != null:
		link.pc.close()
	if link.open:
		print("ROOM_DIRECT closed ", id)
	links.erase(id)

# ---------------------------------------------------------------- setup

func _new_link(id: String, session: int, initiator: bool, attempts: int) -> Dictionary:
	var pc = connection_factory.call()
	if pc == null:
		return {}
	var servers: Array = []
	for url in NetProtocol.direct("ice_servers", []):
		servers.append({"urls": [str(url)]})
	if pc.initialize({"iceServers": servers}) != OK:
		return {}
	# Both sides create the same negotiated channel, so no in-band setup is needed.
	var channel = pc.create_data_channel("fast", {"negotiated": true, "id": 1, "ordered": false, "maxRetransmits": 0})
	if channel == null:
		pc.close()
		return {}
	channel.write_mode = CHANNEL_BINARY
	var link = {"pc": pc, "channel": channel, "session": session, "started": now(), "open": false, "last_received": -INF, "attempts": attempts, "retry_at": INF, "initiator": initiator}
	pc.session_description_created.connect(func(type: String, sdp: String) -> void:
		if links.get(id, {}).get("pc") != pc:
			return
		pc.set_local_description(type, sdp)
		signal_sender.call(id, {"kind": type, "sdp": sdp, "session": session}))
	pc.ice_candidate_created.connect(func(media: String, index: int, candidate: String) -> void:
		if links.get(id, {}).get("pc") != pc:
			return
		signal_sender.call(id, {"kind": "candidate", "media": media, "index": index, "name": candidate, "session": session}))
	links[id] = link
	return link

func _offer(id: String, attempts: int) -> void:
	session_counter += 1
	var session = int(Time.get_ticks_msec()) * 16 + session_counter % 16
	close_link(id)
	var link = _new_link(id, session, true, attempts + 1)
	if link.is_empty():
		# Without a working implementation there is nothing to retry.
		enabled = false
		return
	link.pc.create_offer()

# Connection setup relayed by the room server.
func on_signal(from: String, data: Dictionary) -> void:
	if not enabled or not data is Dictionary:
		return
	var session = int(data.get("session", 0))
	var kind = str(data.get("kind", ""))
	var link: Dictionary = links.get(from, {})
	if kind == "offer":
		# Only the host accepts calls; the server relays them only between members.
		if not room.is_host:
			return
		close_link(from)
		link = _new_link(from, session, false, 0)
		if link.is_empty():
			return
		link.pc.set_remote_description("offer", str(data.get("sdp", "")))
		return
	if link.is_empty() or link.pc == null or int(link.session) != session:
		return
	if kind == "answer" and link.initiator:
		link.pc.set_remote_description("answer", str(data.get("sdp", "")))
	elif kind == "candidate":
		link.pc.add_ice_candidate(str(data.get("media", "")), int(data.get("index", 0)), str(data.get("name", "")))

# ---------------------------------------------------------------- traffic

# Once per frame while in a room: receive, then send what is due.
func update(delta: float) -> void:
	poll()
	if room.connected:
		_send(delta)

func poll() -> void:
	if links.is_empty():
		return
	var t = now()
	for id in links.keys():
		var link: Dictionary = links.get(id, {})
		if link.is_empty() or link.pc == null:
			continue
		link.pc.poll()
		var state = int(link.pc.get_connection_state())
		var channel_state = int(link.channel.get_ready_state())
		if not link.open and channel_state == CHANNEL_OPEN:
			link.open = true
			link.last_received = t
			print("ROOM_DIRECT open ", id)
		while link.channel != null and link.channel.get_available_packet_count() > 0:
			var bytes: PackedByteArray = link.channel.get_packet()
			var message = JSON.parse_string(bytes.get_string_from_utf8())
			if message is Dictionary:
				link.last_received = t
				_receive(id, message)
			if not links.has(id):
				break
		if not links.has(id):
			continue
		var failed = state in [PEER_FAILED, PEER_CLOSED] or channel_state == CHANNEL_CLOSED
		var timed_out = not link.open and t - float(link.started) > float(NetProtocol.direct("connect_timeout", 10.0))
		if failed or timed_out:
			_failed(id, link)

func _failed(id: String, link: Dictionary) -> void:
	var attempts = int(link.attempts)
	var initiator = bool(link.initiator)
	close_link(id)
	if initiator:
		# Keep a placeholder so the guest retries later instead of at once.
		links[id] = {"pc": null, "channel": null, "session": 0, "started": now(), "open": false, "last_received": -INF, "attempts": attempts, "retry_at": now() + float(NetProtocol.direct("retry", 20.0)), "initiator": true}
		print("ROOM_DIRECT failed ", id, " attempt ", attempts)

# A link is healthy while packets keep arriving on it.
func healthy(id: String) -> bool:
	var link: Dictionary = links.get(id, {})
	return not link.is_empty() and link.open and now() - float(link.last_received) <= float(NetProtocol.direct("stale", 0.5))

func open_links() -> Array:
	var result: Array = []
	for id in links:
		if links[id].open and links[id].channel != null:
			result.append(id)
	return result

# Sends one packet; returns false when it cannot go direct (too big, closed).
func send(id: String, message: Dictionary) -> bool:
	return send_bytes(id, JSON.stringify(message).to_utf8_buffer())

func send_bytes(id: String, bytes: PackedByteArray) -> bool:
	var link: Dictionary = links.get(id, {})
	if link.is_empty() or not link.open or link.channel == null:
		return false
	if bytes.size() > int(NetProtocol.direct("max_packet", 16000)):
		return false
	return link.channel.put_packet(bytes) == OK

# ---------------------------------------------------------------- room traffic

# Over open direct links a guest sends its state (with unacknowledged driving
# input) at state_rate, the host sends the hot world at world_rate.
func _send(delta: float) -> void:
	var links: Array = open_links()
	if links.is_empty():
		return
	if room.is_host:
		var crowded = links.size() >= int(NetProtocol.direct("crowded_links", 4))
		var rate = float(NetProtocol.direct("world_rate_crowded" if crowded else "world_rate", 20))
		world_clock += delta
		if world_clock < 1.0 / rate:
			return
		world_clock = fmod(world_clock, 1.0 / rate)
		var bytes = JSON.stringify(world_packet()).to_utf8_buffer()
		for id in links:
			send_bytes(id, bytes)
	elif room.host_id in links:
		state_clock += delta
		var interval = 1.0 / float(NetProtocol.direct("state_rate", 30))
		if state_clock < interval:
			return
		state_clock = fmod(state_clock, interval)
		if send(room.host_id, {"t": "s", "state": room.local_state()}):
			room.prediction.seal()

# What the host sends each guest directly: the hot world (slow sections stay on
# the server path) and every member's state, as the server would list them.
func world_packet() -> Dictionary:
	var hot: Dictionary = room.world_sync.current_parts().hot.duplicate()
	hot.erase("cold_revs")
	var now_ms = int(room.server_clock() * 1000.0)
	var own = room.local_state()
	own.drive_inputs = []
	var players: Array = [_member_entry(room.player_id, own, now_ms)]
	for id in room.peers:
		var peer: Dictionary = room.peers[id]
		if peer.state == null:
			continue
		var state: Dictionary = peer.state.duplicate()
		state.drive_inputs = []
		players.append(_member_entry(str(id), state, int(float(peer.get("last_state_time", room.server_clock())) * 1000.0)))
	return {"t": "w", "time": now_ms, "world": hot, "players": players}

func _member_entry(id: String, state: Dictionary, state_time: int) -> Dictionary:
	var member: Dictionary = room.members.get(id, {})
	return {"id": id, "name": member.get("name", ""), "slot": member.get("slot", 0), "car_model": member.get("car_model", 0), "state_time": state_time, "state": state}

func _receive(from: String, message: Dictionary) -> void:
	match str(message.get("t", "")):
		"s":
			if room.is_host:
				_receive_state(from, message.get("state"))
		"w":
			if not room.is_host and from == room.host_id and message.get("world") is Dictionary and message.get("players") is Array:
				room._guest_world(message.world, float(message.get("time", -1)), message.players, false)

# The host takes a guest's state straight from its link, with the checks the
# server applies to the same state on the server path.
func _receive_state(from: String, raw) -> void:
	if not room.members.has(from) or not room.peers.has(from):
		return
	var state = NetProtocol.clean_state(raw)
	if state == null:
		return
	var member: Dictionary = room.members[from]
	room._update_peer({"id": from, "name": member.name, "slot": member.slot, "car_model": member.car_model, "state_time": int(room.server_clock() * 1000.0), "state": state})
