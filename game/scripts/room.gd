extends Node
# HTTP transport works with the existing minimal web template (no WebSocket module).
const Props = preload("res://scripts/props.gd")
const SHARED_ACTIONS = ["table", "chairs", "grill", "eat", "rally", "random_spot"]
var game: Node3D
var http: HTTPRequest
var server = "http://127.0.0.1:8787"
var room_id = ""
var player_id = ""
var token = ""
var is_host = false
var connected = false
var busy = false
var request_kind = ""
var clock = 0.0
var errors = 0
var sequence = 0
var commands: Array = []
var acknowledgements: Array = []
var processed: Dictionary = {}
var peers: Dictionary = {}
var world_paused = false
var tow_owner = ""
var last_notice = ""
var lobby: PanelContainer
var lobby_status: Label
var room_label: Label
var name_input: LineEdit
var id_input: LineEdit
var create_button: Button
var join_button: Button
var friends_button: Button
var exit_button: Button
var racer_targets: Dictionary = {}
var lobby_back: Button
var last_ui_size = Vector2.ZERO
var last_mobile = false

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--room-server="):
			server = arg.trim_prefix("--room-server=").trim_suffix("/")
	http = HTTPRequest.new()
	http.timeout = 8
	# Browser fetch already decompresses response bodies.
	http.accept_gzip = not OS.has_feature("web")
	http.body_size_limit = 131072
	add_child(http)
	http.request_completed.connect(_response)
	_build_ui()

func _build_ui() -> void:
	var ui = game.menu.get_parent()
	friends_button = Button.new()
	friends_button.text = "С ДРУЗЬЯМИ"
	friends_button.custom_minimum_size.y = 44
	friends_button.add_theme_font_size_override("font_size", 22)
	game.menu.get_child(0).add_child(friends_button)
	friends_button.pressed.connect(func():
		game.menu.hide()
		lobby.show()
	)
	lobby = PanelContainer.new()
	ui.add_child(lobby)
	lobby.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	lobby.offset_left = -300
	lobby.offset_right = 300
	lobby.offset_top = -195
	lobby.offset_bottom = 195
	lobby.add_theme_stylebox_override("panel", game._panel(Color("23342bf5")))
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	lobby.add_child(box)
	game._label(box, "РАЛЛИ С ДРУЗЬЯМИ", 28)
	name_input = LineEdit.new()
	name_input.placeholder_text = "Твоё имя"
	name_input.max_length = 24
	name_input.text = "Овощ"
	name_input.custom_minimum_size.y = 48
	name_input.add_theme_font_size_override("font_size", 22)
	box.add_child(name_input)
	id_input = LineEdit.new()
	id_input.placeholder_text = "ID комнаты · 6 символов"
	id_input.max_length = 6
	id_input.custom_minimum_size.y = 48
	id_input.add_theme_font_size_override("font_size", 22)
	box.add_child(id_input)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	create_button = Button.new()
	create_button.text = "СОЗДАТЬ"
	join_button = Button.new()
	join_button.text = "ВОЙТИ ПО ID"
	for button in [create_button, join_button]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 48
		button.add_theme_font_size_override("font_size", 22)
		row.add_child(button)
	create_button.pressed.connect(func(): connect_room(""))
	join_button.pressed.connect(func():
		if id_input.text.strip_edges() == "":
			lobby_status.text = "Введи ID комнаты."
		else:
			connect_room(id_input.text.strip_edges().to_upper())
	)
	lobby_status = game._label(box, "До 8 игроков. Общий лагерь и ралли.\nСоздатель должен оставаться в комнате.", 18)
	lobby_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var back = Button.new()
	lobby_back = back
	back.text = "НАЗАД"
	back.custom_minimum_size.y = 44
	box.add_child(back)
	back.pressed.connect(func():
		if not busy:
			lobby.hide()
			game.menu.show()
	)
	lobby.hide()
	room_label = game._label(ui, "", 18, Color("ffe4a5"))
	room_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	room_label.offset_left = 36
	room_label.offset_right = -180
	room_label.offset_top = -45
	room_label.offset_bottom = -8
	room_label.hide()
	exit_button = Button.new()
	exit_button.text = "ВЫЙТИ"
	ui.add_child(exit_button)
	exit_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	exit_button.offset_left = -150
	exit_button.offset_right = -36
	exit_button.offset_top = -48
	exit_button.offset_bottom = -6
	exit_button.pressed.connect(leave)
	exit_button.hide()

