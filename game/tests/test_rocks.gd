extends SceneTree
const Stage = preload("res://scripts/stage.gd")
const Motion = preload("res://scripts/vehicle_motion.gd")
var failures = 0
func check(ok: bool, title: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + title)
	if not ok:
		failures += 1
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var stage = Stage.new()
	var origin = stage.at(120)
	stage.rocks.append({"pos": origin, "radius": 0.6, "height": 0.75})
	var hit = stage.rock_hit(origin + Vector3(-5, 0, 0), origin + Vector3(5, 0, 0), 0.85)
	check(not hit.is_empty() and hit.position.x < origin.x and hit.normal.x < -0.9, "fast car sweep hits the near face of a rock")
	check(stage.rock_hit(origin + Vector3(-5, 2, 0), origin + Vector3(5, 2, 0), 0.85).is_empty(), "airborne cars can clear a rock")
	check(stage.rock_hit(origin + Vector3(-5, 2, 0), origin + Vector3(5, 0, 0), 0.85).is_empty(), "landing beyond a rock does not create a false midair hit")
	check(stage.rock_hit(origin + Vector3(0.1, 0, 0), origin + Vector3(0.2, 0, 0), 0.85).is_empty(), "overlapping cars can move out of rock contact")
	check(not stage.rock_hit(origin + Vector3(0.2, 0, 0), origin + Vector3(0.1, 0, 0), 0.85).is_empty(), "moving farther into a rock remains blocked")
	var solver = Motion.new()
	solver.velocity = Vector3(12, 0, 4)
	var energy = solver.velocity.length_squared()
	solver.rock_impulse(Vector3.LEFT, -PI / 2)
	check(solver.velocity.x < 0 and solver.velocity.z > 0 and solver.velocity.length_squared() < energy, "rock rebound loses energy and preserves tangential slide")
	check(solver.vertical_speed > 0 and solver.vertical_speed <= 2.8, "rock strike produces a bounded suspension kick")
	stage.free()
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.start_game()
	game.stage.trees.clear()
	game.stage.rocks.clear()
	origin = game.stage.clearings[0]
	game.stage.rocks.append({"pos": origin, "radius": 0.6, "height": 0.75})
	game.car.position = origin + Vector3(-4, 0, 0)
	game.heading = -PI / 2
	game.speed = 12
	game.vehicle_motion = Motion.new()
	var condition = game.condition
	Input.action_press("forward")
	game._drive(0.5)
	Input.action_release("forward")
	check(game.car.position.x < origin.x and game.condition < condition and game.condition > condition - 15, "player car hits the rock without tunnelling or repeated damage")
	var before = game.car.position.distance_to(origin)
	Input.action_press("back")
	game._drive(0.8)
	Input.action_release("back")
	check(game.car.position.distance_to(origin) > before + 0.2, "player can reverse away after rock collision")
	game.in_car = false
	game.car.position = origin + Vector3(0, 0, 20)
	game.walker = origin + Vector3(-1.1, 0, 0)
	game.view_yaw = -PI / 2
	var previous = game.walker
	Input.action_press("forward")
	game._walk(0.5)
	Input.action_release("forward")
	check(absf(game.walker.x - previous.x) < 0.01, "walking cannot cross a solid rock")
	check(not game.valid_furniture_spot(origin, "table"), "furniture cannot be placed inside rocks")
	game.walker = origin + Vector3(0, 0, 12)
	game.course.phase = "racing"
	game.spawn_racer("crash")
	var racer = game.racers[0]
	racer.state = "offroad"
	racer.age = 0.0
	racer.start = origin + Vector3(-4, 0, 0)
	racer.target = origin + Vector3(4, 0, 0)
	racer.node.position = racer.start
	game._update_racers(0.5)
	check(racer.state == "rock_bounce" and racer.node.position.x < origin.x and racer.motion.velocity.x < 0, "rally car physically rebounds from a roadside rock")
	var snapshot = game.room.world_state()
	check(snapshot.racers[0].state == "rock_bounce" and snapshot.racers[0].has("tilt"), "room shares rally rock rebound and suspension pose")
	game._update_racers(0.9)
	check(racer.state == "stranded", "crashed rally crew waits for towing after rock rebound")
	var passed = game.passed
	racer.state = "offroad"
	racer.counted = false
	racer.age = 0.0
	racer.start = origin + Vector3(-4, 0, 0)
	racer.target = origin + Vector3(1, 0, 0)
	racer.node.position = racer.start
	game._update_racers(0.8)
	check(game.passed == passed + 1, "rock hit on final offroad frame counts the crew once")
	var node = Node3D.new()
	game.add_child(node)
	node.position = origin + Vector3(0, 0.3, 5)
	var gravel = {"node": node, "velocity": Vector3(2, -5, 0), "bounces": 0}
	var alive = game._advance_gravel(gravel, 0.1)
	check(alive and gravel.velocity.y > 0 and gravel.bounces == 1, "flying gravel bounces off terrain")
	check(gravel.velocity.x < 2, "ground bounce dissipates gravel energy")
	var contact_origin = origin + Vector3(0, 0.4, 0)
	node.position = contact_origin + Vector3(-1, 0, 0)
	gravel.velocity = Vector3(15, 0, 0)
	gravel.bounces = 0
	game._advance_gravel(gravel, 0.1)
	check(gravel.velocity.x < 0 and node.position.x < origin.x, "flying gravel rebounds from static rocks")
	node.free()
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	print("ROCK RESULT: %d failures" % failures)
	quit(1 if failures else 0)
