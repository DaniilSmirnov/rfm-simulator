extends Node
# A shared outing: one host simulates the world, guests send their state and
# commands. This node is the room's facade for the rest of the game. The work
# is split into parts:
#   room_transport.gd  HTTP/WebSocket messages and the server clock
#   world_sync.gd      the shared world as snapshot providers (hot/cold)
#   peer_view.gd       how other members look on this client
#   room_lobby.gd      the menu panel and the in-game room line
#   drive_prediction.gd  guest car prediction / host-side simulation
const Prediction = preload("res://scripts/drive_prediction.gd")
const SnapshotMotion = preload("res://scripts/snapshot_motion.gd")
const Props = preload("res://scripts/props.gd")
const NetProtocol = preload("res://scripts/net_protocol.gd")
const Transport = preload("res://scripts/room_transport.gd")
const WorldSync = preload("res://scripts/world_sync.gd")
const PeerView = preload("res://scripts/peer_view.gd")
const Lobby = preload("res://scripts/room_lobby.gd")
const ActionContext = preload("res://scripts/action_context.gd")
const SharedActions = preload("res://scripts/shared_actions.gd")

var game: Node3D
var transport: Node
var world_sync = WorldSync.new()
var ui = Lobby.new()
# Membership.
var room_id = ""
var player_id = ""
var token = ""
var is_host = false
var connected = false
var peers: Dictionary = {}
var world_paused = false
var tow_owner = ""
# Commands: a guest queues them, the host applies and acknowledges them.
var sequence = 0
var commands: Array = []
var acknowledgements: Array = []
var processed: Dictionary = {}
# Sync timer and diagnostics.
var clock = 0.0
var diagnostic_clock = 0.0
var last_world_time = -1.0
# Driving: guests predict their car, the host simulates every guest car.
var prediction = Prediction.new()
var prediction_enabled = false
var input_clock = 0.0
var host_drives: Dictionary = {}
var drive_budgets: Dictionary = {}
var authoritative_drives: Dictionary = {}
var authority_stamp = -1.0
var visual_children: Dictionary = {}

# A request is in flight (HTTP); kept on the room for the menu and tests.
var busy: bool:
	get: return transport.busy if transport != null else false
	set(value):
		if transport != null:
			transport.busy = value

func _ready() -> void:
	transport = Transport.new()
	transport.name = "Transport"
	transport.room = self
	add_child(transport)
	ui.build(self)
	world_sync.setup(self)

# ---------------------------------------------------------------- roles

# A guest renders the host's world and sends commands instead of acting.
func is_guest() -> bool:
	return connected and not is_host

# Solo play or the host: this client owns the shared simulation.
func is_authority() -> bool:
	return not connected or is_host

# ---------------------------------------------------------------- joining

func connect_room(id: String) -> void:
	if game.platform_service != null and (not game.platform_service.can_use("car", game.car_choice.selected) or (id == "" and not game.platform_service.can_use("stage", game.stage_choice.selected))):
		ui.status.text = "Выбери доступную машину и СУ."
		return
	if busy or connected or game.loading_world:
		return
	if id != "" and not NetProtocol.valid_room_id(id):
		ui.status.text = "ID состоит из %d символов: 0–9 и A–F." % NetProtocol.room_id_length()
		return
	room_id = id
	ui.status.text = "Подключаемся…"
	ui.set_entry_enabled(false)
	transport.request("create" if id == "" else "join", room_id, {"name": ui.name_input.text, "car_model": game.selected_car, "stage": game.selected_stage, "protocol": NetProtocol.version()})

func room_endpoint(kind: String) -> String:
	return transport.endpoint(kind, room_id)

# Kept for tests and tools that feed a server response directly.
func _response(result: int, code: int, headers: PackedStringArray, bytes: PackedByteArray) -> void:
	transport.handle_http(result, code, headers, bytes)

func _on_left() -> void:
	game.get_tree().reload_current_scene()

func _on_rate_limited(retry: float) -> void:
	clock = -retry
	ui.room_label.text = "Слишком много запросов. Повторим через %d сек." % ceili(retry)

func _on_failure(kind: String, code: int, message: String, _data) -> void:
	if connected and (code in [401, 404, 410] or transport.errors >= 2):
		disconnect_room(message)
	elif connected:
		transport.errors += 1
		clock = -1
		ui.room_label.text = "Связь прервалась. Переподключаемся…"
	else:
		ui.status.text = message
		ui.set_entry_enabled(true)
		if game.invite_after_room_create:
			game.invite_after_room_create = false
			game.invite_status.text = "Не удалось создать комнату: " + message
			game.invite_status.show()
			game.invite_button.disabled = false
			game.toast(game.invite_status.text)
		game.lobby_ui.refresh()

