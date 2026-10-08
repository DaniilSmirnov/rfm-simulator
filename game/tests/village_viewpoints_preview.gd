extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func shot(camera: Camera3D, p: Vector3, target: Vector3, name: String) -> void:
	camera.position = p
	camera.look_at(target)
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/viewpoints-" + name + ".png")
func run() -> void:
	root.size = Vector2i(1280, 720)
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.select_stage(2)
	game.start_game()
	for panel in game.hud_panels: panel.hide()
	game.title_label.hide()
	game.toast_label.hide()
	game.camera.fov = 75
	var church = game.stage.get_node("VillageChurch")
	await shot(game.camera, church.transform * Vector3(35, 24, -35), church.transform * Vector3(0, 15, -8), "church")
	await shot(game.camera, church.transform * Vector3(0, 1.82, -6.5), church.transform * Vector3(0, 2, 9), "nave")
	await shot(game.camera, church.transform * Vector3(-1, 25.82, -11.1), game.stage.at(382) + Vector3.UP * 2, "tower-view")
	var view = game.stage.city.viewpoints[0]
	await shot(game.camera, view.pose * Vector3(12, 10, -13), view.pose * Vector3(0, 3, 0), "house")
	await shot(game.camera, view.pose * Vector3(2.2, 7.82, -3.2), game.stage.at(378) + Vector3.UP, "roof-view")
	view = game.stage.city.viewpoints[1]
	await shot(game.camera, view.pose * Vector3(2.2, 7.82, -3.2), game.stage.at(494) + Vector3.UP, "second-roof-view")
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	quit()