func connect_room(id: String) -> void:
	if busy or connected:
		return
	if id != "" and (id.length() != 6 or not id.is_valid_hex_number()):
		lobby_status.text = "ID состоит из 6 символов: 0–9 и A–F."
		return
	room_id = id
	lobby_status.text = "Подключаемся…"
	create_button.disabled = true
	join_button.disabled = true
	_request("create" if id == "" else "join", {"name": name_input.text})

func _request(kind: String, body: Dictionary) -> void:
	request_kind = kind
	busy = true
	var path = "/api/rooms" if kind == "create" else "/api/rooms/%s/%s" % [room_id, kind]
	var err = http.request(server + path, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_response(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())

func _response(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
	busy = false
	var parser = JSON.new()
	var data = parser.data if parser.parse(bytes.get_string_from_utf8()) == OK else null
	if request_kind == "leave":
		game.get_tree().reload_current_scene()
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not data is Dictionary:
		var message = str(data.get("error", "Нет связи с сервером комнаты.")) if data is Dictionary else "Нет связи с сервером комнаты."
		if connected and (code in [401, 404, 410] or errors >= 2):
			disconnect_room(message)
		elif connected:
			errors += 1
			clock = -1
			room_label.text = "Связь прервалась. Переподключаемся…"
		else:
			lobby_status.text = message
			create_button.disabled = false
			join_button.disabled = false
		return
	errors = 0
	if request_kind in ["create", "join"]:
		player_id = data.player
		token = data.token
		is_host = data.host
		if is_host:
			room_id = data.room
		connected = true
		for control in [name_input, id_input, create_button, join_button]:
			control.release_focus()
		lobby.hide()
		friends_button.hide()
		room_label.show()
		exit_button.show()
		game.start_game()
		# Separate parked cars at the start; local movement remains responsive.
		var lane = int(data.get("slot", 0))
		game.car.position = game.stage.at(12 + lane * 6)
		game.toast("Комната %s. Передай ID друзьям!" % room_id)
		print("ROOM_CONNECTED ", room_id, " host=", is_host)
	else:
		_update_peers(data.players)
		if is_host:
			for command in data.commands:
				if not processed.has(command.id):
					_apply_command(command)
					processed[command.id] = true
				if command.id not in acknowledgements:
					acknowledgements.append(command.id)
		else:
			commands = commands.filter(func(c): return c.seq > int(data.accepted))
			if data.world is Dictionary:
				apply_world(data.world)
		room_label.text = "ID %s · %d/8 · %s%s" % [room_id, peers.size() + 1, "СОЗДАТЕЛЬ" if is_host else "ЗРИТЕЛЬ", " · ПАУЗА ХОЗЯИНА" if world_paused else ""]

func _process(delta: float) -> void:
	var ui_size = game.get_viewport().get_visible_rect().size
	if ui_size != last_ui_size or game.mobile_mode != last_mobile:
		last_ui_size = ui_size
		last_mobile = game.mobile_mode
		var portrait = game.mobile_mode and ui_size.y > ui_size.x
		lobby.offset_top = -300 if portrait else -195
		lobby.offset_bottom = 300 if portrait else 195
		for input in [name_input, id_input]:
			input.custom_minimum_size.y = 80 if portrait else 48
			input.add_theme_font_size_override("font_size", 26 if portrait else 22)
		for button in [create_button, join_button, lobby_back]:
			button.custom_minimum_size.y = 80 if portrait else 48
			button.add_theme_font_size_override("font_size", 26 if portrait else 22)
		lobby_status.add_theme_font_size_override("font_size", 22 if portrait else 18)
		friends_button.custom_minimum_size.y = 72 if portrait else 44
		room_label.add_theme_font_size_override("font_size", 24 if game.mobile_mode else 18)
	if not connected:
		return
	exit_button.visible = game.paused or game.dead or game.finished
	clock += delta
	if not busy and clock >= 0.2:
		clock = 0
		var body = {"token": token, "state": local_state(), "commands": commands}
		if is_host:
			body.world = world_state()
			body.ack = acknowledgements
		_request("sync", body)
	for peer in peers.values():
		if peer.state == null:
			continue
		peer.car.position = peer.car.position.lerp(v(peer.state.car), minf(1, delta * 12))
		peer.car.rotation.y = lerp_angle(peer.car.rotation.y, peer.state.heading, minf(1, delta * 12))
		peer.avatar.position = peer.avatar.position.lerp(v(peer.state.pos), minf(1, delta * 12))
		peer.avatar.rotation.y = lerp_angle(peer.avatar.rotation.y, peer.state.yaw, minf(1, delta * 12))
		peer.avatar.visible = not peer.state.in_car
		peer.can.visible = peer.state.beer >= 0
		peer.arm.rotation.x = -1.6 if peer.state.beer >= 1.25 else -0.5
		peer.label.position = peer.car.position + Vector3(0, 2.8, 0) if peer.state.in_car else peer.avatar.position + Vector3(0, 2.3, 0)
	if not is_host:
		var nearest: Node3D = null
		var nearest_distance = INF
		for racer in game.racers:
			if racer.state in ["racing", "offroad"] and not world_paused and not game.dead and not game.finished:
				var distance = racer.node.position.distance_to(game.player_position())
				if distance < nearest_distance:
					nearest = racer.node
					nearest_distance = distance
			if racer_targets.has(racer.id):
				var target = racer_targets[racer.id]
				racer.node.position = racer.node.position.lerp(v(target.pos), minf(1, delta * 12))
				racer.node.rotation.y = lerp_angle(racer.node.rotation.y, target.yaw, minf(1, delta * 12))

		if nearest != null:
			game.rally_audio.position = nearest.position
			game.rally_audio.pitch_scale = 1.8
			if not game.rally_audio.playing:
				game._play_audio(game.rally_audio)
		else:
			game.rally_audio.stop()

static func a(pos: Vector3) -> Array:
	return [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(pos.z, 0.01)]
static func v(pos: Array) -> Vector3:
	return Vector3(pos[0], pos[1], pos[2])

func local_state() -> Dictionary:
	return {"pos": a(game.player_position()), "car": a(game.car.position), "heading": game.heading, "yaw": game.view_yaw, "pitch": game.view_pitch, "in_car": game.in_car, "tow": Input.is_action_pressed("tow") and not game.paused and not game.dead, "beer": game.drink_time}

func _update_peers(players: Array) -> void:
	var present = {}
	for p in players:
		if p.id == player_id:
			continue
		present[p.id] = true
		if not peers.has(p.id):
			var color = Color.from_hsv(float(posmod(str(p.id).hash(), 100)) / 100, 0.55, 0.8)
			var car = Props.car(color)
			game.add_child(car)
			var avatar = Node3D.new()
			game.add_child(avatar)
			Props.box(avatar, Vector3(0, 1.1, 0), Vector3(0.55, 0.7, 0.3), color)
			Props.box(avatar, Vector3(0, 1.7, 0), Vector3(0.35, 0.4, 0.35), Color("d2ad83"))
			for x in [-0.17, 0.17]:
				Props.box(avatar, Vector3(x, 0.42, 0), Vector3(0.2, 0.85, 0.22), Color("35445b"))
			var arm = Node3D.new()
			avatar.add_child(arm)
			arm.position = Vector3(0.37, 1.35, 0)
			Props.box(arm, Vector3(0, -0.25, 0), Vector3(0.18, 0.5, 0.18), color)
			var can = Props.cylinder(arm, Vector3(0, -0.52, 0), 0.09, 0.09, 0.25, Color("daa44f"))
			var label = Props.label_3d(game, Vector3.ZERO, p.name, 26, 0.012, Color("fff1cb"))
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			peers[p.id] = {"car": car, "avatar": avatar, "arm": arm, "can": can, "label": label, "state": null}
			if p.state != null:
				car.position = v(p.state.car)
				avatar.position = v(p.state.pos)
		peers[p.id].state = p.state
	for id in peers.keys():
		if not present.has(id):
			for node in [peers[id].car, peers[id].avatar, peers[id].label]:
				node.queue_free()
			peers.erase(id)

func submit(action: String) -> bool:
	if not connected or is_host or action not in SHARED_ACTIONS:
		return false
	if commands.size() < 8:
		sequence += 1
		commands.append({"seq": sequence, "action": action})
	return true

func _apply_command(c: Dictionary) -> void:
	acknowledgements = acknowledgements.slice(-64)
	if game.paused or game.dead or game.finished:
		return
	var old = {"in_car": game.in_car, "walker": game.walker, "car": game.car.position, "yaw": game.view_yaw}
	game.in_car = c.state.in_car
	game.walker = v(c.state.pos)
	game.car.position = v(c.state.car)
	game.view_yaw = c.state.yaw
	match c.action:
		"table": game.place_table()
		"chairs": game.place_chairs()
		"grill": game.start_grill()
		"eat": game.eat_meat()
		"rally": game.start_rally()
		"random_spot":
			game.target_clearing = game.rng.randi_range(0, game.stage.clearings.size() - 1)
			game.toast("Выбрана поляна %d." % (game.target_clearing + 1))
	game.in_car = old.in_car
	game.walker = old.walker
	game.car.position = old.car
	game.view_yaw = old.yaw

func world_state() -> Dictionary:
	var racers = []
	for r in game.racers:
		racers.append({"id": r.id, "variant": r.variant, "pos": a(r.node.position), "yaw": r.node.rotation.y, "state": r.state})
	return {"camp": a(game.camp.position) if game.camp != null else null, "chairs": game.has_chairs, "cooking": game.cooking, "cook_time": game.cook_time, "eaten": game.eaten, "racing": game.racing, "passed": game.passed, "helped": game.helped, "elapsed": game.elapsed, "clearing": game.target_clearing, "paused": game.paused, "dead": game.dead, "finished": game.finished, "title": game.menu_title.text, "text": game.menu_text.text, "racers": racers, "tow": game.tow_target.get_meta("room_id") if game.tow_target != null else -1, "tow_progress": game.tow_progress, "tow_owner": tow_owner, "notice": game.toast_label.text, "notice_time": game.toast_time}

func apply_world(w: Dictionary) -> void:
	world_paused = w.paused
	if w.get("notice_time", 0) > 0 and w.get("notice", "") != last_notice:
		last_notice = w.notice
		game.toast(last_notice)
	if w.camp != null and game.camp == null:
		game.camp = Node3D.new()
		game.add_child(game.camp)
		game.camp.position = v(w.camp)
		Props.table(game.camp)
	if w.chairs and not game.has_chairs:
		Props.chair(game.camp, Vector3(-1.6, 0, 0.7))
		Props.chair(game.camp, Vector3(1.6, 0, 0.7))
	game.has_chairs = w.chairs
	if w.cooking and not game.cooking:
		var old_car = game.in_car
		var old_walker = game.walker
		game.in_car = false
		game.walker = game.camp.position
		game.start_grill()
		game.in_car = old_car
		game.walker = old_walker
	game.cook_time = w.cook_time
	game.eaten = w.eaten
	game.racing = w.racing
	game.passed = w.passed
	game.helped = w.helped
	game.elapsed = w.elapsed
	game.target_clearing = w.clearing
	var present = {}
	for r in w.racers:
		present[r.id] = true
		var exists = false
		for local in game.racers:
			if local.id == r.id:
				local.state = r.state
				exists = true
				break
		if not exists:
			var node = Props.car(Color.WHITE, true, int(r.variant))
			game.add_child(node)
			node.position = v(r.pos)
			node.set_meta("room_id", r.id)
			game.racers.append({"id": r.id, "node": node, "state": r.state, "variant": r.variant})
		racer_targets[r.id] = r
	for local in game.racers.duplicate():
		if not present.has(local.id):
			local.node.queue_free()
			game.racers.erase(local)
			racer_targets.erase(local.id)
	game._cancel_tow()
	for local in game.racers:
		if local.id == w.tow:
			game.tow_target = local.node
	game.tow_progress = w.tow_progress
	tow_owner = w.tow_owner
	if game.tow_target != null:
		var origin = game.car.position
		if peers.has(tow_owner) and peers[tow_owner].state != null:
			origin = v(peers[tow_owner].state.car)
		game.rope_mesh = Props.rope(game, origin + Vector3(0, 0.5, 0), game.tow_target.position + Vector3(0, 0.5, 0))
	if (w.dead or w.finished) and not game.dead and not game.finished:
		game.dead = w.dead
		game.finished = w.finished
		game._show_result(w.title, w.text)

func update_tow(delta: float) -> void:
	var players = {player_id: local_state()}
	for id in peers:
		if peers[id].state != null:
			players[id] = peers[id].state
	if game.tow_target == null:
		tow_owner = ""
		for id in players:
			var p = players[id]
			if not p.tow:
				continue
			for r in game.racers:
				if r.state == "stranded" and v(p.pos).distance_to(r.node.position) < 5 and v(p.car).distance_to(r.node.position) <= 24:
					game.tow_target = r.node
					tow_owner = id
					break
			if game.tow_target != null:
				break
	if game.tow_target == null:
		return
	if not players.has(tow_owner):
		game._cancel_tow()
		return
	var p = players[tow_owner]
	var origin = v(p.car)
	if origin.distance_to(game.tow_target.position) > 26:
		game._cancel_tow()
		return
	if game.rope_mesh != null:
		game.rope_mesh.queue_free()
	game.rope_mesh = Props.rope(game, origin + Vector3(0, 0.5, 0), game.tow_target.position + Vector3(0, 0.5, 0))
	if p.tow and (p.in_car or v(p.pos).distance_to(game.tow_target.position) < 6):
		game.tow_progress += delta / 6
		if game.tow_progress >= 1:
			for r in game.racers:
				if r.node == game.tow_target:
					r.state = "racing"
					r.kind = "pass"
					r.counted = true
					r.s += 10
					game.helped += 1
			game._cancel_tow()

func check_remote_collisions() -> void:
	for peer in peers.values():
		if peer.state == null:
			continue
		for r in game.racers:
			if r.state in ["racing", "offroad"]:
				var pos = v(peer.state.pos)
				var d = Vector2(pos.x - r.node.position.x, pos.z - r.node.position.z).length()
				if d < (2.6 if peer.state.in_car else 1.65):
					game.die("Раллийная машина задела участника вашей компании.\nСовместный выезд окончен.")
					return

func leave() -> void:
	if busy:
		http.cancel_request()
		busy = false
	connected = false
	_request("leave", {"token": token})

func disconnect_room(message: String) -> void:
	connected = false
	game.paused = true
	game.menu.show()
	game.menu_title.text = "Комната закрыта"
	game.menu_text.text = message
	game.start_button.text = "В ГЛАВНОЕ МЕНЮ"
	game.dead = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if game.mobile_controls != null:
		game.mobile_controls.reset_input()
	room_label.text = message
	exit_button.hide()
