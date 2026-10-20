extends SceneTree
# Whole-frame cost and hitches during a race, with the real main loop:
#   godot --headless --fixed-fps 60 --path game --script res://tools/profile/profile_frames.gd -- <stage> [drive|walk] [frames]
# Add `-d --profiling` before --headless for per-function script time (the
# local debugger prints one frame per second; sum them over the run).
# The player drives along the road (or walks and looks around) while 8 crews
# race. --fixed-fps gives every frame one 1/60 s step and no real-time wait,
# so the wall time of a frame is what it costs. Prints mean/p50/p95/p99/max,
# frames over 16.7/33/50 ms, the slowest frames with their process/physics
# split, and how many props are awake. See docs/CPU_PERFORMANCE.md.
const WARMUP = 60

var game: Node
var mode := "drive"
var frames := 900
var started := false
var frame := 0
var last := 0
var samples: Array = []
var slow: Array = []
var nodes_before := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args = OS.get_cmdline_user_args()
	var stage_index = int(args[0]) if args.size() > 0 else 0
	mode = args[1] if args.size() > 1 else "drive"
	frames = int(args[2]) if args.size() > 2 else 900
	root.size = Vector2i(1280, 720)
	game = load("res://main.tscn").instantiate()
	game.defer_world = true
	root.add_child(game)
	await process_frame
	game.room.set_process(false)
	game.select_stage(stage_index)
	game.rng.seed = 20261008
	var load_started = Time.get_ticks_msec()
	await game.start_game()
	print("FRAME_PROFILE load_ms=", Time.get_ticks_msec() - load_started)
	game.course.phase = "racing"
	game.spawn_clock = 999.0
	for i in range(8):
		game.spawn_racer("pass")
		var racer = game.racers.back()
		racer.s = 20.0 + i * 70.0
		racer.node.position = game.race_at(racer.s)
	game.in_car = mode != "walk"
	if game.in_car:
		var s = 260.0
		game.car.position = game.stage.at(s)
		game.car.position.y = game.stage.ground(game.car.position) + 0.3
		var heading = game.stage.direction(s)
		game.car.rotation.y = atan2(-heading.x, -heading.z)
	nodes_before = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	started = true

func _process(_delta: float) -> bool:
	if not started:
		return false
	_steer()
	var now = Time.get_ticks_usec()
	if last > 0 and frame >= WARMUP:
		var wall = now - last
		samples.append(wall)
		var process_us = Performance.get_monitor(Performance.TIME_PROCESS) * 1000000.0
		var physics_us = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000000.0
		slow.append([wall, frame, int(process_us), int(physics_us)])
	last = now
	frame += 1
	if frame >= WARMUP + frames:
		_report()
		return true
	return false

# A crude autopilot: aim 14 m down the road, hold a moderate speed.
func _steer() -> void:
	if not game.in_car:
		Input.action_press("forward", 0.8)
		game.view_yaw += 0.01
		return
	var car: Node3D = game.car
	var s = game.stage.road_s(car.global_position)
	var to_target: Vector3 = game.stage.at(s + 14.0) - car.global_position
	var lateral = to_target.normalized().dot(car.global_basis.x)
	Input.action_release("left")
	Input.action_release("right")
	if absf(lateral) > 0.05:
		Input.action_press("right" if lateral > 0 else "left", clampf(absf(lateral) * 3.0, 0.0, 1.0))
	if absf(game.speed) < 14.0:
		Input.action_press("forward")
	else:
		Input.action_release("forward")

func _report() -> void:
	var sorted = samples.duplicate()
	sorted.sort()
	var total = 0.0
	for value in sorted:
		total += value
	var count = sorted.size()
	var over = [0, 0, 0]
	for value in sorted:
		if value > 16667: over[0] += 1
		if value > 33333: over[1] += 1
		if value > 50000: over[2] += 1
	print("FRAME_PROFILE stage=%d mode=%s frames=%d mean_ms=%.2f p50=%.2f p95=%.2f p99=%.2f max=%.2f over16=%d over33=%d over50=%d nodes=%d->%d" % [
		game.stage.variant, mode, count, total / count / 1000.0, sorted[count / 2] / 1000.0,
		sorted[int(count * 0.95)] / 1000.0, sorted[int(count * 0.99)] / 1000.0, sorted[count - 1] / 1000.0,
		over[0], over[1], over[2], nodes_before, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	slow.sort_custom(func(a, b): return a[0] > b[0])
	var text = "FRAME_SLOWEST"
	for entry in slow.slice(0, 8):
		text += " f%d:%.1fms(proc %.1f phys %.1f)" % [entry[1], entry[0] / 1000.0, entry[2] / 1000.0, entry[3] / 1000.0]
	print(text)
	# Awake props cost a physics body each and collision queries for everyone.
	var awake: Dictionary = {}
	var bodies = 0
	for body in game.find_children("PropBody*", "RigidBody3D", true, false):
		bodies += 1
		if body.moving:
			var key = str(body.record.key).get_slice(":", 0)
			awake[key] = awake.get(key, 0) + 1
	print("FRAME_PROPS bodies=%d awake=%s" % [bodies, awake])
