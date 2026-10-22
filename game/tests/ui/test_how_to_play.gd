extends "res://tests/harness.gd"
# «Как играть»: once before the safety memo on the first VK stage entry, then
# only from the pause menu.
const SETTINGS = "user://test_how_to_play.cfg"

func _initialize() -> void:
	call_deferred("run")

func open_game() -> Node:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.how_to_play.settings_path = SETTINGS
	return game

func run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	var game = await open_game()
	var guide = game.how_to_play
	check(guide.pages.size() == 5 and guide.tab_buttons.size() == 5 and not guide.is_open(), "five tabs, closed in the main menu")
	await game.start_game()
	# Standalone: no section, the memo opens at once.
	game.platform_service.profile = {"platform": "standalone"}
	game._show_stage_safety_gate()
	check(game.safety_gate != null and not guide.is_open(), "outside VK the stage opens with the safety memo only")
	game.safety_gate.queue_free()
	game.safety_gate = null
	# VK first entry: the section comes first, the memo waits.
	game.platform_service.profile = {"platform": "vk", "verified": true}
	game._show_stage_safety_gate()
	check(guide.is_open() and guide.first_time and game.safety_gate == null and game.paused, "first VK entry shows how to play before the memo")
	check(guide.close_button.text == "ПРОПУСТИТЬ" and guide.next_button.text == "ДАЛЕЕ", "first visit offers next and skip")
	var paused_menu = game.menu.visible
	var esc = InputEventAction.new()
	esc.action = "pause_demo"
	esc.pressed = true
	game._unhandled_input(esc)
	check(guide.is_open() and game.menu.visible == paused_menu, "Esc neither closes the first-visit section nor opens the pause menu")
	for i in range(4):
		guide.next_button.pressed.emit()
	check(guide.page == 4 and guide.next_button.text == "К ПАМЯТКЕ", "last tab leads to the memo")
	guide.next_button.pressed.emit()
	check(not guide.is_open() and game.safety_gate != null and guide.seen(), "finishing opens the memo and remembers the section")
	var gate = game.safety_gate
	gate.accepted.emit()
	gate.queue_free()
	check(not game.paused and game.safety_gate == null, "accepting the memo starts play")
	# Second entry in VK: the memo only.
	game._show_stage_safety_gate()
	check(game.safety_gate != null and not guide.is_open(), "later VK entries go straight to the memo")
	game.safety_gate.queue_free()
	game.safety_gate = null
	game.paused = false
	# Pause menu: a button opens the section, Esc or Close returns to pause.
	game._set_paused(true)
	game.hud.update_menu()
	check(game.hud.guide_button.visible and game.hud.guide_button.text == "КАК ИГРАТЬ", "pause menu has a how-to-play button")
	game.hud.guide_button.pressed.emit()
	check(guide.is_open() and not guide.first_time and guide.close_button.text == "ЗАКРЫТЬ", "pause opens the section for browsing")
	guide.tab_buttons[1].pressed.emit()
	check(guide.page == 1 and guide.pages[1].visible and not guide.pages[0].visible, "tabs switch pages")
	game._unhandled_input(esc)
	check(not guide.is_open() and game.paused and game.menu.visible, "Esc closes the section back to the pause menu")
	game._set_paused(false)
	game.dead = true
	game.hud.update_menu()
	check(not game.hud.guide_button.visible, "result window has no how-to-play button")
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	# Touch devices describe the on-screen buttons instead of keys.
	var phone = await open_game()
	phone.enable_mobile()
	var touch_guide = phone.how_to_play
	touch_guide.open()
	var text = ""
	for label in touch_guide.pages[1].find_children("*", "Label", true, false):
		text += label.text + "\n"
	check(text.contains("Правый круг") and not text.contains("WASD"), "touch controls page shows sticks and buttons, not keys")
	await phone._shutdown_audio()
	phone.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	print("HOW TO PLAY RESULT: %d checks, %d failures" % [checks, failures])
	finish()
