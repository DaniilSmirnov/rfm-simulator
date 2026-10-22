extends SceneTree
# Feasibility probe for rally_driver.gd: one crew per stage on the tyre model.
# godot --headless --path game --script res://tools/profile/rally_physics_probe.gd -- [--assist=G] [--slip=RAD]
const Stage = preload("res://scripts/stages/stage.gd")
const Handling = preload("res://scripts/traffic/rally_handling.gd")
const Motion = preload("res://scripts/cars/vehicle_motion.gd")
const Driver = preload("res://scripts/traffic/rally_driver.gd")
const Traffic = preload("res://scripts/traffic/rally_traffic.gd")
const CarRegistry = preload("res://scripts/cars/car_registry.gd")

var assist = 1.0
var max_slip = 0.45

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--assist="): assist = arg.trim_prefix("--assist=").to_float()
		if arg.begins_with("--slip="): max_slip = arg.trim_prefix("--slip=").to_float()
	call_deferred("run")

func probe(index: int) -> void:
	var stage = Stage.new(index)
	root.add_child(stage)
	var node = Node3D.new()
	root.add_child(node)
	var racer = {"node": node, "motion": Motion.new(), "launch": CarRegistry.launch(2.0), "assist": assist, "max_slip": max_slip}
	var s = 2.0
	node.position = Handling.path(stage, s)
	var d = Handling.direction(stage, s)
	node.rotation.y = atan2(-d.x, -d.z)
	var dt = 1.0 / 60.0
	var prev_yaw = node.rotation.y
	var prev_rate = 0.0
	var yaw_acc_sq = 0.0
	var frames = 0
	var slip_sum = 0.0
	var slip_n = 0
	var slip_max = 0.0
	var off = 0
	var worst = 0.0
	var err_max = 0.0
	var err_sq = 0.0
	var cost = 0
	var finished = false
	for frame in range(60 * 240):
		var tick = Time.get_ticks_usec()
		# Track the car's own station along the road.
		var dir = Handling.direction(stage, s)
		s = clampf(s + (node.position - Handling.path(stage, s)).dot(dir), 0.0, stage.length)
		if s >= stage.length - 3:
			finished = true
			break
		var v = racer.motion.velocity.length()
		var target = Traffic.competition_target(stage, s)
		var ahead = minf(s + Driver.LOOK_BASE + Driver.LOOK_TIME * v, stage.length - 0.01)
		var side = Handling.direction(stage, s).cross(Vector3.UP).normalized()
		var error = Driver.drive(racer, stage, Handling.path(stage, s), Handling.path(stage, ahead), side, 0.0, target, dt)
		racer.motion.suspension(node, stage, dt, node.rotation.y, racer.motion.handling.lateral_accel)
		cost += Time.get_ticks_usec() - tick
		frames += 1
		var rate = wrapf(node.rotation.y - prev_yaw, -PI, PI) / dt
		yaw_acc_sq += pow((rate - prev_rate) / dt, 2)
		prev_rate = rate
		prev_yaw = node.rotation.y
		var slip = absf(racer.motion.handling.slip)
		slip_max = maxf(slip_max, slip)
		if absf(rate) > 0.25:
			slip_sum += slip
			slip_n += 1
		if absf(error) > 4.0 and err_max <= 4.0:
			print("  stage %d leaves its line at s=%.0f v=%.1f target=%.1f grip=%.2f" % [index, s, v, target, stage.grip(node.position)])
		err_max = maxf(err_max, absf(error))
		err_sq += error * error
		var gap = stage.road_distance(node.position) - stage.road_width(s) * 0.5
		if gap > 0.0: off += 1
		worst = maxf(worst, gap)
	print("%d finished=%s t=%5.1fs | yawacc rms=%5.1f | slip corner=%4.1f° max=%4.1f° | line err rms %.2f max %.1fm | off-road %4.1f%% worst %.1fm | %.3f ms/frame" % [index, finished, frames / 60.0, sqrt(yaw_acc_sq / maxf(frames, 1)), rad_to_deg(slip_sum / maxf(slip_n, 1)), rad_to_deg(slip_max), sqrt(err_sq / maxf(frames, 1)), err_max, 100.0 * off / maxf(frames, 1), worst, cost / 1000.0 / maxf(frames, 1)])
	node.free()
	stage.free()

func run() -> void:
	for i in range(Stage.STAGES.size()):
		probe(i)
	quit()