func _on_reply(kind: String, data: Dictionary) -> void:
	if kind in ["create", "join"]:
		await _joined(data)
	else:
		_apply_sync(data)

func _joined(data: Dictionary) -> void:
	prediction = Prediction.new()
	prediction.coalesce = true
	prediction_enabled = false
	world_sync.reset()
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
	transport.open_socket(str(data.get("socket", "")))
	if converting_solo:
		_adopt_local_host_state()
	ui.show_connected()
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

# ---------------------------------------------------------------- sync

func _apply_sync(data: Dictionary) -> void:
	if is_host and data.get("cold_revs") is Dictionary:
		world_sync.server_cold_revs = data.cold_revs
	var world = data.get("world")
	if not is_host and world is Dictionary:
		var drive_stamp = float(data.get("world_time", -1))
		if drive_stamp > authority_stamp:
			authoritative_drives = world.get("driving", {})
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
		if world is Dictionary:
			var stamp = float(data.get("world_time", -1))
			if stamp < 0 or stamp > last_world_time:
				prediction_enabled = int(world.get("drive_protocol", 0)) == 1
				var drive = world.get("driving", {}).get(player_id, {})
				if prediction_enabled and not drive.is_empty():
					if not prediction.active:
						prediction.reset(v(drive.pos), drive.yaw)
					prediction.context = drive_context(player_id)
					# Apply world collision geometry before replaying unacknowledged input.
					world_sync.apply_collision(world)
					prediction.reconcile(drive, game.stage, game.selected_car)
					game.condition = prediction.condition
					game.car.position = prediction.node.position
					game.heading = prediction.yaw
				apply_world(world, stamp / 1000.0 if stamp >= 0 else -1.0)
				last_world_time = stamp
	ui.show_room_status(room_id, peers.size() + 1, is_host, world_paused)

func sync_now() -> void:
	clock = maxf(clock, NetProtocol.sync_interval())

func sync_body() -> Dictionary:
	var body = {"token": token, "state": local_state(), "commands": commands, "cold_revs": world_sync.cold_revs}
	if is_host:
		world_sync.host_upload(body)
		body.ack = acknowledgements
	# Commands in this body are on the wire and must not be merged further.
	prediction.seal()
	return body

func world_state() -> Dictionary:
	return world_sync.world_state()

func apply_world(w: Dictionary, sample_time: float = -1.0) -> void:
	world_sync.apply_world(w, sample_time if sample_time >= 0 else server_clock())

func server_clock() -> float:
	return transport.server_clock()

func update_server_clock(server_msec: float, sent_at: float = -1.0) -> void:
	transport.update_server_clock(server_msec, sent_at)

func _process(delta: float) -> void:
	if not connected or game.loading_world:
		return
	clock += delta
	transport.poll(delta)
	if not connected:
		return
	if clock >= NetProtocol.sync_interval() and transport.ready_to_sync():
		clock = fmod(clock, NetProtocol.sync_interval())
		transport.send_sync(sync_body(), room_id)
	diagnostic_clock += delta
	if diagnostic_clock >= 5.0:
		diagnostic_clock = 0.0
		print("[RFM network] RTT=%.0fms jitter=%.0fms peers=%d transport=%s" % [transport.round_trip_ms, transport.network_jitter_ms, peers.size(), transport.transport_name()])
	game.cargo.refresh_opened()
	var frozen = world_paused or game.paused or game.dead or game.finished
	for peer in peers.values():
		if peer.state != null:
			PeerView.animate(game, peer, delta, server_clock(), frozen, world_paused)
	if is_guest():
		_render_guest_world(delta)

# Guests move flying gravel and rally cars between host snapshots.
func _render_guest_world(delta: float) -> void:
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
		if world_sync.racer_motion.has(racer.id):
			var frozen = world_paused or game.dead or game.finished
			var pose = world_sync.racer_motion[racer.id].render(server_clock(), frozen)
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

func _requests(source: Dictionary) -> Array:
	var result = []
	for index in source:
		result.append({"id": index, "dir": a(source[index])})
	return result.slice(0, NetProtocol.limit("object_requests_per_sync"))

func tree_requests() -> Array:
	return _requests(game.tree_requests)

func lamp_requests() -> Array:
	return _requests(game.lamp_requests)

