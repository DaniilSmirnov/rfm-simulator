extends SceneTree
const Rejoin = preload("res://scripts/rally_rejoin.gd")
const Traffic = preload("res://scripts/rally_traffic.gd")
const Stage = preload("res://scripts/stage.gd")
class Harness:
	extends "res://scripts/game.gd"
	func toast(_message: String) -> void: pass
	func _play_audio(_audio: Node) -> void: pass
var failures = 0
func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok: failures += 1
func _initialize() -> void: call_deferred("run")
func scenario(reverse: bool, backwards: bool = false, speed: float = 0.0, fps: int = 60, role: String = "racer") -> void:
	var game = Harness.new()
	game.stage = Stage.new(2)
	root.add_child(game.stage)
	game.room = load("res://scripts/room.gd").new()
	game.add_child(game.room)
	game.spectators = load("res://scripts/spectators.gd").new()
	game.add_child(game.spectators)
	game.car = Node3D.new()
	game.car.position = Vector3(-170, 2, 5)
	game.add_child(game.car)
	game.rally_audio = AudioStreamPlayer3D.new()
	game.add_child(game.rally_audio)
	game.in_car = true
	game.rng.seed = 20261009
	var r = game._add_course_vehicle(Node3D.new(), 1, "pass", 0, role)
	game.course.pass_index = 2 if reverse else 1
	r.s = 100.0
	r.focus = 5000
	r.drive_speed = 12.0
	r.node.position = game.race_at(r.s)
	r.node.rotation.y = atan2(-game.race_direction(r.s).x, -game.race_direction(r.s).z)
	if not reverse and not backwards and speed == 0 and fps == 60 and role == "racer":
		var maximum = 0.0
		for station in range(20, 820, 2):
			r.s = station
			r.node.position = game.race_at(r.s)
			maximum = maxf(maximum, absf(Traffic.corner_line(game, r, 0.0)))
		check(maximum > Stage.WIDTH * 0.5, "corner cuts can use the shoulder (%.2f m)" % maximum)
		r.s = 100.0
		r.node.position = game.race_at(r.s)
		var goal: Vector3 = game.race_at(112)
		game.car.position = r.node.position.lerp(goal, 0.5)
		check(not Rejoin.clear(game, r, r.node.position, goal), "return waits for a blocked corridor")
		game.car.position = Vector3(-170, 2, 5)
		var rock_position: Vector3 = r.node.position.lerp(goal, 0.5)
		rock_position.y = game.stage.ground(rock_position)
		game.stage.rocks.append({"pos": rock_position, "radius": 1.5, "height": 2.0})
		check(not Rejoin.clear(game, r, r.node.position, goal), "return avoids rocks")
		game.stage.rocks.clear()
		r.recovery_helpers = 1
		r.self_rejoin = true
		check(not Rejoin.step(game, r, 1.0 / 120) and not r.self_rejoin, "player assistance takes priority")
		r.recovery_helpers = 0
	r.node.position += game.race_side(r.s) * 7.0
	r.node.position.y = game.stage.ground(r.node.position) + 0.06
	if backwards: r.node.rotation.y += PI
	r.motion.velocity = game.race_direction(r.s) * speed
	r.kind = "crash"
	r.state = "offroad"
	r.age = 1.0
	r.self_rejoin = true
	var max_step = 0.0
	var reversed = false
	for frame in range(fps * 30):
		var previous: Vector3 = r.node.position
		game._update_racers(1.0 / fps)
		max_step = maxf(max_step, previous.distance_to(r.node.position))
		var forward = Vector3(-sin(r.node.rotation.y), 0, -cos(r.node.rotation.y))
		reversed = reversed or r.motion.velocity.dot(forward) < -0.1
		if r.state == "racing": break
	check(r.state == "racing", "self return reverse=%s backwards=%s (state=%s)" % [reverse, backwards, r.state])
	if r.state == "racing":
		for frame in range(3):
			var previous: Vector3 = r.node.position
			game._update_racers(1.0 / fps)
			max_step = maxf(max_step, previous.distance_to(r.node.position))
	check(max_step < maxf(0.6, speed / fps + 0.15), "return has no teleport")
	check(game.helped == 0, "self return does not count player assistance")
	if backwards: check(reversed, "driver uses reverse gear")
	game.free()
func run() -> void:
	scenario(false)
	scenario(true)
	scenario(false, true)
	scenario(false, false, 18.0, 24)
	scenario(true, false, 18.0, 144)
	scenario(false, false, 0.0, 60, "zero")
	check(not Rejoin.eligible({"kind": "stuck"}), "stuck crews still need assistance")
	print("Rally rejoin failures: ", failures)
	quit(failures)
