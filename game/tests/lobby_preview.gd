extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func capture(game: Node, name: String) -> void:
	game.lobby_ui.refresh()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var error = root.get_texture().get_image().save_png("res://../.cache/ui-screens/" + name + ".png")
	if error != OK:
		push_error("Screenshot failed")
func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://../.cache/ui-screens")
	root.size = Vector2i(1440, 900)
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	await capture(game, "desktop-lobby")
	game.platform_service.catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/store_catalog.json"))
	game.platform_service.entitlements = {"mode": "restricted", "skus": []}
	game.select_player_car(9)
	game.select_stage(2)
	await capture(game, "desktop-locked")
	game.select_player_car(0)
	game.select_stage(1)
	game.platform_service.profile = {"platform": "vk"}
	game.platform_service.catalog[1].purchase_enabled = true
	game.platform_service.catalog[1].price = 1
	await capture(game, "desktop-test-purchase")
	root.size = Vector2i(1280, 720)
	game.enable_mobile()
	await capture(game, "mobile-lobby")
	await capture(game, "mobile-test-purchase")
	game.platform_service.entitlements.skus = ["stage_02"]
	game.platform_service.purchase_message = "Покупка подтверждена · СУ открыт"
	await capture(game, "mobile-purchase-confirmed")
	game.select_player_car(0)
	game.select_stage(0)
	game.start_game()
	game.paused = true
	game.menu.show()
	game.menu_title.text = "Перерыв на природе"
	game.menu_text.text = "Выезд приостановлен. Продолжить или вернуться в меню."
	game.start_button.text = "ПРОДОЛЖИТЬ"
	await capture(game, "mobile-pause")
	game.paused = false
	game.menu.hide()
	game.room.connected = true
	game.room.is_host = false
	game.room.world_paused = true
	await capture(game, "mobile-host-pause")
	game.room.connected = false
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	quit()
