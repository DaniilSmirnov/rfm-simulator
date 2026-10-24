extends Node
# A shared outing: one host simulates the world, guests send their state and
# commands. This node is the room's facade for the rest of the game. The work
# is split into parts:
#   room_transport.gd  HTTP/WebSocket messages and the server clock
#   world_sync.gd      the shared world as snapshot providers (hot/cold)
#   peer_view.gd       how other members look on this client
#   room_lobby.gd      the menu panel and the in-game room line
#   direct_link.gd     WebRTC data channels host <-> guest: the whole game
#   drive_prediction.gd  guest car prediction / host-side simulation
const Hitbox = preload("res://scripts/cars/car_hitbox.gd")
const Prediction = preload("res://scripts/net/drive_prediction.gd")
const Props = preload("res://scripts/core/props.gd")
const NetProtocol = preload("res://scripts/net/net_protocol.gd")
const Transport = preload("res://scripts/net/room_transport.gd")
const WorldSync = preload("res://scripts/net/world_sync.gd")
const PeerView = preload("res://scripts/net/peer_view.gd")
const Lobby = preload("res://scripts/net/room_lobby.gd")
const ActionContext = preload("res://scripts/player/action_context.gd")
const SharedActions = preload("res://scripts/player/shared_actions.gd")
const DirectLink = preload("res://scripts/net/direct_link.gd")
const CarRides = preload("res://scripts/cars/car_rides.gd")
const Loc = preload("res://scripts/ui/loc.gd")
const WorldValidation = preload("res://scripts/net/world_validation.gd")
const VoiceChat = preload("res://scripts/net/voice_chat.gd")
const Dedicated = preload("res://scripts/net/dedicated.gd")
const JoinCheck = preload("res://scripts/net/join_check.gd")

var game: Node3D
var voice: Node
var transport: Node
var direct: Node
var world_sync = WorldSync.new()
var ui = Lobby.new()
var join_check = JoinCheck.new()
# Membership.
var room_id = ""
var player_id = ""
var token = ""
var is_host = false
var connected = false
var peers: Dictionary = {}
# Membership as the server reports it: id -> {"name", "slot", "car_model", "character"}.
var members: Dictionary = {}
var host_id = ""
var world_paused = false
# Commands: a guest queues them, the host runs them and reports the last one
# run from each guest (`accepted`, guest id -> seq).
var sequence = 0
var commands: Array = []
var accepted: Dictionary = {}
var processed: Dictionary = {}
# Guest: seconds without a working direct link to the host; past LINK_GIVE_UP
# it leaves the room. The server path no longer carries the game.
const LINK_GIVE_UP = 20.0
var link_lost = 0.0
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
	voice = VoiceChat.new()
	voice.name = "Voice"
	voice.setup(self)
	add_child(voice)
	transport = Transport.new()
	transport.name = "Transport"
	transport.room = self
	add_child(transport)
	direct = DirectLink.new()
	direct.name = "DirectLink"
	add_child(direct)
	direct.setup(self)
	ui.build(self)
	world_sync.setup(self)
	if Dedicated.active(): add_child(Dedicated.new())

# ---------------------------------------------------------------- roles

# A guest renders the host's world and sends commands instead of acting.
func is_guest() -> bool:
	return connected and not is_host

# Solo play or the host: this client owns the shared simulation.
func is_authority() -> bool:
	return not connected or is_host

# ---------------------------------------------------------------- joining

func connect_room(id: String) -> void:
	if game.platform_service != null and (not game.platform_service.can_use("car", game.car_choice.selected) or not game.platform_service.can_use("character", game.avatar_variant) or (id == "" and not game.platform_service.can_use("stage", game.stage_choice.selected))):
		ui.status.text = "Выбери доступную машину, персонажа и СУ."
		return
	if busy or connected or game.loading_world:
		return
	if id != "" and not NetProtocol.valid_room_id(id):
		ui.status.text = Loc.t("ID состоит из %d символов: 0–9 и A–F.") % NetProtocol.room_id_length()
		return
	# This runs directly from the create/join button. Capture here, before the
	# server response calls start_game() after its asynchronous request.
	game._request_game_mouse_capture()
	room_id = id
	ui.status.text = "Подключаемся…"
	ui.set_entry_enabled(false)
	transport.request("create" if id == "" else "join", room_id, {"name": ui.name_input.text, "car_model": game.selected_car, "character": game.avatar_variant, "stage": game.selected_stage, "protocol": NetProtocol.version()})

