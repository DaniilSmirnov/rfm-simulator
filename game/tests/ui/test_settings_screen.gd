extends "res://tests/harness.gd"
# The settings window: the gear in the menu header (main menu and pause), draw
# distance, volume and the desktop screen options, all kept between launches.
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	game.defer_world = true
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	var lobby = game.lobby_ui
	var screen = game.hud.settings_screen
	screen.audio_path = "user://audio_settings_test.cfg"
	screen.display_path = "user://display_settings_test.cfg"
	game.draw_distance.settings_path = "user://draw_distance_settings_test.json"
	check(lobby.settings_button.is_visible_in_tree() and lobby.settings_button.get_parent() == game.hud.links and lobby.settings_button.icon != null and lobby.settings_button.text.is_empty(), "the main menu header has a gear icon")
	check(lobby.quit_button.get_parent() == game.hud.links and lobby.quit_button.icon != null and lobby.quit_button.text.is_empty() and lobby.quit_button.tooltip_text != "", "quit is an icon at the top with a tooltip")
	check(not screen.is_open(), "settings start closed")
	lobby.settings_button.pressed.emit()
	check(screen.is_open() and game.draw_distance_controls.is_visible_in_tree() and screen.volume_slider.is_visible_in_tree(), "the gear opens draw distance and sound")
	check(screen.display_controls.is_visible_in_tree() == screen.has_display_settings(), "screen options appear only in a desktop window")
	game.draw_distance_buttons[game.draw_distance.NEAR].pressed.emit()
	check(game.draw_distance.mode == game.draw_distance.NEAR and FileAccess.file_exists(game.draw_distance.settings_path), "draw distance applies and is saved from the main menu")
	screen.volume_slider.value = 40
	var saved = ConfigFile.new()
	check(saved.load(screen.audio_path) == OK and is_equal_approx(float(saved.get_value("audio", "volume")), 40.0) and screen.volume_label.text.contains("40"), "volume is saved and shown")
	screen.volume_slider.value = 100
	screen.set_window_mode(screen.WINDOWED)
	screen.resolution_choice.cycle(-1)
	var pick: Vector2i = screen.resolution
	var display = ConfigFile.new()
	check(display.load(screen.display_path) == OK and display.get_value("display", "mode") == "windowed" and display.get_value("display", "resolution") == pick, "window mode and resolution are saved")
	check(not screen.resolution_choice.get_child(0).disabled and screen.window_mode_buttons[screen.WINDOWED].button_pressed, "a window can be resized from the list")
	screen.set_window_mode(screen.FULLSCREEN)
	check(screen.resolution_choice.get_child(0).disabled and screen.window_mode_buttons[screen.FULLSCREEN].button_pressed, "fullscreen uses the screen resolution")
	screen.window_mode = screen.WINDOWED
	screen._load_display()
	check(screen.window_mode == screen.FULLSCREEN and screen.resolution == pick, "the saved screen choice is read back")
	var escape = InputEventAction.new()
	escape.action = "pause_demo"
	escape.pressed = true
	screen._unhandled_input(escape)
	check(not screen.is_open(), "Esc closes the settings")
	game.playing = true
	game.paused = true
	game.menu.show()
	game.hud.update_menu()
	check(lobby.settings_button.is_visible_in_tree(), "the pause menu keeps the gear")
	lobby.settings_button.pressed.emit()
	screen._process(0)
	check(screen.is_open(), "settings open from the pause")
	game.paused = false
	screen._process(0)
	check(not screen.is_open(), "resuming closes the settings")
	for path in [screen.audio_path, screen.display_path, game.draw_distance.settings_path]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	finish()
