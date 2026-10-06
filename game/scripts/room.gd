extends Node
# HTTP transport works with the existing minimal web template (no WebSocket module).
const SnapshotMotion = preload("res://scripts/snapshot_motion.gd")
const SYNC_INTERVAL = 0.1
var server_offset = 0.0
var clock_initialized = false
var best_round_trip = INF
var request_sent_at = 0.0
var last_world_time = -1.0
var racer_motion: Dictionary = {}
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
	_request("create" if id == "" else "join", {"name": name_input.text, "car_model": game.selected_car, "stage": game.selected_stage})

func _request(kind: String, body: Dictionary) -> void:
	request_kind = kind
	request_sent_at = Time.get_ticks_usec() / 1000000.0
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
	if data.has("server_time"):
		update_server_clock(float(data.server_time))
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
		game.select_stage(int(data.get("stage", 0)))
		game.start_game()
		# Separate parked cars at the start; local movement remains responsive.
		var lane = int(data.get("slot", 0))
		game.avatar_variant = posmod(lane, Props.SPECTATOR_MODELS.size())
		game.select_player_car(int(data.get("car_model", game.selected_car)))
		game.car.position = game.stage.at(12 + lane * 6)
		game.toast("Комната %s · %s. Передай ID друзьям!" % [room_id, game.car.get_meta("model")])
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
				var stamp = float(data.get("world_time", -1))
				if stamp < 0 or stamp > last_world_time:
					apply_world(data.world, stamp / 1000.0 if stamp >= 0 else -1.0)
					last_world_time = stamp
		room_label.text = "ID %s · %d/8 · %s%s" % [room_id, peers.size() + 1, "СОЗДАТЕЛЬ" if is_host else "ЗРИТЕЛЬ", " · ПАУЗА ХОЗЯИНА" if world_paused else ""]

func update_server_clock(server_msec: float) -> void:
	var now = Time.get_ticks_usec() / 1000000.0
	var round_trip = clampf(now - request_sent_at, 0, 2.0)
	var estimate = server_msec / 1000.0 - now + round_trip * 0.5
	best_round_trip = minf(best_round_trip, round_trip)
	if not clock_initialized:
		server_offset = estimate
		clock_initialized = true
	elif round_trip <= best_round_trip + 0.05:
		# A slow first response must not leave the room clock permanently behind.
		# Slow outliers cannot move a clock calibrated by faster round trips.
		if absf(estimate - server_offset) > 0.2:
			server_offset = estimate
		else:
			server_offset += clampf((estimate - server_offset) * 0.1, -0.01, 0.01)

