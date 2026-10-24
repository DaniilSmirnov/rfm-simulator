extends "res://tests/harness.gd"
# Direct (WebRTC) links between host and guest, with an in-process stand-in for
# the browser's peer connection: setup over the relayed signals, then the whole
# game over the channel, and leaving the room when the link does not come.
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

# The hot world as per-guest deltas (world_delta.gd), on hand-made providers.
func delta_checks() -> void:
	var Delta = load("res://scripts/net/world_delta.gd")
	var providers = [{"name": "status", "section": "", "keys": ["notice"]}, {"name": "progress", "section": "", "keys": ["elapsed"]}, {"name": "racers", "section": "", "keys": ["racers", "recovery_links"]}, {"name": "camp", "section": "camp", "keys": ["camp"]}]
	var crews = func(far_x: float) -> Array: return [{"id": 1, "pos": [0, 0, 0], "yaw": 0.0}, {"id": 2, "pos": [far_x, 0, 0], "yaw": 0.0}]
	var hot = {"notice": "a", "elapsed": 1.0, "racers": crews.call(500.0)}
	var link = {}
	var packet = func(time: int, world: Dictionary) -> Dictionary:
		var whole = {"t": "w", "time": time, "world": world, "players": [], "accepted": {}}
		return JSON.parse_string(JSON.stringify(Delta.packet(link, whole, Delta.parts(world, providers), [0, 0, 0])))
	var first = packet.call(1000, hot)
	check(first.get("full", false) and first.parts.size() == 3 and first.world.racers.size() == 2 and not first.world.has("camp"), "a link's first world is whole and carries no slow section")
	var again = packet.call(1050, hot)
	check(again.parts.size() == 3, "unconfirmed parts ride every packet")
	link.acked = 1050
	hot.elapsed = 2.0
	var quiet = packet.call(1100, hot)
	check(quiet.parts == ["progress"] and quiet.world.keys() == ["elapsed"], "after the guest confirms, only the part that changed goes")
	hot.notice = ""
	hot.erase("notice")
	var emptied = packet.call(1150, hot)
	check(emptied.parts.has("status") and not emptied.world.has("notice"), "a part that became empty is named without fields")
	link.acked = 1150
	hot.racers = crews.call(510.0)
	hot.racers[0].yaw = 1.0
	var near_only = packet.call(1200, hot)
	check(near_only.world.racers.size() == 1 and near_only.world.racers[0].id == 1 and near_only.crews.map(func(id): return int(id)) == [1, 2], "a far crew waits for its refresh while a near one goes at once")
	var refreshed = packet.call(1200 + int(Delta.FAR_INTERVAL * 1000.0), hot)
	var sends = 0
	for i in range(4):
		var later = packet.call(1300 + int(Delta.FAR_INTERVAL * 1000.0) + i * 50, hot)
		if later.has("world") and later.world.get("racers", []).any(func(r): return r.id == 2): sends += 1
	check(refreshed.world.racers.any(func(r): return r.id == 2) and sends == Delta.FAR_SENDS - 1, "a far crew's refresh goes a bounded number of times")
	var whole_again = packet.call(1000 + int(Delta.FULL_EVERY * 1000.0), hot)
	check(whole_again.get("full", false) and whole_again.parts.size() == 3 and whole_again.world.racers.size() == 2, "a whole world goes every FULL_EVERY")
	# The guest merges what arrives into what it holds.
	var base = {}
	var merged = Delta.merge(base, first, providers)
	check(merged.world.notice == "a" and merged.world.racers.size() == 2 and merged.changed.size() == 3, "a whole world fills the guest's copy")
	merged = Delta.merge(base, quiet, providers)
	check(merged.world.notice == "a" and merged.world.elapsed == 2.0 and merged.world.racers.size() == 2 and merged.changed.keys() == ["progress"], "a delta keeps the parts it does not carry")
	merged = Delta.merge(base, emptied, providers)
	check(not merged.world.has("notice"), "an emptied part clears its fields")
	merged = Delta.merge(base, near_only, providers)
	check(merged.world.racers.size() == 2 and merged.crews.keys() == ["1"] and float(merged.world.racers[0].yaw) == 1.0, "unchanged crews stay and only the arrived ones count as fresh")
	var left = near_only.duplicate(true)
	left.crews = [2]
	left.world.racers = []
	merged = Delta.merge(base, left, providers)
	check(merged.world.racers.size() == 1 and merged.world.racers[0].id == 2, "a crew missing from the ids leaves")
	check(Delta.merge(base, {"world": {"elapsed": 3.0}}, providers).changed == null and base.is_empty(), "a world without parts is whole")
	check(not Delta.valid({"parts": [1]}) and not Delta.valid({"parts": ["racers"]}) and Delta.valid({"parts": ["racers"], "crews": []}), "malformed delta fields are refused")

