extends SceneTree
const Predictor = preload("res://scripts/drive_prediction.gd")
const Motion = preload("res://scripts/vehicle_motion.gd")
var failures = 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	game.defer_world = true
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.playing = true
	var solver = Predictor.new()
	for model in range(10):
		game.selected_car = model
		game.car.position = game.stage.at(100)
		game.heading = 0
		game.speed = 0
		game.condition = 100
		game.rock_impact_timer = 0
		game.vehicle_motion = Motion.new()
		solver.reset(game.car.position, 0)
		for frame in range(120):
			var steer = 0.2 if frame < 60 else -0.3
			Input.action_press("forward")
			Input.action_release("left")
			Input.action_release("right")
			Input.action_press("right" if steer > 0 else "left", absf(steer))
			if frame > 90: Input.action_press("brake")
			else: Input.action_release("brake")
			game._drive(1.0 / 60)
			solver.step({"ticks":2,"throttle":1,"steer":steer,"brake":frame > 90}, game.stage, model)
		check(game.car.transform.is_equal_approx(solver.node.transform) and game.vehicle_motion.velocity.is_equal_approx(solver.motion.velocity) and is_equal_approx(game.condition, solver.condition), "offline and authoritative physics agree for model %d" % model)
	for action in ["forward", "left", "right", "brake"]: Input.action_release(action)
	await game._shutdown_audio()
	game.free()
	print("SHARED VEHICLE failures=", failures)
	quit(1 if failures else 0)
