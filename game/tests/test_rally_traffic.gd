extends "res://tests/harness.gd"
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
# start is the follower's progress; the leader runs 40 m ahead of it.
func pair(game, moving: bool = false, start: float = 150.0) -> Array:
	clear_cars(game)
	game.course.phase = "racing"
	game.spawn_racer("pass")
	game.spawn_racer("pass")
	var lead = game.racers[0]
	var follower = game.racers[1]
	lead.s = start + 40.0
	lead.focus = 650.0
	lead.node.position = game.race_at(start + 40.0)
	lead.state = "racing" if moving else "stranded"
	lead.pace = 0.55
	lead.drive_speed = 13.2
	follower.s = start
	follower.focus = 650.0
	follower.node.position = game.race_at(start)
	follower.line = 0.0
	follower.slide = 0.0
	follower.pace = 1.15
	follower.drive_speed = 27.6
	return [lead, follower]
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	# game._ready() randomizes crews; a fixed seed keeps this test repeatable.
	game.rng.seed = 6022026
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.select_stage(2)
	game.start_game()
	game.in_car = false
	game.walker = Vector3(170, 2, 5)
	game.course.phase = "racing"
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
	# Overtake on the open plateau, clear of the narrow Grand-Rue entry.
	cars = pair(game, true, 175.0)
	lead = cars[0]
	follower = cars[1]
	var overtook = false
	var logged = false
	safe = true
	for i in range(240):
		game._update_racers(1.0 / 24)
		overtook = overtook or follower.s > lead.s + 8
		if not logged and (follower.state != "racing" or lead.state != "racing"):
			logged = true
			print("OVERTAKE COLLISION: frame=%d lead=%.2f/%s/line%.2f/speed%.2f follower=%.2f/%s/line%.2f/speed%.2f distance=%.2f" % [i, lead.s, lead.state, lead.line, lead.drive_speed, follower.s, follower.state, follower.line, follower.drive_speed, lead.node.position.distance_to(follower.node.position)])
		safe = safe and follower.state == "racing" and lead.state == "racing"
	check(overtook and safe, "faster moving crew overtakes a slower moving crew without collision")
	cars = pair(game)
	lead = cars[0]
	follower = cars[1]
	lead.node.position += game.race_side(lead.s) * -1.6
	game.car.position = game.race_at(lead.s) + game.race_side(lead.s) * 1.6
	for i in range(180):
		game._update_racers(1.0 / 24)
	check(follower.state == "racing" and follower.drive_speed < 0.5 and follower.s > 170 and follower.s < lead.s - 5, "blocked road produces a waiting queue instead of another stranded crew")
	var waiting: float = follower.s
	lead.node.position += game.race_side(lead.s) * -20
	game.car.position = Vector3(170, 2, 5)
	for i in range(60):
		game._update_racers(1.0 / 24)
	check(follower.state == "racing" and follower.s > waiting + 5, "waiting crew automatically resumes when the road becomes clear")
	var snapshot = game.room.world_state()
	check(snapshot.racers.size() == 2 and snapshot.racers[1].pos == game.room.a(follower.node.position), "multiplayer snapshot carries the actual chosen rally trajectory")
	game.course.pass_index = 2
	# Reverse pass: the stranded car sits in the vineyard valley, not the hairpin.
	cars = pair(game, false, 50.0)
	lead = cars[0]
	follower = cars[1]
	follower.s = 60.0
	follower.node.position = game.race_at(follower.s)
	var plan = game.Traffic.plan(game, follower)
	check(plan.avoiding, "reverse traffic recognizes a blocker ahead in travel direction")
	safe = true
	for i in range(160):
		game._update_racers(1.0 / 24)
		var frame_safe = follower.state == "racing" and follower.node.position.distance_to(lead.node.position) > 2.5
		if safe and not frame_safe:
			print("REVERSE COLLISION: frame=%d s=%.2f state=%s line=%.2f lead_line=%.2f gap=%.2f" % [i, follower.s, follower.state, follower.line, lead.line, follower.node.position.distance_to(lead.node.position)])
		safe = safe and frame_safe
	if not (safe and follower.s > lead.s + 12):
		print("REVERSE RESULT: s=%.2f target=%.2f speed=%.2f state=%s line=%.2f" % [follower.s, lead.s + 12, follower.drive_speed, follower.state, follower.line])
	check(safe and follower.s > lead.s + 12, "reverse crew safely overtakes stranded car")
	game.recover_racer(lead)
	# The crew restarts on its own line across the road, where it was brought back.
	var lane: Vector3 = game.race_at(lead.s) + game.race_side(lead.s) * lead.line - lead.node.position
	check(lead.state == "racing" and Vector2(lane.x, lane.z).length() < 0.01 and (-lead.node.basis.z).dot(game.race_direction(lead.s)) > 0.99, "recovery rejoins road in reverse travel direction")
	clear_cars(game)
	game.course.phase = "racing"
	game.spawn_racer("pass")
	var drifting = game.racers[0]
	drifting.s = 160.0
	drifting.focus = 650.0
	drifting.node.position = game.race_at(drifting.s)
	drifting.slide = 1.0
	drifting.slide_speed = 0.5
	game._update_racers(1.0 / 60.0)
	var lateral: float = (drifting.node.position - game.race_at(drifting.s)).dot(game.race_side(drifting.s))
	check(absf(lateral - drifting.line - drifting.slide) < 0.01, "slide displaces the actual vehicle rather than only changing its steering target")
	drifting.slide = 3.6
	game._update_racers(1.0 / 60.0)
	check(drifting.state == "offroad" and drifting.motion.velocity.length() > 5, "excessive slide releases the vehicle from the road with momentum")
	var carried: Vector3 = (drifting.node.position - drifting.previous) * 60.0
	carried.y = 0.0
	check(drifting.motion.velocity.distance_to(carried) < 0.001, "departure carries actual trajectory velocity, including lane changes")
	game.recover_racer(drifting)
	check(drifting.slide == 0 and drifting.slide_speed == 0 and drifting.drift_yaw == 0 and drifting.yaw_rate == 0 and drifting.motion.velocity == Vector3.ZERO, "towing resets lateral inertia and accident rotation")
	clear_cars(game)
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	print("RALLY TRAFFIC RESULT: %d failures" % failures)
	finish()
