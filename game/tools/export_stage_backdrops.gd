extends SceneTree
# Offline captures: the actual menu only loads these images.
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	game.defer_world = false
	root.add_child(game)
	game.set_process(false)
	game.room.set_process(false)
	var viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.world_3d = game.get_world_3d()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	var camera = Camera3D.new()
	camera.fov = 65
	camera.far = 1100
	viewport.add_child(camera)
	camera.current = true
	for i in range(game.Stage.STAGES.size()):
		game.select_stage(i)
		var target = game.stage.at(435 if i == 2 else (420 if i == 1 else 280))
		camera.position = target + (Vector3(70, 38, 65) if i == 2 else Vector3(40, 22, 45))
		camera.look_at(target + Vector3(0, 4, -18))
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_webp("res://textures/previews/backdrop_%d.webp" % i, false, 0.85)
	await game._shutdown_audio()
	quit()
