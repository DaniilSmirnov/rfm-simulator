extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func snap(path: String) -> void:
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func run() -> void:
	root.size = Vector2i(1280, 720)
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.select_stage(2)
	game.start_game()
	game.camera.fov = 58
	game.camera.position = Vector3(115, 130, -170)
	game.camera.look_at(Vector3(20, 2, -180))
	await snap("res://../city-overview.png")
	game.camera.position = Vector3(60, 32, -270)
	game.camera.look_at(Vector3(0, 5, -320))
	await snap("res://../city-roundabout.png")
	game.camera.position = Vector3(-24, 7, -105)
	game.camera.look_at(Vector3(-24, 6, -155))
	await snap("res://../city-street.png")
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	quit()
