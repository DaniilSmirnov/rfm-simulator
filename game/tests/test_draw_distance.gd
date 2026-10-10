extends "res://tests/harness.gd"
const Distance = preload("res://scripts/draw_distance.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var setting = Distance.new()
	setting.settings_path = "user://test_draw_distance.json"
	DirAccess.remove_absolute(setting.settings_path)
	setting.load_settings(true)
	check(setting.mode == Distance.MEDIUM, "mobile installs default to current medium drawing ranges")
	setting.load_settings(false)
	check(setting.mode == Distance.FAR, "desktop installs default to unlimited drawing ranges")
	setting.apply_device_default(true)
	check(setting.mode == Distance.MEDIUM, "late mobile detection updates the unused device default")
	var world = Node3D.new()
	root.add_child(world)
	var tile = MultiMeshInstance3D.new()
	tile.visibility_range_end = 160
	tile.visibility_range_end_margin = 15
	world.add_child(tile)
	var unlimited = MeshInstance3D.new()
	world.add_child(unlimited)
	for mode in [Distance.NEAR, Distance.FAR, Distance.NEAR, Distance.MEDIUM, Distance.FAR, Distance.MEDIUM]:
		setting.mode = mode
		setting.apply(world)
		check(is_equal_approx(tile.visibility_range_end, 112 if mode == Distance.NEAR else (0 if mode == Distance.FAR else 160)), "presets scale authored range, including repeated roundtrips")
		check(unlimited.visibility_range_end == 0, "unlimited terrain stays visible in every preset")
	check(tile.visibility_range_end_margin == 15, "medium restores the original culling margin")
	setting.mode = Distance.FAR
	check(setting.save_settings() == OK, "rendering preference saves locally")
	var restored = Distance.new()
	restored.settings_path = setting.settings_path
	restored.load_settings(true)
	check(restored.mode == Distance.FAR, "saved preference overrides the mobile default")
	restored.apply_device_default(true)
	check(restored.mode == Distance.FAR, "late mobile detection preserves a saved choice")
	setting.mode = Distance.MEDIUM
	setting.save_settings()
	restored.load_settings(false)
	check(restored.mode == Distance.MEDIUM, "saved medium preference overrides desktop default")
	var file = FileAccess.open(setting.settings_path, FileAccess.WRITE)
	file.store_string('{"mode":99}')
	file.close()
	restored.load_settings()
	check(restored.mode == Distance.FAR, "invalid saved preset falls back to desktop default")
	restored.load_settings(true)
	check(restored.mode == Distance.MEDIUM, "invalid saved preset falls back to mobile default")
	DirAccess.remove_absolute(setting.settings_path)
	world.free()
	var game = load("res://main.tscn").instantiate()
	game.defer_world = true
	game.draw_distance.settings_path = setting.settings_path
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	check(not game.draw_distance_controls.visible, "draw distance controls stay out of main menu")
	check(game.draw_distance.mode == (Distance.MEDIUM if "--mobile-controls" in OS.get_cmdline_user_args() else Distance.FAR), "startup applies the detected device default")
	game.enable_mobile()
	check(game.draw_distance.mode == Distance.MEDIUM and game.draw_distance_buttons[Distance.MEDIUM].button_pressed, "touch detection updates the default and selected UI button")
	game.playing = true
	game.paused = true
	game.lobby_ui._process(0)
	check(game.draw_distance_controls.visible, "three rendering presets appear in game pause")
	var live_tile = MultiMeshInstance3D.new()
	live_tile.visibility_range_end = 70
	game.stage.add_child(live_tile)
	game.draw_distance_buttons[Distance.FAR].pressed.emit()
	check(live_tile.visibility_range_end == 0 and game.paused, "pause button immediately removes range culling without resuming play")
	game.draw_distance_buttons[Distance.NEAR].pressed.emit()
	check(is_equal_approx(live_tile.visibility_range_end, 49), "near button reduces the current range by exactly thirty percent")
	game.playing = false
	game.select_stage(2)
	await game.prepare_world()
	game.playing = true
	var ranged = game.stage.find_children("*", "GeometryInstance3D", true, false).filter(func(node): return float(node.get_meta("draw_distance_base_end", 0)) > 0)
	check(game.stage.loaded_baked and ranged.size() > 20, "saved preset also applies to a newly loaded baked village")
	var correct = true
	for node in ranged:
		correct = correct and is_equal_approx(node.visibility_range_end, float(node.get_meta("draw_distance_base_end")) * 0.7)
	check(correct, "all baked distance-limited objects use the near preset")
	game.draw_distance_buttons[Distance.FAR].pressed.emit()
	correct = true
	for node in ranged:
		correct = correct and node.visibility_range_end == 0
	check(correct, "far removes distance cutoffs from the entire baked village")
	game.draw_distance_buttons[Distance.NEAR].pressed.emit()
	check(game.draw_distance_buttons[Distance.NEAR].button_pressed and not game.draw_distance_buttons[Distance.FAR].button_pressed, "only the selected preset is highlighted")
	game.paused = false
	game.lobby_ui._process(0)
	check(not game.draw_distance_controls.visible, "settings hide when resuming")
	game.paused = true
	game.finished = true
	game.lobby_ui._process(0)
	check(not game.draw_distance_controls.visible, "settings stay out of result dialog")
	DirAccess.remove_absolute(setting.settings_path)
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	print("DRAW DISTANCE RESULT: %d failures" % failures)
	finish()
