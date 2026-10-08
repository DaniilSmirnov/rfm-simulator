extends SceneTree
const Stage = preload("res://scripts/stage.gd")
const Handling = preload("res://scripts/rally_handling.gd")
class Harness:
	extends "res://scripts/game.gd"
	func toast(_message: String) -> void: pass
	func _play_audio(_audio: Node) -> void: pass
var failures = 0
func check(ok: bool, text: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + text)
	if not ok: failures += 1
func _initialize() -> void:
	call_deferred("run")
func drive(fps: int, reverse: bool = false) -> Dictionary:
	var game = Harness.new()
	game.stage = Stage.new(2)
	root.add_child(game.stage)
	game.stage.city = load("res://scripts/vineyard.gd").new()
	game.stage.city.stage = game.stage
	game.stage.add_child(game.stage.city)
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
	var r = game._add_course_vehicle(Node3D.new(), 1, "pass", 0)
	game.course.pass_index = 2 if reverse else 1
	r.s = 330.0 if reverse else 350.0
	r.focus = 800
	r.drive_speed = 12.0
	r.node.position = game.race_at(r.s)
	r.node.rotation.y = atan2(-game.race_direction(r.s).x, -game.race_direction(r.s).z)
	var smooth = true
	var measured = true
	var slide = 0.0
	var worst = 0.0
	for frame in range(fps * 25):
		var before: Vector3 = r.node.position
		var yaw: float = r.node.rotation.y
		var speed: float = r.drive_speed
		game._update_racers(1.0 / fps)
		if r.state != "racing":
			print("DEPARTURE s=", r.s, " slide=", r.slide)
			break
		smooth = smooth and absf(wrapf(r.node.rotation.y - yaw, -PI, PI)) <= 2.5 / fps + 0.001 and absf(r.drive_speed - speed) <= 18.0 / fps + 0.001
		var movement: Vector3 = r.node.position - before
		var velocity = Vector2(movement.x, movement.z).length() * fps
		if velocity - r.drive_speed > worst:
			worst = velocity - r.drive_speed
			if worst > 5: print("SPEED s=",r.s," measured=",velocity," target=",r.drive_speed," slide=",r.slide)
		measured = measured and velocity < r.drive_speed * 1.3 + 1.0
		slide = maxf(slide, absf(r.slide))
	check(smooth, "heading and acceleration are bounded at %d FPS" % fps)
	check(measured, "world-space speed matches intended speed at %d FPS" % fps)
	check(r.state == "racing" and r.s > 400, "crew negotiates village junctions at %d FPS" % fps)
	check(slide > 0.02, "lateral slide remains active at %d FPS" % fps)
	var result = {"pos": r.node.position, "s": r.s}
	game.stage.free()
	game.free()
	return result
func run() -> void:
	drive(60, true)
	var stage = Stage.new(2)
	var inside_road = true
	var worst_distance = 0.0
	for i in range(1480, 2001):
		var station = i * 0.25
		var distance = stage.road_distance(Handling.path(stage, station))
		worst_distance = maxf(worst_distance, distance)
		inside_road = inside_road and distance < stage.road_width(station) * 0.5
	check(inside_road, "rounded driving line stays inside village road (maximum %.2f m)" % worst_distance)
	stage.free()
	var low = drive(24)
	var normal = drive(60)
	var high = drive(144)
	check(low.pos.distance_to(normal.pos) < 1.0 and high.pos.distance_to(normal.pos) < 1.0, "trajectory agrees across render frame rates")
	print("Rally smoothness failures: ", failures)
	quit(1 if failures else 0)
