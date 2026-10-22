extends "res://tests/harness.gd"
# The crews' driver on the tyre model (rally_driver.gd): a crew flies through
# a whole stage on the road, the body slides in the bends and the driver
# catches it with opposite lock.
const Stage = preload("res://scripts/stages/stage.gd")
const Handling = preload("res://scripts/traffic/rally_handling.gd")
const Motion = preload("res://scripts/cars/vehicle_motion.gd")
const Driver = preload("res://scripts/traffic/rally_driver.gd")
const Traffic = preload("res://scripts/traffic/rally_traffic.gd")
const CarRegistry = preload("res://scripts/cars/car_registry.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for index in [0, 1]:
		var stage = Stage.new(index)
		root.add_child(stage)
		var node = Node3D.new()
		root.add_child(node)
		var racer = {"node": node, "motion": Motion.new(), "launch": CarRegistry.launch(2.0)}
		var s = 2.0
		node.position = Handling.path(stage, s)
		var d = Handling.direction(stage, s)
		node.rotation.y = atan2(-d.x, -d.z)
		var dt = 1.0 / 60.0
		var frames = 0
		var off = 0
		var slip_sum = 0.0
		var slip_frames = 0
		var slip_max = 0.0
		var opposite_lock = 0
		var prev_yaw = node.rotation.y
		for frame in range(60 * 120):
			var dir = Handling.direction(stage, s)
			s = clampf(s + (node.position - Handling.path(stage, s)).dot(dir), 0.0, stage.length)
			if s >= stage.length - 3:
				break
			var ahead = minf(s + Driver.LOOK_BASE + Driver.LOOK_TIME * racer.motion.velocity.length(), stage.length - 0.01)
			var side = dir.cross(Vector3.UP).normalized()
			Driver.drive(racer, stage, Handling.path(stage, s), Handling.path(stage, ahead), side, 0.0, Traffic.competition_target(stage, s), dt)
			racer.motion.suspension(node, stage, dt, node.rotation.y, racer.motion.handling.lateral_accel)
			frames += 1
			if stage.road_distance(node.position) > stage.road_width(s) * 0.5:
				off += 1
			var rate = wrapf(node.rotation.y - prev_yaw, -PI, PI) / dt
			prev_yaw = node.rotation.y
			var slip = absf(racer.motion.handling.slip)
			slip_max = maxf(slip_max, slip)
			if absf(rate) > 0.25:
				slip_sum += slip
				slip_frames += 1
			# Opposite lock: the front wheels point out of the turn the body makes.
			if slip > 0.15 and racer.motion.handling.steering * -rate < -0.01:
				opposite_lock += 1
		var seconds = frames * dt
		check(s >= stage.length - 3 and seconds < stage.length / 12.0, "stage %d: the crew finishes on the tyre model (%.1f s)" % [index, seconds])
		check(off == 0, "stage %d: the crew stays on the road (%d frames off)" % [index, off])
		var average = rad_to_deg(slip_sum / maxf(slip_frames, 1))
		check(average > 3.0 and rad_to_deg(slip_max) > 10.0, "stage %d: the body slides in the bends (%.1f° average, %.1f° peak)" % [index, average, rad_to_deg(slip_max)])
		if index == 1:
			check(opposite_lock > 0, "stage %d: the driver catches slides with opposite lock (%d frames)" % [index, opposite_lock])
		node.free()
		stage.free()
	print("RALLY DRIVER RESULT: %d failures" % failures)
	finish()
