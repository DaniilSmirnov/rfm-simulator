extends "res://tests/harness.gd"
# Menu picks survive a restart and a return to the main menu (a scene reload):
# car, stage, character and the typed nickname; a saved car that the stage does
# not offer (the helicopter outside Charyn) falls back to the first car.
const SETTINGS = "user://test_menu_memory.cfg"
const CharacterProfiles = preload("res://scripts/people/character_profiles.gd")
func _initialize() -> void:
	call_deferred("run")
func launch() -> Node:
	var game = load("res://main.tscn").instantiate()
	game.defer_world = true
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	check(game.lobby_ui.memory.settings_path.is_empty(), "test runs leave the player's saved picks alone")
	game.lobby_ui.memory.settings_path = SETTINGS
	game.lobby_ui.memory.restore()
	return game
func close(game: Node) -> void:
	game.queue_free()
	await process_frame
	await process_frame
func run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	var game = await launch()
	var registry = game.Props.CarRegistry
	var helicopter = -1
	var charyn = -1
	for variant in range(game.car_choice.item_count):
		if not registry.car(variant).get("stages", []).is_empty():
			helicopter = variant
	for stage in range(game.stage_choice.item_count):
		if registry.offered(helicopter, stage):
			charyn = stage
	check(helicopter > 0 and charyn > 0, "a stage-bound car and its stage exist")
	check(game.selected_stage == 0 and game.selected_car == 0, "a first launch starts from the default picks")
	var looks = CharacterProfiles.playable()
	# Picks made the way the arrows make them.
	game.stage_choice.select(charyn)
	game.stage_choice.item_selected.emit(charyn)
	game.car_choice.select(helicopter)
	game.car_choice.item_selected.emit(helicopter)
	game.lobby_ui.character_choice.item_selected.emit(looks.size() - 1)
	game.room.ui.name_input.text = "Штурман"
	game.room.ui.name_input.text_changed.emit("Штурман")
	check(game.selected_stage == charyn and game.selected_car == helicopter and game.avatar_variant == looks[-1], "the picks apply in the menu")
	await close(game)
	game = await launch()
	check(game.selected_stage == charyn and game.stage_choice.selected == charyn, "the stage comes back after a restart")
	check(game.selected_car == helicopter and game.car_choice.selected == helicopter, "the car comes back after a restart")
	check(game.avatar_variant == looks[-1] and game.lobby_ui.character_choice.selected == looks.size() - 1, "the character comes back after a restart")
	check(game.room.ui.name_input.text == "Штурман", "the nickname comes back after a restart")
	check(game.stage_caption.text == game.StageRegistry.caption(charyn).to_upper(), "the stage caption follows the restored stage")
	# A hand-edited or outdated file: the helicopter saved with another stage.
	var config = ConfigFile.new()
	config.load(SETTINGS)
	config.set_value("menu", "stage", 0)
	config.set_value("menu", "name", "Фанат")
	config.save(SETTINGS)
	await close(game)
	game = await launch()
	check(game.selected_stage == 0 and game.selected_car == 0, "a car the stage does not offer falls back to the first car")
	check(game.room.ui.name_input.text == game.Loc.t("Фанат"), "the default nickname keeps following the language")
	# Leaving the stage for another one in the menu also falls back, and that is saved.
	game.stage_choice.item_selected.emit(charyn)
	game.car_choice.item_selected.emit(helicopter)
	game.stage_choice.item_selected.emit(0)
	config = ConfigFile.new()
	check(config.load(SETTINGS) == OK and int(config.get_value("menu", "stage")) == 0 and int(config.get_value("menu", "car")) == 0, "the fallback is what gets saved")
	await close(game)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	finish()
