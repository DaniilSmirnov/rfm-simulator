extends "res://tests/harness.gd"
# The chase camera stays in front of tent roofs and conifer crowns between it
# and the car, and a fan getting out does not put his head inside a crown.
const ViewClearance = preload("res://scripts/player/view_clearance.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	await game.start_game()
	var stage = game.stage

	# The first frames in the service park: nothing between the car and the camera.
	game.in_car = true
	var body: Node3D = game.rides.vehicle()
	game.camera.position = body.position + Vector3(0, 30, 0)
	for i in range(90):
		game.player.update_camera(1.0 / 30.0)
	var pivot = body.position + Vector3(0, 1.1, 0)
	check(stage.solids.hit(pivot, game.camera.position, 0.2, false, Vector3.ZERO, body).is_empty(), "no service solid between the car and the camera")
	check(ViewClearance.crown_fraction(stage, pivot, game.camera.position) >= 1.0, "no crown between the car and the camera")

	# A tent roof: the camera above it comes down in front of it.
	var roof = {}
	for object in stage.solids.obstacles:
		if object.kind == "service" and object.half.y < 0.1 and object.half.x > 1.0:
			roof = object
			break
	check(not roof.is_empty(), "the service park has a tent roof")
	var top: Vector3 = roof.body.global_position
	var under = top + Vector3(0, -2.4, 0)
	var above = top + Vector3(0.5, 3.0, 0.5)
	var seen = ViewClearance.clear_view(stage, under, above, body)
	check(seen.y < top.y - 0.1 and seen.distance_to(under) < under.distance_to(above), "the camera stops under the tent roof")
	# The chase camera does not settle inside its own car when the roof is that close: it rises around it.
	var reach = 3.5
	var chase = ViewClearance.chase_view(stage, under, above, body, reach)
	check(chase.distance_to(under) >= reach - 0.01, "the chase camera keeps out of the car body under a roof")

	# A standing conifer: a camera behind its crown is pulled in front of it.
	var tree = -1
	for i in range(stage.trees.size()):
		if not stage.fallen.has(i) and float(stage.forest_data[i].height) > 10.0:
			tree = i
			break
	check(tree >= 0, "the stage has a tall standing conifer")
	var base: Vector3 = stage.trees[tree]
	var height = float(stage.forest_data[tree].height)
	var from = base + Vector3(height * 0.6, height * 0.4, 0)
	var to = base + Vector3(-height * 0.6, height * 0.4, 0)
	var pulled = ViewClearance.clear_view(stage, from, to)
	var lifted = ViewClearance.chase_view(stage, from, to, null, 3.5)
	check(lifted.distance_to(from) >= 3.49, "behind a crown the chase camera stays a car's length away")
	check(pulled.distance_to(from) < from.distance_to(to) * 0.5, "the camera is pulled in front of the crown")
	check(not ViewClearance.in_crown(base, height, pulled, 0.0), "the pulled camera is outside the crown")
	var sky = base + Vector3(0, height * 2.0, 0)
	check(ViewClearance.clear_view(stage, sky, sky + Vector3(6, 0, 0)) == sky + Vector3(6, 0, 0), "an open view is kept as is")

	# Getting out: the side with low branches at eye height gives way to the other.
	var small = -1
	for i in range(stage.trees.size()):
		if not stage.fallen.has(i) and float(stage.forest_data[i].height) < 7.0:
			small = i
			break
	check(small >= 0, "the stage has a small conifer")
	var foot: Vector3 = stage.trees[small]
	var inside = foot + Vector3(0.6, 0, 0)
	check(ViewClearance.eyes_in_crown(stage, Vector3(inside.x, stage.walking_ground(inside), inside.z)), "next to a small conifer the head is in its branches")
	var outside = foot + Vector3(6.0, 0, 0)
	var spot = ViewClearance.exit_spot(stage, [inside, outside])
	var expected = inside if ViewClearance.eyes_in_crown(stage, Vector3(outside.x, stage.walking_ground(outside), outside.z)) else outside
	check(Vector2(spot.x, spot.z).distance_to(Vector2(expected.x, expected.z)) < 0.01, "the fan gets out on the side where his head is clear")
	finish()
