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
	game.playing = false
	game.lobby_ui._process(0)
	check(not game.mobile_top.visible and not game.mobile_bottom.visible, "main mobile menu has no empty HUD backgrounds")
	game.playing = true
	game.paused = true
	game.lobby_ui._process(0)
	check(not game.mobile_top.visible and not game.mobile_bottom.visible, "mobile pause hides gameplay HUD panels")
	game.paused = false
	game.info_label.text = "20 КМ/Ч"
	game.lobby_ui._process(0)
	check(game.mobile_top.visible and game.mobile_bottom.visible, "resuming restores populated HUD")
	game.room.connected = false
	game.queue_free()
	await process_frame
	print("LOBBY_UI failures=", failures)
	quit(1 if failures else 0)
