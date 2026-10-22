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
const Mistakes = preload("res://scripts/traffic/rally_mistakes.gd")

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
	personalities()
	for kind in ["moment", "excursion"]:
		mistake(kind)
	print("RALLY DRIVER RESULT: %d failures" % failures)
	finish()

func personalities() -> void:
	var counts = {"leader": 0, "midfield": 0, "amateur": 0}
	var pace = {"leader": 0.0, "midfield": 0.0, "amateur": 0.0}
	for id in range(1, 401):
		var driver = Mistakes.personality(id, "racer")
		counts[driver.class] += 1
		pace[driver.class] += driver.pace
	check(counts.leader > 50 and counts.midfield > 150 and counts.amateur > 80, "the field mixes leaders, midfield and amateurs (%s)" % counts)
	check(pace.leader / counts.leader > pace.midfield / counts.midfield and pace.midfield / counts.midfield > pace.amateur / counts.amateur, "leaders are quicker than the midfield, the midfield than amateurs")
	var zero = Mistakes.personality(7, "zero")
	check(zero.rate == 0.0 and zero.assist > Mistakes.CLASSES.leader.assist and zero.drift < Mistakes.CLASSES.leader.drift.x, "zero cars are tidy: firm assist, little drift, no mistakes")
	var racer = {"id": 3, "role": "racer", "s": 0.0}
	Mistakes.apply(racer)
	check(racer.next_mistake >= Mistakes.CALM_START and racer.next_mistake < INF, "a competitor's first mistake waits past the start (%.0f m)" % racer.next_mistake)

# Drive stage 1 and make the driver err in its first proper bend: a moment
# is a big slide the driver catches, a lapse into the ditch leaves the road.
func mistake(kind: String) -> void:
	var stage = Stage.new(1)
	root.add_child(stage)
	var node = Node3D.new()
	root.add_child(node)
	var racer = {"id": 2, "node": node, "motion": Motion.new(), "launch": CarRegistry.launch(2.0)}
	var s = 2.0
	node.position = Handling.path(stage, s)
	var d = Handling.direction(stage, s)
	node.rotation.y = atan2(-d.x, -d.z)
	var dt = 1.0 / 60.0
	var started = -1
	var slip_max = 0.0
	var off = 0
	for frame in range(60 * 30):
		var dir = Handling.direction(stage, s)
		s = clampf(s + (node.position - Handling.path(stage, s)).dot(dir), 0.0, stage.length)
		if s >= stage.length - 3:
			break
		var to = Handling.direction(stage, minf(s + Mistakes.BEND_SPAN, stage.length - 0.01))
		var bend = wrapf(atan2(-to.x, -to.z) - atan2(-dir.x, -dir.z), -PI, PI)
		if started < 0 and s > 100.0 and absf(bend) > 0.4:
			Mistakes.start(racer, kind, bend)
			started = frame
		var over = Mistakes.update(racer, s, bend, false, dt) if started >= 0 else 1.0
		var ahead = minf(s + Driver.LOOK_BASE + Driver.LOOK_TIME * racer.motion.velocity.length(), stage.length - 0.01)
		Driver.drive(racer, stage, Handling.path(stage, s), Handling.path(stage, ahead), dir.cross(Vector3.UP).normalized(), 0.0, Traffic.competition_target(stage, s) * over, dt)
		racer.motion.suspension(node, stage, dt, node.rotation.y, racer.motion.handling.lateral_accel)
		if started >= 0 and frame < started + 240:
			slip_max = maxf(slip_max, absf(racer.motion.handling.slip))
			if stage.road_distance(node.position) > stage.road_width(s) * 0.5 + 0.5:
				off += 1
	check(started >= 0, "%s: the crew reaches a bend to err in" % kind)
	if kind == "moment":
		check(rad_to_deg(slip_max) > 20.0 and off == 0, "a moment swings the tail out (%.0f°) and the driver catches it on the road (%d frames off)" % [rad_to_deg(slip_max), off])
	else:
		check(off > 0, "a lapse puts the car off the road (%d frames off, %.0f° slip)" % [off, rad_to_deg(slip_max)])
	node.free()
	stage.free()
