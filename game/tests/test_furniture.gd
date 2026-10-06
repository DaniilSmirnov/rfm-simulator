extends SceneTree
var failures = 0
func check(ok: bool, title: String) -> void:
	if not ok:
		failures += 1
		push_error(title)
	else:
		print("PASS: " + title)
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
		game.stage.trees.clear()
		game.room.connected = true
	host.room.is_host = true
	host.room.player_id = "host"
	guest.room.player_id = "guest"
	var origin = host.stage.clearings[0]
	host.walker = origin
	check(host.place_table(origin, 0.5), "table can be positioned and rotated freely")
	var chair_pos = origin + Vector3(3, 0, 0)
	check(host.place_chairs(chair_pos, 0.8), "host places one personal chair")
	check(host.place_chairs(chair_pos + Vector3(0, 0, 2), 1.2) and host.personal_chairs.size() == 1, "repositioning never duplicates a personal chair")
	var command = {"player": "guest", "action": "chairs", "state": {"in_car": false, "pos": host.room.a(origin), "car": host.room.a(host.car.position), "yaw": 0}, "placement": {"pos": host.room.a(origin + Vector3(-3, 0, 0)), "yaw": -0.7}}
	host.room._apply_command(command)
	check(host.personal_chairs.has("guest") and host.personal_chairs.size() == 2, "guest chair has a separate authenticated owner")
	check(host.start_grill(origin + Vector3(0, 0, -3), 0.9), "grill has an independent position")
	host.cook_time = 12
	check(host.start_grill(origin + Vector3(0, 0, -4), 1.4) and host.cook_time == 12, "moving grill preserves cooking progress")
	host.place_table(origin + Vector3(0, 0, 1), 1.0)
	var snapshot = host.room.world_state()
	guest.room.apply_world(snapshot)
	check(guest.personal_chairs.size() == 2 and guest.has_personal_chair(), "late guest receives both chairs and recognizes their own")
	check(guest.grill.position.distance_to(host.grill.position) < 0.03 and absf(guest.grill.rotation.y - 1.4) < 0.01, "grill placement and rotation replicate")
	guest.room.apply_world(snapshot)
	check(guest.personal_chairs.size() == 2, "repeated snapshots never duplicate chairs")
	check(not host.valid_furniture_spot(host.stage.at(140), "table"), "furniture cannot be placed on rally road")
	host.walker = origin + Vector3(0, 0, 6)
	check(host.place_flag(host.walker + Vector3(2, 0, 0), 0.0), "first personal Rally Fan Maps flag can be placed")
	check(host.flag_count() == 1, "flag count is tracked per player")
	check(host.place_flag(host.walker + Vector3(3, 0, 0), 0.4), "second personal flag can be placed")
	check(host.place_flag(host.walker + Vector3(4, 0, 0), 0.8), "third personal flag can be placed")
	check(not host.place_flag(host.walker + Vector3(5, 0, 0), 1.2), "fourth flag is rejected")
	for game in [host, guest]:
		await game._shutdown_audio()
		game.queue_free()
	await process_frame
	quit(1 if failures else 0)
