extends "res://tests/harness.gd"
# Interface language: Russian source text, English from data/translations_en.json,
# the choice by system language and by the menu button, and Russian-only VK.
const Loc = preload("res://scripts/ui/loc.gd")
func _initialize() -> void:
	call_deferred("run")
func has_cyrillic(text: String) -> bool:
	for i in range(text.length()):
		if text.unicode_at(i) >= 0x0400 and text.unicode_at(i) <= 0x04FF:
			return true
	return false
func run() -> void:
	Loc.settings_path = "user://language_test.cfg"
	DirAccess.remove_absolute(Loc.settings_path)
	check(Loc.from_system("ru") == "ru" and Loc.from_system("RU") == "ru", "a Russian system keeps Russian")
	check(Loc.from_system("en") == "en" and Loc.from_system("de") == "en" and Loc.from_system("uk") == "en" and Loc.from_system("") == "en", "any other system language gets English")
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	var lobby = game.lobby_ui
	Loc.set_language("ru", false)
	check(Loc.t("ПОЕХАЛИ") == "ПОЕХАЛИ" and Loc.t("Осталось %d") == "Осталось %d", "Russian text passes through unchanged")
	check(lobby.language_button.is_visible_in_tree() and lobby.language_button.text == "ENGLISH", "the menu offers English next to Help")
	check(lobby.language_button.get_parent() == lobby.help_button.get_parent(), "language button sits with Help and About")
	lobby.language_button.pressed.emit()
	check(Loc.current == "en" and lobby.language_button.text == "РУССКИЙ", "the button switches to English and offers Russian")
	check(Loc.saved_language() == "en", "the choice is remembered")
	check(game.lobby_ui.about_button.atr(lobby.about_button.text) == "ABOUT US" and lobby.help_button.atr(lobby.help_button.text) == "HELP", "buttons translate themselves")
	check(game.start_button.atr("ПОЕХАЛИ") == "LET'S GO", "the start button translates")
	check(Loc.t("Шашлык удался. Осталось %d шампуров.") % 3 == "The shashlik turned out great. 3 skewers left.", "a formatted message translates and keeps its number")
	game.toast("Подожди, пока водитель остановится.")
	check(game.toast_label.text == "Wait for the driver to stop.", "toasts are stored translated")
	check(lobby.help_dialog.find_child("Message", true, false).text.contains("write to us") and lobby.help_dialog.find_child("Message", true, false).text.contains(lobby.SUPPORT_EMAIL), "the support text follows the language")
	check(game.room.ui.id_input.placeholder_text.contains("Friend's room ID"), "text built in code is rebuilt")
	check(game.room.ui.name_input.text == "Fan", "the untouched default name is translated")
	check(game.course.short_caption().begins_with("SS 1/2"), "course caption in English")
	var names_ok = true
	for car in game.Props.PLAYER_MODELS:
		names_ok = names_ok and not has_cyrillic(Loc.t(car.name))
	check(names_ok, "every car name has an English name")
	var stages_ok = true
	for i in range(game.Stage.STAGES.size()):
		stages_ok = stages_ok and not has_cyrillic(game.StageRegistry.caption(i))
	check(stages_ok, "every stage caption has an English name")
	var rally_ok = true
	for car in game.Props.RALLY_MODELS:
		rally_ok = rally_ok and not has_cyrillic(Loc.t(car.name))
	check(rally_ok, "every rally car has an English name")
	# Playing in English: no HUD text is left in Russian, on foot, in the car and in the menu.
	game.start_game()
	var shown = true
	var leaked = ""
	for state in ["walk", "car", "broken", "pause", "result"]:
		game.in_car = state in ["car", "broken"]
		game.condition = 0.0 if state == "broken" else 80.0
		game.paused = state == "pause"
		game.hud.update_hud()
		game.hud.update_menu()
		for label in [game.course_label, game.quest_label, game.status_label, game.info_label, game.hint_label, game.menu_title, game.menu_text]:
			if has_cyrillic(label.atr(label.text)):
				shown = false
				leaked += "[%s: %s]" % [state, label.text]
	check(shown, "no Russian is left on the HUD in English " + leaked)
	lobby.language_button.pressed.emit()
	check(Loc.current == "ru" and game.room.ui.name_input.text == "Фанат" and game.toast_label.text != "", "switching back restores Russian")
	game.platform_service.profile = {"platform": "vk"}
	Loc.set_language("en", false)
	lobby.refresh()
	check(Loc.current == "ru" and not lobby.language_button.visible, "VK is Russian only and has no language button")
	Loc.forced = ""
	DirAccess.remove_absolute(Loc.settings_path)
	print("LOCALIZATION failures=%d" % failures)
	finish()