func server_clock() -> float:
	return Time.get_ticks_usec() / 1000000.0 + server_offset

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
	if not busy and clock >= SYNC_INTERVAL:
		clock = fmod(clock, SYNC_INTERVAL)
		var body = {"token": token, "state": local_state(), "commands": commands}
		if is_host:
			body.world = world_state()
			body.ack = acknowledgements
		_request("sync", body)
	for peer in peers.values():
		if peer.state == null:
			continue
		var car_pose = peer.car_motion.render(server_clock())
		peer.car.position = car_pose.position
		peer.car.rotation = car_pose.rotation
		var avatar_pose = peer.avatar_motion.render(server_clock())
		peer.avatar.position = avatar_pose.position
		peer.avatar.rotation.y = avatar_pose.rotation.y
		peer.avatar.visible = not peer.state.in_car
		var collapsed = int(peer.state.get("beers", 0)) >= 30
		peer.avatar.rotation.z = lerp_angle(peer.avatar.rotation.z, PI / 2 if collapsed else 0.0, 1.0 - exp(-delta * 8))
		if collapsed:
			peer.avatar.position.y = avatar_pose.position.y + 0.25
		var food_sample = float(peer.state.get("eat", -1))
		if food_sample != peer.eat_sample:
			peer.eat_time = food_sample
			peer.eat_sample = food_sample
		if peer.eat_time >= 0 and not world_paused and not game.paused:
			peer.eat_time = minf(3.6, peer.eat_time + delta)
		peer.skewer.visible = peer.eat_time >= 0 and peer.eat_time < 3.6 and not peer.state.in_car
		var drink_sample = float(peer.state.beer)
		if drink_sample != peer.drink_sample:
			peer.drink_time = drink_sample
			peer.drink_sample = drink_sample
		if peer.drink_time >= 0 and not world_paused and not game.paused:
			peer.drink_time = minf(3.3, peer.drink_time + delta)
		peer.can.visible = peer.drink_time >= 0 and peer.drink_time < 3.3 and not peer.skewer.visible and not peer.state.in_car
		if peer.skewer.visible:
			peer.arm.rotation.x = lerpf(0.25, 2.3, Props.food_lift(peer.eat_time))
			peer.arm.rotation.z = -0.45 * Props.food_lift(peer.eat_time)
			peer.skewer.rotation.x = -Props.food_lift(peer.eat_time)
			Props.pose_skewer(peer.skewer, peer.eat_time)
		else:
			peer.arm.rotation.z = 0
			var lift = smoothstep(0.8, 1.25, peer.drink_time) * (1.0 - smoothstep(2.5, 3.3, peer.drink_time))
			peer.arm.rotation.x = lerpf(0.5, 1.6, lift)
			peer.can.rotation.x = 0.35 * lift
		peer.label.position = peer.car.position + Vector3(0, 2.8, 0) if peer.state.in_car else peer.avatar.position + Vector3(0, 2.3, 0)
	if not is_host:
		if not world_paused and not game.paused and not game.dead and not game.finished:
			for stone in game.stones:
				if not game._advance_gravel(stone, delta):
					stone.node.hide()
		var nearest: Node3D = null
		var nearest_distance = INF
		for racer in game.racers:
			if racer.state in ["racing", "offroad", "rock_bounce"] and not world_paused and not game.dead and not game.finished:
				var distance = racer.node.position.distance_to(game.player_position())
				if distance < nearest_distance:
					nearest = racer.node
					nearest_distance = distance
			if racer_motion.has(racer.id):
				var frozen = world_paused or game.dead or game.finished
				var pose = racer_motion[racer.id].render(server_clock(), frozen)
				racer.node.position = pose.position
				racer.node.rotation = pose.rotation


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

func tree_requests() -> Array:
	var result = []
	for index in game.tree_requests:
		result.append({"id": index, "dir": a(game.tree_requests[index])})
	return result.slice(0, 8)

func local_state() -> Dictionary:
	return {"pos": a(game.player_position()), "car": a(game.car.position), "heading": game.heading, "tilt": a(game.car.rotation), "yaw": game.view_yaw, "pitch": game.view_pitch, "in_car": game.in_car, "tow": Input.is_action_pressed("tow") and not game.paused and not game.dead and game.beers < 30, "speed": game.speed, "beers": game.beers, "trees": tree_requests(), "beer": game.drink_time, "eat": game.eat_time}

func _update_peers(players: Array) -> void:
	var present = {}
	for p in players:
		if p.id == player_id:
			continue
		present[p.id] = true
		if not peers.has(p.id):
			var car = Props.player_car(int(p.get("car_model", p.get("slot", 0))))
			game.add_child(car)
			var avatar = Props.player_avatar(int(p.get("slot", 0)))
			game.add_child(avatar)
			var arm = avatar.get_node("RightArm")
			var can = arm.get_node("BeerCan")
			var skewer = arm.get_node("Skewer")
			var label = Props.label_3d(game, Vector3.ZERO, p.name, 26, 0.012, Color("fff1cb"))
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			peers[p.id] = {"id": p.id, "car": car, "avatar": avatar, "arm": arm, "can": can, "skewer": skewer, "eat_time": -1.0, "eat_sample": -1.0, "drink_time": -1.0, "drink_sample": -1.0, "label": label, "last_car": null, "state": null, "car_motion": SnapshotMotion.new(), "avatar_motion": SnapshotMotion.new()}
			if p.state != null:
				car.position = v(p.state.car)
				avatar.position = v(p.state.pos)
		if p.state != null:
			var peer = peers[p.id]
			var switched = peer.state != null and peer.state.in_car != p.state.in_car
			var sample_time = float(p.state_time) / 1000.0 if p.has("state_time") else server_clock()
			var tilt = v(p.state.get("tilt", [0, p.state.heading, 0]))
			tilt.y = p.state.heading
			peer.car_motion.push(sample_time, v(p.state.car), tilt)
			peer.avatar_motion.max_speed = 12.0
			peer.avatar_motion.push(sample_time, v(p.state.pos), Vector3(0, p.state.yaw, 0), switched)
		peers[p.id].state = p.state
	for id in peers.keys():
		if not present.has(id):
			for node in [peers[id].car, peers[id].avatar, peers[id].label]:
				node.queue_free()
			peers.erase(id)

