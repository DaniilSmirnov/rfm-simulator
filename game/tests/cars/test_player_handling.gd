extends "res://tests/harness.gd"
const Motion = preload("res://scripts/cars/vehicle_motion.gd")
const Handling = preload("res://scripts/cars/player_handling.gd")
const CarRegistry = preload("res://scripts/cars/car_registry.gd")
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
	for step in range(240):
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
	for variant in range(RallyProps.PLAYER_MODELS.size()):
		motion = Motion.new()
		motion.velocity = Vector3(0, 0, -19)
		yaw = 0
		for step in range(2400):
			var throttle = 1.0 if step < 600 else 0.0
			var steer = sin(step * Handling.STEP * 2.0)
			yaw = motion.handling.advance(motion, yaw, throttle, steer, step > 1800, 0.22, 19, variant, Handling.STEP)
			stable = stable and motion.velocity.is_finite() and is_finite(yaw) and motion.velocity.length() < 25
	check(stable, "all ten profiles remain finite and bounded through slippery acceleration, slalom and braking")
	# One speed range for all cars; each reaches 100 km/h in its own time.
	var launch_ok = true
	var top_ok = true
	var report = []
	for variant in range(CarRegistry.count()):
		motion = Motion.new()
		var hundred = INF
		var top = 0.0
		for step in range(int(90.0 / Handling.STEP)):
			motion.handling.advance(motion, 0, 1, 0, false, 1.0, CarRegistry.TOP_SPEED, variant, Handling.STEP)
			top = maxf(top, motion.velocity.length())
			if hundred == INF and motion.velocity.length() >= 100.0 / 3.6:
				hundred = (step + 1) * Handling.STEP
		var spec = float(CarRegistry.car(variant).handling.zero_to_100)
		report.append("%s %.1f/%.1f s, %d km/h" % [CarRegistry.car(variant).name, hundred, spec, int(top * 3.6)])
		launch_ok = launch_ok and absf(hundred - spec) <= spec * 0.1
		top_ok = top_ok and top * 3.6 > 200.0 and top <= CarRegistry.TOP_SPEED + 0.01
	print("\n".join(report))
	check(launch_ok, "every player car reaches 100 km/h in its own zero_to_100 time")
	check(top_ok, "every player car tops out at the shared 220 km/h")
	motion = Motion.new()
	motion.velocity = Vector3(0, 0, -40)
	for step in range(240):
		motion.handling.advance(motion, 0, 1, 0, false, 1.0, CarRegistry.OFFROAD_SPEED, 0, Handling.STEP)
	check(motion.velocity.length() < 25, "full throttle off the road still rolls down to the off-road limit")
	motion = Motion.new()
	for step in range(1200):
		motion.handling.advance(motion, 0, -1, 0, false, 1.0, CarRegistry.TOP_SPEED, 9, Handling.STEP)
	check(motion.velocity.length() <= CarRegistry.REVERSE_SPEED + 1.0, "reverse stays slow")
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
	finish()
