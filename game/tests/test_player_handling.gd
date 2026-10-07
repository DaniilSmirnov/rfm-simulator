extends SceneTree
const Motion = preload("res://scripts/vehicle_motion.gd")
const Handling = preload("res://scripts/player_handling.gd")
var failures = 0
func check(ok: bool, title: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + title)
	if not ok:
		failures += 1
func _initialize() -> void:
	call_deferred("run")
func stopping(grip: float) -> float:
	var motion = Motion.new()
	motion.velocity = Vector3(0, 0, -18)
	var distance = 0.0
	for step in range(2400):
		motion.handling.advance(motion, 0, 0, 0, true, grip, 19, 0, Handling.STEP)
		distance += motion.velocity.length() * Handling.STEP
		if motion.velocity.length() < 0.01:
			return distance
	return INF
func turn(grip: float, counter: bool = false) -> Dictionary:
	var motion = Motion.new()
	motion.velocity = Vector3(0, 0, -18)
	var yaw = 0.0
	for step in range(180):
		yaw = motion.handling.advance(motion, yaw, 0, 1 if step < 60 else (-1 if counter else 0), false, grip, 19, 3, Handling.STEP)
	return {"yaw": yaw, "slip": absf(motion.handling.slip), "motion": motion}
func run() -> void:
	check(stopping(1.05) < stopping(0.78) and stopping(0.78) < stopping(0.22), "asphalt, gravel and snow have increasing stopping distances")
	var road = turn(1.05)
	var snow = turn(0.22)
	check(absf(road.yaw) > absf(snow.yaw), "front tyres push wide on slippery road instead of turning instantly")
	check(snow.slip > 0.02, "a fast slippery turn produces measurable side slip")
	var caught = turn(0.22, true)
	check(caught.slip < snow.slip, "countersteering reduces slide compared with releasing the wheel")
	var motion = Motion.new()
	var yaw = 0.0
	for step in range(120):
		yaw = motion.handling.advance(motion, yaw, 1, 0, false, 1, 19, 0, Handling.STEP)
	check(motion.velocity.z < -3 and absf(yaw) < 0.001, "straight acceleration does not create spontaneous yaw")
	for step in range(240):
		yaw = motion.handling.advance(motion, yaw, -1, 0, false, 1, 19, 0, Handling.STEP)
	check(motion.velocity.z > 0.5, "opposite pedal slows the car before engaging reverse")
	motion = Motion.new()
	motion.grounded = false
	for step in range(120):
		yaw = motion.handling.advance(motion, 0, 1, 1, false, 1, 19, 9, Handling.STEP)
	check(motion.velocity.is_zero_approx() and is_zero_approx(yaw), "airborne tyres cannot accelerate or steer the car")
	check(Handling.profile(3).rear_bias == 1 and Handling.profile(0).rear_bias == 0 and Handling.profile(2).rear_bias == 0.5, "fleet has rear, front and all-wheel traction profiles")
	var stable = true
	for variant in range(10):
		motion = Motion.new()
		motion.velocity = Vector3(0, 0, -19)
		yaw = 0
		for step in range(2400):
			var throttle = 1.0 if step < 600 else 0.0
			var steer = sin(step * Handling.STEP * 2.0)
			yaw = motion.handling.advance(motion, yaw, throttle, steer, step > 1800, 0.22, 19, variant, Handling.STEP)
			stable = stable and motion.velocity.is_finite() and is_finite(yaw) and motion.velocity.length() < 25
	check(stable, "all ten profiles remain finite and bounded through slippery acceleration, slalom and braking")
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.start_game()
	game.stage.trees.clear()
	game.stage.rocks.clear()
	var start: Vector3 = game.stage.at(120)
	var results: Array = []
	Input.action_press("forward")
	for fps in [24, 60, 144]:
		game.car.position = start
		game.heading = 0
		game.speed = 0
		game.vehicle_motion = Motion.new()
		for frame in range(fps * 2):
			game._drive(1.0 / fps)
		results.append({"pos": game.car.position, "speed": game.speed})
	Input.action_release("forward")
	check(results[0].pos.distance_to(results[1].pos) < 0.001 and results[0].pos.distance_to(results[2].pos) < 0.001, "actual driving uses identical 120 Hz ticks at 24, 60 and 144 FPS")
	check(absf(results[0].speed - results[2].speed) < 0.001, "render FPS does not change acceleration")
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	print("PLAYER HANDLING RESULT: %d failures" % failures)
	quit(1 if failures else 0)