func submit(action: String, placement: Dictionary = {}) -> bool:
	if not connected or is_host or action not in SHARED_ACTIONS:
		return false
	if commands.size() < 8:
		sequence += 1
		commands.append({"seq": sequence, "action": action, "placement": placement})
		clock = SYNC_INTERVAL
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
	var placement = c.get("placement", {})
	var spot = v(placement.pos) if placement.has("pos") else Vector3.INF
	var yaw = float(placement.get("yaw", 0.0))
	if spot != Vector3.INF and (spot.distance_to(game.walker) > 5.0 or int(c.state.get("beers", 0)) >= 30):
		game.in_car = old.in_car
		game.walker = old.walker
		game.car.position = old.car
		game.view_yaw = old.yaw
		return
	match c.action:
		"table": game.place_table(spot, yaw)
		"chairs": game.place_chairs(spot, yaw, str(c.get("player", "guest")))
		"grill": game.start_grill(spot, yaw)
		"eat": game.commit_meat()
		"rally": game.start_rally()
		"random_spot":
			game.target_clearing = game.rng.randi_range(0, game.stage.clearings.size() - 1)
			game.toast("Выбрана поляна %d." % (game.target_clearing + 1))
	game.in_car = old.in_car
	game.walker = old.walker
	game.car.position = old.car
	game.view_yaw = old.yaw

func world_state() -> Dictionary:
	var chair_poses = {}
	for owner in game.personal_chairs:
		var chair = game.personal_chairs[owner]
		chair_poses[owner] = {"pos": a(chair.position), "yaw": chair.rotation.y}
	var racers = []
	for r in game.racers:
		racers.append({"id": r.id, "variant": r.variant, "pos": a(r.node.position), "yaw": r.node.rotation.y, "tilt": a(r.node.rotation), "state": r.state})
	return {"chair_poses": chair_poses, "table_yaw": game.camp.rotation.y if game.camp != null else 0.0, "grill_pose": {"pos": a(game.grill.position), "yaw": game.grill.rotation.y} if game.grill != null else null, "fallen": game.stage.tree_snapshot(), "stones": stone_state(), "impacts": game.impact_serials, "camp": a(game.camp.position) if game.camp != null else null, "chairs": game.has_chairs, "cooking": game.cooking, "cook_time": game.cook_time, "eaten": game.eaten, "racing": game.racing, "passed": game.passed, "helped": game.helped, "elapsed": game.elapsed, "clearing": game.target_clearing, "paused": game.paused, "dead": game.dead, "finished": game.finished, "title": game.menu_title.text, "text": game.menu_text.text, "racers": racers, "tow": game.tow_target.get_meta("room_id") if game.tow_target != null else -1, "tow_progress": game.tow_progress, "tow_owner": tow_owner, "notice": game.toast_label.text, "notice_time": game.toast_time}

func stone_state() -> Array:
	var result = []
	for stone in game.stones:
		result.append({"id": stone.id, "pos": a(stone.node.position), "velocity": a(stone.velocity), "bounces": int(stone.get("bounces", 0))})
	return result

var last_impact = 0
func apply_stones(w: Dictionary, sample_time: float = -1.0) -> void:
	var age = clampf(server_clock() - sample_time, 0, 0.15) if sample_time >= 0 else 0.0
	var count = int(w.get("impacts", {}).get(player_id, 0))
	if count > last_impact:
		game.impact_shake = 0.8
		if game.in_car:
			game.condition = maxf(0, game.condition - (count - last_impact) * 0.8)
		game.toast("Гравий из-под колёс! Отойди дальше от края СУ.")
	last_impact = count
	var present = {}
	for remote in w.get("stones", []):
		var velocity = v(remote.velocity) + Vector3(0, -9.8 * age, 0)
		var position = v(remote.pos) + v(remote.velocity) * age + Vector3(0, -4.9 * age * age, 0)
		present[remote.id] = true
		var found = false
		for stone in game.stones:
			if stone.id == remote.id:
				stone.node.position = stone.node.position.lerp(position, 0.35) if stone.node.position.distance_to(position) < 3 else position
				stone.velocity = velocity
				stone.bounces = int(remote.get("bounces", 0))
				stone.node.show()
				found = true
		if not found:
			var node = Props.box(game, position, Vector3.ONE * 0.10, Color("9b9079"))
			game.stones.append({"id": remote.id, "node": node, "velocity": velocity, "bounces": int(remote.get("bounces", 0))})
	for stone in game.stones.duplicate():
		if not present.has(stone.id):
			stone.node.queue_free()
			game.stones.erase(stone)

