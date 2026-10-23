extends "res://tests/harness.gd"
# Direct (WebRTC) links between host and guest, with an in-process stand-in for
# the browser's peer connection: setup over the relayed signals, the hot world
# and guest input over the channel, server fallback when the link goes quiet.
const NetProtocol = preload("res://scripts/net/net_protocol.gd")

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
	var DirectNative = load("res://scripts/net/direct_native.gd")
	check(host.room.direct.enabled == DirectNative.available(), "native builds link directly exactly when the native library is installed")
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
	check(not packet.world.has("cold_revs") and not packet.world.has("npc_people") and not packet.world.has("camp"), "before any upload no slow section rides the direct packet")
	var full_hot: Dictionary = host.room.world_sync.current_parts().hot
	full_hot.erase("cold_revs")
	check(JSON.stringify(packet.world, "", true) == JSON.stringify(full_hot, "", true), "the direct packet is the hot world without building the slow sections")
	var guest_entry = packet.players.filter(func(e): return e.id == "guest")
	check(guest_entry.size() == 1 and int(guest_entry[0].state_time) == int(float(host.room.drive_budgets.guest.stamp) * 1000.0), "a guest car the host drives is stamped with its simulation time")
	for entry in packet.players:
		check(not entry.state.has("drive_inputs") and not entry.state.has("trees") and not entry.has("name"), "raw driving input, object requests and the roster are never forwarded to guests")
	check(guest.room.sync_body().get("direct", false) == true and not host.room.sync_body().has("direct"), "a guest with a healthy link tells the server to leave the hot world to it")
	# A changed slow section follows the host's upload over the link, a few
	# packets in a row, instead of guest -> server -> host -> server -> guest.
	host.room.sync_body()
	var with_cold: Dictionary = host.room.direct.world_packet()
	check(with_cold.world.get("cold", {}).has("camp") and with_cold.world.cold_revs.camp == host.room.world_sync.latest_revs.camp, "a changed slow section rides the direct packet")
	for i in range(host.room.world_sync.DIRECT_COLD_REPEATS - 1):
		host.room.direct.world_packet()
	check(not host.room.direct.world_packet().world.get("cold", {}).has("camp"), "an unchanged section stops after its repeats")
	host.room.world_sync.direct_revs.erase("camp")
	host.room.direct._send(1.0)
	guest.room.direct.poll()
	check(guest.room.world_sync.cold_revs.get("camp") == host.room.world_sync.latest_revs.camp, "the guest applies a slow section from the link")
	var older = {"cold": {"camp": host.room.world_sync.latest_cold.camp}, "cold_revs": {"camp": 12345}}
	guest.room.world_sync.apply_cold(older, -1.0)
	check(guest.room.world_sync.cold_revs.camp == host.room.world_sync.latest_revs.camp, "the server's older copy of a section that just came directly is ignored")
	# Commands ride the guest's packets; the server's copy is only acknowledged.
	guest.room.commands = [{"seq": 41, "action": "stand_person", "placement": {"pos": [1.0e6, 0, 0], "resource_id": 2.0}}]
	guest.room.direct._send(1.0)
	host.room.direct.poll()
	check(host.room.processed.has("guest:41"), "the host runs a guest command from the direct link")
	check(host.room.direct._placement({"pos": [1.0e6, 0, 0], "yaw": 0, "resource_id": 2.0}, [0, 0, 0]) == {"resource_id": 2}, "a direct command's placement gets the server's checks")
	host.room.acknowledgements.clear()
	host.room._apply_checked_sync({"host": "host", "players": players, "world": null, "commands": [{"id": "guest:41", "player": "guest", "action": "stand_person", "state": players[1].state, "placement": {}}]})
	check(host.room.acknowledgements == ["guest:41"], "the server's copy of a command already run is acknowledged")
	guest.room.commands.clear()
	# The host's own notices stay on its screen; shared events and a guest's
	# own command results reach that guest.
	var shared_before: String = host.hud.notice
	host.hud.toast("Ты выпил пиво.")
	check(host.hud.notice == shared_before and host.toast_label.text != "", "a host's personal notice is not shared")
	host.acting = load("res://scripts/player/action_context.gd").from_command({"state": players[1].state}, "guest", 0)
	var host_text: String = host.toast_label.text
	host.hud.toast("Мангал разожжён. Дождись, пока угли прогорят.")
	host.acting = null
	check(host.toast_label.text == host_text and host.hud.notice_for == "guest", "a guest command's result goes to that guest, not the host's screen")
	var status: Dictionary = host.room.world_sync._status_snapshot()
	guest.toast_label.text = ""
	guest.room.world_sync._status_apply(status, 0.0)
	check(guest.toast_label.text != "", "the guest sees its own command's result")
	guest.toast_label.text = ""
	guest.room.world_sync._status_apply({"notice": "Чужое", "notice_time": 3.0, "notice_for": "someone"}, 0.0)
	check(guest.toast_label.text == "", "another member's result is not shown")
	host.hud.announce("Экипаж застрял. Нужен трос — T рядом с машиной.")
	guest.room.world_sync._status_apply(host.room.world_sync._status_snapshot(), 0.0)
	check(guest.toast_label.text != "" and host.hud.notice_for == "", "a shared event reaches everyone")
	# The guest's world clock runs every frame between the host's packets.
	guest.playing = true
	guest.room.world_sync._progress_apply({"elapsed": 100.0}, 0.0)
	var first: float = guest.elapsed
	guest.room.world_sync.advance_clock(0.05, false)
	var second: float = guest.elapsed
	guest.room.world_sync.advance_clock(0.05, true)
	check(first == 100.0 and second > first + 0.04 and guest.elapsed == second, "a guest's world clock advances locally and stops while frozen")
	# Compact states expand to what the server would have listed, after a JSON round trip.
	var original: Dictionary = host.room.local_state()
	original.beers = 3
	original.speed = 12.3456
	var compact: Dictionary = NetProtocol.compact_state(original)
	check(not compact.has("food_kind") and not compact.has("push") and not compact.has("ride") and not compact.has("car") and not compact.has("tilt"), "idle values, the driver's car position and flat tilt are left out")
	var restored: Dictionary = NetProtocol.expand_state(JSON.parse_string(JSON.stringify(compact)))
	var restored_ok = true
	for key in original:
		if key in NetProtocol.STATE_HOST_ONLY:
			restored_ok = restored_ok and restored[key] == []
		elif key == "tilt":
			# The middle angle is the heading; guests overwrite it with the heading anyway.
			restored_ok = restored_ok and absf(restored.tilt[0] - original.tilt[0]) < 0.002 and absf(restored.tilt[2] - original.tilt[2]) < 0.002 and restored.tilt[1] == restored.heading
		elif original[key] is Array:
			restored_ok = restored_ok and str(restored[key].map(func(n): return snappedf(float(n), 0.001))) == str(original[key].map(func(n): return snappedf(float(n), 0.001)))
		elif original[key] is float:
			restored_ok = restored_ok and absf(float(restored[key]) - original[key]) < 0.006
		else:
			restored_ok = restored_ok and restored[key] == original[key]
	check(restored_ok and restored.size() == original.size() and int(restored.beers) == 3, "an expanded state matches the original")
	var walking: Dictionary = original.duplicate(true)
	walking.in_car = false
	walking.car = [4.0, 1.0, 2.0]
	walking.tilt = [0.1, walking.heading, -0.2]
	walking.push = [0.5, 0.0, -0.5]
	walking.ride = "friend"
	var walking_back: Dictionary = NetProtocol.expand_state(JSON.parse_string(JSON.stringify(NetProtocol.compact_state(walking))))
	check(walking_back.car == [4.0, 1.0, 2.0] and absf(walking_back.tilt[2] + 0.2) < 0.002 and absf(walking_back.tilt[1] - walking.heading) < 0.002 and walking_back.push == [0.5, 0.0, -0.5] and walking_back.ride == "friend", "a walking member keeps its car, tilt, push and ride")
	# Gravel travels as events: new stones in full, every living stone by id.
	host.stones.clear()
	var node = Node3D.new()
	host.add_child(node)
	node.position = Vector3(1, 2, 3)
	host.stones.append({"id": 77, "node": node, "velocity": Vector3(1, 0, 0), "life": 2.0, "bounces": 0})
	var snapshot_a: Dictionary = host.room.world_sync._stones_snapshot()
	check(snapshot_a.stones.size() == 1 and snapshot_a.stone_ids == [77], "a new stone travels in full")
	host.stones[0].fresh_until = 0
	var snapshot_b: Dictionary = host.room.world_sync._stones_snapshot()
	check(snapshot_b.stones.is_empty() and snapshot_b.stone_ids == [77] and not snapshot_b.has("impacts"), "an older stone is only listed by id")
	guest.room.apply_stones(JSON.parse_string(JSON.stringify(snapshot_a)), -1.0)
	check(guest.stones.size() == 1 and int(guest.stones[0].id) == 77, "the guest creates the stone")
	guest.room.apply_stones({"stones": [], "stone_ids": [77]}, -1.0)
	check(guest.stones.size() == 1, "a listed stone keeps flying on the guest")
	guest.room.apply_stones({"stones": [], "stone_ids": []}, -1.0)
	check(guest.stones.is_empty(), "a stone that left the list is removed")
	host.stones.clear()
	node.queue_free()
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
