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
	for racer in [lead, follower]:
		var direction: Vector3 = game.race_direction(racer.s)
		racer.node.rotation.y = atan2(-direction.x, -direction.z)
		racer.previous = racer.node.position
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
	# The player waits far off the road; these check the crews' own motion.
	game.crews.full_rate = true
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
	# Overtake on the open approach, before parked village cars require braking.
	cars = pair(game, true, 80.0)
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
	if not (overtook and safe):
		print("OVERTAKE RESULT: lead=%.2f/%s/line%.2f follower=%.2f/%s/line%.2f speed=%.2f safe=%s" % [lead.s, lead.state, lead.line, follower.s, follower.state, follower.line, follower.drive_speed, safe])
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
	# The reverse pass finishes into the park where players' cars start the
	# day, down the aisle past the end of the road: they are not on the road.
	clear_cars(game)
	game.course.phase = "racing"
	game.spawn_racer("pass")
	var finishing = game.racers[0]
	finishing.s = game.stage.length - 12.0
	finishing.focus = 5000.0
	finishing.node.position = game.race_at(finishing.s)
	game.car.position = game.stage.parks.visitor_pose(0, 0).origin
	plan = game.Traffic.plan(game, finishing)
	check(not plan.avoiding and plan.speed > 5.0, "a player's car in the finish park does not stop crews before the line (%s)" % plan)
	game.in_car = false
	game.walker = game.car.position
	plan = game.Traffic.ServiceTraffic.pedestrian_plan(game, finishing, {"line": 0.0, "speed": 10.0, "avoiding": false})
	check(plan.speed >= 10.0 and float(plan.get("advance", INF)) == INF, "a player on foot in the finish park does not stop the convoy (%s)" % plan)
	game.walker = game.race_at(game.stage.length - 1.0)
	plan = game.Traffic.ServiceTraffic.pedestrian_plan(game, finishing, {"line": 0.0, "speed": 30.0, "avoiding": false})
	check(plan.speed < 30.0, "a player on foot at the end of the road still stops the convoy")
	game.walker = Vector3(170, 2, 5)
	game.car.position = Vector3(170, 2, 5)
	# Leaving the village in reverse, the Grand-Rue passes a car parked on the
	# pavement. A crew whose planned line runs too close to it, with every
	# passing line blocked by the house fronts, keeps the line it drives on.
	clear_cars(game)
	game.spawn_racer("pass")
	var leaving = game.racers[0]
	leaving.track_parts = PackedInt32Array()
	leaving.bias = 1.4
	leaving.s = game.stage.length - 330.0
	leaving.focus = 5000.0
	leaving.line = 0.3
	leaving.drive_speed = 8.0
	leaving.node.position = game.race_at(leaving.s) + game.race_side(leaving.s) * leaving.line
	leaving.previous = leaving.node.position
	for i in range(240):
		game._update_racers(1.0 / 24)
	check(leaving.state == "racing" and leaving.s > game.stage.length - 280.0, "a crew leaving the village in reverse drives past the car parked on the pavement (station %.1f, %s)" % [game.stage.length - leaving.s, leaving.state])
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
	# A hard sideways shove carries the car past the road edge: the driver
	# cannot catch it, and it leaves the road with its momentum.
	drifting.motion.velocity += game.race_side(drifting.s) * 20.0
	for i in range(60):
		game._update_racers(1.0 / 60.0)
		if drifting.state != "racing":
			break
	check(drifting.state == "offroad" and drifting.motion.velocity.length() > 5, "excessive slide releases the vehicle from the road with momentum")
	var carried: Vector3 = (drifting.node.position - drifting.previous) * 60.0
	carried.y = 0.0
	check(drifting.motion.velocity.distance_to(carried) < 0.001, "departure carries actual trajectory velocity, including lane changes")
	game.recover_racer(drifting)
	check(drifting.slide == 0 and drifting.slide_speed == 0 and drifting.drift_yaw == 0 and drifting.yaw_rate == 0 and drifting.motion.velocity == Vector3.ZERO, "towing resets lateral inertia and accident rotation")
	check(drifting.drive_speed == 0.0, "a towed crew restarts from a standstill")
	var launch = float(drifting.launch)
	game._update_racers(1.0 / 60.0)
	var early_gain: float = drifting.drive_speed * 60.0
	check(early_gain > 0.0 and early_gain < launch * 0.5, "a towed crew pulls away gently instead of at full launch")
	game._update_racers(game.crews.RECOVERY_RAMP)
	check(not drifting.has("recovery_time"), "the gentle restart ends after the ramp")
	var before_speed: float = drifting.drive_speed
	game._update_racers(1.0 / 60.0)
	var late_gain: float = (drifting.drive_speed - before_speed) * 60.0
	check(late_gain <= 0.0 or late_gain > early_gain, "full launch returns after the ramp")
	clear_cars(game)
	# Red flags stop already-started competitors and zero cars in either direction.
	game.stage.trees.clear()
	game.stage.rocks.clear()
	for pass_index in [1, 2]:
		game.course.pass_index = pass_index
		for role in ["racer", "zero"]:
			clear_cars(game)
			game.spawn_racer("pass")
			var red_flag_car = game.racers[0]
			red_flag_car.role = role
			red_flag_car.s = 150.0
			red_flag_car.node.position = game.race_at(red_flag_car.s)
			red_flag_car.drive_speed = 20.0
			red_flag_car.slide = 0.0
			red_flag_car.slide_speed = 0.0
			game.course.red_flag = true
			game._update_racers(1.0 / 60.0)
			check(red_flag_car.drive_speed > 0.0 and red_flag_car.drive_speed < 20.0 and red_flag_car.s > 150.0, "red flag brakes progressively instead of freezing immediately")
			# Brakes at the tyres' grip, about 1 g: 20 m/s needs over two seconds.
			game._update_racers(3.0)
			check(red_flag_car.drive_speed == 0.0 and red_flag_car.state == "racing", "competitors and zeros stop without becoming stranded")
			var held: Vector3 = red_flag_car.node.position
			red_flag_car.age = 25.0
			game._update_racers(1.0)
			check(game.racers.has(red_flag_car) and Vector2(red_flag_car.node.position.x - held.x, red_flag_car.node.position.z - held.z).length() < 0.001, "red-flag wait neither creeps nor despawns")
			game.course.red_flag = false
			game._update_racers(0.5)
			check(red_flag_car.drive_speed > 0.0 and red_flag_car.node.position.distance_to(held) > 0.1, "crews resume when the red flag clears")
	clear_cars(game)
	game.spawn_racer("pass")
	var ambulance = game.racers[0]
	ambulance.role = "ambulance"
	ambulance.s = 150.0
	ambulance.node.position = game.race_at(150.0)
	game.course.red_flag = true
	game._update_racers(0.5)
	check(ambulance.s > 150.0 and ambulance.drive_speed > 0.0, "ambulance continues while the red flag is active")
	check(game.course.phase_caption().contains("КРАСНЫЙ ФЛАГ"), "red-flag status is visible")
	game.course.red_flag = false
	clear_cars(game)
	# Service traffic yields to pedestrians, including emergency swept stops.
	game.course.pass_index = 1
	game.course.red_flag = false
	for role in ["ambulance", "opening_police", "closing_police"]:
		clear_cars(game)
		game.spawn_racer("pass")
		var service = game.racers[0]
		service.role = role
		service.s = 180.0
		service.line = 0.0
		service.node.position = game.race_at(service.s)
		game.walker = game.race_at(service.s + 6.0)
		var safety_plan = game.crews.ServiceTraffic.pedestrian_plan(game, service, {"speed": 20.0, "line": 0.0, "can_pass": false})
		check(safety_plan.speed < 20.0 and safety_plan.advance <= 2.1 and not safety_plan.can_pass, "service vehicle brakes before a pedestrian")
		if role == "ambulance":
			var escape_plan = game.crews.ServiceTraffic.pedestrian_plan(game, service, {"speed": 6.0, "line": 4.0, "can_pass": true})
			check(escape_plan.speed <= 6.0 and escape_plan.advance <= 2.1 and escape_plan.can_pass and escape_plan.line == 4.0, "departing ambulance brakes but retains its safe lateral escape")
		var before = game.crews.ServiceTraffic.save(service)
		service.node.position = game.walker
		service.s += 6.0
		check(game.crews.ServiceTraffic.guard(game, service, before), "swept guard stops service vehicle crossing a pedestrian")
		check(service.node.position == before.position and service.s == before.s and service.state == "racing", "safety stop preserves route state for resuming")
		game.walker = Vector3(170, 2, 5)
		service.node.position = game.car.position
		check(game.crews.ServiceTraffic.guard(game, service, before), "service vehicle cannot pass through a player car")
	# The ambulance uses the verge around every stopped course-vehicle role.
	for blocker_role in ["racer", "zero", "opening_police", "closing_police"]:
		var queue = pair(game, false, 175.0)
		queue[0].role = blocker_role
		queue[1].role = "ambulance"
		queue[1].track_parts = PackedInt32Array()
		var bypass = game.Traffic.plan(game, queue[1])
		check(bypass.get("can_pass", false) and absf(bypass.line) >= game.crews.ServiceTraffic.CAR_CLEARANCE, "ambulance plans a clear shoulder pass around stopped course vehicles")
		check(bypass.speed <= 6.0, "shoulder pass uses a reduced speed")
	# Static scenery used to make service traffic brake to zero forever. It now
	# selects a clear shoulder line and keeps moving around the obstruction.
	clear_cars(game)
	game.spawn_racer("pass")
	var obstacle_ambulance = game.racers[0]
	obstacle_ambulance.role = "ambulance"
	obstacle_ambulance.s = 180.0
	obstacle_ambulance.node.position = game.race_at(obstacle_ambulance.s)
	var obstacle_position: Vector3 = game.race_at(obstacle_ambulance.s + 25.0)
	obstacle_position.y = game.stage.ground(obstacle_position)
	game.stage.rocks.append({"pos": obstacle_position, "radius": 1.2, "height": 1.1})
	var detour = game.crews.ServiceTraffic.pedestrian_plan(game, obstacle_ambulance, {"speed": 20.0, "line": 0.0, "can_pass": false})
	check(detour.get("can_pass", false) and absf(detour.line) > 2.0 and detour.speed > 0.0, "ambulance steers around a roadside obstacle instead of stopping short")
	game.stage.rocks.clear()
	# Village walkers are numerous and can move along the road. The ambulance
	# should pass a standing villager safely instead of waiting indefinitely.
	if game.stage.life != null and "walkers" in game.stage.life:
		var saved_walkers: Array = game.stage.life.walkers.duplicate()
		game.stage.life.walkers.clear()
		game.car.position = Vector3(10000, 0, 10000)
		var walker_node = Node3D.new()
		game.add_child(walker_node)
		var walker_position: Vector3 = game.race_at(obstacle_ambulance.s + 24.0)
		walker_position.y = game.stage.ground(walker_position)
		walker_node.position = walker_position
		game.stage.life.walkers.append({"id": 999, "node": walker_node, "path": [], "t": 0.0, "direction": 1.0, "speed": 1.0, "pause": 0.0, "knocked": false})
		var crowd_detour = game.crews.ServiceTraffic.pedestrian_plan(game, obstacle_ambulance, {"speed": 20.0, "line": 0.0, "can_pass": false})
		check(crowd_detour.get("can_pass", false) and absf(crowd_detour.line) > 2.0 and crowd_detour.speed > 0.0, "ambulance safely passes a standing village resident")
		game.stage.life.walkers.clear()
		game.stage.life.walkers.append_array(saved_walkers)
		walker_node.queue_free()
	# Park at a safe braking distance; the doctor starts treatment after walking.
	var medical = obstacle_ambulance
	medical.role = "ambulance"
	medical.target_key = "test:casualty"
	medical.target_s = medical.s + 5.0
	medical.drive_speed = 0.0
	game.injuries.records[medical.target_key] = {"pos": game.race_at(medical.target_s)}
	game.injuries.ambulance_step(medical)
	check(medical.state == "parked" and medical.drive_speed == 0.0, "ambulance parks without driving into the casualty")
	check(str(medical.get("treating", "")) == "", "parking alone does not start treatment before the doctor arrives")
	game.injuries.records.erase("test:casualty")
	# Nerve: a bold driver carries more speed into the tightest bend, a driver
	# with none brakes exactly as before.
	var tightest = 0.0
	var slowest_target = INF
	for station in range(0, int(game.stage.length), 5):
		var calm = game.Traffic.competition_target(game.stage, float(station))
		if calm < slowest_target:
			slowest_target = calm
			tightest = float(station)
	check(game.Traffic.competition_target(game.stage, tightest, 1.0, false, 1.0) > slowest_target + 0.5, "a driver with nerve takes the tightest bend faster (%.1f vs %.1f m/s)" % [game.Traffic.competition_target(game.stage, tightest, 1.0, false, 1.0), slowest_target])
	check(game.Traffic.competition_target(game.stage, tightest, 1.0, false, 0.0) == slowest_target, "no nerve changes nothing")
	clear_cars(game)
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	print("RALLY TRAFFIC RESULT: %d failures" % failures)
	finish()
