extends SceneTree
# Northern lights over «Поречье» (scripts/core/aurora.gd) at full display, a few
# seconds apart to show them move.
# Then a fan watching them and his view.
# With `-- --frames=N` it saves N frames of the first view for an animation.
# Run: xvfb-run godot --path game --rendering-method gl_compatibility --script res://tools/screenshots/export_aurora.gd -- --out=<dir>
const ScreenshotRig = preload("res://tools/screenshots/screenshot_rig.gd")
const StageRegistry = preload("res://scripts/stages/stage_registry.gd")

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var out = "res://../docs/screenshots"
	var frames = 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		if arg.begins_with("--frames="):
			frames = arg.trim_prefix("--frames=").to_int()
	var rig = ScreenshotRig.new(self, "AURORA_SCREENSHOT")
	var game = rig.open_stage(StageRegistry.index_of("sever"))
	if game == null:
		return
	var stage = game.stage
	var sky = game.sky_weather
	sky.set_conditions("night", "sun")
	var aurora = sky.aurora
	aurora.shown = true
	aurora.level = 1.0
	aurora._clock = 1000.0
	var views = [[200.0, 2.0, 280.0, -0.3], [470.0, 30.0, 560.0, -0.45], [640.0, 1.6, 720.0, -0.2]]
	for v in range(views.size()):
		var spec: Array = views[v]
		var from = stage.at(spec[0]) + stage.side(spec[0]) * 3.0
		from.y = stage.ground(from) + spec[1]
		var ahead = Vector3(0, 0, -1) * 200.0 + from
		ahead.y = from.y + 200.0 * absf(spec[3]) * 1.6
		rig.aim(from, ahead, 70.0)
		game.camera.global_transform = rig.camera.global_transform
		for frame in range(frames):
			await rig.capture("%s/frame_%03d.png" % [out, frame], Vector2i(640, 360))
		if frames > 0:
			break
		for shot in range(2):
			aurora._surging = shot == 1
			aurora.surge = 1.0 if shot == 1 else 0.0
			aurora._apply()
			await rig.capture("%s/aurora_%d_%d.png" % [out, v, shot], Vector2i(1280, 720))
			for i in range(60):
				await process_frame
	# Watching them (player/stargaze.gd): a fan leaning back on the road, and
	# the view he gets.
	if frames == 0:
		var spot = stage.at(240.0)
		spot.y = stage.ground(spot)
		var fan = game.Props.player_avatar(1)
		game.add_child(fan)
		fan.position = spot
		fan.rotation.y = 0.0
		preload("res://scripts/people/character_rig.gd").pose(fan, {"gaze": 1.0})
		rig.aim(spot + Vector3(3.2, 0.5, 1.2), spot + Vector3(-0.4, 1.9, -3.0), 62.0)
		game.camera.global_transform = rig.camera.global_transform
		await rig.capture("%s/aurora_watcher.png" % out, Vector2i(1280, 720))
		fan.queue_free()
		var eye = spot + Vector3(0, 1.56, 0.3)
		rig.camera.position = eye
		rig.camera.rotation = Vector3(preload("res://scripts/player/stargaze.gd").GAZE_PITCH, 0.0, 0.0)
		rig.camera.fov = 68.0
		game.camera.global_transform = rig.camera.global_transform
		await rig.capture("%s/aurora_gaze_view.png" % out, Vector2i(1280, 720))
	await game._shutdown_audio()
	quit()