func room_endpoint(kind: String) -> String:
	return transport.endpoint(kind, room_id)

# Kept for tests and tools that feed a server response directly.
func _response(result: int, code: int, headers: PackedStringArray, bytes: PackedByteArray) -> void:
	transport.handle_http(result, code, headers, bytes)

func _on_left() -> void:
	game.get_tree().reload_current_scene()

func _on_rate_limited(retry: float) -> void:
	clock = -retry
	ui.room_label.text = Loc.t("Слишком много запросов. Повторим через %d сек.") % ceili(retry)

func _on_failure(kind: String, code: int, message: String, _data) -> void:
	if join_check.fail(message) or (connected and kind == "sync" and transport.tolerate_refused_sync(code)): return
	if connected and code in [400, 401, 404, 410, 413]:
		disconnect_room(message)
	elif connected:
		var retry = transport.recovery_delay()
		if retry < 0:
			disconnect_room(message)
			return
		clock = -retry
		ui.room_label.text = "Связь прервалась. Переподключаемся…"
	else:
		ui.status.text = "Комната не найдена или закрыта. Если хозяин пересоздал комнату, у неё новый ID: попроси прислать его." if kind == "join" and code in [404, 410] else message
		ui.set_entry_enabled(true)
		if game.invite_after_room_create:
			game.invite_after_room_create = false
			game.invite_status.text = Loc.t("Не удалось создать комнату: %s") % message
			game.invite_status.show()
			game.invite_button.disabled = false
			game.toast(game.invite_status.text)
		game.lobby_ui.refresh()

func _on_reply(kind: String, data: Dictionary) -> void:
	if kind in ["create", "join"]:
		join_check.start(self, data)
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
	accepted.clear()
	processed.clear()
	link_lost = 0.0
	clock = INF
	var converting_solo = game.playing and bool(data.host)
	player_id = data.player
	token = data.token
	is_host = data.host
	if is_host:
		room_id = data.room
	connected = true
	voice.join()
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
		# The look picked in the menu, as the server accepted it; others see the same.
		game.avatar_variant = int(data.get("character", game.avatar_variant))
		game.heading = game.stage.parks.park_visitor(game.car, lane)
	if not transport.socket_open: transport.open_socket(str(data.get("socket", "")))  # a host's after the load, or the hello is late
	game.toast(Loc.t("Комната %s · %s. Передай ID друзьям!") % [room_id, Loc.t(game.car.get_meta("model"))])
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
	if data.get("world") != null and not WorldValidation.valid(data.world): return
	WorldValidation.trust(data.get("world"))
	_apply_checked_sync(data)
	WorldValidation.trust(null)

# The server's reply: membership, the host and the server clock. The world,
# states and commands go over the direct links.
func _apply_checked_sync(data: Dictionary) -> void:
	host_id = str(data.get("host", host_id))
	ui.limit = int(data.get("max_players", NetProtocol.max_players()))
	_update_members(data.players)
	if game.playing: _update_peers(data.players, false)  # a guest still in the menu draws nobody
	ui.show_room_status(room_id, peers.size() + 1, is_host, world_paused)

# A guest applies the host's world from its direct link.
# `changed`: the hot providers this packet changed (null: all).
func _guest_world(world, stamp: float, players: Array, membership: bool, changed = null) -> void:
	if world != null and not WorldValidation.valid(world): return
	WorldValidation.trust(world)
	_apply_guest_world(world, stamp, players, membership, changed)
	WorldValidation.trust(null)

func _apply_guest_world(world, stamp: float, players: Array, membership: bool, changed = null) -> void:
	if world is Dictionary and stamp > authority_stamp:
		authoritative_drives = world.get("driving", {})
		authority_stamp = stamp
	_update_peers(players, true, membership)
	if not world is Dictionary or not (stamp < 0 or stamp > last_world_time):
		return
	prediction_enabled = int(world.get("drive_protocol", 0)) == 1
	var drive = world.get("driving", {}).get(player_id, {})
	if prediction_enabled and not drive.is_empty() and (changed == null or changed.has("drive")):
		if not prediction.active:
			prediction.reset(v(drive.pos), drive.yaw)
		prediction.context = drive_context(player_id)
		# Apply world collision geometry before replaying unacknowledged input.
		world_sync.apply_collision(world)
		prediction.reconcile(drive, game.stage, game.selected_car)
		game.condition = prediction.condition
		game.car.position = prediction.node.position
		game.heading = prediction.yaw
	world_sync.apply_world(world, stamp / 1000.0 if stamp >= 0 else server_clock(), changed)
	last_world_time = stamp

