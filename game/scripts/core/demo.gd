extends RefCounted
# Demo build (export feature "demo"; --demo tries it from a normal build):
# one player on the default stage, car and character, «Как играть» before
# every stage entry, and a main menu with only «Играть» and «Выйти из игры».
static var forced = false

static func active() -> bool:
	return forced or OS.has_feature("demo") or "--demo" in OS.get_cmdline_user_args()

# The menu's main button: in the demo main menu it starts a solo trip
# instead of creating a room.
static func start_pressed(game) -> void:
	if active() and not game.playing:
		game.start_game()
	else:
		game._menu_action()

# The demo main menu shows no selection, rooms or links: only «Играть» and
# «Выйти из игры» (the corner icon), with the version below them. Pause keeps
# its links (help, language, settings).
static func trim_menu(game, hud, pause: bool) -> void:
	if not active():
		return
	game.start_button.show()
	game.selection_controls.hide()
	var lobby = game.lobby_ui
	hud.links.visible = pause or not game.playing
	lobby.help_button.visible = pause
	lobby.settings_button.visible = pause
	lobby.language_button.visible = pause and not lobby._is_vk_family()
	hud.footer.get_parent().move_child(hud.footer, -1)
	if game.room != null:
		game.room.ui.panel.hide()
