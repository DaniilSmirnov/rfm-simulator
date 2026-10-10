extends RefCounted
# Room entry panel inside the main menu and the in-game room status line.
# UI only: pressing a button calls room.connect_room(); room.gd decides the rest.
const NetProtocol = preload("res://scripts/net_protocol.gd")
var room
var game
var panel: PanelContainer
var status: Label
var room_label: Label
var name_input: LineEdit
var id_input: LineEdit
var create_button: Button
var join_button: Button

func build(owner_room) -> void:
	room = owner_room
	game = room.game
	var ui = game.menu.get_parent()
	panel = PanelContainer.new()
	game.menu_content.add_child(panel)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	game._label(box, "НАЧАТЬ ВЫЕЗД", 16, Color("dfb270"))
	name_input = LineEdit.new()
	name_input.placeholder_text = "Твой ник"
	name_input.max_length = NetProtocol.name_input_length()
	name_input.text = "Овощ"
	name_input.custom_minimum_size.y = 48
	name_input.add_theme_font_size_override("font_size", 22)
	var fields = HBoxContainer.new()
	fields.add_theme_constant_override("separation", 12)
	box.add_child(fields)
	name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_child(name_input)
	id_input = LineEdit.new()
	id_input.placeholder_text = "ID комнаты · %d символов" % NetProtocol.room_id_length()
	id_input.max_length = NetProtocol.room_id_length()
	id_input.custom_minimum_size.y = 48
	id_input.add_theme_font_size_override("font_size", 22)
	id_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_child(id_input)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	create_button = Button.new()
	create_button.text = "СОЗДАТЬ ВЫЕЗД"
	create_button.add_theme_color_override("font_color", Color("25352b"))
	create_button.add_theme_stylebox_override("normal", game._panel(Color("e3b16b")))
	create_button.add_theme_stylebox_override("hover", game._panel(Color("f1c687")))
	create_button.add_theme_stylebox_override("pressed", game._panel(Color("c78f4a")))
	join_button = Button.new()
	join_button.text = "ВОЙТИ ПО ID"
	for button in [create_button, join_button]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 48
		button.add_theme_font_size_override("font_size", 22)
		row.add_child(button)
	create_button.pressed.connect(func(): room.connect_room(""))
	join_button.pressed.connect(func():
		if id_input.text.strip_edges() == "":
			status.text = "Введи ID комнаты."
		else:
			room.connect_room(id_input.text.strip_edges().to_upper())
	)
	status = game._label(box, "До %d игроков. Общий лагерь и ралли.\nСоздатель должен оставаться в комнате." % NetProtocol.max_players(), 18)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	id_input.text_changed.connect(func(_text): game.lobby_ui.refresh())
	game.lobby_ui.refresh.call_deferred()
	room_label = game._label(ui, "", 18, Color("ffe4a5"))
	room_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	room_label.offset_left = 36
	room_label.offset_right = -180
	room_label.offset_top = -45
	room_label.offset_bottom = -8
	room_label.hide()

func set_entry_enabled(enabled: bool) -> void:
	create_button.disabled = not enabled
	join_button.disabled = not enabled

# Joined: the panel gives way to the status line.
func show_connected() -> void:
	for control in [name_input, id_input, create_button, join_button]:
		control.release_focus()
	panel.hide()
	room_label.show()

func show_room_status(room_id: String, players: int, is_host: bool, host_paused: bool) -> void:
	room_label.text = "ID %s · %d/%d · %s%s" % [room_id, players, NetProtocol.max_players(), "СОЗДАТЕЛЬ" if is_host else "ЗРИТЕЛЬ", " · ПАУЗА ХОЗЯИНА" if host_paused else ""]
