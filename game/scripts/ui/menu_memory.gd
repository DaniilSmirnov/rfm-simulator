extends RefCounted
# The player's menu picks (car, stage, character and nickname) kept between
# launches and over a return to the main menu, which reloads the scene.
# Written on every pick made in the menu; a guest borrowing the host's stage
# is not a pick. Read back once the menu is built. A saved pick that no longer
# fits falls back the same way a menu pick does: the helicopter only flies on
# the Charyn stage, so another stage brings back the first car.
const SETTINGS_PATH = "user://menu_choice.cfg"
const DEFAULT_NAMES = ["Фанат", "Fan"]
var game
# Empty turns the memory off: automated runs (tests, captures, the dedicated
# server) start from the default picks and leave the player's file alone.
var settings_path = "" if "--script" in OS.get_cmdline_args() or "--smoke-test" in OS.get_cmdline_user_args() or "--capture" in OS.get_cmdline_user_args() or "--capture-menu" in OS.get_cmdline_user_args() or "--dedicated" in OS.get_cmdline_user_args() else SETTINGS_PATH

func setup(owner) -> void:
	game = owner
	game.car_choice.item_selected.connect(func(_index): save())
	game.stage_choice.item_selected.connect(func(_index): save())
	game.lobby_ui.character_choice.item_selected.connect(func(_index): save())
	game.room.ui.name_input.text_changed.connect(func(_text): save())

func save() -> void:
	if settings_path.is_empty() or game.playing:
		return
	var config = ConfigFile.new()
	config.set_value("menu", "car", game.selected_car)
	config.set_value("menu", "stage", game.selected_stage)
	config.set_value("menu", "character", game.avatar_variant)
	# The untouched default name stays out, so it keeps following the language.
	var name: String = game.room.ui.name_input.text.strip_edges()
	config.set_value("menu", "name", "" if name in DEFAULT_NAMES or not game.room.ui.name_input.editable else name)
	if config.save(settings_path) != OK:
		push_warning("Menu choice was not saved to %s" % settings_path)

func restore() -> void:
	var config = ConfigFile.new()
	if settings_path.is_empty() or game.playing or game.loading_world or config.load(settings_path) != OK:
		return
	# Stage first: it decides which cars are offered.
	game.select_stage(int(config.get_value("menu", "stage", 0)))
	game.select_player_car(int(config.get_value("menu", "car", 0)))
	game.lobby_ui.select_character(int(config.get_value("menu", "character", game.avatar_variant)))
	# A platform profile (VK) fixes the nickname; it is not overwritten.
	var name = str(config.get_value("menu", "name", ""))
	if not name.is_empty() and game.room.ui.name_input.editable:
		game.room.ui.name_input.text = name