func _update_members(players: Array) -> void:
	members.clear()
	for p in players:
		members[str(p.id)] = {"name": p.get("name", ""), "slot": int(p.get("slot", 0)), "car_model": int(p.get("car_model", 0)), "character": int(p.get("character", p.get("slot", 0))), "dedicated": p.get("dedicated", false) == true}
	direct.sync_members(host_id, members.keys())
	voice.sync_members(members.keys())

func sync_now() -> void:
	clock = maxf(clock, NetProtocol.membership_interval())

func sync_body() -> Dictionary:
	return {"token": token, "state": NetProtocol.outgoing_state(local_state(), true), "direct": true}

func world_state() -> Dictionary:
	return world_sync.world_state()

func apply_world(w: Dictionary, sample_time: float = -1.0) -> void:
	world_sync.apply_world(w, sample_time if sample_time >= 0 else server_clock())

func server_clock() -> float:
	return transport.server_clock()

func update_server_clock(server_msec: float, sent_at: float = -1.0) -> void:
	transport.update_server_clock(server_msec, sent_at)

func _process(delta: float) -> void:
	if not connected or join_check.update(delta) or game.loading_world:
		return
	clock += delta
	transport.poll(delta)
	if not connected:
		return
	if clock >= NetProtocol.membership_interval() and transport.ready_to_sync():
		clock = 0.0
		transport.send_sync(sync_body(), room_id)
	direct.update(delta)
	if is_guest() and not _linked(delta):
		return
	diagnostic_clock += delta
	if diagnostic_clock >= 5.0:
		diagnostic_clock = 0.0
		print("[RFM network] RTT=%.0fms jitter=%.0fms peers=%d transport=%s direct=%d" % [transport.round_trip_ms, transport.network_jitter_ms, peers.size(), transport.transport_name(), direct.open_links().size()])
	game.cargo.refresh_opened()
	var frozen = world_paused or game.paused or game.dead or game.finished
	for peer in peers.values():
		if peer.state != null:
			PeerView.animate(game, peer, delta, transport.view_clock, frozen, world_paused)
	if is_guest():
		_render_guest_world(delta)

# A guest without a working link to the host waits for it, then gives up.
func _linked(delta: float) -> bool:
	if direct.healthy(host_id):
		link_lost = 0.0
		return true
	link_lost += delta
	ui.room_label.text = "Соединяемся с хозяином комнаты…"
	if link_lost > LINK_GIVE_UP or not direct.enabled:
		disconnect_room("Не удалось соединиться с хозяином комнаты. Проверь интернет или попробуй другую сеть.", "Не удалось соединиться")
	return connected

# Guests move flying gravel and rally cars between host snapshots.
func _render_guest_world(delta: float) -> void:
	world_sync.advance_clock(delta, not game.playing or world_paused or game.paused or game.dead or game.finished)
	if not world_paused and not game.paused and not game.dead and not game.finished:
		for stone in game.stones:
			if not game._advance_gravel(stone, delta):
				stone.node.hide()
	for racer in game.racers:
		Props.update_course_lights(racer.node, game.elapsed)
		if world_sync.racer_motion.has(racer.id):
			var frozen = world_paused or game.dead or game.finished
			var pose = world_sync.racer_motion[racer.id].render(transport.view_clock, frozen)
			racer.node.position = pose.position
			racer.node.rotation = pose.rotation
	game.crews.draw_recovery_ropes()
	game.park_traffic.render_guest(transport.view_clock, world_paused or game.dead or game.finished)

static func a(pos: Vector3) -> Array:
	return [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(pos.z, 0.01)]
# Velocities to 0.1 m/s: guests only draw ahead with them, a tenth of a second.
static func av(velocity: Vector3) -> Array:
	return [snappedf(velocity.x, 0.1), snappedf(velocity.y, 0.1), snappedf(velocity.z, 0.1)]
static func v(pos: Array) -> Vector3:
	return Vector3(pos[0], pos[1], pos[2])

