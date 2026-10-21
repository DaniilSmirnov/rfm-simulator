extends "res://tests/harness.gd"
# Demo build: the main menu has only «Играть» and «Выйти из игры», play starts
# a solo trip on the default stage, car and character without a room, and
# «Как играть» opens before the memo on every stage entry.
const Demo = preload("res://scripts/core/demo.gd")
const SETTINGS = "user://test_demo_build.cfg"

func _initialize() -> void:
	call_deferred("run")

func shown(control: Control) -> bool:
	return control.is_visible_in_tree()

func run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	Demo.forced = true
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.how_to_play.settings_path = SETTINGS
	game.hud.update_menu()
	await process_frame
	check(shown(game.start_button) and game.start_button.text == "ИГРАТЬ", "main menu offers «Играть»")
	check(game.lobby_ui.quit_button.visible and game.lobby_ui.quit_button.text == "ВЫЙТИ ИЗ ИГРЫ", "main menu offers «Выйти из игры» on desktop")
	check(not shown(game.selection_controls), "no stage, car or character selection")
	check(not shown(game.room.ui.panel), "no room creation or joining")
	check(not shown(game.hud.links), "no site, support or language links in the main menu")
	var buttons = game.menu.find_children("*", "Button", true, false).filter(func(button): return button.is_visible_in_tree())
	check(buttons.size() == 2, "the main menu has exactly two buttons")
	game.platform_service.profile = {"platform": "standalone"}
	game.start_button.pressed.emit()
	await process_frame
	while game.loading_world:
		await process_frame
	check(game.playing and not game.room.connected and not game.room.busy, "«Играть» starts a solo trip without a room")
	check(game.selected_stage == 0 and game.selected_car == 0 and game.avatar_variant == 0, "default stage, car and character")
	game._show_stage_safety_gate()
	check(game.how_to_play.is_open() and game.how_to_play.first_time and game.safety_gate == null, "how to play opens before the memo")
	var text = ""
	for page in game.how_to_play.pages:
		for label in page.find_children("*", "Label", true, false):
			text += label.text + "\n"
	check(not text.contains("Рация") and not text.contains("машины друга"), "how to play leaves out the radio and friends' cars")
	game.how_to_play.close()
	check(game.safety_gate != null, "closing it leads to the memo")
	game.safety_gate.queue_free()
	game.safety_gate = null
	check(game.how_to_play.seen(), "the section is marked seen")
	game._show_stage_safety_gate()
	check(game.how_to_play.is_open() and game.how_to_play.first_time, "the next entry shows how to play again")
	game.how_to_play.close()
	if game.safety_gate != null:
		game.safety_gate.queue_free()
		game.safety_gate = null
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	Demo.forced = false
	print("DEMO BUILD RESULT: %d checks, %d failures" % [checks, failures])
	finish()
