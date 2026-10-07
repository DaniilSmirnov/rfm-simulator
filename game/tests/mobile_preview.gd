extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280, 720)
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.enable_mobile()
	game.start_game()
	game.room.set_process(false)
	game.walker = game.stage.clearings[0]
	game.car.position = game.walker + Vector3(0, 0, 12)
	game.in_car = false
	game._update_camera(1)
	game._update_hud()
	for view in ["walking", "gear", "driving"]:
		game.in_car = view == "driving"
		game.mobile_controls.gear_open = view == "gear"
		game.mobile_controls._process(0)
		game._update_camera(1)
		game._update_hud()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		if root.get_texture().get_image().save_png("../mobile-%s.png" % view) != OK:
			quit(1)
			return
		print("MOBILE PREVIEW: " + view)
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	quit()