func _requests(source: Dictionary) -> Array:
	var result = []
	for index in source:
		result.append({"id": index, "dir": a(source[index])})
	return result.slice(0, NetProtocol.limit("object_requests_per_sync"))

func local_state() -> Dictionary:
	return {"drive_enabled": prediction_enabled, "drive_inputs": prediction.outgoing() if prediction_enabled else [], "pos": a(game.player_position()), "car": a(game.car.position), "heading": snappedf(game.heading, 0.001), "tilt": a(game.car.rotation), "yaw": snappedf(game.view_yaw, 0.001), "pitch": snappedf(game.view_pitch, 0.001), "in_car": game.in_car,
		"tow": Input.is_action_pressed("tow") and not game.in_car and not game.injuries.down and not game.paused and not game.dead and not game.finished and game.beers < 30 and game.drink_time < 0 and game.eat_time < 0,
		"push": a(game.walking_intent()), "speed": snappedf(game.speed, 0.01), "beers": game.beers, "trees": _requests(game.tree_requests), "lamps": _requests(game.lamp_requests), "beer": snappedf(game.drink_time, 0.01), "eat": snappedf(game.eat_time, 0.01), "food_kind": game.eat_kind, "food_species": game.food_species, "seated": game.seated, "running": game.running(), "airborne": game.jump_height > 0.01, "relief": game.player.relief.active,
		"ride": game.rides.ride, "hitch": game.rides.hitch, "broken": game.condition <= 0,
		"radio": voice.on_air()}.merged(game.player.perches.state_fields())

# ---------------------------------------------------------------- peers

# `use_states`: take positions from these entries (false: membership only, the
# direct link delivers states). `membership`: add and remove peers to match.
func _update_peers(players: Array, use_states: bool = true, membership: bool = true) -> void:
	var present = {}
	for p in players:
		# A dedicated server hosts the room but is nobody on the stage.
		if p.id == player_id or members.get(str(p.id), {}).get("dedicated", false):
			continue
		present[p.id] = true
		if not peers.has(p.id):
			if not membership:
				continue
			peers[p.id] = PeerView.create(game, p)
		# The host takes a guest's state from its direct link while that is alive.
		if use_states and not (is_host and direct.healthy(str(p.id))):
			_update_peer(p)
	if membership:
		for id in peers.keys():
			if not present.has(id):
				PeerView.remove(peers[id])
				peers.erase(id)
				host_drives.erase(id)
				drive_budgets.erase(id)
		game.cargo.release_departed()

func _update_peer(p: Dictionary) -> void:
	if is_host and p.state != null and (bool(p.state.get("drive_enabled", false)) or host_drives.has(p.id)):
		_simulate_guest_drive(p)
	elif not is_host and p.state != null and authoritative_drives.has(p.id):
		var drive = authoritative_drives[p.id]
		p.state.car = drive.pos
		p.state.heading = drive.yaw
		p.state.tilt = [drive.pitch, drive.yaw, drive.roll]
		p.state.speed = v(drive.velocity).dot(Vector3(-sin(drive.yaw), 0, -cos(drive.yaw)))
		if CarRides.driving(p.state):
			p.state.pos = drive.pos
	var peer = peers[p.id]
	if p.state != null:
		var sample_time = float(p.state_time) / 1000.0 if p.has("state_time") else server_clock()
		if is_host and host_drives.has(p.id):
			sample_time = float(drive_budgets[p.id].stamp)
		elif not is_host and authoritative_drives.has(p.id) and not p.get("host_stamped", false):
			sample_time = authority_stamp / 1000.0
		if peer.has("last_sample_time") and sample_time <= peer.last_sample_time:
			return
		var switched = peer.state != null and peer.state.in_car != p.state.in_car
		var tilt = v(p.state.get("tilt", [0, p.state.heading, 0]))
		tilt.y = p.state.heading
		# Cars the host simulates come with their exact velocity.
		var velocity = null
		if is_host and host_drives.has(p.id):
			velocity = host_drives[p.id].motion.velocity
		elif not is_host and authoritative_drives.has(p.id):
			velocity = v(authoritative_drives[p.id].velocity)
		peer.car_motion.push(sample_time, v(p.state.car), tilt, false, velocity)
		peer.avatar_motion.max_speed = 12.0
		peer.avatar_motion.push(sample_time, v(p.state.pos), Vector3(0, p.state.yaw, 0), switched)
		peer.last_sample_time = sample_time
	peer.state = p.state
	if p.state != null:
		PeerView.note_activity(peer, float(p.state_time) / 1000.0 if p.has("state_time") else server_clock())

