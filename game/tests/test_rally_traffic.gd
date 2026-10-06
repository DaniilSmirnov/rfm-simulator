extends SceneTree
var failures = 0
func check(ok: bool, title: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + title)
	if not ok:
		failures += 1
func _initialize() -> void:
	call_deferred("run")
func clear_cars(game) -> void:
	for racer in game.racers:
		racer.node.free()
	game.racers.clear()
	game.rally_spawn_count = 0
	game.passed = 0
	game.dead = false
	game.car.position = Vector3(170, 2, 5)
func pair(game, moving: bool = false) -> Array:
	clear_cars(game)
	game.spawn_racer("pass")
	game.spawn_racer("pass")
	var lead = game.racers[0]
	var follower = game.racers[1]
	lead.s = 190.0
	lead.focus = 650.0
	lead.node.position = game.stage.at(190)
	lead.state = "racing" if moving else "stranded"
	lead.pace = 0.55
	lead.drive_speed = 13.2
	follower.s = 150.0
	follower.focus = 650.0
	follower.node.position = game.stage.at(150)
	follower.line = 0.0
	follower.slide = 0.0
	follower.pace = 1.15
	follower.drive_speed = 27.6
	return [lead, follower]
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.select_stage(2)
	game.start_game()
	game.in_car = false
	game.walker = Vector3(170, 2, 5)
	var biases = []
	for i in range(10):
		game.spawn_racer("pass")
		biases.append(game.Traffic.nominal(game.racers[-1], 160))
	biases.sort()
	check(biases[-1] - biases[0] > 0.8, "ten crews have different road lines rather than one shared centerline")
	var cars = pair(game)
	var lead = cars[0]
	var follower = cars[1]
	var avoided = false
	var safe = true
	for i in range(160):
		game._update_racers(1.0 / 24)
		avoided = avoided or absf(follower.line) > 2.7
		safe = safe and follower.state == "racing" and follower.node.position.distance_to(lead.node.position) > 2.5
	check(avoided and safe and follower.s > lead.s + 12, "crew safely steers around a stranded car and continues")
	cars = pair(game, true)
	lead = cars[0]
	follower = cars[1]
	var overtook = false
	safe = true
	for i in range(240):
		game._update_racers(1.0 / 24)
		overtook = overtook or follower.s > lead.s + 8
		safe = safe and follower.state == "racing" and lead.state == "racing"
	check(overtook and safe, "faster moving crew overtakes a slower moving crew without collision")
	cars = pair(game)
	lead = cars[0]
	follower = cars[1]
	lead.node.position += game.stage.side(lead.s) * -1.6
	game.car.position = game.stage.at(lead.s) + game.stage.side(lead.s) * 1.6
	for i in range(180):
		game._update_racers(1.0 / 24)
	check(follower.state == "racing" and follower.drive_speed < 0.5 and follower.s > 170 and follower.s < lead.s - 5, "blocked road produces a waiting queue instead of another stranded crew")
	var waiting: float = follower.s
	lead.node.position += game.stage.side(lead.s) * -20
	game.car.position = Vector3(170, 2, 5)
	for i in range(60):
		game._update_racers(1.0 / 24)
	check(follower.state == "racing" and follower.s > waiting + 5, "waiting crew automatically resumes when the road becomes clear")
	var snapshot = game.room.world_state()
	check(snapshot.racers.size() == 2 and snapshot.racers[1].pos == game.room.a(follower.node.position), "multiplayer snapshot carries the actual chosen rally trajectory")
	clear_cars(game)
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	print("RALLY TRAFFIC RESULT: %d failures" % failures)
	quit(1 if failures else 0)
