extends SceneTree
# Interface screenshots for layout review: one state per run, desktop or
# mobile (add --mobile-controls), optionally as a VK player.
#   xvfb-run godot --path game --rendering-driver opengl3 --resolution 844x390 \
#     --script res://tools/export_ui_screenshots.gd -- --state=pause --vk --mobile-controls --out=/tmp/pause.png
# States: menu, hud, drawer, car, pause, guest_pause, result, safety, help,
# about, guide (first VK entry, --page=N), guide_pause, loading.

func _initialize() -> void:
	call_deferred("run")

func arg(name: String, fallback: String = "") -> String:
	for value in OS.get_cmdline_user_args():
		if value.begins_with("--" + name + "="):
			return value.trim_prefix("--" + name + "=")
	return fallback

func frames(count: int) -> void:
	for i in range(count):
		await process_frame

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await frames(2)
	if "--vk" in OS.get_cmdline_user_args():
		fake_vk(game)
	var state = arg("state", "menu")
	var stage = int(arg("stage", "0"))
	if state == "menu":
		game.select_stage(stage)
		game.stage_choice.select(stage)
	if state in ["hud", "drawer", "car", "pause", "guest_pause", "result", "safety", "guide", "guide_pause"]:
		await game.start_game()
		game._prepare_capture()
		game.camera.position = game.camp.position + Vector3(10, 5, 12)
		await frames(4)
		if state == "drawer" and game.mobile_controls != null:
			game.mobile_controls.gear_open = true
		elif state == "car":
			game.walker = game.car.position + Vector3(1.5, 0, 0)
			game._toggle_car()
		elif state == "pause":
			game._set_paused(true)
		elif state == "guest_pause":
			# Show the guest overlay without a server: a connected non-host room.
			game.room.set_process(false)
			game.room.connected = true
			game.room.is_host = false
			game.room.world_paused = true
		elif state == "result":
			game.die("Тебя задела машина экипажа.")
		elif state == "safety":
			game._show_stage_safety_gate()
		elif state == "guide":
			game.how_to_play.settings_path = "user://screenshot_how_to_play.cfg"
			DirAccess.remove_absolute(ProjectSettings.globalize_path(game.how_to_play.settings_path))
			game._show_stage_safety_gate()
			game.how_to_play.show_page(int(arg("page", "0")))
		elif state == "guide_pause":
			game._set_paused(true)
			game.how_to_play.open()
			game.how_to_play.show_page(int(arg("page", "0")))
	elif state == "help":
		game.lobby_ui.help_dialog.show()
	elif state == "about":
		game.lobby_ui.about_dialog.show()
	elif state == "loading":
		game.loading_screen.show_loading()
		game.loading_screen.caption.text = "Деревья и подлесок"
		game.loading_screen.bar.value = 46
	await frames(int(arg("frames", "40")))
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(arg("out", "res://../ui.png"))
	await game._shutdown_audio()
	quit()

func fake_vk(game: Node) -> void:
	var service = game.platform_service
	var catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/store_catalog.json"))
	service.profile = {"platform": "vk", "nickname": "Иван Петров", "verified": true}
	service.entitlements = {"mode": "restricted", "skus": []}
	service.catalog = catalog if catalog is Array else []
	service.profile_ready.emit(service.profile)
	service.purchase_changed.emit()
