extends SceneTree
const Stage = preload("res://scripts/stage.gd")
const Village = preload("res://scripts/vineyard.gd")
var failures = 0
var walking_game: Node3D
var render_fps = 60.0
func check(ok: bool, title: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + title)
	if not ok: failures += 1
func _initialize() -> void:
	call_deferred("run")
func route(city, pose: Transform3D, points: Array) -> bool:
	var current: Vector3 = pose * points[0]
	current.y = city.walking_floor(current, current.y)
	for i in range(1, points.size()):
		var target: Vector3 = pose * points[i]
		var start = current
		var steps = ceili(Vector2(target.x-start.x, target.z-start.z).length() / (4.3 / render_fps))
		for step in range(1, steps + 1):
			var next = start.lerp(target, float(step) / steps)
			next.y = city.walking_floor(next, current.y)
			if absf(next.y - current.y) > 0.45 or not city.hit(current, next, 0.3).is_empty():
				print("BLOCKED ", pose.affine_inverse() * current, " -> ", pose.affine_inverse() * next)
				return false
			if walking_game != null:
				var direction = Vector3(next.x-current.x, 0, next.z-current.z)
				walking_game.walker = current
				walking_game.view_yaw = atan2(-direction.x, -direction.z)
				Input.action_press("forward")
				walking_game._walk(direction.length() / walking_game.WALK_SPEED)
				Input.action_release("forward")
				if walking_game.walker.distance_to(next) > 0.03:
					print("WALK MISMATCH ", walking_game.walker, " expected ", next)
					return false
			current = next
	return absf(current.y - (pose * points.back()).y) < 0.2
func run() -> void:
	var stage = Stage.new(2)
	root.add_child(stage)
	var city = Village.new()
	city.stage = stage
	stage.city = city
	stage.add_child(city)
	city._church(stage.village_main_at(435.0) + stage.village_main_side(435.0) * 43.0)
	city._side_lane_houses()
	check(city.viewpoints.size() == 3, "church and exactly two existing side-lane houses offer viewpoints")
	for action in ["forward", "back", "left", "right", "sprint"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	walking_game = load("res://scripts/game.gd").new()
	walking_game.stage = stage
	walking_game.in_car = false
	walking_game.car = Node3D.new()
	walking_game.car.position = Vector3(1000, 0, 1000)
	walking_game.add_child(walking_game.car)
	walking_game.spectators = load("res://scripts/spectators.gd").new()
	walking_game.add_child(walking_game.spectators)
	walking_game.room = load("res://scripts/room.gd").new()
	walking_game.add_child(walking_game.room)
	var church = stage.get_node("VillageChurch")
	var path: Array = [Vector3(0, 0.1, -16), Vector3(0, 0.1, -13.1), Vector3(-1.45, 0.1, -13.1)]
	for flight in range(10):
		var forward = flight % 2 == 0
		var x = -1.45 if forward else 1.45
		var z = -9.2 if forward else -13.2
		var y = 0.1 + (flight + 1) * 2.4
		path.append(Vector3(x, y, z))
		if flight < 9:
			path.append(Vector3(-x, y, z))
	path.append(Vector3(-1, 24.1, -13.2))
	path.append(Vector3(-1, 24.1, -11.1))
	for fps in [24.0, 60.0, 144.0]:
		render_fps = fps
		check(route(city, church.transform, path), "actual walking climbs ten tower flights at %d FPS" % fps)
	var reverse = path.duplicate()
	reverse.reverse()
	check(route(city, church.transform, reverse), "walk back down tower without jumps or teleportation")
	check(route(city, church.transform, [Vector3(0, 0.1, -16), Vector3(0, 0.1, 7)]), "church entrance and central aisle are open")
	for view in city.viewpoints:
		if view.kind != "roof": continue
		var house_path: Array = [Vector3(0, 0.1, -5), Vector3(0, 0.1, -3.1), Vector3(2, 0.1, -3.1), Vector3(2, 3.1, 3.35), Vector3(0, 3.1, 3.35), Vector3(0, 6.1, -3.35), Vector3(2.2, 6.1, -3.35), Vector3(2.2, 6.1, -2)]
		check(route(city, view.pose, house_path), "house entrance and both stair flights lead to roof")
		house_path.reverse()
		check(route(city, view.pose, house_path), "roof has a usable return route")
		check(not city._point_clear_of_obstacles(view.pose * Vector3(0.5, 0, 0.5)), "interior footprint rejects generated grass stones and trees")
		var underneath: Vector3 = view.pose * Vector3(2.2, 0.1, -2)
		check(city.walking_floor(underneath, underneath.y) < underneath.y + 0.45, "ground-floor walker cannot snap to the roof")
		var edge: Vector3 = view.pose * Vector3(3.3, 6.1, -2)
		var outside: Vector3 = view.pose * Vector3(4.2, 6.1, -2)
		check(not city.hit(edge, outside, 0.3).is_empty(), "roof balustrade prevents walking off the edge")
	var roof_view = city.viewpoints[1]
	walking_game.walker = roof_view.position
	walking_game.playing = true
	check(walking_game.jump(), "player can jump from a rooftop floor")
	walking_game._walk(0.2)
	check(walking_game.jump_height > 0.6, "rooftop jump rises above the floor")
	walking_game._walk(0.6)
	check(walking_game.jump_height == 0 and absf(walking_game.walker.y - roof_view.position.y) < 0.01, "rooftop jump lands on the same floor")
	walking_game.walker = roof_view.pose * Vector3(5, 6.1, -2)
	var fall_start = walking_game.walker.y
	walking_game._walk(1.0 / 60)
	check(walking_game.walker.y < fall_start and walking_game.walker.y > stage.ground(walking_game.walker) + 4, "leaving an elevated surface starts a fall instead of snapping down")
	walking_game._walk(1.0)
	check(walking_game.jump_height == 0, "falling player lands on terrain")
	var deck: Vector3 = church.transform * Vector3(-1, 24.1, -11.1)
	check(is_equal_approx(stage.ground(deck), stage.ground(Vector3(deck.x, 0, deck.z))), "elevated walking floors do not change vehicle terrain")
	walking_game.free()
	stage.queue_free()
	await process_frame
	print("Village viewpoints failures: ", failures)
	quit(1 if failures else 0)
