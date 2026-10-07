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
func aim(game: Node3D, point: Vector3) -> void:
	game._update_camera(1)
	game.camera.look_at(point)
func press(game: Node3D) -> void:
	var event = InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	game._unhandled_input(event)
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.start_game()
	check(InputMap.action_get_events("interact").any(func(e): return e is InputEventKey and e.physical_keycode == KEY_F), "F is the interaction key")
	check(not InputMap.action_get_events("table").any(func(e): return e is InputEventKey and e.physical_keycode == KEY_F), "F never starts table placement")
	press(game)
	check(not game.in_car, "F exits a stopped car")
	game.walker = game.stage.clearings[0]
	var center: Vector3 = game.walker
	# Isolate interaction geometry from ambient forest/NPCs.
	game.stage.collectibles.clear()
	game.stage.harvested.clear()
	game.car.position = center + Vector3(0, 0, -15)
	game.camp = Node3D.new()
	game.add_child(game.camp)
	game.camp.position = center + Vector3(5, 0, 0)
	game.grill = preload("res://scripts/props.gd").grill(game)
	game.grill.position = center
	game.cook_time = 35
	game.walker = center + Vector3(0, 0, 2)
	game.walker.y = game.stage.ground(game.walker)
	aim(game, center + Vector3(0, 0.9, 0))
	check(game.interaction.current().get("action") == "meat", "looking at cooked grill offers meat")
	var count = game.grill_servings
	press(game)
	check(game.eat_time == 0 and game.eat_source_group == -1, "F starts eating from selected grill")
	game._update_eating(2.7)
	check(game.grill_servings == count - 1, "selected serving commits after bite")
	game._cancel_eat()
	game.foraging.stock().mushrooms = 1
	aim(game, center + Vector3(0, 0.9, 0))
	check(game.interaction.current().get("action") == "mount", "free skewer and inventory offer mounting")
	press(game)
	check(game.foraging.stock().mushrooms == 0, "F mounts one mushroom")
	game.elapsed += 11
	check(game.interaction.current().get("action") == "mushroom", "cooked mushroom becomes contextual action")
	press(game)
	check(game.eat_kind == "mushroom" and game.eat_time == 0, "F starts mushroom animation")
	game._cancel_eat()
	game.grill.position = center + Vector3(-10, 0, 0)
	game.apply_chair(game.chair_owner(), center, 0)
	aim(game, center + Vector3(0, 0.65, 0))
	check(game.interaction.current().get("action") == "sit", "gaze selects personal chair")
	press(game)
	check(game.seated and game.walking_intent() == Vector3.ZERO, "F seats player and blocks walking")
	var seat: Vector3 = game.walker
	Input.action_press("forward")
	game._walk(1)
	Input.action_release("forward")
	check(game.walker == seat and game.room.local_state().seated, "seat remains stationary and synchronizes")
	press(game)
	check(not game.seated and game.walker != seat, "F stands and restores approach position")
	game.personal_chairs[game.chair_owner()].position = center + Vector3(-12, 0, 0)
	var mushroom = center + Vector3(0, 0, 0.5)
	game.stage.collectibles.append({"kind": "mushrooms", "pos": mushroom, "quantity": 1, "parts": {}})
	game.walker = center + Vector3(0, 0, 1.6)
	game.walker.y = game.stage.ground(game.walker)
	aim(game, mushroom + Vector3(0, 0.15, 0))
	check(game.interaction.current().get("action") == "collect", "gaze selects nearby mushroom")
	game.camera.rotation.y += PI
	check(game.interaction.current().is_empty(), "nearby object behind player does not intercept F")
	aim(game, mushroom + Vector3(0, 0.15, 0))
	press(game)
	check(game.stage.harvested.has(0) and game.foraging.stock().mushrooms == 1, "F harvests selected mushroom once")
	press(game)
	check(game.foraging.stock().mushrooms == 1, "harvested mushroom no longer interacts")
	game.stage.collectibles.append({"kind": "berries", "pos": mushroom, "quantity": 3, "parts": {}})
	aim(game, mushroom + Vector3(0, 0.6, 0))
	press(game)
	check(game.foraging.stock().berries == 3, "F harvests berry bush")
	game.camp.position = center
	aim(game, center + Vector3(0, 0.75, 0))
	press(game)
	check(game.drink_time == 0, "F drinks at gaze-selected table")
	game._cancel_drink()
	game.camp.position = center + Vector3(10, 0, 0)
	game.car.position = center
	game.walker = game.cargo.point(game.cargo.poses()[game.chair_owner()])
	aim(game, center + Vector3(0, 0.9, 0))
	check(game.interaction.current().get("action", "") != "car", "open trunk never offers car entry even when looking at the body")
	press(game)
	check(not game.in_car, "F at an open trunk cannot put the spectator in the car")
	game.cancel_placement()
	if game.cargo.held.has(game.chair_owner()):
		game.cargo.return_item(game.cargo.point(game.cargo.poses()[game.chair_owner()]))
	game.walker = center + Vector3(1.8, 0, -0.2).rotated(Vector3.UP, game.heading)
	game.walker.y = game.stage.ground(game.walker)
	aim(game, center + Vector3(0, 0.9, 0))
	check(game.interaction.current().get("action", "") == "car", "side door still offers entry while the trunk is open")
	press(game)
	check(game.in_car, "F enters selected car from its door")
	game.speed = 5
	check(game.interaction.current().is_empty(), "moving car cannot be exited")
	game.speed = 0
	game.paused = true
	check(game.interaction.current().is_empty(), "pause disables interactions")
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	print("INTERACTION RESULT: %d failures" % failures)
	quit(1 if failures else 0)
