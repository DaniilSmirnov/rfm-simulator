extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func capture(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../.cache/ui-screens/" + name + ".png")
func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://../.cache/ui-screens")
	root.size = Vector2i(1440, 900)
	var game = load("res://main.tscn").instantiate()
	game.defer_world = true
	root.add_child(game)
	game.set_process(false)
	game.room.set_process(false)
	await capture("memory-menu-desktop")
	root.size = Vector2i(1280, 720)
	game.enable_mobile()
	await capture("memory-menu-mobile")
	game.start_game()
	while game.loading_screen.caption.text != "Объекты спецучастка":
		await process_frame
	await capture("memory-loading-mobile")
	root.size = Vector2i(1440, 900)
	await capture("memory-loading-desktop")
	while game.loading_world:
		await process_frame
	await game._shutdown_audio()
	quit()
