extends "res://tests/harness.gd"
# Direct (WebRTC) links between host and guest, with an in-process stand-in for
# the browser's peer connection: setup over the relayed signals, the hot world
# and guest input over the channel, server fallback when the link goes quiet.
const NetProtocol = preload("res://scripts/net_protocol.gd")

class FakeChannel extends RefCounted:
	var write_mode = 0
	var other: FakeChannel
	var inbox: Array = []
	var connected = false
	var closed = false
	var drop = false
	func get_ready_state() -> int:
		return 3 if closed else (1 if connected else 0)
	func put_packet(bytes: PackedByteArray) -> int:
		if not connected or closed:
			return ERR_UNAVAILABLE
		if not drop and other != null:
			other.inbox.append(bytes)
		return OK
	func get_available_packet_count() -> int:
		return inbox.size()
	func get_packet() -> PackedByteArray:
		return inbox.pop_front()
	func close() -> void:
		closed = true

class FakeConnection extends RefCounted:
	signal session_description_created(type: String, sdp: String)
	signal ice_candidate_created(media: String, index: int, name: String)
	static var offers: Dictionary = {}
	var channel: FakeChannel
	var connected = false
	var closed = false
	var never_connects = false
	var name = ""
	func initialize(_config: Dictionary) -> int:
		return OK
	func create_data_channel(_label: String, options: Dictionary) -> FakeChannel:
		if not options.get("negotiated", false) or options.get("ordered", true) or int(options.get("maxRetransmits", -1)) != 0:
			return null
		channel = FakeChannel.new()
		return channel
	func create_offer() -> int:
		name = "offer-%d" % randi()
		offers[name] = self
		session_description_created.emit("offer", name)
		ice_candidate_created.emit("0", 0, "candidate:" + name)
		return OK
	func set_local_description(_type: String, _sdp: String) -> int:
		return OK
	func set_remote_description(type: String, sdp: String) -> int:
		if type == "offer":
			var offerer: FakeConnection = offers.get(sdp)
			if offerer != null and not offerer.never_connects:
				channel.other = offerer.channel
				offerer.channel.other = channel
			session_description_created.emit("answer", "answer-" + sdp)
		elif type == "answer" and channel.other != null:
			for c in [channel, channel.other]:
				c.connected = true
			connected = true
		return OK
	func add_ice_candidate(_media: String, _index: int, _name: String) -> int:
		return OK
	func poll() -> int:
		return OK
	func get_connection_state() -> int:
		return 5 if closed else (2 if connected else 1)
	func close() -> void:
		closed = true