# The host runs each guest's car from the guest's input, within a time budget.
func _simulate_guest_drive(p: Dictionary) -> void:
	if not host_drives.has(p.id):
		var solver = Prediction.new()
		var pose: Transform3D = game.stage.parks.free_visitor_pose(int(p.get("slot", 1)), Hitbox.player(int(p.get("car_model", 0))), drive_context(str(p.id)).contacts)
		solver.reset(pose.origin, pose.basis.get_euler().y)
		drive_budgets[p.id] = {"time": Time.get_ticks_usec(), "ticks": 30.0, "stamp": server_clock() - Prediction.STAMP_LAG}
		host_drives[p.id] = solver
	var solver = host_drives[p.id]
	var budget = drive_budgets[p.id]
	var now = Time.get_ticks_usec()
	budget.ticks = minf(120.0, budget.ticks + maxf(0, (now - budget.time) / 1000000.0) * 120.0)
	budget.time = now
	solver.context = drive_context(str(p.id))
	var consumed = 0
	if not game.paused and not game.dead and not game.finished:
		consumed = solver.accept(p.state.get("drive_inputs", []), game.stage, int(p.get("car_model", 0)), int(budget.ticks))
		budget.ticks -= consumed
		apply_drive_events(solver, true)
	else:
		# Acknowledgement prevents pre-pause inputs from playing after resume.
		for c in p.state.get("drive_inputs", []):
			if int(c.seq) == solver.ack + 1:
				solver.ack = int(c.seq)
	budget.stamp = Prediction.stamp(float(budget.stamp), consumed, server_clock())
	if not p.state.in_car:
		solver.motion.velocity = Vector3.ZERO
	p.state.car = a(solver.node.position)
	if CarRides.driving(p.state):
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
		direct.send_soon()
	return true

# The host runs a guest's command as that guest: an explicit action context
# (position, car, seat) instead of the host's own player state.
func _apply_command(c: Dictionary) -> void:
	if game.paused or game.dead or game.finished:
		return
	var actor = str(c.get("player", "guest"))
	var variant = int(peers[actor].car.get_meta("variant", 0)) if peers.has(actor) and peers[actor].has("car") else 0
	var context = ActionContext.from_command(c, actor, variant)
	SharedActions.run(game, context, str(c.action), c.get("placement", {}))

# ---------------------------------------------------------------- gravel

# Guests fly a stone themselves (advance_gravel with the same stage), so its
# state travels only while it is new, for long enough to survive a lost packet
# on the direct link; "stone_ids" lists every stone still alive.
const STONE_FRESH_MSEC = 200

func stone_state() -> Array:
	var now = Time.get_ticks_msec()
	var result = []
	for stone in game.stones:
		if not stone.has("fresh_until"):
			stone.fresh_until = now + STONE_FRESH_MSEC
		if now < int(stone.fresh_until):
			var entry = {"id": stone.id, "pos": a(stone.node.position), "velocity": av(stone.velocity)}
			if int(stone.get("bounces", 0)) > 0: entry.bounces = int(stone.bounces)
			result.append(entry)
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
	var local = {}
	for stone in game.stones:
		local[stone.id] = stone
	for remote in w.get("stones", []):
		var velocity = v(remote.velocity) + Vector3(0, -9.8 * age, 0)
		var position = v(remote.pos) + v(remote.velocity) * age + Vector3(0, -4.9 * age * age, 0)
		present[remote.id] = true
		var stone = local.get(remote.id)
		if stone != null:
			stone.node.position = stone.node.position.lerp(position, 0.35) if stone.node.position.distance_to(position) < 3 else position
			stone.velocity = velocity
			stone.bounces = int(remote.get("bounces", 0))
			stone.node.show()
		else:
			var node = Props.box(game, position, Vector3.ONE * 0.10, Color("9b9079"))
			game.stones.append({"id": remote.id, "node": node, "velocity": velocity, "bounces": int(remote.get("bounces", 0))})
	# With the list of living stones, a stone missing from "stones" just flies on.
	var alive = null
	if w.has("stone_ids"):
		alive = {}
		for id in w.stone_ids:
			alive[int(id)] = true
	for stone in game.stones.filter(func(stone): return not (present.has(stone.id) if alive == null else alive.has(int(stone.id)))):
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

