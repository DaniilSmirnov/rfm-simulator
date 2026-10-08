extends RefCounted
var game: Node3D
var room: Node

func _build_ui() -> void:
	var ui = game.menu.get_parent()
	room.lobby = PanelContainer.new()
	game.menu_content.add_child(room.lobby)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	room.lobby.add_child(box)
	game._label(box, "НАЧАТЬ ВЫЕЗД", 16, Color("dfb270"))
	room.name_input = LineEdit.new()
	room.name_input.placeholder_text = "Твой ник"
	room.name_input.max_length = 24
	room.name_input.text = "Овощ"
	room.name_input.custom_minimum_size.y = 48
	room.name_input.add_theme_font_size_override("font_size", 22)
	var fields = HBoxContainer.new()
	fields.add_theme_constant_override("separation", 12)
	box.add_child(fields)
	room.name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_child(room.name_input)
	room.id_input = LineEdit.new()
	room.id_input.placeholder_text = "ID комнаты · 6 символов"
	room.id_input.max_length = 6
	room.id_input.custom_minimum_size.y = 48
	room.id_input.add_theme_font_size_override("font_size", 22)
	room.id_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_child(room.id_input)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	room.create_button = Button.new()
	room.create_button.text = "СОЗДАТЬ ВЫЕЗД"
	room.create_button.add_theme_color_override("font_color", Color("25352b"))
	room.create_button.add_theme_stylebox_override("normal", game._panel(Color("e3b16b")))
	room.create_button.add_theme_stylebox_override("hover", game._panel(Color("f1c687")))
	room.create_button.add_theme_stylebox_override("pressed", game._panel(Color("c78f4a")))
	room.join_button = Button.new()
	room.join_button.text = "ВОЙТИ ПО ID"
	for button in [room.create_button, room.join_button]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 48
		button.add_theme_font_size_override("font_size", 22)
		row.add_child(button)
	room.create_button.pressed.connect(func(): room.connect_room(""))
	room.join_button.pressed.connect(func():
		if room.id_input.text.strip_edges() == "":
			room.lobby_status.text = "Введи ID комнаты."
		else:
			room.connect_room(room.id_input.text.strip_edges().to_upper())
	)
	room.lobby_status = game._label(box, "До 8 игроков. Общий лагерь и ралли.\nСоздатель должен оставаться в комнате.", 18)
	room.lobby_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	room.id_input.text_changed.connect(func(_text): game.lobby_ui.refresh())
	game.lobby_ui.refresh.call_deferred()
	room.room_label = game._label(ui, "", 18, Color("ffe4a5"))
	room.room_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	room.room_label.offset_left = 36
	room.room_label.offset_right = -180
	room.room_label.offset_top = -45
	room.room_label.offset_bottom = -8
	room.room_label.hide()