func wire(a, b, a_id: String, b_id: String, created: Array) -> void:
	for pair in [[a, b, b_id], [b, a, a_id]]:
		var from = pair[0]
		var to = pair[1]
		var target_id: String = pair[2]
		var own_id = a_id if from == a else b_id
		from.room.direct.enabled = true
		from.room.direct.connection_factory = func():
			var connection = FakeConnection.new()
			created.append(connection)
			return connection
		from.room.direct.signal_sender = func(target: String, data: Dictionary) -> bool:
			if target != target_id:
				return false
			to.room.direct.on_signal(own_id, data.duplicate(true))
			return true
		from.room.transport.socket_open = true

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var host = load("res://main.tscn").instantiate()
	var guest = load("res://main.tscn").instantiate()
	root.add_child(host)
	root.add_child(guest)
	await process_frame
	for g in [host, guest]:
		g.set_process(false)
		g.room.set_process(false)
		g.start_game()
	check(not host.room.direct.enabled, "native builds keep the server path")
	host.room.player_id = "host"
	guest.room.player_id = "guest"
	host.room.is_host = true
	for g in [host, guest]:
		g.room.connected = true
	var created: Array = []
	wire(host, guest, "host", "guest", created)
	var players = [{"id": "host", "name": "Хозяин", "slot": 0, "car_model": 0, "state": host.room.local_state(), "state_time": 0},
		{"id": "guest", "name": "Гость", "slot": 1, "car_model": 3, "state": guest.room.local_state(), "state_time": 0}]
	host.room.host_id = "host"
	guest.room.host_id = "host"
	host.room._update_members(players)
	host.room._update_peers(players)
	guest.room._update_members(players)
	# Membership (who is in the room) always comes from the server.
	guest.room._update_peers(players, false)
	check(created.size() == 2 and guest.room.direct.links.has("host") and host.room.direct.links.has("guest"), "guest calls the host through relayed setup")
	host.room.direct.poll()
	guest.room.direct.poll()
	check(guest.room.direct.open_links() == ["host"] and host.room.direct.open_links() == ["guest"], "both ends open the negotiated unordered channel")
	# Guest input goes straight to the host, which simulates the guest's car.
	guest.room.prediction_enabled = true
	guest.room.prediction.coalesce = true
	guest.room.prediction.reset(guest.car.position, guest.heading)
	for i in range(6):
		guest.room.prediction.predict(4, 1.0, 0.2 * (i % 2), false, guest.stage, guest.selected_car)
	host.room.peers.guest.state.drive_enabled = true
	guest.room.direct._send(1.0)
	host.room.direct.poll()
	check(host.room.host_drives.has("guest") and host.room.host_drives.guest.ack == guest.room.prediction.seq, "host applies guest driving input from the direct link")
	check(host.room.peers.guest.state.car != players[1].state.car, "host moves the guest's car from direct input")
	check(guest.room.prediction.sealed_seq == guest.room.prediction.seq, "sent input is sealed against further merging")
	# The host's world goes straight to the guest.
	host.course.phase = "racing"
	host.spawn_racer()
	host.room.direct._send(1.0)
	guest.room.direct.poll()
	check(guest.room.direct.healthy("host"), "a link with fresh packets is healthy")
	check(guest.racers.size() == 1 and guest.racers[0].id == host.racers[0].id, "guest receives the hot world directly")
	check(guest.room.authoritative_drives.has("guest") and int(guest.room.authoritative_drives.guest.ack) == guest.room.prediction.seq, "guest reconciles against the host's direct authority")
	check(guest.room.peers.has("host") and guest.room.peers.host.state != null, "guest sees the host's own state from the direct packet")
	var packet: Dictionary = host.room.direct.world_packet()
	check(not packet.world.has("cold_revs") and not packet.world.has("npc_people") and not packet.world.has("camp"), "slow sections stay on the server path")
	for entry in packet.players:
		check(entry.state.drive_inputs.is_empty(), "raw driving input is never forwarded to guests")
	# While the link is healthy, server snapshots only bring slow sections.
	var stale_world = host.room.world_sync.current_parts().hot.duplicate()
	stale_world.racers = []
	stale_world.cold = {"camp": host.room.world_sync.current_parts().cold.camp}
	guest.room._apply_sync({"host": "host", "players": players, "world": stale_world, "world_time": 10.0e12, "accepted": 0, "commands": []})
	check(guest.racers.size() == 1, "server hot world is ignored while the direct link is healthy")
	check(guest.room.world_sync.cold_revs.has("camp"), "slow sections still arrive from the server")
	# A quiet link falls back to the server path.
	guest.room.direct.links.host.last_received -= 1.0
	check(not guest.room.direct.healthy("host"), "a link without packets for half a second is stale")
	guest.room._apply_sync({"host": "host", "players": players, "world": stale_world, "world_time": 10.0e12, "accepted": 0, "commands": []})
	check(guest.racers.is_empty(), "the server path takes over from a stale link")
	# Hosts check direct states like the server does.
	check(NetProtocol.clean_state({"pos": [0, 0, 0]}) == null, "malformed direct state is rejected")
	var cleaned = NetProtocol.clean_state({"pos": [0, 0, 0], "car": [1, 1, 1], "heading": 0, "yaw": 0, "pitch": 0, "in_car": true, "speed": 999, "drive_inputs": [{"seq": 1, "ticks": 99, "throttle": 1, "steer": 0, "brake": false}, {"seq": 2, "ticks": 2, "throttle": 5, "steer": 0, "brake": false}, {"seq": 3, "ticks": 2, "throttle": 1, "steer": 0, "brake": false}]})
	check(cleaned != null and cleaned.speed == 50 and cleaned.drive_inputs.size() == 1 and cleaned.drive_inputs[0].seq == 3, "direct state is clamped and bad input dropped")
	# A link that never opens is retried later, a bounded number of times.
	guest.room.direct.close_all()
	guest.room.direct.connection_factory = func():
		var connection = FakeConnection.new()
		connection.never_connects = true
		return connection
	guest.room._update_members(players)
	var link: Dictionary = guest.room.direct.links.host
	link.started -= 60.0
	guest.room.direct.poll()
	check(guest.room.direct.links.host.pc == null and guest.room.direct.links.host.attempts == 1, "a link that does not open waits before the next attempt")
	guest.room.direct.links.host.retry_at = 0.0
	guest.room._update_members(players)
	check(guest.room.direct.links.host.pc != null and guest.room.direct.links.host.attempts == 2, "the guest retries after the pause")
	guest.room.direct.links.host.attempts = NetProtocol.direct("max_attempts", 3)
	guest.room.direct.links.host.started -= 60.0
	guest.room.direct.poll()
	guest.room.direct.links.host.retry_at = 0.0
	guest.room._update_members(players)
	check(guest.room.direct.links.host.pc == null, "after the last attempt the room stays on the server path")
	# A departed member's link closes.
	host.room._update_members([players[0]])
	check(not host.room.direct.links.has("guest"), "links to departed members close")
	print("DIRECT LINK RESULT: %d checks, %d failures" % [checks, failures])
	for g in [host, guest]:
		g.queue_free()
	await process_frame
	finish()
