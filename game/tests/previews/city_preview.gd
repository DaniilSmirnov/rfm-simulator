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
	var stage = game.stage
	var square: Vector3 = stage.village.square.center + Vector3(0, stage.village.square.height, 0)
	game.camera.position = stage.at(90) + Vector3(-60, 30, 30)
	game.camera.look_at(stage.at(150))
	await snap("res://../vineyard-overview.png")
	game.camera.position = square + Vector3(70, 45, 60)
	game.camera.look_at(square + Vector3(-10, 0, -40))
	await snap("res://../vineyard-village.png")
	game.camera.position = stage.at(305) + Vector3(0, 1.8, 0) + stage.side(305) * 2.5
	game.camera.look_at(stage.at(345) + Vector3(0, 3, 0))
	await snap("res://../vineyard-street.png")
	var grapes = stage.collectibles.filter(func(item): return item.get("name", "") == "виноград")
	var vine: Vector3 = grapes[grapes.size() / 3].pos
	game.camera.position = vine + Vector3(2.3, 2.0, 3.0)
	game.camera.look_at(vine + Vector3(0, 1.1, 0))
	await snap("res://../vineyard-grapes.png")
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	quit()
