extends SceneTree
# Measures how much crews weave on straights: drives one crew per stage (and a
# zero car on the first) at 60 FPS and, wherever the road is straight for
# 40 m either way, prints the body's yaw against the road (rms and peak), the
# sideways wander off the planned line, the steering wheel's travel and how
# often the yaw rate swings from side to side.
# A local check, not part of CI:
# godot --headless --path game --script res://tools/profile/rally_weave_probe.gd
const Stage = preload("res://scripts/stages/stage.gd")
class Harness:
	extends "res://scripts/core/game.gd"
	func toast(_message: String) -> void: pass
	func _play_audio(_audio: Node) -> void: pass

func _initialize() -> void:
	call_deferred("run")

func straight(crews, s: float) -> bool:
	var a = crews.race_direction(maxf(s - 40.0, 0.0))
	var b = crews.race_direction(s)
	var c = crews.race_direction(s + 40.0)
	return a.dot(b) > 0.995 and b.dot(c) > 0.995

func probe(index: int, role: String, id: int) -> Dictionary:
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
	var r = game._add_course_vehicle(Node3D.new(), id, "pass", 0, role)
	if role == "racer":
		r.nerve = 0.0
	r.focus = 1e9
	r.drive_speed = 10.0
	var crews = game.crews
	var dt = 1.0 / 60.0
	var frames = 0
	var yaw_sq = 0.0
	var yaw_max = 0.0
	var err_sq = 0.0
	var steer_sq = 0.0
	var swings = 0
	var last_sign = 0
	var prev_yaw = r.node.rotation.y
	var speed_sum = 0.0
	for frame in range(60 * 240):
		game._update_racers(dt)
		if r.state in ["stranded", "stopped"] or r.s >= game.stage.length - 2:
			break
		var yaw = r.node.rotation.y
		var rate = wrapf(yaw - prev_yaw, -PI, PI) / dt
		prev_yaw = yaw
		if r.state != "racing" or r.has("mistake") or r.s < 80.0 or r.drive_speed < 15.0:
			continue
		if not straight(crews, r.s):
			continue
		var road = crews.race_direction(r.s)
		var rel = wrapf(yaw - atan2(-road.x, -road.z), -PI, PI)
		frames += 1
		yaw_sq += rel * rel
		yaw_max = maxf(yaw_max, absf(rel))
		err_sq += float(r.slide) * float(r.slide)
		var steer = float(r.motion.handling.steering)
		steer_sq += steer * steer
		speed_sum += r.drive_speed
		var sgn = 1 if rate > 0.05 else (-1 if rate < -0.05 else 0)
		if sgn != 0 and last_sign != 0 and sgn != last_sign:
			swings += 1
		if sgn != 0:
			last_sign = sgn
	var seconds = frames * dt
	var out = {"frames": frames, "yaw": rad_to_deg(sqrt(yaw_sq / maxf(frames, 1))), "yaw_max": rad_to_deg(yaw_max), "err": sqrt(err_sq / maxf(frames, 1)), "steer": rad_to_deg(sqrt(steer_sq / maxf(frames, 1))), "swings": swings / maxf(seconds, 0.01), "speed": speed_sum / maxf(frames, 1) * 3.6}
	print("%d %-5s id=%2d %-8s straight=%5.1fs v=%4.0fkm/h | yaw vs road rms=%4.2f° max=%5.2f° | off line rms=%4.2fm | wheel rms=%4.2f° | yaw swings %4.2f/s" % [index, role, id, r.get("class", "?"), seconds, out.speed, out.yaw, out.yaw_max, out.err, out.steer, out.swings])
	game.stage.free()
	game.free()
	return out

func run() -> void:
	var ids = [3, 7, 11, 18]
	var args = OS.get_cmdline_user_args()
	var stages = range(Stage.STAGES.size())
	if args.size() > 0:
		stages = [int(args[0])]
	var total = {"yaw": 0.0, "yaw_max": 0.0, "err": 0.0, "swings": 0.0}
	var n = 0
	for i in stages:
		for id in ids:
			var o = probe(i, "racer", id + i)
			if o.frames > 0:
				n += 1
				for k in total: total[k] += o[k]
	probe(0, "zero", 7)
	print("MEAN yaw rms=%.2f° yaw max=%.2f° off line=%.2fm swings=%.2f/s over %d runs" % [total.yaw / n, total.yaw_max / n, total.err / n, total.swings / n, n])
	quit()
