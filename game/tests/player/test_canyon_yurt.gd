extends "res://tests/harness.gd"
# The guest yurt of the steppe camp on «Чарынский каньон»: its door stands
# open, a fan walks in onto the felt floor, the round wall holds them inside,
# and the room is furnished.
const Interior = preload("res://scripts/stages/canyon/yurt_interior.gd")

func _initialize() -> void:
	call_deferred("run")

func walk_to(game, target: Vector3, seconds: float) -> void:
	Input.action_press("forward")
	for i in range(int(seconds * 30.0)):
		var to = target - game.walker
		to.y = 0
		if to.length() < 0.15:
			break
		game.view_yaw = atan2(-to.x, -to.z)
		game.player.walk(1.0 / 30.0)
	Input.action_release("forward")

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.select_stage(3)
	await game.start_game()
	game.in_car = false
	var stage = game.stage
	var camp: Node3D = stage.get_node_or_null("SteppeYurtCamp")
	var guest: Node3D = camp.get_node_or_null("GuestYurt") if camp != null else null
	check(guest != null, "the steppe camp has a guest yurt with its door open")
	if guest == null:
		print("CANYON YURT RESULT: %d failures" % failures)
		finish()
		return
	var pose: Transform3D = camp.transform * guest.transform
	var parts: Dictionary = camp.get_meta("baked_parts", {})
	for part in ["YurtLining", "YurtFloor", "ShanyrakInner"]:
		check(parts.has(part), "the guest yurt is furnished: %s" % part)
	check(guest.get_node_or_null("YurtLantern") != null and guest.get_node("YurtLantern").has_meta("night_light"), "a lantern lights the room at night")
	var other = camp.get_node_or_null("Yurt")
	check(other != null and other.get_node_or_null("YurtLantern") == null, "the other yurts stay closed")

	# Walk in from the yard through the doorway.
	var outside = pose * Vector3(0, 0, 6.0)
	game.walker = Vector3(outside.x, stage.ground(outside), outside.z)
	walk_to(game, pose * Vector3(0, 0, 1.6), 6.0)
	walk_to(game, pose * Vector3(-1.2, 0, 0.4), 3.0)
	var local = pose.affine_inverse() * game.walker
	check(Vector2(local.x, local.z).length() < 2.6, "a fan walks through the door into the yurt (%.2f m from the middle)" % Vector2(local.x, local.z).length())
	# The wall holds them in, wherever they walk.
	var inside = true
	for angle in [PI * 0.5, PI, -PI * 0.5, PI * 0.75]:
		game.walker = pose * Vector3(0.6, 0, 1.6)
		game.walker.y = stage.ground(game.walker)
		walk_to(game, pose * (Vector3(sin(angle), 0, cos(angle)) * 6.0), 4.0)
		local = pose.affine_inverse() * game.walker
		inside = inside and Vector2(local.x, local.z).length() < 3.2
	check(inside, "the round wall stops a walker inside the yurt")
	# From outside the felt wall is solid too, away from the door.
	game.walker = pose * Vector3(-6.0, 0, -1.0)
	game.walker.y = stage.ground(game.walker)
	walk_to(game, pose * Vector3(0, 0, -1.0), 4.0)
	local = pose.affine_inverse() * game.walker
	check(Vector2(local.x, local.z).length() > 3.3, "nobody walks into the yurt through its wall")
	check(not stage.solids.clear(pose * Vector3(0.5, 0, -1.0), 0.0), "scenery and camps keep out of the room")
	print("CANYON YURT RESULT: %d failures" % failures)
	finish()