func local_state() -> Dictionary:
	return {"drive_enabled": prediction_enabled, "drive_inputs": prediction.outgoing() if prediction_enabled else [], "pos": a(game.player_position()), "car": a(game.car.position), "heading": game.heading, "tilt": a(game.car.rotation), "yaw": game.view_yaw, "pitch": game.view_pitch, "in_car": game.in_car,
		"tow": Input.is_action_pressed("tow") and not game.in_car and not game.paused and not game.dead and not game.finished and game.beers < 30 and game.drink_time < 0 and game.eat_time < 0,
		"push": a(game.walking_intent()), "speed": game.speed, "beers": game.beers, "trees": tree_requests(), "lamps": lamp_requests(), "beer": game.drink_time, "eat": game.eat_time, "food_kind": game.eat_kind, "food_species": game.food_species, "seated": game.seated, "running": game.running(), "airborne": game.jump_height > 0.01}

# ---------------------------------------------------------------- peers

func _update_peers(players: Array) -> void:
	var present = {}
	for p in players:
		if p.id == player_id:
			continue
		present[p.id] = true
		if not peers.has(p.id):
			peers[p.id] = PeerView.create(game, p)
		if is_host and p.state != null and (bool(p.state.get("drive_enabled", false)) or host_drives.has(p.id)):
			_simulate_guest_drive(p)
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
			PeerView.remove(peers[id])
			peers.erase(id)
			host_drives.erase(id)
			drive_budgets.erase(id)
	game.cargo.release_departed()

# The host runs each guest's car from the guest's input, within a time budget.
func _simulate_guest_drive(p: Dictionary) -> void:
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

# ---------------------------------------------------------------- commands

func submit(action: String, placement: Dictionary = {}) -> bool:
	if not is_guest() or action not in NetProtocol.actions():
		return false
	if commands.size() < NetProtocol.limit("commands_per_sync"):
		sequence += 1
		commands.append({"seq": sequence, "action": action, "placement": placement})
		sync_now()
	return true

# The host runs a guest's command as that guest: an explicit action context
# (position, car, seat) instead of the host's own player state.
func _apply_command(c: Dictionary) -> void:
	acknowledgements = acknowledgements.slice(-NetProtocol.limit("acknowledgements_per_sync"))
	if game.paused or game.dead or game.finished:
		return
	var actor = str(c.get("player", "guest"))
	var variant = int(peers[actor].car.get_meta("variant", 0)) if peers.has(actor) and peers[actor].has("car") else 0
	var context = ActionContext.from_command(c, actor, variant)
	SharedActions.run(game, context, str(c.action), c.get("placement", {}))

# ---------------------------------------------------------------- gravel

func stone_state() -> Array:
	var result = []
	for stone in game.stones:
		result.append({"id": stone.id, "pos": a(stone.node.position), "velocity": a(stone.velocity), "bounces": int(stone.get("bounces", 0))})
	return result

func apply_stones(w: Dictionary, sample_time: float = -1.0) -> void:
	var age = clampf(server_clock() - sample_time, 0, 0.15) if sample_time >= 0 else 0.0
	var count = int(w.get("impacts", {}).get(player_id, 0))
	if count > world_sync.last_impact:
		game.impact_shake = 0.8
		if game.in_car:
			if not prediction_enabled or not prediction.active:
				game.condition = maxf(0, game.condition - (count - world_sync.last_impact) * 0.8)
		game.toast("Гравий из-под колёс! Отойди дальше от края СУ.")
	world_sync.last_impact = count
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

# ---------------------------------------------------------------- host checks

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
		for request in peer.state.get("lamps", []):
			var index = int(request.id)
			if index >= 0 and index < game.stage.solids.lamps.size() and current.distance_to(game.stage.solids.lamps[index].body.position) < 5 and peer.state.in_car and v(request.dir).length() > 5:
				game.stage.solids.knock_lamp(index, v(request.dir))
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

# ---------------------------------------------------------------- leaving

func leave() -> void:
	transport.close_socket()
	transport.cancel()
	connected = false
	transport.request("leave", room_id, {"token": token})

func disconnect_room(message: String) -> void:
	connected = false
	transport.close_socket()
	game.paused = true
	game.menu.show()
	game.menu_title.text = "Комната закрыта"
	game.menu_text.text = message
	game.start_button.text = "В ГЛАВНОЕ МЕНЮ"
	game.dead = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if game.mobile_controls != null:
		game.mobile_controls.reset_input()
	ui.room_label.text = message

# ---------------------------------------------------------------- driving

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
			"city": game.knock_solid(event.hit, event.velocity)
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
	if prediction.full():
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
