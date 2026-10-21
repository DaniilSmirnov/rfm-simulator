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
# «Выйти из игры», with the version below them. Pause keeps its links (help,
# language).
static func trim_menu(game, hud, pause: bool) -> void:
	if not active():
		return
	game.start_button.show()
	game.selection_controls.hide()
	hud.links.visible = pause
	hud.footer.get_parent().move_child(hud.footer, -1)
	if game.room != null:
		game.room.ui.panel.hide()
