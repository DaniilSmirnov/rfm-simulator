extends SceneTree
var failures = 0
func check(ok: bool, title: String) -> void:
	if ok:
		print("PASS: " + title)
	else:
		failures += 1
		push_error(title)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.start_game()
	game.in_car = false
	game.walker = game.stage.at(200)
	game.car.position = game.stage.at(30)
	game.stage.trees.clear()
	game.stage.rocks.clear()
	game.view_yaw = 0
	var start: Vector3 = game.walker
	Input.action_press("forward")
	game._walk(0.1)
	var walked = game.walker.distance_to(start)
	game.walker = start
	Input.action_press("sprint")
	game._walk(0.1)
	check(game.walker.distance_to(start) > walked * 1.5 and game.running(), "Shift increases walking speed")
	Input.action_release("sprint")
	Input.action_release("forward")
	check(game.jump(), "grounded player can jump")
	game._walk(0.2)
	check(game.jump_height > 0.65 and game.walker.y > game.stage.ground(game.walker), "jump lifts physical player position above terrain")
	check(not game.jump() and game.walking_intent() == Vector3.ZERO, "no double jump or airborne push")
	var height = game.jump_height
	game.paused = true
	game._process(0.2)
	check(game.jump_height == height, "pause freezes jump")
	game.paused = false
	game._walk(0.6)
	check(game.jump_height == 0 and absf(game.walker.y - game.stage.ground(game.walker)) < 0.001, "jump lands back on ground")
	game.in_car = true
	check(not game.jump(), "driver cannot jump")
	game.in_car = false
	game.seated = true
	check(not game.jump() and not game.running(), "seated player cannot jump or sprint")
	game.seated = false
	game.beers = 30
	check(not game.jump(), "collapsed player cannot jump")
	game.beers = 0
	game.enable_mobile()
	game.mobile_controls._layout()
	check(game.mobile_controls.buttons.any(func(b): return b.action == "jump") and game.mobile_controls.buttons.any(func(b): return b.action == "sprint" and b.hold), "touch controls offer jump and held sprint")
	# Isolate one roadside helper, retaining NPC camp data for meal compatibility.
	var crowd = game.spectators
	var person: Dictionary = crowd.people[0]
	crowd.people.clear()
	crowd.people.append(person)
	person.home = game.stage.at(200) + game.stage.side(200) * 10
	person.home.y = game.stage.ground(person.home)
	person.watch = game.stage.at(200) + game.stage.side(200) * 6.4
	person.watch.y = game.stage.ground(person.watch)
	person.avatar.position = person.watch
	game.course.phase = "racing"
	game.spawn_racer("pass")
	var racer: Dictionary = game.racers[0]
	racer.node.position = game.stage.at(200)
	var cheering = false
	for time in range(80):
		crowd.update(float(time), 0, false)
		if person.action == "cheer":
			cheering = true
			check(person.arm.rotation.x > 2 and not person.can.visible and not person.food.visible, "cheer raises arms without food or beer")
			break
	check(cheering, "nearby moving crew triggers cheering")
	racer.state = "stranded"
	racer.node.position = game.stage.at(200) + game.stage.side(200) * 9
	racer.node.position.y = game.stage.ground(racer.node.position)
	racer.previous = racer.node.position
	var road = game.Recovery.road_direction(game, racer)
	person.avatar.position = racer.node.position - road * 4.5
	person.avatar.position.y = game.stage.ground(person.avatar.position)
	var before: Vector3 = person.avatar.position
	crowd.update(81, 0.2, false)
	check(person.action == "help" and person.avatar.position.distance_to(before) > 0.1, "nearby NPC walks toward stranded car")
	person.avatar.position = racer.node.position - road * 2
	person.avatar.position.y = game.stage.ground(person.avatar.position)
	crowd.update(82, 0, false)
	check(person.action == "push" and crowd.push_helpers().size() == 1, "NPC contributes only after reaching pushing position")
	game.Recovery.update(game, {}, 0.5)
	var solo: float = racer.get("recovery_progress", 0)
	check(solo > 0.05 and game.recovery_helpers == 1, "NPC effort physically moves car")
	racer.erase("recovery_start")
	racer.erase("recovery_goal")
	racer.erase("recovery_progress")
	racer.node.position = racer.previous - road * 0.1
	person.avatar.position = racer.node.position - road * 2
	person.avatar.position.y = game.stage.ground(person.avatar.position)
	crowd.update(83, 0, false)
	var player = {"pos": game.room.a(racer.node.position + road * 3), "in_car": false, "tow": true, "push": [0, 0, 0], "beers": 0}
	game.Recovery.update(game, {"player": player}, 0.5)
	check(racer.get("recovery_progress", 0) > solo * 1.8 and game.recovery_helpers == 2, "player and NPC recovery efforts stack")
	var snapshot = crowd.actor_snapshot()
	crowd.apply_actor_snapshot(snapshot)
	person.avatar.position += Vector3(3, 0, 0)
	crowd.update(83, 0.1, true)
	check(person.avatar.position.distance_to(game.room.v(snapshot[0].pos)) < 3, "guest smoothly follows authoritative NPC positions")
	racer.state = "racing"
	crowd.update(84, 0.1, false)
	check(person.helper == -1 and crowd.push_helpers().is_empty(), "NPC stops pushing recovered car")
	racer.state = "stranded"
	person.home = game.stage.at(700)
	crowd.update(85, 0, false)
	check(person.helper == -1, "distant NPC never joins recovery")
	check(game.room.world_state().has("npc_people"), "world snapshots carry NPC poses and actions")
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	print("RUN JUMP NPC RESULT: %d failures" % failures)
	quit(1 if failures else 0)
