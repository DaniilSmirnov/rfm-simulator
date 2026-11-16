extends SceneTree
# Rain kept out of shelter (scripts/core/rain_shelter.gd): beside a tree on the
# forest pass, inside a village room and next to a parked car.
# Run: xvfb-run godot --path game --rendering-method gl_compatibility --script res://tools/screenshots/export_rain_shelter.gd -- --out=<dir>
const ScreenshotRig = preload("res://tools/screenshots/screenshot_rig.gd")
const StageRegistry = preload("res://scripts/stages/stage_registry.gd")

func _initialize() -> void: call_deferred("run")

func shot(rig, game, from: Vector3, to: Vector3, path: String) -> void:
	rig.aim(from, to, 70.0)
	game.camera.global_transform = rig.camera.global_transform
	for i in range(30):
		await process_frame
	await rig.capture(path, Vector2i(1280, 720))

func run() -> void:
	var out = "res://../docs/screenshots"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	var rig = ScreenshotRig.new(self, "RAIN_SCREENSHOT")
	var game = rig.open_stage(StageRegistry.index_of("forest"))
	if game == null:
		return
	game.sky_weather.set_conditions("day", "rain")
	Engine.time_scale = 0.05
	var stage = game.stage
	var base: Vector3 = stage.trees[0]
	for i in range(stage.trees.size()):
		var p: Vector3 = stage.trees[i]
		if p.distance_to(stage.at(120)) < 40.0 and not stage.fallen.has(i):
			base = p
			break
	await shot(rig, game, base + Vector3(7, 1.7, 5), base + Vector3(0, 2.5, 0), "%s/rain_tree.png" % out)
	var car: Node3D = game.car
	car.visible = true
	car.global_position = stage.at(150) + Vector3(0, 0.1, 0)
	print("RAIN_CAR ", car.is_inside_tree(), " ", car.global_position)
	var pose: Transform3D = car.global_transform
	await shot(rig, game, pose * Vector3(-0.35, 1.15, 0.2), pose * Vector3(-0.35, 1.0, -8.0), "%s/rain_cabin.png" % out)
	await shot(rig, game, pose * Vector3(3.5, 1.6, 3.5), pose * Vector3(0, 0.8, 0), "%s/rain_car.png" % out)
	game.select_stage(StageRegistry.index_of("provence"))
	game.stage.build()
	game.sky_weather.set_conditions("day", "rain")
	var area: Dictionary = game.stage.solids.interior_footprints[0]
	var room: Transform3D = game.stage.global_transform * area.inverse.affine_inverse()
	var eye = room.origin + Vector3(0, 1.7, 0)
	await shot(rig, game, eye, eye + room.basis.x * 6.0, "%s/rain_room.png" % out)
	await shot(rig, game, room.origin + room.basis.x * (area.half.x + 8.0) + Vector3(0, 3, 0), room.origin + Vector3(0, 3, 0), "%s/rain_room_outside.png" % out)
	Engine.time_scale = 1.0
	await game._shutdown_audio()
	quit()
