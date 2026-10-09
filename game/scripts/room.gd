extends Node
# HTTP transport works with the existing minimal web template (no WebSocket module).
const Prediction = preload("res://scripts/drive_prediction.gd")
var prediction = Prediction.new()
var host_drives: Dictionary = {}
var prediction_enabled = false
var input_clock = 0.0
var authoritative_drives: Dictionary = {}
var authority_stamp = -1.0
var drive_budgets: Dictionary = {}
var visual_children: Dictionary = {}
const SnapshotMotion = preload("res://scripts/snapshot_motion.gd")
const SYNC_INTERVAL = 0.1
var server_offset = 0.0
var clock_initialized = false
var best_round_trip = INF
var round_trip_ms = 0.0
var network_jitter_ms = 0.0
var previous_round_trip = -1.0
var diagnostic_clock = 0.0
var request_sent_at = 0.0
var last_world_time = -1.0
var racer_motion: Dictionary = {}
const Props = preload("res://scripts/props.gd")
const SHARED_ACTIONS = ["table", "chairs", "grill", "flag", "eat", "rally", "collect", "mount_mushroom", "eat_mushroom", "eat_berries", "pack", "take_gear", "return_gear", "trunk", "firewood", "cauldron", "plov_cook", "eat_plov", "church_bell", "dig_snow"]
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
var racer_targets: Dictionary = {}
var last_ui_size = Vector2.ZERO
var last_mobile = false

# In browser builds the Worker serves /api/rooms on the same origin as /vk/.
# Never attempt to connect to the user's 127.0.0.1 or downgrade HTTPS to HTTP.
# Native development still uses the localhost Worker unless overridden.
static func default_server(is_web: bool) -> String:
	return "" if is_web else "http://127.0.0.1:8787"

func room_endpoint(kind: String) -> String:
	return server + ("/api/rooms" if kind == "create" else "/api/rooms/%s/%s" % [room_id, kind])

func _ready() -> void:
	server = default_server(OS.has_feature("web"))
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
	lobby = PanelContainer.new()
	game.menu_content.add_child(lobby)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	lobby.add_child(box)
	game._label(box, "НАЧАТЬ ВЫЕЗД", 16, Color("dfb270"))
	name_input = LineEdit.new()
	name_input.placeholder_text = "Твой ник"
	name_input.max_length = 24
	name_input.text = "Овощ"
	name_input.custom_minimum_size.y = 48
	name_input.add_theme_font_size_override("font_size", 22)
	var fields = HBoxContainer.new()
	fields.add_theme_constant_override("separation", 12)
	box.add_child(fields)
	name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_child(name_input)
	id_input = LineEdit.new()
	id_input.placeholder_text = "ID комнаты · 6 символов"
	id_input.max_length = 6
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
	create_button.pressed.connect(func(): connect_room(""))
	join_button.pressed.connect(func():
		if id_input.text.strip_edges() == "":
			lobby_status.text = "Введи ID комнаты."
		else:
			connect_room(id_input.text.strip_edges().to_upper())
	)
	lobby_status = game._label(box, "До 8 игроков. Общий лагерь и ралли.\nСоздатель должен оставаться в комнате.", 18)
	lobby_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	id_input.text_changed.connect(func(_text): game.lobby_ui.refresh())
	game.lobby_ui.refresh.call_deferred()
	room_label = game._label(ui, "", 18, Color("ffe4a5"))
	room_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	room_label.offset_left = 36
	room_label.offset_right = -180
	room_label.offset_top = -45
	room_label.offset_bottom = -8
	room_label.hide()

