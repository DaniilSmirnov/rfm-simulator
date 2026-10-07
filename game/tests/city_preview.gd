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
	for panel in game.hud_panels:
		panel.hide()
	game.toast_label.hide()
	game.camera.fov = 58
	game.camera.position = Vector3(140, 110, -170)
	game.camera.look_at(Vector3(0, 10, -180))
	await snap("res://../vineyard-overview.png")
	game.camera.position = Vector3(-65, 38, -390)
	game.camera.look_at(Vector3(15, 8, -430))
	await snap("res://../vineyard-village.png")
	game.camera.position = game.stage.at(365) + Vector3(0, 3.8, 0)
	game.camera.look_at(game.stage.at(420) + Vector3(0, 3.5, 0))
	await snap("res://../vineyard-street.png")
	var vine = game.stage.collectibles[80].pos
	game.camera.position = vine + Vector3(2.3, 2.0, 3.0)
	game.camera.look_at(vine + Vector3(0, 1.1, 0))
	await snap("res://../vineyard-grapes.png")
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	quit()
