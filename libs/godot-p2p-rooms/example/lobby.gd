extends Control
# A minimal lobby on P2PRooms: create or join a room and chat over the link.
# The host relays each guest's line to everyone (guests only reach the host).

var rooms := P2PRooms.new()
var room_field := LineEdit.new()
var name_field := LineEdit.new()
var chat_field := LineEdit.new()
var log_view := RichTextLabel.new()


func _ready() -> void:
	add_child(rooms)
	# rooms.server_url = "http://127.0.0.1:8787"  # a local `wrangler dev`
	rooms.app_protocol = 1_000_001
	rooms.room_joined.connect(func(id, _me, host): _log("Комната %s, я %s" % [id, "хост" if host else "гость"]))
	rooms.room_failed.connect(func(error, status): _log("Ошибка %d: %s" % [status, error]))
	rooms.room_closed.connect(func(reason): _log("Комната закрыта: " + reason))
	rooms.members_changed.connect(func(list): _log("Игроки: " + ", ".join(list.map(func(m): return m.name))))
	rooms.peer_connected.connect(func(id): _log("Связь с " + _name(id)))
	rooms.peer_disconnected.connect(func(id): _log("Нет связи с " + _name(id)))
	rooms.message_received.connect(_on_message)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 16)
	add_child(box)
	name_field.placeholder_text = "Имя"
	name_field.text = "Игрок"
	room_field.placeholder_text = "ID комнаты"
	chat_field.placeholder_text = "Сообщение"
	var row := HBoxContainer.new()
	row.add_child(name_field)
	row.add_child(room_field)
	row.add_child(_button("Создать", func(): rooms.create_room(name_field.text)))
	row.add_child(_button("Войти", func(): rooms.join_room(room_field.text, name_field.text)))
	row.add_child(_button("Выйти", func(): rooms.leave_room(); _log("Вышел")))
	box.add_child(row)
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(log_view)
	chat_field.text_submitted.connect(func(_t): _say())
	box.add_child(chat_field)


func _say() -> void:
	var line := {"from": rooms.player_id, "text": chat_field.text}
	chat_field.clear()
	if rooms.is_host:
		rooms.broadcast(line)
		_show(line)
	else:
		rooms.send_to_host(line)


func _on_message(from: String, data, _reliable: bool) -> void:
	if not data is Dictionary or not data.get("text") is String:
		return
	if rooms.is_host:
		# Trust the link, not the packet, for who wrote it.
		data.from = from
		rooms.broadcast(data)
	_show(data)


func _show(line: Dictionary) -> void:
	_log("%s: %s" % [_name(str(line.get("from", ""))), line.text])


func _name(id: String) -> String:
	return rooms.members.get(id, {}).get("name", id.left(6))


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	return button


func _log(text: String) -> void:
	log_view.append_text(text + "\n")