func apply_world(w: Dictionary, sample_time: float = -1.0) -> void:
	if sample_time < 0:
		sample_time = server_clock()
	game.stage.apply_trees(w.get("fallen", []))
	for f in w.get("fallen", []):
		game.tree_requests.erase(int(f.id))
	apply_stones(w, sample_time)
	world_paused = w.paused
	if w.get("notice_time", 0) > 0 and w.get("notice", "") != last_notice:
		last_notice = w.notice
		game.toast(last_notice)
	if w.camp != null:
		if game.camp == null:
			game.camp = Node3D.new()
			game.add_child(game.camp)
			Props.table(game.camp)
		game.camp.position = v(w.camp)
		game.camp.rotation.y = float(w.get("table_yaw", 0.0))
	if w.has("chair_poses"):
		for owner in w.chair_poses:
			var pose = w.chair_poses[owner]
			game.apply_chair(owner, v(pose.pos), float(pose.yaw))
	else:
		if w.chairs and not game.has_chairs and game.camp != null:
			game.apply_chair("legacy", game.camp.position + Vector3(-1.6, 0, 0.7), 0.0)
	game.has_chairs = w.chairs
	if w.cooking:
		var grill_pose = w.get("grill_pose", null)
		var spot = v(grill_pose.pos) if grill_pose != null else game.camp.position + Vector3(0.3, 0, -2.4)
		var yaw = float(grill_pose.yaw) if grill_pose != null else 0.0
		game.start_grill(spot, yaw, true)
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
		if not racer_motion.has(r.id):
			racer_motion[r.id] = SnapshotMotion.new()
		var tilt = v(r.get("tilt", [0, r.yaw, 0]))
		tilt.y = r.yaw
		racer_motion[r.id].push(sample_time, v(r.pos), tilt)
		racer_targets[r.id] = r
	for local in game.racers.duplicate():
		if not present.has(local.id):
			local.node.queue_free()
			game.racers.erase(local)
			racer_targets.erase(local.id)
			racer_motion.erase(local.id)
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
	var people = [{"id": player_id, "state": local_state()}]
	for peer in peers.values():
		if peer.state != null:
			people.append({"id": peer.id, "state": peer.state})
	for peer in peers.values():
		if peer.state == null:
			continue
		var previous = v(peer.state.car) if peer.last_car == null else peer.last_car
		var current = v(peer.state.car)
		for request in peer.state.get("trees", []):
			var index = int(request.id)
			if index >= 0 and index < game.stage.trees.size() and current.distance_to(game.stage.trees[index]) < 4 and absf(float(peer.state.get("speed", 0))) > 1:
				game.knock_tree(index, v(request.dir))
		if absf(float(peer.state.get("speed", 0))) > 5:
			for person in people:
				if person.id != peer.id and not person.state.in_car and game.Motion.swept_hit(previous + Vector3(0, 0.7, 0), current + Vector3(0, 0.7, 0), v(person.state.pos) + Vector3(0, 0.7, 0), 1.55):
					game.die("Легковушка сбила участника вашей компании.")
					return
		peer.last_car = current
	for peer in peers.values():
		if peer.state == null:
			continue
		for r in game.racers:
			if r.state in ["racing", "offroad", "rock_bounce"]:
				var pos = v(peer.state.pos)
				if game.Motion.swept_hit(r.get("previous", r.node.position) + Vector3(0, 0.7, 0), r.node.position + Vector3(0, 0.7, 0), pos + Vector3(0, 0.7, 0), 2.6 if peer.state.in_car else 1.65):
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
