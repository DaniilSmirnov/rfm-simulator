extends SceneTree
# Documentation screenshots of the Provençal village stage (docs/screenshots).
# xvfb-run -a godot --path game --rendering-method gl_compatibility --script res://tools/export_provence_screenshots.gd
var game

func _initialize() -> void:
	call_deferred("run")

func shot(file: String, from: Vector3, to: Vector3) -> void:
	game.camera.fov = 58
	game.camera.far = 2500
	game.camera.position = from
	game.camera.look_at(to)
	# Interface layers are hidden: the documentation shows only the scene.
	for layer in game.find_children("*", "CanvasLayer", true, false):
		layer.visible = false
	for control in game.find_children("*", "Control", false, false):
		control.visible = false
	# Let villagers, laundry and smoke settle into a natural pose.
	for i in range(8):
		game.stage.update_life(0.1, from)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_webp("res://../docs/screenshots/%s.webp" % file, false, 0.85)

func run() -> void:
	root.size = Vector2i(1280, 720)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.select_stage(2)
	game.start_game()
	var distance = preload("res://scripts/draw_distance.gd").new()
	distance.mode = distance.FAR
	distance.apply(game.stage)
	var stage = game.stage
	var village = stage.village
	var square: Vector3 = village.square.center + Vector3(0, village.square.height, 0)
	await shot("provence-plateau", stage.at(90) + Vector3(-60, 30, 30), stage.at(150))
	await shot("provence-village", square + Vector3(70, 45, 60), square + Vector3(-10, 0, -40))
	await shot("provence-grand-rue", stage.at(305) + Vector3(0, 1.8, 0) + stage.side(305) * 2.5, stage.at(345) + Vector3(0, 3, 0))
	await shot("provence-square", stage.at(372) + Vector3(0, 1.7, 0), square)
	await shot("provence-lane", stage.at(455) + Vector3(0, 1.8, 0), stage.at(495) + Vector3(0, 3, 0))
	await shot("provence-terraces", stage.at(600) + Vector3(0, 6, 0) + stage.side(600) * -10.0, stage.at(680))
	await shot("provence-valley", stage.at(730) + Vector3(0, 2.0, 0), stage.at(800) + Vector3(0, 2, 0))
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	quit()
