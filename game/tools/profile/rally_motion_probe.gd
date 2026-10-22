extends SceneTree
# Drives one crew (and one zero car on the first stage) through every stage at
# 60 FPS and prints how smooth the run is: the body's yaw acceleration, how
# often it sits at the turn-rate limit, throttle/brake reversals per minute,
# body slip in bends, peak lateral load and the host's cost per frame.
# A local check, not part of CI:
# godot --headless --path game --script res://tools/profile/rally_motion_probe.gd
const Stage = preload("res://scripts/stages/stage.gd")
class Harness:
	extends "res://scripts/core/game.gd"
	func toast(_message: String) -> void: pass
	func _play_audio(_audio: Node) -> void: pass

func _initialize() -> void:
	call_deferred("run")

func probe(index: int, role: String) -> void:
	var game = Harness.new()
	game.stage = Stage.new(index)
	root.add_child(game.stage)
	game.room = load("res://scripts/net/room.gd").new()
	game.add_child(game.room)
	game.spectators = load("res://scripts/people/spectators.gd").new()
	game.add_child(game.spectators)
	game.car = Node3D.new()
	game.car.position = Vector3(99999, 0, 99999)
	game.add_child(game.car)
	game.in_car = true
	game.rng.seed = 20261022 + index
	game.course.pass_index = 1
	var r = game._add_course_vehicle(Node3D.new(), 7 + index, "pass", 0, role)
	if role == "racer":
		r.nerve = 0.0
	r.focus = 1e9
	r.drive_speed = 10.0
	var fps = 60
	var dt = 1.0 / fps
	var prev_yaw = r.node.rotation.y
	var prev_rate = 0.0
	var prev_speed = r.drive_speed
	var prev_pos = r.node.position
	var frames = 0
	var cost = 0
	var clamp_frames = 0
	var brake_frames = 0
	var switches = 0
	var last_sign = 0
	var yaw_acc_sq = 0.0
	var yaw_acc_max = 0.0
	var slip_max = 0.0
	var slip_sum = 0.0
	var corner_frames = 0
	var speeds = 0.0
	var lat_max = 0.0
	var jerk_frames = 0
	var prev_acc = 0.0
	for frame in range(fps * 240):
		var tick = Time.get_ticks_usec()
		game._update_racers(dt)
		cost += Time.get_ticks_usec() - tick
		if r.state != "racing" or r.s >= game.stage.length - 2:
			break
		frames += 1
		var yaw = r.node.rotation.y
		var rate = wrapf(yaw - prev_yaw, -PI, PI) / dt
		if absf(rate) >= 2.5 - 0.01: clamp_frames += 1
		var yaw_acc = (rate - prev_rate) / dt
		yaw_acc_sq += yaw_acc * yaw_acc
		yaw_acc_max = maxf(yaw_acc_max, absf(yaw_acc))
		var acc = (r.drive_speed - prev_speed) / dt
		if acc <= -17.0: brake_frames += 1
		var sgn = 1 if acc > 2.0 else (-1 if acc < -2.0 else 0)
		if sgn != 0 and last_sign != 0 and sgn != last_sign: switches += 1
		if sgn != 0: last_sign = sgn
		if absf(acc - prev_acc) / dt > 200.0: jerk_frames += 1
		prev_acc = acc
		var move = r.node.position - prev_pos
		if Vector2(move.x, move.z).length() > 0.05:
			var heading = Vector2(-sin(yaw), -cos(yaw))
			var slip = absf(heading.angle_to(Vector2(move.x, move.z).normalized()))
			slip_max = maxf(slip_max, slip)
			if absf(rate) > 0.25:
				slip_sum += slip
				corner_frames += 1
		lat_max = maxf(lat_max, absf(rate) * r.drive_speed)
		speeds += r.drive_speed
		prev_yaw = yaw
		prev_rate = rate
		prev_speed = r.drive_speed
		prev_pos = r.node.position
	var seconds = frames * dt
	print("%d %-6s %-5s len=%4.0fm t=%5.1fs avg=%4.0fkm/h | yawacc rms=%5.1f max=%6.0f rad/s2 | yawclamp=%4.1f%% | maxbrake=%4.1f%% | thr<->brk=%3d (%.1f/min) | accjerk=%4.1f%% | slip corner=%4.1f° max=%4.1f° | lat max=%4.1fg | %.3f ms/frame" % [index, role, "baked" if not r.track_parts.is_empty() else "heur", game.stage.length, seconds, speeds / maxf(frames, 1) * 3.6, sqrt(yaw_acc_sq / maxf(frames, 1)), yaw_acc_max, 100.0 * clamp_frames / maxf(frames, 1), 100.0 * brake_frames / maxf(frames, 1), switches, switches / maxf(seconds / 60.0, 0.01), 100.0 * jerk_frames / maxf(frames, 1), rad_to_deg(slip_sum / maxf(corner_frames, 1)), rad_to_deg(slip_max), lat_max / 9.8, cost / 1000.0 / maxf(frames, 1)])
	game.stage.free()
	game.free()

func run() -> void:
	var count = Stage.STAGES.size()
	for i in range(count):
		probe(i, "racer")
	probe(0, "zero")
	quit()
