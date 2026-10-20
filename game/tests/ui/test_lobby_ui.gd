extends "res://tests/harness.gd"
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	game.defer_world = true
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	check(game.menu.get_child(0) == game.menu_content, "main menu contains no scroll container")
	check(not game.menu_title.visible and not game.menu_text.visible, "main menu hides duplicate heading and player count")
	check(game.room.ui.panel.is_visible_in_tree() and not game.start_button.visible, "all starts use the unified room menu")
	check(game.lobby_ui.images.size() == 3 and game.lobby_ui.images.all(func(image): return image.texture != null), "car, stage and character cards have rendered previews")
	# Laid out as the menu is drawn: full width, then scaled to the window.
	game.hud.layout_menu()
	await process_frame
	check(game.menu.custom_minimum_size.x == 1100, "main menu gives selection cards more width")
	game.lobby_ui.quit_button.pressed.emit()
	check(game.lobby_ui.quit_dialog.visible and not game.lobby_ui.quit_button.disabled, "quit asks for confirmation before shutdown")
	game.lobby_ui.quit_dialog.find_child("CancelQuit", true, false).pressed.emit()
	check(not game.lobby_ui.quit_dialog.visible and not game.lobby_ui.quit_button.disabled, "cancel keeps the game open and allows another attempt")
	var cut: Array[String] = []
	for choice in [game.car_choice, game.stage_choice, game.lobby_ui.character_choice]:
		var start = choice.selected
		for i in range(choice.item_count):
			choice.select(i)
			var label: Label = choice.caption
			var font_size = label.get_theme_font_size("font_size")
			var width = label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			if font_size < choice.MIN_FONT_SIZE or (width > label.size.x and (label.autowrap_mode == TextServer.AUTOWRAP_OFF or label.get_line_count() > 2)):
				cut.append("%s: %d px, %.0f/%.0f, wrap %d, lines %d" % [label.text, font_size, width, label.size.x, label.autowrap_mode, label.get_line_count()])
		choice.select(start)
	check(cut.is_empty(), "every car, stage and character name fits between the arrows " + str(cut))
	var looks = preload("res://scripts/people/character_profiles.gd").playable()
	check(game.lobby_ui.character_choice.item_count == looks.size() and not "Коллекционер нашивок" in game.lobby_ui.character_choice.items, "every look but the patch collector can be picked")
	game.lobby_ui.character_choice.cycle(-1)
	check(game.avatar_variant == looks[-1] and game.lobby_ui.images[2].texture.resource_path.ends_with("character_%d.webp" % looks[-1]), "previous arrow wraps to the last playable look in summer clothes")
	game.select_stage(1)
	check(game.lobby_ui.images[2].texture.resource_path.ends_with("character_winter_%d.webp" % looks[-1]), "a winter stage shows the pick in winter clothes")
	game.lobby_ui.select_character(11)
	check(game.avatar_variant == looks[0], "a spectator-only look cannot be selected")
	game.select_stage(0)
	check(game.lobby_ui.background.visible and game.lobby_ui.background.mouse_filter == Control.MOUSE_FILTER_IGNORE, "menu backdrop is visible and does not intercept input")
	game.platform_service.catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/store_catalog.json"))
	game.platform_service.entitlements = {"mode": "restricted", "skus": []}
	game.room.ui.id_input.text = "ABCDEF"
	game.select_player_car(9)
	game.select_stage(2)
	game.lobby_ui.refresh()
	check(game.lobby_ui.background.texture.resource_path.ends_with("backdrop_2.webp"), "backdrop follows locked stage selection")
	check(game.selected_car == 9 and game.selected_stage == 2, "closed content can be previewed")
	check(game.room.ui.create_button.disabled and game.room.ui.join_button.disabled, "locked car blocks both entry actions")
	game.start_game()
	check(not game.playing, "direct start cannot bypass ownership")
	game.select_player_car(0)
	game.lobby_ui.refresh()
	check(game.room.ui.create_button.disabled and not game.room.ui.join_button.disabled, "guest can join host stage with free car")
	game.room.connect_room("")
	check(not game.room.busy, "locked stage cannot create room")
	game.select_stage(1)
	game.platform_service.profile = {"platform": "vk"}
	check(game.lobby_ui.help_button != null and game.lobby_ui.help_dialog != null, "help action has a support dialog")
	game.lobby_ui._open_help()
	check(game.lobby_ui.help_dialog.visible and game.lobby_ui.help_dialog.get_node("Center/Panel/Content/Message").text.contains(game.lobby_ui.SUPPORT_EMAIL), "VK help displays support email without relying on mailto")
	game.lobby_ui.help_dialog.get_node("Center/Panel/Content/Actions/Close").pressed.emit()
	check(not game.lobby_ui.help_dialog.visible, "support dialog closes through its button")
	check(game.hud.brand.is_visible_in_tree() and game.title_label.text == "Rally Fans Simulator" and game.hud.brand.get_node("Names/Byline").text == "от Rally Fans Map" and game.hud.brand.get_node("Logo").texture != null, "main menu shows the logo, title and Rally Fans Map credit")
	check(game.lobby_ui.about_button.is_visible_in_tree() and game.lobby_ui.help_button.is_visible_in_tree() and game.lobby_ui.about_button.get_parent() == game.lobby_ui.help_button.get_parent(), "about and help sit together in the menu header")
	game.lobby_ui._open_about()
	check(game.lobby_ui.about_dialog.visible and game.lobby_ui.about_dialog.get_node("Center/Panel/Content/Message").text.contains("https://rallyfansmap.ru/"), "VK about offers the site address instead of relying on a popup")
	game.lobby_ui.about_dialog.get_node("Center/Panel/Content/Actions/Close").pressed.emit()
	check(not game.lobby_ui.about_dialog.visible, "about dialog closes through its button")

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
	check(not game.room.ui.create_button.disabled and not game.lobby_ui.purchase_button.visible, "confirmed winter ownership unlocks host and hides purchase")
	# Red Canyon is a separate paid VK map, not covered by a winter purchase.
	game.select_stage(3)
	game.lobby_ui.refresh()
	check(not game.platform_service.can_use("stage", 3), "unpaid canyon locked after buying winter stage")
	check(game.room.ui.create_button.disabled and not game.room.ui.join_button.disabled, "unpaid canyon cannot host but can join another owner's room")
	check(game.lobby_ui.purchase_button.visible and game.lobby_ui.purchase_button.text == "ОТКРЫТЬ СУ · 20 ГОЛОСОВ", "canyon exposes 20-vote purchase")
	game.platform_service.entitlements.skus.append("stage_04")
	game.lobby_ui.refresh()
	check(game.platform_service.can_use("stage", 3) and not game.room.ui.create_button.disabled, "owned canyon unlocks new room")
	check(game.lobby_ui.states[1].text.contains("Куплено") and not game.lobby_ui.purchase_button.visible, "purchased canyon hides purchase button")
	game.platform_service.entitlements.skus.erase("stage_04")
	game.select_stage(1)
	game.lobby_ui.refresh()
	game.car_choice.select(3)
	game.platform_service.catalog[7].purchase_enabled = true
	game.platform_service.catalog[7].price = 3
	game.platform_service.catalog[7].payment_mode = "production"
	game.lobby_ui.refresh()
	check(game.lobby_ui.car_purchase_button.visible and game.room.ui.create_button.disabled, "locked selected car exposes its own purchase")
	check(game.lobby_ui.car_purchase_button.text == "КУПИТЬ МАШИНУ · 3 ГОЛОСА", "production car price")
	game.car_choice.select(0)
	game.select_stage(0)
	game.lobby_ui.refresh()
	check(not game.room.ui.create_button.disabled, "free baseline enables create")
	check(not game.world_ready and game.stage.get_child_count() == 0, "menu previews keep the world deferred across selection changes")
	game.room.connected = true
	game.room.is_host = false
	game.room.world_paused = true
	game.lobby_ui._process(0)
	check(game.lobby_ui.host_pause.visible, "guest sees persistent host pause banner")
	game.paused = true
	game.playing = true
	game.lobby_ui._process(0)
	check(not game.lobby_ui.background.visible and game.lobby_ui.background.texture == null, "gameplay releases menu background texture")
	check(game.menu.find_child("ReturnButton", true, false) == null and not game.lobby_ui.host_pause.visible, "pause has no redundant return button")
	game.menu.show()
	game.hud.update_menu()
	check(game.hud.menu_dim.visible and game.hud.links.visible and game.hud.settings.visible and not game.hud.brand.visible, "pause dims the stage and keeps settings and links")
	game.dead = true
	game.hud.update_menu()
	check(not game.hud.links.visible and not game.hud.settings.visible and game.menu_title.visible, "result window shows only its title, text and actions")
	game.dead = false
	game.paused = false
	game.room.world_paused = false
	game.lobby_ui._process(0)
	check(not game.lobby_ui.host_pause.visible, "resuming host hides banner")
	game.enable_mobile()
	check(game.menu_content.is_visible_in_tree() and game.room.ui.panel.is_visible_in_tree(), "mobile keeps compact menu content visible")
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
	for control in [game.room.ui.create_button, game.room.ui.join_button, game.lobby_ui.purchase_button, game.lobby_ui.car_purchase_button, game.lobby_ui.check_purchase, game.lobby_ui.purchase_status]:
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
	finish()