func connect_room(id: String) -> void:
	if game.platform_service != null and (not game.platform_service.can_use("car", game.car_choice.selected) or (id == "" and not game.platform_service.can_use("stage", game.stage_choice.selected))):
		lobby_status.text = "Выбери доступную машину и СУ."
		return
	if busy or connected or game.loading_world:
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
	var err = http.request(room_endpoint(kind), ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_response(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())

# Convert an already-running solo stage to a hosted room without losing the
# local player's furniture, carried gear, foraged food or placement ownership.
func _adopt_local_host_state() -> void:
	if player_id.is_empty():
		return
	for mapping in [game.personal_chairs, game.personal_flags, game.foraging.inventories, game.foraging.effects, game.cargo.opened]:
		if mapping.has("local"):
			mapping[player_id] = mapping["local"]
			mapping.erase("local")
	if game.cargo.held.has("local"):
		var carry: Dictionary = game.cargo.held["local"]
		if str(carry.get("owner", "")) == "local":
			carry["owner"] = player_id
		game.cargo.held[player_id] = carry
		game.cargo.held.erase("local")
	for item in game.packing.items():
		if str(item.node.get_meta("gear_owner", "")) == "local":
			item.node.set_meta("gear_owner", player_id)

func _response(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
	busy = false
	var parser = JSON.new()
	var data = parser.data if parser.parse(bytes.get_string_from_utf8()) == OK else null
	if request_kind == "leave":
		game.get_tree().reload_current_scene()
		return
	if result == HTTPRequest.RESULT_SUCCESS and code == 429 and connected:
		var retry = clampf(float(data.get("retry_after", 10)) if data is Dictionary else 10.0, 1.0, 60.0)
		clock = -retry
		room_label.text = "Слишком много запросов. Повторим через %d сек." % ceili(retry)
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
			if game.invite_after_room_create:
				game.invite_after_room_create = false
				game.invite_status.text = "Не удалось создать комнату: " + message
				game.invite_status.show()
				game.invite_button.disabled = false
				game.toast(game.invite_status.text)
			game.lobby_ui.refresh()
		return
	errors = 0
	if data.has("server_time"):
		update_server_clock(float(data.server_time))
	if request_kind in ["create", "join"]:
		prediction = Prediction.new()
		prediction_enabled = false
		input_clock = 0.0
		host_drives.clear()
		drive_budgets.clear()
		authoritative_drives.clear()
		authority_stamp = -1.0
		var converting_solo = game.playing and bool(data.host)
		player_id = data.player
		token = data.token
		is_host = data.host
		if is_host:
			room_id = data.room
		connected = true
		if converting_solo:
			_adopt_local_host_state()
		for control in [name_input, id_input, create_button, join_button]:
			control.release_focus()
		lobby.hide()
		room_label.show()
		if not converting_solo:
			game.select_stage(int(data.get("stage", 0)), not is_host)
			game.select_player_car(int(data.get("car_model", game.selected_car)))
			await game.start_game()
			# New guests and lobby hosts spawn at the start; a player already
			# watching the stage keeps their current parking and camp position.
			var lane = int(data.get("slot", 0))
			game.avatar_variant = posmod(lane, Props.SPECTATOR_MODELS.size())
			game.car.position = game.stage.at(12 + lane * 6)
		game.toast("Комната %s · %s. Передай ID друзьям!" % [room_id, game.car.get_meta("model")])
		if game.invite_after_room_create:
			game.invite_after_room_create = false
			game._invite_friends()
		print("ROOM_CONNECTED ", room_id, " host=", is_host)
	else:
		if not is_host and data.world is Dictionary:
			var drive_stamp = float(data.get("world_time", -1))
			if drive_stamp > authority_stamp:
				authoritative_drives = data.world.get("driving", {})
				authority_stamp = drive_stamp
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
					prediction_enabled = int(data.world.get("drive_protocol", 0)) == 1
					var drive = data.world.get("driving", {}).get(player_id, {})
					if prediction_enabled and not drive.is_empty():
						if not prediction.active:
							prediction.reset(v(drive.pos), drive.yaw)
						prediction.context = drive_context(player_id)
						# Apply world collision geometry before replaying unacknowledged input.
						if game.stage.winter:
							game.stage.snow.authoritative = false
							game.stage.snow.apply_snapshot(data.world.get("snow", []))
							game.stage.snow.apply_dug_snapshot(data.world.get("snow_dug", []))
						game.stage.apply_trees(data.world.get("fallen", []))
						if game.stage.urban:
							game.stage.city.apply_snapshot(data.world.get("city_lamps", []))
						prediction.reconcile(drive, game.stage, game.selected_car)
						game.condition = prediction.condition
						game.car.position = prediction.node.position
						game.heading = prediction.yaw
					apply_world(data.world, stamp / 1000.0 if stamp >= 0 else -1.0)
					last_world_time = stamp
		room_label.text = "ID %s · %d/8 · %s%s" % [room_id, peers.size() + 1, "СОЗДАТЕЛЬ" if is_host else "ЗРИТЕЛЬ", " · ПАУЗА ХОЗЯИНА" if world_paused else ""]

func update_server_clock(server_msec: float) -> void:
	var now = Time.get_ticks_usec() / 1000000.0
	var round_trip = clampf(now - request_sent_at, 0, 2.0)
	round_trip_ms = round_trip * 1000.0
	if previous_round_trip >= 0:
		network_jitter_ms = lerpf(network_jitter_ms, absf(round_trip - previous_round_trip) * 1000.0, 0.2)
	previous_round_trip = round_trip
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
	if not connected or game.loading_world:
		return
	clock += delta
	if not busy and clock >= SYNC_INTERVAL:
		clock = fmod(clock, SYNC_INTERVAL)
		var body = {"token": token, "state": local_state(), "commands": commands}
		if is_host:
			body.world = world_state()
			body.ack = acknowledgements
		_request("sync", body)
	diagnostic_clock += delta
	if diagnostic_clock >= 5.0:
		diagnostic_clock = 0.0
		print("[RFM network] RTT=%.0fms jitter=%.0fms peers=%d" % [round_trip_ms, network_jitter_ms, peers.size()])
	game.cargo.refresh_opened()
	for peer in peers.values():
		if peer.state == null:
			continue
		var frozen = world_paused or game.paused or game.dead or game.finished
		var car_pose = peer.car_motion.render(server_clock(), frozen)
		peer.car.position = car_pose.position
		peer.car.rotation = car_pose.rotation
		Props.animate_wheels(peer.car)
		var avatar_pose = peer.avatar_motion.render(server_clock(), frozen)
		peer.avatar.position = avatar_pose.position
		peer.avatar.rotation.y = avatar_pose.rotation.y
		peer.avatar.visible = not peer.state.in_car
		Props.update_player_trunk(peer.car, bool(game.cargo.opened.get(peer.id, false)), game.cargo.boxes(peer.id), delta)
		var carry = game.cargo.held.get(peer.id, {})
		var kind = str(carry.get("kind", ""))
		if kind != "" and kind != peer.held_kind:
			peer.held_box.queue_free()
			peer.held_box = Props.gear_box(peer.avatar, kind, Vector3(0, 1.0, -0.5))
			peer.held_kind = kind
		peer.held_box.visible = kind != "" and not peer.state.in_car
		var sitting = bool(peer.state.get("seated", false)) and not peer.state.in_car
		peer.avatar.position.y -= 0.2 if sitting else 0.0
		for leg_name in ["LeftLeg", "RightLeg"]:
			var leg = peer.avatar.get_node_or_null(leg_name)
			if leg != null:
				var moving = v(peer.state.get("push", [0, 0, 0])).length() > 0.1
				var wave = sin(server_clock() * (13 if peer.state.get("running", false) else 8)) * (0.7 if peer.state.get("running", false) else 0.35)
				leg.rotation.x = PI / 2 if sitting else (0.6 if peer.state.get("airborne", false) else (wave * (-1 if leg_name == "LeftLeg" else 1) if moving else 0.0))
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
			Props.pose_food(peer.skewer, peer.eat_time, str(peer.state.get("food_kind", "meat")))
			Props.style_mushrooms(peer.skewer, str(peer.state.get("food_species", "edible")))
		else:
			peer.arm.rotation.z = 0
			var lift = smoothstep(0.8, 1.25, peer.drink_time) * (1.0 - smoothstep(2.5, 3.3, peer.drink_time))
			peer.arm.rotation.x = lerpf(0.5, 1.6, lift)
			peer.can.rotation.x = 0.35 * lift
		if peer.held_box.visible and not peer.can.visible and not peer.skewer.visible:
			peer.arm.rotation.x = -0.9
			peer.avatar.get_node("LeftArm").rotation.x = -0.9
		else:
			peer.avatar.get_node("LeftArm").rotation.x = 0.0
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
			Props.update_course_lights(racer.node, game.elapsed)
			if racer_motion.has(racer.id):
				var frozen = world_paused or game.dead or game.finished
				var pose = racer_motion[racer.id].render(server_clock(), frozen)
				racer.node.position = pose.position
				racer.node.rotation = pose.rotation


		game.draw_recovery_ropes()
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

func lamp_requests() -> Array:
	var result = []
	for index in game.lamp_requests:
		result.append({"id": index, "dir": a(game.lamp_requests[index])})
	return result.slice(0, 8)

func local_state() -> Dictionary:
	return {"drive_enabled": prediction_enabled, "drive_inputs": prediction.pending if prediction_enabled else [], "pos": a(game.player_position()), "car": a(game.car.position), "heading": game.heading, "tilt": a(game.car.rotation), "yaw": game.view_yaw, "pitch": game.view_pitch, "in_car": game.in_car, "tow": Input.is_action_pressed("tow") and not game.in_car and not game.paused and not game.dead and not game.finished and game.beers < 30 and game.drink_time < 0 and game.eat_time < 0, "push": a(game.walking_intent()), "speed": game.speed, "beers": game.beers, "trees": tree_requests(), "lamps": lamp_requests(), "beer": game.drink_time, "eat": game.eat_time, "food_kind": game.eat_kind, "food_species": game.food_species, "seated": game.seated, "running": game.running(), "airborne": game.jump_height > 0.01}

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
			var carried_box = Props.gear_box(avatar, "table", Vector3(0, 1.0, -0.5))
			carried_box.name = "CarriedBox"
			carried_box.hide()
			var arm = avatar.get_node("RightArm")
			var can = arm.get_node("BeerCan")
			var skewer = arm.get_node("Skewer")
			var label = Props.label_3d(game, Vector3.ZERO, p.name, 26, 0.012, Color("fff1cb"))
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			peers[p.id] = {"id": p.id, "car": car, "avatar": avatar, "arm": arm, "held_box": carried_box, "held_kind": "table", "can": can, "skewer": skewer, "eat_time": -1.0, "eat_sample": -1.0, "drink_time": -1.0, "drink_sample": -1.0, "label": label, "last_car": null, "state": null, "car_motion": SnapshotMotion.new(), "avatar_motion": SnapshotMotion.new()}
			if p.state != null:
				car.position = v(p.state.car)
				avatar.position = v(p.state.pos)
		if is_host and p.state != null and (bool(p.state.get("drive_enabled", false)) or host_drives.has(p.id)):
			if not host_drives.has(p.id):
				var solver = Prediction.new()
				solver.reset(game.stage.at(12 + int(p.get("slot", 1)) * 6), atan2(-game.stage.direction(12).x, -game.stage.direction(12).z))
				drive_budgets[p.id] = {"time": Time.get_ticks_usec(), "ticks": 30.0}
				host_drives[p.id] = solver
			var solver = host_drives[p.id]
			var budget = drive_budgets[p.id]
			var now = Time.get_ticks_usec()
			budget.ticks = minf(120.0, budget.ticks + maxf(0, (now - budget.time) / 1000000.0) * 120.0)
			budget.time = now
			solver.context = drive_context(str(p.id))
			if not game.paused and not game.dead and not game.finished:
				budget.ticks -= solver.accept(p.state.get("drive_inputs", []), game.stage, int(p.get("car_model", 0)), int(budget.ticks))
				apply_drive_events(solver, true)
			else:
				# Acknowledgement prevents pre-pause inputs from playing after resume.
				for c in p.state.get("drive_inputs", []):
					if int(c.seq) == solver.ack + 1:
						solver.ack = int(c.seq)
			if not p.state.in_car:
				solver.motion.velocity = Vector3.ZERO
			p.state.car = a(solver.node.position)
			if p.state.in_car:
				p.state.pos = p.state.car
			p.state.heading = solver.yaw
			p.state.speed = solver.motion.velocity.dot(Vector3(-sin(solver.yaw), 0, -cos(solver.yaw)))
			p.state.tilt = a(solver.node.rotation)
		elif not is_host and p.state != null and authoritative_drives.has(p.id):
			var drive = authoritative_drives[p.id]
			p.state.car = drive.pos
			p.state.heading = drive.yaw
			p.state.tilt = [drive.pitch, drive.yaw, drive.roll]
			p.state.speed = v(drive.velocity).dot(Vector3(-sin(drive.yaw), 0, -cos(drive.yaw)))
			if p.state.in_car:
				p.state.pos = drive.pos
		if p.state != null:
			var peer = peers[p.id]
			var sample_time = float(p.state_time) / 1000.0 if p.has("state_time") else server_clock()
			if is_host and host_drives.has(p.id):
				sample_time = server_clock()
			elif not is_host and authoritative_drives.has(p.id):
				sample_time = authority_stamp / 1000.0
			if peer.has("last_sample_time") and sample_time <= peer.last_sample_time:
				continue
			var switched = peer.state != null and peer.state.in_car != p.state.in_car
			var tilt = v(p.state.get("tilt", [0, p.state.heading, 0]))
			tilt.y = p.state.heading
			peer.car_motion.push(sample_time, v(p.state.car), tilt)
			peer.avatar_motion.max_speed = 12.0
			peer.avatar_motion.push(sample_time, v(p.state.pos), Vector3(0, p.state.yaw, 0), switched)
			peer.last_sample_time = sample_time
		peers[p.id].state = p.state
		if p.state != null:
			peers[p.id].last_state_time = float(p.state_time) / 1000.0 if p.has("state_time") else server_clock()
	for id in peers.keys():
		if not present.has(id):
			for node in [peers[id].car, peers[id].avatar, peers[id].label]:
				node.queue_free()
			peers.erase(id)
			host_drives.erase(id)
			drive_budgets.erase(id)
	game.cargo.release_departed()

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
	var old = {"in_car": game.in_car, "walker": game.walker, "car": game.car.position, "yaw": game.view_yaw, "beers": game.beers}
	game.in_car = c.state.in_car
	game.walker = v(c.state.pos)
	game.car.position = v(c.state.car)
	game.view_yaw = c.state.yaw
	game.beers = int(c.state.get("beers", 0))
	var placement = c.get("placement", {})
	var spot = v(placement.pos) if placement.has("pos") else Vector3.INF
	var yaw = float(placement.get("yaw", 0.0))
	if spot != Vector3.INF and (spot.distance_to(game.walker) > 5.0 or int(c.state.get("beers", 0)) >= 30):
		game.in_car = old.in_car
		game.walker = old.walker
		game.car.position = old.car
		game.view_yaw = old.yaw
		game.beers = old.beers
		return
	var actor = str(c.get("player", "guest"))
	var variant = int(peers[actor].car.get_meta("variant", 0)) if peers.has(actor) and peers[actor].has("car") else 0
	game.cargo.context = {"owner": actor, "car": v(c.state.car), "heading": float(c.state.get("heading", 0.0)), "variant": variant, "host_car": old.car, "speed": float(c.state.get("speed", 0))}
	match c.action:
		"trunk":
			if spot != Vector3.INF:
				game.cargo.toggle(spot)
		"dig_snow":
			if spot != Vector3.INF: game.dig_snow(spot)
		"take_gear":
			var index = int(placement.get("resource_id", -1))
			if index >= 0 and index < game.cargo.KINDS.size():
				game.cargo.take(game.cargo.KINDS[index])
		"return_gear":
			if spot != Vector3.INF:
				game.cargo.return_item(spot)
		"pack":
			if spot != Vector3.INF:
				game.packing.pack(spot, true)
		"table", "chairs", "grill", "firewood", "cauldron":
			if spot != Vector3.INF:
				game.cargo.deploy(str(c.action), spot, yaw)
		"flag":
			if not game.packing.active():
				game.place_flag(spot, yaw, str(c.get("player", "guest")))
		"plov_cook": game.camp_cooking.start()
		"eat_plov": game.camp_cooking.consume()
		"eat": game.commit_meat(int(placement.get("source", -2)))
		"church_bell":
			if game.stage.urban and game.stage.city.bell != null:
				game.stage.city.bell.pull(game.walker)
		"collect": game.foraging.collect(int(placement.get("resource_id", -1)), str(c.get("player", "guest")))
		"mount_mushroom": game.foraging.mount(int(placement.get("source", -2)), str(c.get("player", "guest")))
		"eat_mushroom": game.foraging.consume("mushroom", str(c.get("player", "guest")), int(placement.get("source", -2)))
		"eat_berries": game.foraging.consume("berries", str(c.get("player", "guest")))
		"rally": game.start_rally()
	game.cargo.context = {}
	game.in_car = old.in_car
	game.walker = old.walker
	game.car.position = old.car
	game.view_yaw = old.yaw
	game.beers = old.beers

func world_state() -> Dictionary:
	var chair_poses = {}
	for owner in game.personal_chairs:
		var chair = game.personal_chairs[owner]
		chair_poses[owner] = {"pos": a(chair.position), "yaw": chair.rotation.y}
	var flag_poses = {}
	for owner in game.personal_flags:
		flag_poses[owner] = []
		for flag in game.personal_flags[owner]:
			flag_poses[owner].append({"pos": a(flag.position), "yaw": flag.rotation.y})
	var racers = []
	for r in game.racers:
		racers.append({"id": r.id, "role": r.get("role", "racer"), "zero_index": r.get("zero_index", 0), "variant": r.variant, "pos": a(r.node.position), "yaw": r.node.rotation.y, "tilt": a(r.node.rotation), "state": r.state, "recovery_progress": r.get("recovery_progress", 0), "recovery_helpers": r.get("recovery_helpers", 0)})
	var driving = {}
	for id in host_drives:
		driving[id] = host_drives[id].snapshot()
	return {"drive_protocol": 1, "driving": driving, "camp_cooking": game.camp_cooking.snapshot(), "cargo": game.cargo.snapshot(), "foraging": game.foraging.snapshot(), "course": game.course.snapshot(), "church_bell": game.stage.city.bell.snapshot() if game.stage.urban and game.stage.city.bell != null else {}, "city_lamps": game.stage.city.snapshot() if game.stage.urban else [], "chair_poses": chair_poses, "flag_poses": flag_poses, "table_yaw": game.camp.rotation.y if game.camp != null else 0.0, "grill_pose": {"pos": a(game.grill.position), "yaw": game.grill.rotation.y} if game.grill != null else null, "snow_dug": game.stage.snow.dug_snapshot(), "snow": game.stage.snow.snapshot() if game.stage.winter else [], "fallen": game.stage.tree_snapshot(), "stones": stone_state(), "impacts": game.impact_serials, "camp": a(game.camp.position) if game.camp != null else null, "chairs": game.has_chairs, "cooking": game.cooking, "cook_time": game.cook_time, "grill_servings": game.grill_servings, "npc_servings": game.spectators.snapshot(), "npc_people": game.spectators.actor_snapshot(), "marshals": game.stage.officials.snapshot(), "eaten": game.eaten, "racing": game.racing, "passed": game.passed, "helped": game.helped, "elapsed": game.elapsed, "paused": game.paused, "dead": game.dead, "finished": game.finished, "title": game.menu_title.text, "text": game.menu_text.text, "racers": racers, "tow": game.tow_target.get_meta("room_id") if game.tow_target != null else -1, "tow_progress": game.tow_progress, "tow_owner": tow_owner, "recovery_links": game.recovery_links, "recovery_helpers": game.recovery_helpers, "notice": game.toast_label.text, "notice_time": game.toast_time}

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
			if not prediction_enabled or not prediction.active:
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
	if game.stage.urban:
		game.stage.city.apply_snapshot(w.get("city_lamps", []))
		if game.stage.city.bell != null:
			game.stage.city.bell.apply_snapshot(w.get("church_bell", {}))
		for item in w.get("city_lamps", []):
			game.lamp_requests.erase(int(item.id))
	if game.stage.winter:
		game.stage.snow.authoritative = false
		game.stage.snow.apply_snapshot(w.get("snow", []))
		game.stage.snow.apply_dug_snapshot(w.get("snow_dug", []))
	game.stage.apply_trees(w.get("fallen", []))
	for f in w.get("fallen", []):
		game.tree_requests.erase(int(f.id))
	apply_stones(w, sample_time)
	world_paused = w.paused
	if w.get("notice_time", 0) > 0 and w.get("notice", "") != last_notice:
		last_notice = w.notice
		game.toast(last_notice)
	# Full snapshots reconcile removals as well as additions.
	if w.camp == null and game.camp != null:
		game.packing.remove({"kind": "table", "node": game.camp})
	if w.has("chair_poses"):
		for owner in game.personal_chairs.keys():
			if not w.chair_poses.has(owner):
				game.packing.remove({"kind": "chair", "owner": owner, "node": game.personal_chairs[owner]})
	if w.has("flag_poses"):
		for owner in game.personal_flags.keys():
			if not w.flag_poses.has(owner):
				for node in game.personal_flags[owner].duplicate():
					game.packing.remove({"kind": "flag", "owner": owner, "node": node})
	if not w.cooking and game.grill != null:
		game.packing.remove({"kind": "grill", "node": game.grill})
	if w.camp != null:
		if game.camp == null:
			game.camp = Node3D.new()
			game.add_child(game.camp)
			Props.table(game.camp)
		game.camp.position = v(w.camp)
		game.camp.rotation.y = float(w.get("table_yaw", 0.0))
	if w.has("flag_poses"):
		for owner in w.flag_poses:
			var poses = w.flag_poses[owner]
			var existing: Array = game.personal_flags.get(owner, [])
			while existing.size() > poses.size():
				var old_flag = existing.pop_back()
				old_flag.queue_free()
			for i in range(poses.size()):
				var pose = poses[i]
				if i >= existing.size():
					game.place_flag(v(pose.pos), float(pose.yaw), str(owner), true)
					existing = game.personal_flags.get(owner, [])
				else:
					existing[i].position = v(pose.pos)
					existing[i].rotation.y = float(pose.yaw)
			game.personal_flags[owner] = existing
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
	game.grill_servings = int(w.get("grill_servings", Props.FOOD_PORTIONS))
	if game.grill != null:
		Props.set_grill_servings(game.grill, game.grill_servings)
	game.spectators.apply_snapshot(w.get("npc_servings", []))
	game.spectators.apply_actor_snapshot(w.get("npc_people", []))
	game.stage.officials.apply_snapshot(w.get("marshals", []))
	game.foraging.apply_snapshot(w.get("foraging", {}))
	game.eaten = w.eaten
	game.course.apply_snapshot(w.get("course", {}))
	game.cargo.apply_snapshot(w.get("cargo", {}))
	game.racing = w.racing
	game.passed = w.passed
	game.helped = w.helped
	game.elapsed = w.elapsed
	game.camp_cooking.apply_snapshot(w.get("camp_cooking", {}))
	var present = {}
	for r in w.racers:
		present[r.id] = true
		var exists = false
		for local in game.racers:
			if local.id == r.id:
				local.state = r.state
				local.recovery_progress = float(r.get("recovery_progress", 0))
				local.recovery_helpers = int(r.get("recovery_helpers", 0))
				exists = true
				break
		if not exists:
			var role = str(r.get("role", "racer"))
			var node = Props.car(Color.WHITE, true, int(r.variant)) if role == "racer" else Props.course_car(role, int(r.get("zero_index", 0)))
			game.add_child(node)
			node.position = v(r.pos)
			node.set_meta("room_id", r.id)
			game.racers.append({"id": r.id, "role": role, "zero_index": int(r.get("zero_index", 0)), "node": node, "state": r.state, "variant": r.variant})
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
	game.recovery_links = w.get("recovery_links", []).duplicate(true)
	game.recovery_helpers = int(w.get("recovery_helpers", 0))
	game.draw_recovery_ropes()
	if (w.dead or w.finished) and not game.dead and not game.finished:
		game.dead = w.dead
		game.finished = w.finished
		game._show_result(w.title, w.text)

func update_tow(delta: float) -> void:
	var players = {player_id: local_state()}
	for id in peers:
		var peer: Dictionary = peers[id]
		if peer.state != null and server_clock() - float(peer.get("last_state_time", server_clock())) <= 1.0:
			players[id] = peer.state
	game.Recovery.update(game, players, delta)
	tow_owner = str(game.recovery_links[0].player) if not game.recovery_links.is_empty() else ""

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
		if game.stage.urban:
			for request in peer.state.get("lamps", []):
				var index = int(request.id)
				if index >= 0 and index < game.stage.city.lamps.size() and current.distance_to(game.stage.city.lamps[index].body.position) < 5 and peer.state.in_car and v(request.dir).length() > 5:
					game.stage.city.knock_lamp(index, v(request.dir))
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

func predict_drive(delta: float) -> bool:
	if is_host or not prediction_enabled:
		return false
	if not prediction.active:
		return true
	input_clock += minf(delta, 0.1)
	var ticks = int(input_clock / prediction.motion.handling.STEP)
	input_clock -= ticks * prediction.motion.handling.STEP
	prediction.context = drive_context(player_id)
	prediction.predict(ticks, Input.get_axis("back", "forward"), Input.get_axis("left", "right"), Input.is_action_pressed("brake"), game.stage, game.selected_car)
	apply_drive_events(prediction, false)
	game.condition = prediction.condition
	game.car.position = prediction.node.position
	game.car.rotation = prediction.node.rotation
	game.heading = prediction.yaw
	game.speed = prediction.motion.velocity.dot(Vector3(-sin(game.heading), 0, -cos(game.heading)))
	game.vehicle_motion = prediction.motion
	prediction.visual_offset *= exp(-delta * 10.0)
	prediction.visual_yaw *= exp(-delta * 10.0)
	return true

func drive_context(owner: String) -> Dictionary:
	var contacts: Array = []
	for group in game.spectators.groups:
		contacts.append({"position": group.car.position})
	for person in game.spectators.people:
		contacts.append({"position": person.avatar.position})
	for racer in game.racers:
		contacts.append({"position": racer.node.position})
	if owner != player_id:
		contacts.append({"position": game.car.position})
		if not game.in_car:
			contacts.append({"position": game.walker, "person": true})
	for id in peers:
		var peer = peers[id]
		if id == owner or peer.state == null:
			continue
		contacts.append({"position": v(peer.state.car)})
		if not peer.state.in_car:
			contacts.append({"position": v(peer.state.pos), "person": true})
	return {"contacts": contacts, "racing": game.racing}

func apply_drive_events(solver, authoritative: bool) -> void:
	for event in solver.events:
		match event.kind:
			"tree": game.knock_tree(event.index, event.velocity)
			"city": game.knock_city(event.hit, event.velocity)
			"person":
				if authoritative:
					game.die("Легковушка сбила участника вашей компании.")
			"impact":
				if not authoritative:
					game.impact_shake = minf(0.8, float(event.speed) * 0.055)
					game.toast("Удар! Сбавь скорость.")
	solver.events.clear()
	if authoritative and solver.condition <= 0:
		game.die("Легковушка участника разбита. Совместный выезд окончен.")

func recover_drive() -> bool:
	if is_host or not prediction_enabled:
		return false
	if not prediction.active:
		game.toast("Дождись синхронизации машины с хозяином.")
		return true
	if prediction.pending.size() >= Prediction.LIMIT:
		game.toast("Дождись восстановления связи, затем верни машину на СУ.")
		return true
	prediction.context = drive_context(player_id)
	prediction.predict(1, 0, 0, false, game.stage, game.selected_car, true)
	game.toast("Машина возвращена на СУ.")
	return true

func smooth_car_visuals() -> void:
	var offset = Vector3.ZERO
	if connected and prediction_enabled and prediction.active:
		offset = game.car.basis.inverse() * prediction.visual_offset
	var correction = Transform3D(Basis(Vector3.UP, prediction.visual_yaw if connected and prediction_enabled else 0.0), offset)
	var present = {}
	for child in game.car.get_children():
		if child is Node3D and not child is CollisionObject3D and not child is CollisionShape3D:
			var id = child.get_instance_id()
			child.transform = correction * visual_children.get(id, Transform3D.IDENTITY).affine_inverse() * child.transform
			visual_children[id] = correction
			present[id] = true
	for id in visual_children.keys():
		if not present.has(id):
			visual_children.erase(id)
