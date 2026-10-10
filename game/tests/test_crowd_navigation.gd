extends "res://tests/harness.gd"
const Navigation = preload("res://scripts/crowd_navigation.gd")
func _initialize() -> void:
	call_deferred("run")
func ground(game, p: Vector3) -> Vector3:
	p.y = game.stage.ground(p)
	return p
func route_clear(game, start: Vector3, goal: Vector3, ctx: Dictionary, route: Array) -> bool:
	if route.is_empty():
		return false
	var previous = start
	for step in route:
		if not Navigation.clear(game, previous, step, ctx):
			return false
		previous = step
	return previous.distance_to(goal) < 0.01
func run() -> void:
	Engine.max_fps = 0
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.start_game()
	game.in_car = false
	game.stage.trees.clear()
	game.stage.forest_data.clear()
	game.stage.rocks.clear()
	game.car.position = ground(game, Vector3(140, 0, -50))
	var person: Dictionary = game.spectators.people[0]
	var start = ground(game, Vector3(65, 0, -200))
	var goal = ground(game, Vector3(75, 0, -200))
	person.avatar.position = start
	person.helper = -1
	game.stage.rocks.append({"pos": ground(game, Vector3(70, 0, -200)), "radius": 2.0, "height": 3.0})
	var ctx = Navigation.context(game, person, start, goal, false)
	check(not Navigation.clear(game, start, goal, ctx), "boulder blocks direct route")
	var route = Navigation.plan(game, start, goal, ctx)
	check(route_clear(game, start, goal, ctx, route), "planner finds swept collision-free route around boulder")
	var reached = false
	for frame in range(100):
		game.spectators.navigation_budget.advance(0.1)
		Navigation.move(game, person, goal, 0.1, false)
		if person.avatar.position.distance_to(goal) < 0.2:
			reached = true
			break
		await process_frame
	check(reached, "NPC follows detour and reaches destination")
	# A fallen tree is a wide obstacle, not a point to sidestep into.
	game.stage.rocks.clear()
	game.stage.trees.append(ground(game, Vector3(70, 0, -200)))
	game.stage.forest_data.append({"height": 8.0})
	game.stage.fell(0, Vector3.FORWARD)
	game.stage.update_fallen(2)
	ctx = Navigation.context(game, person, start, goal, false)
	route = Navigation.plan(game, start, goal, ctx)
	check(route_clear(game, start, goal, ctx, route), "planner routes around a fallen trunk")
	game.stage.trees.clear()
	game.stage.forest_data.clear()
	game.stage.fallen.clear()
	game.car.position = ground(game, Vector3(70, 0, -200))
	ctx = Navigation.context(game, person, start, goal, false)
	route = Navigation.plan(game, start, goal, ctx)
	check(not Navigation.clear(game, start, goal, ctx) and route_clear(game, start, goal, ctx, route), "parked car is avoided")
	game.car.position = ground(game, Vector3(140, 0, -50))
	person.avatar.position = start
	person.erase("navigation")
	await process_frame
	game.spectators.navigation_budget.advance(0.1)
	Navigation.move(game, person, goal, 0.1, false)
	game.stage.rocks.append({"pos": ground(game, start + Vector3(3, 0, 0)), "radius": 1.4, "height": 3.0})
	var previous: Vector3 = person.avatar.position
	await process_frame
	game.spectators.navigation_budget.advance(0.1)
	Navigation.move(game, person, goal, 0.1, false)
	ctx = Navigation.context(game, person, previous, goal, false)
	check(Navigation.clear(game, previous, person.avatar.position, ctx) and person.navigation.route.size() > 1, "new obstruction triggers safe route rebuild")
	# Marshal tracks a passing crew, then joins a recovery through the same navigator.
	game.stage.rocks.clear()
	game.course.phase = "racing"
	game.spawn_racer("pass")
	var racer: Dictionary = game.racers[0]
	var officials = game.stage.officials
	var marshal: Dictionary = officials.people[0]
	var station = game.stage.road_s(marshal.home)
	racer.node.position = game.stage.at(station - 12)
	officials.update(game, 0.5, false)
	var before: float = marshal.avatar.rotation.y
	racer.node.position = game.stage.at(station + 12)
	officials.update(game, 0.5, false)
	var toward: Vector3 = racer.node.position - marshal.avatar.position
	toward.y = 0
	check(absf(angle_difference(before, marshal.avatar.rotation.y)) > 0.5 and (-marshal.avatar.basis.z).dot(toward.normalized()) > 0.9, "marshal turns after passing crew")
	racer.state = "stranded"
	racer.node.position = ground(game, marshal.home + game.stage.side(station) * 2.0)
	racer.previous = racer.node.position
	var road = game.Recovery.road_direction(game, racer)
	var rear = ground(game, racer.node.position - road * 2.0)
	marshal.avatar.position = rear
	officials.update(game, 0, false)
	check(marshal.action == "push" and officials.push_helpers(game).size() == 1, "marshal joins pushing after reaching car")
	game.Recovery.update(game, {}, 0.5)
	check(racer.get("recovery_progress", 0) > 0 and game.recovery_helpers >= 1, "marshal pushing moves the actual rally car")
	var record: Dictionary = marshal.avatar.get_meta("solid_record")
	check(record.pos == marshal.avatar.position, "marshal collision follows moving actor")
	var poses = officials.snapshot()
	officials.apply_snapshot(poses)
	marshal.avatar.position += Vector3(3, 0, 0)
	officials.update(game, 0.1, true)
	check(marshal.avatar.position.distance_to(game.room.v(poses[0].pos)) < 3, "guest interpolates authoritative marshal movement")
	check(game.room.world_state().has("marshals"), "marshal poses are included in room snapshots")
	racer.state = "racing"
	officials.update(game, 0.1, false)
	check(marshal.helper == -1 and officials.push_helpers(game).is_empty(), "marshal stops helping recovered crew")
	game.paused = true
	var paused: Vector3 = marshal.avatar.position
	game._process(1)
	check(marshal.avatar.position == paused, "pause freezes marshal movement")
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	print("CROWD NAVIGATION RESULT: %d failures" % failures)
	finish()