func check_remote_collisions() -> void:
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
		# A friend's car (not simulated here) throws people it runs into.
		var speed = absf(float(peer.state.get("speed", 0)))
		if speed > game.injuries.PLAYER_CAR_SPEED and current.distance_to(previous) > 0.001:
			game.injuries.vehicle_sweep(previous, current, (current - previous).normalized() * speed, game.injuries.PLAYER_CAR_SPEED, Hitbox.shape(Hitbox.bounds(peer.car), float(peer.state.get("heading", 0))))
		peer.last_car = current

# ---------------------------------------------------------------- leaving

func leave() -> void:
	voice.leave()
	direct.close_all()
	transport.close_socket()
	transport.cancel()
	connected = false
	transport.request("leave", room_id, {"token": token})

func disconnect_room(message: String, title: String = "Комната закрыта") -> void:
	connected = false
	voice.leave()
	direct.close_all()
	transport.close_socket()
	game.paused = true
	game.menu.show()
	if not (game.finished or game.dead): # a trip's results stay; their button leads to the menu
		game.menu_title.text = title
		game.menu_text.text = message
		game.start_button.text = "В ГЛАВНОЕ МЕНЮ"
	game.dead = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if game.mobile_controls != null:
		game.mobile_controls.reset_input()
	ui.room_label.text = message

# ---------------------------------------------------------------- driving

func predict_drive(delta: float) -> bool:
	if is_host: return false
	# Until the host's first world the car waits where the host starts it.
	if not prediction_enabled or not prediction.active:
		return true
	input_clock += minf(delta, 0.1)
	var ticks = int(input_clock / prediction.motion.handling.STEP)
	input_clock -= ticks * prediction.motion.handling.STEP
	prediction.context = drive_context(player_id)
	prediction.predict(ticks, Input.get_axis("back", "forward"), Input.get_axis("left", "right"), Input.is_action_pressed("brake"), game.stage, game.selected_car, false, float(Input.is_action_pressed("jump")) - float(Input.is_action_pressed("sprint")))
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
		contacts.append(Hitbox.contact(group.car))
	for racer in game.racers:
		contacts.append(Hitbox.contact(racer.node))
	for park in game.park_traffic.parked:
		for node in park.values():
			if is_instance_valid(node): contacts.append(Hitbox.contact(node))
	for entry in game.park_traffic.movers:
		if is_instance_valid(entry.node): contacts.append(Hitbox.contact(entry.node))
	if owner != player_id:
		contacts.append(Hitbox.contact(game.car))
	# A guest predicting its own car meets other cars where it shows them, ahead
	# of their last snapshot, which is closer to where the host has them.
	var shown = is_guest() and owner == player_id
	for id in peers:
		if id != owner and peers[id].state != null:
			var car: Node3D = peers[id].car
			var position = car.position if shown and not peers[id].car_motion.samples.is_empty() else v(peers[id].state.car)
			var yaw = car.rotation.y if shown and not peers[id].car_motion.samples.is_empty() else peers[id].state.get("heading", 0)
			contacts.append({"position": position, "yaw": yaw, "box": Hitbox.bounds(car)})
	# Everybody on foot except the driver; people lying after a hit are passed.
	for person in game.injuries.people():
		if person.key != "player:" + owner and not game.injuries.is_down(person.key) and not person.get("riding", false):
			contacts.append({"position": person.pos, "person": true})
	return {"contacts": contacts, "racing": game.racing}

func apply_drive_events(solver, authoritative: bool) -> void:
	for event in solver.events:
		match event.kind:
			"tree": game.knock_tree(event.index, event.velocity)
			"city": game.knock_solid(event.hit, event.velocity)
			"person":
				if authoritative:
					game.injuries.knock_near(event.position, event.velocity, solver.node.position)
			"impact":
				if not authoritative:
					game.impact_shake = minf(0.8, float(event.speed) * 0.055)
					game.toast("Удар! Сбавь скорость.")
	solver.events.clear()

func recover_drive() -> bool:
	if is_host:
		return false
	if not prediction_enabled or not prediction.active:
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
