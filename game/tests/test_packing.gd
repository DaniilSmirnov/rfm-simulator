extends SceneTree
var failures = 0
func check(ok: bool, title: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + title)
	if not ok:
		failures += 1
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var host = load("res://main.tscn").instantiate()
	var guest = load("res://main.tscn").instantiate()
	for game in [host, guest]:
		root.add_child(game)
	await process_frame
	for game in [host, guest]:
		game.set_process(false)
		game.room.set_process(false)
		game.start_game()
		game.in_car = false
		game.walker = game.stage.clearings[0]
		game.stage.trees.clear()
		game.stage.rocks.clear()
		game.car.position = Vector3(190, 30, 30)
	host.camp = Node3D.new()
	host.add_child(host.camp)
	host.camp.position = host.walker
	host.apply_chair("guest", host.walker + Vector3(2, 0, 0), 0)
	host.start_grill(host.walker + Vector3(-2, 0, 0), 0, true)
	host.place_flag(host.walker + Vector3(0, 0, 4), 0, "guest", true)
	var table_spot = host.camp.position
	check(host.packing.remaining() == 4 and not host.packing.pack(table_spot), "packing cannot remove equipment during a live stage")
	host.course.phase = "complete"
	host.course.pass_index = 2
	host.passed = 10
	host.foraging.skewers["-1"] = [{"ready_at": 0}]
	host._check_finish()
	check(not host.finished, "standing beside an unpacked camp never ends the outing")
	host.camera.position = table_spot + Vector3(0, 1.6, 2)
	host.camera.look_at(table_spot + Vector3(0, 0.75, 0))
	host.walker = table_spot + Vector3(0, 0, 2)
	check(host.interaction.current().get("action", "") == "pack", "gaze-selected F offers packing instead of beer")
	host.begin_placement("table")
	check(host.placement_preview == null, "equipment cannot be placed again during cleanup")
	guest.room.connected = true
	guest.room.player_id = "guest"
	guest.room.is_host = false
	host.room.connected = true
	host.room.player_id = "host"
	host.room.is_host = true
	guest.room.apply_world(host.room.world_state())
	check(guest.packing.active() and guest.packing.remaining() == 4, "late guest inherits reverse pass and cleanup objective")
	guest.walker = table_spot + Vector3(0, 0, 1)
	check(guest.packing.pack(table_spot) and guest.camp != null and guest.room.commands[-1].action == "pack", "guest requests packing without speculative removal")
	var command = {"action": "pack", "player": "guest", "state": guest.room.local_state(), "placement": guest.room.commands[-1].placement}
	command.state.pos = [190, 30, 30]
	host.room._apply_command(command)
	check(host.camp != null, "host rejects packing from outside interaction range")
	command.state.pos = guest.room.a(guest.walker)
	host.room._apply_command(command)
	host.room._apply_command(command)
	check(host.camp == null and host.packing.remaining() == 4 and host.cargo.held.has("guest"), "authorized pickup is idempotent and remains pending until returned")
	host.cargo.opened["host"] = true
	command.action = "return_gear"
	var trunk_spot = host.cargo.point(host.cargo.poses()["host"])
	command.state.pos = host.room.a(trunk_spot)
	command.placement = {"pos": host.room.a(trunk_spot), "yaw": 0}
	host.room._apply_command(command)
	check(not host.cargo.held.has("guest"), "friend returns shared equipment to owner's open trunk")
	for item in host.packing.items():
		host.walker = item.node.position
		check(host.packing.pack(item.node.position), "every kind of camp equipment can be packed")
		if item.kind != "flag":
			host.walker = trunk_spot
			check(host.cargo.return_item(trunk_spot), "collected equipment returns to an open trunk")
	guest.room.apply_world(host.room.world_state())
	guest.room.apply_world(host.room.world_state())
	check(guest.packing.remaining() == 0 and not guest.cooking and guest.smoke == null and guest.foraging.skewers.get("-1", []).is_empty(), "repeated snapshots remove table, chair, grill, smoke and all flags")
	host.in_car = true
	host.room.peers["guest"] = {"state": {"in_car": false}}
	host._check_finish()
	check(not host.finished, "host waits for a friend still outside their car")
	host.room.peers["guest"].state.in_car = true
	host._check_finish()
	check(host.finished, "shared outing finishes when cleanup is done and everyone is in a car")
	host.room.peers.clear()
	for arch in host.stage.officials.arches:
		check(arch.get_meta("caption") == "Rally Fans Map", "both arches display only Rally Fans Map")
	for game in [host, guest]:
		await game._shutdown_audio()
		game.queue_free()
	await process_frame
	print("PACKING RESULT: %d failures" % failures)
	quit(1 if failures else 0)