# Guests index flying gravel by id.
func stone_checks(guest) -> void:
	guest.stones.clear()
	guest.room.apply_stones({"stones": [{"id": 1, "pos": [0, 5, 0], "velocity": [0, 0, 0]}, {"id": 2, "pos": [1, 5, 0], "velocity": [0, 0, 0]}], "stone_ids": [1, 2]})
	guest.room.apply_stones({"stones": [{"id": 2, "pos": [1, 6, 0], "velocity": [0, 0, 0]}], "stone_ids": [2]})
	check(guest.stones.size() == 1 and guest.stones[0].id == 2 and guest.stones[0].node.position.y > 5.0, "a stone moves by its id and a gone one is removed")
	for stone in guest.stones:
		stone.node.queue_free()
	guest.stones.clear()

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
	check(not packet.world.has("cold_revs") and not packet.world.has("npc_people") and not packet.world.has("camp"), "no slow section rides the world packet")
	var full_hot: Dictionary = host.room.world_sync.current_parts().hot
	full_hot.erase("cold_revs")
	check(JSON.stringify(packet.world, "", true) == JSON.stringify(full_hot, "", true), "the direct packet is the hot world without building the slow sections")
	var guest_entry = packet.players.filter(func(e): return e.id == "guest")
	check(guest_entry.size() == 1 and int(guest_entry[0].state_time) == int(float(host.room.drive_budgets.guest.stamp) * 1000.0), "a guest car the host drives is stamped with its simulation time")
	for entry in packet.players:
		check(not entry.state.has("drive_inputs") and not entry.state.has("trees") and not entry.has("name"), "raw driving input, object requests and the roster are never forwarded to guests")
	var body: Dictionary = guest.room.sync_body()
	check(body.keys().all(func(key): return key in ["token", "state", "direct"]) and not body.state.has("drive_inputs") and not host.room.sync_body().has("world"), "the server gets only the membership: no world, commands or driving input")
	# Slow sections go over the link in pieces until the guest reports holding them.
	host.room.world_sync.refresh_cold()
	var sections: Array = host.room.world_sync.latest_revs.keys()
	var rounds = 0
	while rounds < 20 and sections.any(func(section): return guest.room.world_sync.cold_revs.get(section) != host.room.world_sync.latest_revs[section]):
		host.room.direct._send(1.0)
		guest.room.direct.poll()
		guest.room.direct._send(1.0)
		host.room.direct.poll()
		rounds += 1
	check(rounds < 20 and guest.room.world_sync.cold_revs.get("camp") == host.room.world_sync.latest_revs.camp, "the guest gets every slow section over the link")
	check(host.room.direct.cold_messages("guest").is_empty(), "sections the guest reported are not sent again")
	var big = "x".repeat(host.room.direct.COLD_PIECE * 2 + 10)
	host.room.world_sync.latest_texts.camp = JSON.stringify({"camp": null, "padding": big})
	host.room.world_sync.latest_revs.camp = 4242
	host.room.world_sync.latest_at += 1000
	var first_pieces: Array = host.room.direct.cold_messages("guest")
	check(first_pieces.size() == 3 and first_pieces.all(func(m): return m.s == "camp" and m.n == 3), "a large section goes in pieces")
	check(host.room.direct.cold_messages("guest").is_empty(), "a sent copy waits for the guest's report before it goes again")
	host.room.direct.links.guest.cold.camp.sent -= 10.0
	check(host.room.direct.cold_messages("guest").size() == 3, "an unconfirmed copy goes again")
	guest.room.world_sync.receive_piece(first_pieces[2])
	guest.room.world_sync.receive_piece(first_pieces[0])
	check(guest.room.world_sync.pieces.has("camp") and guest.room.world_sync.cold_revs.camp != 4242, "a section waits for all its pieces")
	var stale: Dictionary = first_pieces[1].duplicate()
	stale.v = 0
	guest.room.world_sync.receive_piece(stale)
	check(guest.room.world_sync.cold_revs.camp != 4242, "a piece of an older copy is ignored")
	host.room.world_sync.refresh_cold()
	# Commands ride the guest's packets until the host's world lists them as run.
	guest.room.commands = [{"seq": 41, "action": "stand_person", "placement": {"pos": [1.0e6, 0, 0], "resource_id": 2.0}}]
	guest.room.direct._send(1.0)
	host.room.direct.poll()
	check(host.room.processed.has("guest:41") and host.room.accepted.guest == 41, "the host runs a guest command from the direct link")
	check(host.room.direct._placement({"pos": [1.0e6, 0, 0], "yaw": 0, "resource_id": 2.0}, [0, 0, 0]) == {"resource_id": 2}, "a direct command's placement gets the server's checks")
	host.room.processed.erase("guest:41")
	guest.room.direct._send(1.0)
	host.room.direct.poll()
	check(not host.room.processed.has("guest:41"), "a repeated command is not run twice")
	host.room.direct._send(1.0)
	guest.room.direct.poll()
	check(guest.room.commands.is_empty(), "the guest drops commands the host ran")
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
	# A client's own state leaves its idle fields out; the receiver's checks fill
	# in the same values (and beer, which they would read as 0, still goes).
	var own: Dictionary = guest.room.local_state()
	var sent: Dictionary = NetProtocol.outgoing_state(own)
	check(not sent.has("food_kind") and not sent.has("trees") and not sent.has("stand_at") and sent.has("beer") and NetProtocol.clean_state(JSON.parse_string(JSON.stringify(sent))) == NetProtocol.clean_state(JSON.parse_string(JSON.stringify(own))), "a client's own state leaves out idle fields the receiver fills in alike")
	own.drive_inputs = [{"seq": 1, "ticks": 2, "throttle": 1.0, "steer": 0.0, "brake": false}]
	check(NetProtocol.outgoing_state(own).has("drive_inputs") and not NetProtocol.outgoing_state(own, true).has("drive_inputs"), "with the direct link alive the server copy carries no drive input")
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
	# The server's reply brings only the membership.
	var stale_world = host.room.world_sync.current_parts().hot.duplicate()
	stale_world.racers = []
	guest.room._apply_sync({"host": "host", "players": players, "world": stale_world, "world_time": 10.0e12, "accepted": 0, "commands": []})
	check(guest.racers.size() == 1, "a world from the server is ignored")
	# A guest without a link waits, then leaves the room with a message.
	guest.room.direct.links.host.last_received -= 1.0
	check(not guest.room.direct.healthy("host"), "a link without packets for half a second is stale")
	check(guest.room._linked(1.0) and guest.room.connected, "a guest waits for a quiet link")
	guest.room._linked(guest.room.LINK_GIVE_UP)
	check(not guest.room.connected and guest.menu_title.text == "Не удалось соединиться", "a guest whose link does not come back leaves the room")
	guest.room.connected = true
	guest.dead = false
	guest.paused = false
	guest.room.link_lost = 0.0
	guest.room.transport.socket_open = true
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
	check(guest.room.direct.links.host.pc == null, "after the last attempt the guest stops calling")
	# A departed member's link closes.
	host.room._update_members([players[0]])
	check(not host.room.direct.links.has("guest"), "links to departed members close")
	delta_checks()
	stone_checks(guest)
	print("DIRECT LINK RESULT: %d checks, %d failures" % [checks, failures])
	for g in [host, guest]:
		g.queue_free()
	await process_frame
	finish()
