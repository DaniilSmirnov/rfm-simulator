extends "res://tests/harness.gd"
const Tracks = preload("res://scripts/rally_tracks.gd")
const Stage = preload("res://scripts/stage.gd")
class Harness:
	extends "res://scripts/game.gd"
	func toast(_message: String) -> void: pass
	func _play_audio(_audio: Node) -> void: pass
func _initialize() -> void:
	call_deferred("run")
func harness(reverse: bool = false):
	var game = Harness.new()
	game.stage = Stage.new(2)
	root.add_child(game.stage)
	game.room = load("res://scripts/room.gd").new()
	game.add_child(game.room)
	game.spectators = load("res://scripts/spectators.gd").new()
	game.add_child(game.spectators)
	game.car = Node3D.new()
	game.car.position = Vector3(-300, 2, 100)
	game.add_child(game.car)
	game.rally_audio = AudioStreamPlayer3D.new()
	game.add_child(game.rally_audio)
	game.in_car = true
	game.course.pass_index = 2 if reverse else 1
	game.rng.seed = 12345
	return game
func full_run(parts: PackedInt32Array, reverse: bool, fps: int, role: String = "racer") -> Dictionary:
	var game = harness(reverse)
	var racer = game._add_course_vehicle(Node3D.new(), 1, "pass", 0, role)
	racer.track_parts = parts
	racer.drive_speed = 8.0
	racer.focus = 5000.0
	var max_yaw_rate = 0.0
	var max_acceleration = 0.0
	var max_speed_error = 0.0
	var frames = 0
	var start = Time.get_ticks_usec()
	while not game.racers.is_empty() and racer.state == "racing" and frames < fps * 180:
		var position: Vector3 = racer.node.position
		var yaw: float = racer.node.rotation.y
		var speed: float = racer.drive_speed
		game._update_racers(1.0 / fps)
		max_yaw_rate = maxf(max_yaw_rate, absf(wrapf(racer.node.rotation.y-yaw, -PI, PI))*fps)
		max_acceleration = maxf(max_acceleration, absf(racer.drive_speed-speed)*fps)
		var movement: Vector3 = racer.node.position-position
		max_speed_error = maxf(max_speed_error, Vector2(movement.x,movement.z).length()*fps-racer.drive_speed)
		frames += 1
	check(racer.s >= 839.0 and racer.state == "racing", "mixed run reaches finish: reverse=%s fps=%d role=%s (s=%.1f state=%s)" % [reverse, fps, role, racer.s, racer.state])
	check(max_yaw_rate <= 2.501 and max_acceleration <= 18.01 and max_speed_error < 2.0, "mixed playback bounds yaw/acceleration/world speed (%.3f/%.3f/%.3f)" % [max_yaw_rate,max_acceleration,max_speed_error])
	var result = {"time":frames / float(fps), "cost_ms":(Time.get_ticks_usec()-start)/1000.0 / maxf(frames,1)}
	game.stage.free()
	game.free()
	return result
func run() -> void:
	var stage = Stage.new(2)
	check(Tracks.available(stage) and Tracks.BANK.runs.size() == 10, "five baked runs have forward and reverse recordings matching village geometry")
	var other = Stage.new(0)
	var rng = RandomNumberGenerator.new()
	rng.seed = 123
	check(Tracks.choose(other,rng,"racer").is_empty() and Tracks.choose(stage,rng,"safety").is_empty(), "other stages and safety convoy retain existing movement")
	var seeded = Tracks.choose(stage,rng,"racer")
	rng.seed = 123
	check(seeded == Tracks.choose(stage,rng,"racer"), "four-part random selection is reproducible from host seed")
	var combinations = {}
	for i in range(100): combinations[str(Tracks.choose(stage,rng,"racer"))] = true
	check(combinations.size() > 70, "independent quarters produce diverse combinations")
	var valid = true
	var distinct = true
	var min_speed = INF
	var max_speed = 0.0
	var max_slip = 0.0
	for reverse in [false,true]:
		for run in range(5):
			var parts = PackedInt32Array([run,run,run,run])
			for station in range(841):
				var row = Tracks.sample(parts,station,reverse)
				valid = valid and is_finite(row.line) and is_finite(row.speed) and is_finite(row.yaw) and row.metric >= 0.2 and row.speed > 0 and row.speed <= 140.0/3.6+0.001
				min_speed = minf(min_speed,row.speed)
				max_speed = maxf(max_speed,row.speed)
				max_slip = maxf(max_slip,absf(row.yaw))
			if run > 0:
				distinct = distinct and absf(Tracks.sample(parts,120,reverse).line - Tracks.sample(PackedInt32Array([0,0,0,0]),120,reverse).line) > 0.1
	check(valid and distinct, "recordings are finite, bounded and use distinct road lines")
	check(min_speed < 9 and max_speed > 37 and max_slip > 0.15, "bank includes slow corners, full-speed straights and visible body slip")
	var seams_smooth = true
	var worst = Vector3.ZERO
	for reverse in [false,true]:
		var cuts = Tracks.BANK.reverse_cuts if reverse else Tracks.BANK.cuts
		var blends = Tracks.BANK.reverse_blends if reverse else Tracks.BANK.blends
		for left in range(5):
			for right in range(5):
				for seam in range(3):
					var parts = PackedInt32Array([left,left,left,left])
					parts[seam+1] = right
					var s: float = cuts[seam]
					for edge in [blends[seam*2], s, blends[seam*2+1]]:
						var a = Tracks.sample(parts,edge-0.001,reverse)
						var b = Tracks.sample(parts,edge+0.001,reverse)
						worst = Vector3(maxf(worst.x,absf(a.line-b.line)), maxf(worst.y,absf(a.speed-b.speed)), maxf(worst.z,absf(a.yaw-b.yaw)))
						seams_smooth = seams_smooth and absf(a.line-b.line)<0.01 and absf(a.speed-b.speed)<0.05 and absf(a.yaw-b.yaw)<0.01
	check(seams_smooth, "all 25 pairings at all quarter seams are continuous: %s" % worst)
	stage.points[20].x += 1.0
	stage.remove_meta("rally_tracks_valid")
	check(not Tracks.available(stage), "stale route recordings are rejected when village geometry changes")
	stage.free()
	other.free()
	for profile in range(5):
		full_run(PackedInt32Array([profile,(profile+1)%5,(profile+3)%5,(profile+2)%5]),false,60)
	full_run(PackedInt32Array([4,0,3,1]),true,60)
	full_run(PackedInt32Array([4,0,3,1]),false,60,"zero")
	var low = full_run(PackedInt32Array([4,0,3,1]),false,24)
	var high = full_run(PackedInt32Array([4,0,3,1]),false,144)
	check(absf(low.time-high.time)<0.25, "mixed playback travel time agrees at 24 and 144 FPS")
	print("TRACK_PLAYBACK_CPU_MS low=",low.cost_ms," high=",high.cost_ms," (headless, not device FPS)")
	print("RALLY TRACKS RESULT: %d failures" % failures)
	finish()
