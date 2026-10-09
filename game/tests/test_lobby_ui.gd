extends SceneTree
var failures = 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	check(game.menu.get_child(0) == game.menu_content, "main menu contains no scroll container")
	check(not game.menu_title.visible and not game.menu_text.visible, "main menu hides duplicate heading and player count")
	check(game.room.lobby.is_visible_in_tree() and not game.start_button.visible, "all starts use the unified room menu")
	check(game.lobby_ui.images.size() == 2 and game.lobby_ui.images[0].texture != null, "both cards have rendered previews")
	check(game.lobby_ui.background.visible and game.lobby_ui.background.mouse_filter == Control.MOUSE_FILTER_IGNORE, "menu backdrop is visible and does not intercept input")
	game.platform_service.catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/store_catalog.json"))
	game.platform_service.entitlements = {"mode": "restricted", "skus": []}
	game.room.id_input.text = "ABCDEF"
	game.select_player_car(9)
	game.select_stage(2)
	game.lobby_ui.refresh()
	check(game.lobby_ui.background.texture.resource_path.ends_with("backdrop_2.webp"), "backdrop follows locked stage selection")
	check(game.selected_car == 9 and game.selected_stage == 2, "closed content can be previewed")
	check(game.room.create_button.disabled and game.room.join_button.disabled, "locked car blocks both entry actions")
	game.start_game()
	check(not game.playing, "direct start cannot bypass ownership")
	game.select_player_car(0)
	game.lobby_ui.refresh()
	check(game.room.create_button.disabled and not game.room.join_button.disabled, "guest can join host stage with free car")
	game.room.connect_room("")
	check(not game.room.busy, "locked stage cannot create room")
	game.select_stage(1)
	game.platform_service.profile = {"platform": "vk"}
	game.platform_service.catalog[1].purchase_enabled = true
	game.platform_service.catalog[1].price = 20
	game.platform_service.catalog[1].payment_mode = "production"
	game.lobby_ui.refresh()
	check(not game.lobby_ui.states[1].text.contains("Куплено"), "unpaid stage has no purchase label")
	check(game.lobby_ui.purchase_button.visible and game.lobby_ui.check_purchase.visible, "test winter stage exposes purchase and reconciliation")
	game.platform_service.busy = true
	check(game.lobby_ui.purchase_button.text == "ОТКРЫТЬ СУ · 20 ГОЛОСОВ", "production stage price")
	game.platform_service.purchase_message = "Ожидаем VK…"
	game.lobby_ui.refresh()
	check(game.lobby_ui.purchase_button.disabled and game.lobby_ui.check_purchase.disabled, "pending order blocks double purchase")
	game.platform_service.busy = false
	game.platform_service.entitlements.skus = ["stage_02"]
	game.lobby_ui.refresh()
	check(game.lobby_ui.states[1].text.contains("Куплено"), "server ownership shows purchase label")
	check(not game.room.create_button.disabled and not game.lobby_ui.purchase_button.visible, "confirmed winter ownership unlocks host and hides purchase")
	game.car_choice.select(3)
	game.platform_service.catalog[7].purchase_enabled = true
	game.platform_service.catalog[7].price = 3
	game.platform_service.catalog[7].payment_mode = "production"
	game.lobby_ui.refresh()
	check(game.lobby_ui.car_purchase_button.visible and game.room.create_button.disabled, "locked selected car exposes its own purchase")
	check(game.lobby_ui.car_purchase_button.text == "КУПИТЬ МАШИНУ · 3 ГОЛОСА", "production car price")
	game.car_choice.select(0)
	game.select_stage(0)
	game.lobby_ui.refresh()
	check(not game.room.create_button.disabled, "free baseline enables create")
	game.room.connected = true
	game.room.is_host = false
	game.room.world_paused = true
	game.lobby_ui._process(0)
	check(game.lobby_ui.host_pause.visible, "guest sees persistent host pause banner")
	game.paused = true
	game.playing = true
	game.lobby_ui._process(0)
	check(not game.lobby_ui.background.visible and game.lobby_ui.background.texture == null, "gameplay releases menu background texture")
	check(game.lobby_ui.return_button.visible and not game.lobby_ui.host_pause.visible, "own pause offers return to main menu")
	game.paused = false
	game.room.world_paused = false
	game.lobby_ui._process(0)
	check(not game.lobby_ui.host_pause.visible, "resuming host hides banner")
	game.enable_mobile()
	check(game.menu_content.is_visible_in_tree() and game.room.lobby.is_visible_in_tree(), "mobile keeps compact menu content visible")
	game.playing = false
	game.lobby_ui._process(0)
	check(not game.mobile_top.visible and not game.mobile_bottom.visible, "main mobile menu has no empty HUD backgrounds")
	game.room.connected = false
	game.select_stage(1)
	game.platform_service.entitlements.skus = []
	game.car_choice.select(3)
	game.platform_service.purchase_message = "Ждём подтверждения VK. Нажмите «Проверить покупку»."
	game.lobby_ui.refresh()
	await process_frame
	await process_frame
	var safe = Rect2(54, 120, 852, 390)
	game.apply_mobile_safe_rect(safe)
	game.fit_mobile_dialogs()
	await process_frame
	check(game.lobby_ui.background.get_global_rect().size.distance_to(game.get_viewport().get_visible_rect().size) < 1, "backdrop covers full viewport outside safe HUD rectangle")
	check(safe.encloses(game.menu.get_global_rect()), "entire mobile main menu fits VK safe area without scrolling")
	for control in [game.room.create_button, game.room.join_button, game.lobby_ui.purchase_button, game.lobby_ui.car_purchase_button, game.lobby_ui.check_purchase, game.lobby_ui.purchase_status]:
		check(game.menu.get_global_rect().encloses(control.get_global_rect()), "all menu actions and purchase status stay inside panel")
	check(not game.menu_title.visible and not game.menu_text.visible, "mobile main menu has no duplicate heading or subtitle")
	game.playing = true
	game.paused = true
	game.lobby_ui._process(0)
	check(not game.mobile_top.visible and not game.mobile_bottom.visible, "mobile pause hides gameplay HUD panels")
	game.paused = false
	game.info_label.text = "20 КМ/Ч"
	game.lobby_ui._process(0)
	check(game.mobile_top.visible and game.mobile_bottom.visible, "resuming restores populated HUD")
	game.room.connected = false
	game.playing = true
	game.paused = false
	var lifecycle = {"width": 960, "height": 540, "left": 0, "right": 0, "top": 0, "bottom": 0, "lifecycle": {"hidden": false, "pause_sequence": 1}}
	game._mobile_safe_response(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(lifecycle).to_utf8_buffer())
	check(game.paused and game.menu.visible, "rapid hide/restore still pauses the game")
	game._set_paused(false)
	game._mobile_safe_response(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(lifecycle).to_utf8_buffer())
	check(not game.paused, "an acknowledged hide does not pause again after Continue")
	game.mobile_mode = false
	lifecycle.lifecycle.hidden = true
	game._mobile_safe_response(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(lifecycle).to_utf8_buffer())
	check(game.paused, "desktop VK lifecycle also pauses gameplay")
	game.queue_free()
	await process_frame
	print("LOBBY_UI failures=", failures)
	quit(1 if failures else 0)
