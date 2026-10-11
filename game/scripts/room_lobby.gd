extends RefCounted
# Room entry block inside the main menu and the in-game room status line.
# UI only: pressing a button calls room.connect_room(); room.gd decides the rest.
const NetProtocol = preload("res://scripts/net_protocol.gd")
const UiKit = preload("res://scripts/ui_kit.gd")
const DEFAULT_NAME = "Фанат"
var default_hint = "До %d фанатов в одном лагере. Создатель выезда должен оставаться в комнате." % NetProtocol.max_players()
var room
var game
var panel: PanelContainer
var status: Label
var caption: Label
var room_label: Label
var name_input: LineEdit
var id_input: LineEdit
var create_button: Button
var join_button: Button

func build(owner_room) -> void:
	room = owner_room
	game = room.game
	panel = UiKit.card(game.hud.entry_slot, UiKit.SURFACE_SUNKEN, Vector2(16, 14))
	panel.name = "RoomEntry"
	var box = UiKit.vbox(panel, 10)
	caption = UiKit.label(box, "ВЫЕЗД", "caption")
	var start_row = UiKit.hbox(box, 12)
	name_input = field(start_row, "Твой ник", NetProtocol.name_input_length())
	name_input.text = DEFAULT_NAME
	create_button = UiKit.expand(UiKit.button(start_row, "СОЗДАТЬ ВЫЕЗД", "primary", 48))
	create_button.pressed.connect(func(): room.connect_room(""))
	var join_row = UiKit.hbox(box, 12)
	id_input = field(join_row, "ID комнаты друга · %d символов" % NetProtocol.room_id_length(), NetProtocol.room_id_length())
	if OS.has_feature("web") and OS.has_feature("vk"):
		# VK mobile web: a native DOM input opens the keyboard reliably.
		var native_input = preload("res://scripts/mobile_room_input.gd").new()
		native_input.field = id_input
		native_input.room = room
		room.add_child(native_input)
	join_button = UiKit.expand(UiKit.button(join_row, "ВОЙТИ ПО ID", "secondary", 48))
	join_button.pressed.connect(func():
		if id_input.text.strip_edges() == "":
			status.text = "Введи ID комнаты."
		else:
			room.connect_room(id_input.text.strip_edges().to_upper())
	)
	status = UiKit.wrap(UiKit.label(box, default_hint, "muted"))
	id_input.text_changed.connect(func(_text): game.lobby_ui.refresh())
	game.lobby_ui.refresh.call_deferred()
	room_label = UiKit.label(game.hud.top_box, "", "muted")
	room_label.name = "RoomLine"
	room_label.add_theme_color_override("font_color", UiKit.HIGHLIGHT)
	room_label.hide()

func field(parent: Control, placeholder: String, length: int) -> LineEdit:
	var input = LineEdit.new()
	input.placeholder_text = placeholder
	input.max_length = length
	input.custom_minimum_size.y = 48
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(input)
	return input

func set_entry_enabled(enabled: bool) -> void:
	create_button.disabled = not enabled
	join_button.disabled = not enabled

# Joined: the entry block gives way to the room line in the stage card.
func show_connected() -> void:
	for control in [name_input, id_input, create_button, join_button]:
		control.release_focus()
	panel.hide()
	room_label.show()

func show_room_status(room_id: String, players: int, is_host: bool, host_paused: bool) -> void:
	room_label.text = "КОМНАТА %s · %d/%d · %s%s" % [room_id, players, NetProtocol.max_players(), "СОЗДАТЕЛЬ" if is_host else "ГОСТЬ", " · ПАУЗА ХОЗЯИНА" if host_paused else ""]
