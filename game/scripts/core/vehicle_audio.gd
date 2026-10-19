extends Node
# Cars as this client hears them. The player's own car from the driver's seat:
# engine (an idle loop and an on/off-throttle pair, pitched to simulated revs
# and gears), tyres on the surface under them, skids, the starter. Cars around
# (crews, course and park cars, friends' cars) share a few 3D voices, nearest
# first, with engine, tyres, sirens, backfires and the Doppler shift of a car
# passing by. Doors, trunk lids, crashes and tow ropes are one-shots.
# Everything is read from the scene (node motion between frames) and the
# session state, so host and guests hear the same cars without network data.
const SoundBank = preload("res://scripts/core/sound_bank.gd")
const ParkTraffic = preload("res://scripts/traffic/park_traffic.gd")
const CarRides = preload("res://scripts/cars/car_rides.gd")
# Revs of the engine loops as rendered (scripts/generate-sounds.mjs ENGINE_RPM).
const LOW_RPM = 1500.0
const HIGH_RPM = 5000.0
# Revs where the idle loop hands over to the on/off-throttle pair.
const BLEND_FROM = 2000.0
const BLEND_TO = 3200.0
const ENGINES = ["sedan", "utility", "kei", "diesel", "i4", "i4t", "i5", "boxer", "v6"]
const RALLY_ENGINES = ["i4", "i4t", "i5", "boxer", "v6"]
const WHEEL_RADIUS = 0.31
const SOUND_SPEED = 343.0
# Road cars shift early; competition cars rev out. `up` and `down` are shares
# of the redline where the box changes gear.
const GEARBOX = {
	"road": {"ratios": [3.6, 2.1, 1.4, 1.0, 0.8], "final": 3.9, "idle": 850.0, "redline": 6200.0, "up": 0.62, "down": 0.28},
	"rally": {"ratios": [3.1, 2.2, 1.7, 1.35, 1.1, 0.95], "final": 4.4, "idle": 1100.0, "redline": 8200.0, "up": 0.9, "down": 0.36},
}
const SIRENS = {"opening_police": "siren-police", "closing_police": "siren-police", "ambulance": "siren-ambulance"}
const VOICES = 3
const HEARING = 260.0
const SIREN_REACH = 320.0
# Seconds a car keeps its engine running after it stopped moving.
const ENGINE_LINGER = 4.0
# Speed (m/s) lost faster than braking can that sounds like a crash, and the
# speed before it that makes the crash a heavy one.
const CRASH_DROP = 6.0
const HEAVY_CRASH_SPEED = 14.0
const GUEST_CRASH_CONFIRM = 0.3
const START_SECONDS = 0.75
# Loudness of the layers before their gains (dB).
const OWN_ENGINE_DB = -15.0
const OWN_TYRES_DB = -19.0
const OWN_SKID_DB = -17.0
const VOICE_ENGINE_DB = -3.0
const VOICE_TYRES_DB = -7.0

var game
# Cars around by node instance id: motion, revs, gear, load, surface.
var cars: Dictionary = {}
var own: Dictionary = {"rpm": 850.0, "gear": 1, "load": 0.0, "surface": "gravel", "surface_clock": 0.0}
var own_layers: Dictionary = {}
var voices: Array[Dictionary] = []
var sirens: Array[AudioStreamPlayer3D] = []
var siren_cars: Array = []
var shots: Array[AudioStreamPlayer3D] = []
var shot_index = 0
var starter: AudioStreamPlayer
var start_hold = 0.0
var listener = Vector3.ZERO
var listener_velocity = Vector3.ZERO
var was_driving = false
var seat_car: Node3D
# Last seen seat and lid states, null until first seen (no sound on joining).
var was_in_car = null
var peer_seats: Dictionary = {}
var trunks: Dictionary = {}
var rope_count = 0
var rng = RandomNumberGenerator.new()
var all_players: Array = []

func _ready() -> void:
	rng.seed = 2026101
	for layer in ["low", "on", "off", "tyre", "skid"]:
		own_layers[layer] = SoundBank.player(self, -80.0)
	starter = SoundBank.player(self, -9.0, "engine-start")
	for i in range(VOICES):
		var voice = {"car": 0}
		for layer in ["low", "on", "off"]:
			voice[layer] = SoundBank.spatial(self, -80.0, 14.0, HEARING)
		for layer in ["tyre", "skid"]:
			voice[layer] = SoundBank.spatial(self, -80.0, 8.0, 140.0)
		voices.append(voice)
	for i in range(2):
		sirens.append(SoundBank.spatial(self, -4.0, 24.0, SIREN_REACH))
		siren_cars.append(0)
	for i in range(6):
		shots.append(SoundBank.spatial(self, 0.0, 6.0, 140.0))
	all_players = own_layers.values() + sirens + shots + [starter]
	for voice in voices:
		all_players.append_array([voice.low, voice.on, voice.off, voice.tyre, voice.skid])

# ---------------------------------------------------------------- engine model

# Revs, gear and load of one car from its speed (m/s) and throttle (0..1).
static func advance_engine(state: Dictionary, speed: float, throttle: float, box: Dictionary, delta: float) -> void:
	var ratios: Array = box.ratios
	var wheel = absf(speed) / (TAU * WHEEL_RADIUS) * 60.0 * float(box.final)
	var redline: float = box.redline
	var gear = clampi(int(state.get("gear", 1)), 1, ratios.size())
	state.cut = maxf(0.0, float(state.get("cut", 0.0)) - delta)
	if throttle > 0.2 and gear < ratios.size() and wheel * float(ratios[gear - 1]) > redline * float(box.up):
		gear += 1
		# The throttle lifts for the shift.
		state.cut = 0.12
	while gear > 1 and wheel * float(ratios[gear - 1]) < redline * float(box.down):
		gear -= 1
	state.gear = gear
	var idle: float = box.idle
	var target = maxf(wheel * float(ratios[gear - 1]), idle)
	# Pulling away the clutch slips: the revs rise before the car moves.
	if gear == 1:
		target = maxf(target, idle + throttle * redline * 0.35 * clampf(1.0 - absf(speed) / 7.0, 0.0, 1.0))
	target = minf(target, redline)
	state.rpm = lerpf(float(state.get("rpm", idle)), target, 1.0 - exp(-delta * 10.0))
	var pedal = 0.0 if state.cut > 0.0 else throttle
	state.load = lerpf(float(state.get("load", 0.0)), pedal, 1.0 - exp(-delta * 8.0))

# Linear gains of the idle, on- and off-throttle loops for revs and load.
static func layer_gains(rpm: float, load: float) -> Dictionary:
	var high = smoothstep(BLEND_FROM, BLEND_TO, rpm)
	return {"low": (1.0 - high) * (0.7 + 0.3 * load), "on": high * (0.2 + 0.8 * load), "off": high * (1.0 - load) * 0.9}

static func character(node: Node) -> String:
	var engine = str(node.get_meta("engine", "sedan")) if node != null else "sedan"
	return engine if engine in ENGINES else "sedan"

# Pitch factor of a source moving at `velocity` heard by a moving listener.
static func doppler(source: Vector3, velocity: Vector3, ear: Vector3, ear_velocity: Vector3) -> float:
	var direction = source - ear
	if direction.length() < 0.5:
		return 1.0
	direction = direction.normalized()
	return clampf((SOUND_SPEED + ear_velocity.dot(direction)) / (SOUND_SPEED + velocity.dot(direction)), 0.75, 1.35)

# ---------------------------------------------------------------- frame

func update(delta: float, running: bool, paused: bool) -> void:
	for node in all_players:
		SoundBank.set_paused(node, paused)
	if paused or delta <= 0.0:
		return
	if not running:
		silence()
		return
	_follow_listener(delta)
	_update_own(delta)
	_track_cars(delta)
	_assign_voices()
	for voice in voices:
		_sound_voice(voice)
	_update_sirens()
	_watch_seats()
	_watch_trunks_and_ropes()

# Everything stops; seats and lids are re-read without sounds next time.
func silence() -> void:
	for node in all_players:
		if node.playing:
			node.stop()
	for voice in voices:
		voice.car = 0
	for i in range(siren_cars.size()):
		siren_cars[i] = 0
	was_driving = false
	was_in_car = null
	peer_seats.clear()
	trunks.clear()
	rope_count = 0
	cars.clear()

func play_at(sound: String, where: Vector3, volume_db: float, unit: float = 6.0, pitch: float = 1.0) -> void:
	var shot = shots[shot_index]
	shot_index = (shot_index + 1) % shots.size()
	shot.stream = SoundBank.stream(sound)
	shot.global_position = where
	shot.volume_db = volume_db
	shot.unit_size = unit
	shot.pitch_scale = pitch * rng.randf_range(0.95, 1.05)
	game._play_audio(shot)

# A crash of the local player's car or the player being knocked down.
func impact(strength: float) -> void:
	if game.in_car:
		var heavy = strength >= 0.45
		play_at("crash-heavy" if heavy else "crash-light", game.rides.vehicle().global_position, -2.0 if heavy else -5.0, 8.0)
	else:
		play_at("body-thud", game.walker, -4.0, 4.0)

func _follow_listener(delta: float) -> void:
	var camera = get_viewport().get_camera_3d()
	var at: Vector3 = camera.global_position if camera != null else game.player_position()
	var step = (at - listener) / delta
	listener_velocity = listener_velocity.lerp(step, 1.0 - exp(-delta * 6.0)) if at.distance_to(listener) < 12.0 else Vector3.ZERO
	listener = at

# Starts a loop at a random point, so equal loops on several cars do not phase.
# A loop starts above 1% gain and stops below 0.2%, so a gain hovering at the
# edge does not restart it every frame. Volume is written only when it moves
# audibly (each write is a WebAudio call on the Web); pitch every frame, as a
# Web sample loses it when its loop wraps.
func _layer(node: Node, sound: String, gain: float, pitch: float, base_db: float) -> void:
	if gain < (0.002 if node.playing else 0.01):
		if node.playing:
			node.stop()
		return
	var stream = SoundBank.stream(sound)
	if node.stream != stream:
		node.stream = stream
		node.stop()
	var volume = base_db + linear_to_db(maxf(gain, 0.002))
	if absf(node.volume_db - volume) > 0.1:
		node.volume_db = volume
	node.pitch_scale = clampf(pitch, 0.3, 3.0)
	if not node.playing and DisplayServer.get_name() != "headless":
		node.play(rng.randf_range(0.0, 1.0))

func _surface(state: Dictionary, at: Vector3, delta: float) -> String:
	state.surface_clock = float(state.get("surface_clock", 0.0)) - delta
	if state.surface_clock <= 0.0:
		state.surface_clock = 0.25
		var water = game.stage.water
		state.surface = "water" if water != null and water.depth(at) > 0.08 else game.stage.biome.surface_sound(at)
	return state.surface

static func tyre_gain(speed: float) -> float:
	return pow(clampf(absf(speed) / 24.0, 0.0, 1.0), 0.8)

static func skid_sound(surface: String) -> String:
	return "tyres-skid-asphalt" if surface == "asphalt" else "tyres-skid-gravel"

static func slip_gain(slip: float, speed: float) -> float:
	return smoothstep(1.2, 5.0, slip) * clampf(absf(speed) / 4.0, 0.0, 1.0)

# ---------------------------------------------------------------- own car

func _update_own(delta: float) -> void:
	var driving = game.in_car and not game.rides.riding() and game.condition > 0.0
	if driving and not was_driving:
		start_hold = START_SECONDS
		game._play_audio(starter)
	was_driving = driving
	start_hold = maxf(0.0, start_hold - delta)
	if not driving:
		for node in own_layers.values():
			if node.playing:
				node.stop()
		return
	var throttle = Input.get_axis("back", "forward")
	var speed: float = game.speed
	# Pressing against the motion is braking, not throttle.
	var pedal = absf(throttle) if absf(speed) < 0.5 or signf(throttle) == signf(speed) else 0.0
	advance_engine(own, speed, pedal, GEARBOX.road, delta)
	var gains = layer_gains(own.rpm, own.load)
	var warm = 1.0 - start_hold / START_SECONDS
	var engine = "engine-%s-" % character(game.car)
	for layer in ["low", "on", "off"]:
		_layer(own_layers[layer], engine + layer, gains[layer] * warm, own.rpm / (LOW_RPM if layer == "low" else HIGH_RPM), OWN_ENGINE_DB)
	var surface = _surface(own, game.car.position, delta)
	var forward = Vector3(-sin(game.heading), 0, -cos(game.heading))
	var velocity: Vector3 = game.vehicle_motion.velocity
	var slip = Vector2(velocity.x, velocity.z).length() if absf(speed) < 0.1 else (velocity - forward * velocity.dot(forward)).length()
	_layer(own_layers.tyre, "tyres-" + surface, tyre_gain(speed) + (0.6 if surface == "water" and absf(speed) > 0.5 else 0.0), 0.8 + 0.4 * clampf(absf(speed) / 30.0, 0.0, 1.0), OWN_TYRES_DB)
	_layer(own_layers.skid, skid_sound(surface), slip_gain(slip, speed) if surface != "water" else 0.0, 0.9 if surface == "snow" else 1.0, OWN_SKID_DB)

# ---------------------------------------------------------------- cars around

func _track_cars(delta: float) -> void:
	var seen: Dictionary = {}
	for racer in game.racers:
		_track(seen, racer.node, str(racer.get("role", "racer")), false, true, delta)
	for entry in game.park_traffic.movers:
		_track(seen, entry.node, ParkTraffic.role_of(str(entry.key)), false, false, delta)
	for peer in game.room.peers.values():
		if peer.has("car") and peer.state != null:
			_track(seen, peer.car, "player", CarRides.driving(peer.state) and not bool(peer.state.get("broken", false)), false, delta)
	for id in cars.keys():
		if not seen.has(id):
			cars.erase(id)

func _track(seen: Dictionary, node: Node3D, role: String, driving: bool, on_stage: bool, delta: float) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	var id = node.get_instance_id()
	seen[id] = true
	var at = node.global_position
	var car: Dictionary = cars.get(id, {})
	if car.is_empty() or at.distance_to(car.pos) > 12.0:
		# New, or put back on the road: the jump is not motion.
		car = {"pos": at, "velocity": Vector3.ZERO, "speed": 0.0, "accel": 0.0, "still": ENGINE_LINGER, "recent": 0.0, "crash_clock": 0.0, "pop_clock": 0.0}
		cars[id] = car
	car.node = node
	car.role = role
	car.on_stage = on_stage
	car.engine = character(node)
	car.velocity = car.velocity.lerp((at - car.pos) / delta, 1.0 - exp(-delta * 10.0))
	car.pos = at
	var speed = Vector2(car.velocity.x, car.velocity.z).length()
	car.accel = lerpf(car.accel, (speed - car.speed) / delta, 1.0 - exp(-delta * 4.0))
	car.speed = speed
	car.still = 0.0 if speed > 0.4 else car.still + delta
	car.running = driving or car.still < ENGINE_LINGER
	var rally = role in ["racer", "zero"]
	var was_loaded = float(car.get("load", 0.0))
	var throttle = clampf(0.35 + car.accel / 4.0, 0.0, 1.0) if car.accel > -1.5 else 0.0
	advance_engine(car, speed, throttle, GEARBOX.rally if rally else GEARBOX.road, delta)
	_backfire(car, was_loaded, throttle, delta)
	_crash(car, delta)

# Lifting off at high revs, a competition engine spits flames.
func _backfire(car: Dictionary, was_loaded: float, throttle: float, delta: float) -> void:
	car.pop_clock = maxf(0.0, car.pop_clock - delta)
	if car.engine in RALLY_ENGINES and car.role in ["racer", "zero"] and was_loaded > 0.5 and throttle <= 0.0 and car.rpm > 4500.0 and car.pop_clock <= 0.0:
		car.pop_clock = 0.9
		if rng.randf() < 0.6 and car.pos.distance_to(listener) < 160.0:
			play_at("backfire-%d" % rng.randi_range(1, 3), car.pos, -4.0, 12.0)

# Losing speed faster than any brake can is a crash. A guest waits a moment
# for the car to stay slow: a stalled snapshot (the car holds, then catches
# up) must not sound like one.
func _crash(car: Dictionary, delta: float) -> void:
	car.crash_clock = maxf(0.0, car.crash_clock - delta)
	if float(car.get("pending", 0.0)) > 0.0:
		car.pending -= delta
		if car.pending <= 0.0 and car.speed < car.impact * 0.4:
			_crash_sound(car)
		return
	car.recent = maxf(car.speed, car.recent - 12.0 * delta)
	if car.recent - car.speed > CRASH_DROP:
		car.impact = car.recent
		car.recent = car.speed
		if game.room.is_guest():
			car.pending = GUEST_CRASH_CONFIRM
		else:
			_crash_sound(car)

func _crash_sound(car: Dictionary) -> void:
	if car.crash_clock > 0.0:
		return
	car.crash_clock = 1.5
	play_at("crash-heavy" if car.impact > HEAVY_CRASH_SPEED else "crash-light", car.pos, 0.0, 12.0)

func _assign_voices() -> void:
	var ranked: Array = []
	for id in cars:
		var car = cars[id]
		var distance = car.pos.distance_to(listener)
		if car.running and distance < HEARING:
			ranked.append([distance, id])
	ranked.sort_custom(func(a, b): return a[0] < b[0])
	var wanted: Dictionary = {}
	for i in range(mini(VOICES, ranked.size())):
		wanted[ranked[i][1]] = true
	for voice in voices:
		if voice.car != 0 and not wanted.has(voice.car):
			voice.car = 0
	for id in wanted:
		if voices.any(func(voice): return voice.car == id):
			continue
		for voice in voices:
			if voice.car == 0:
				voice.car = id
				break

func _sound_voice(voice: Dictionary) -> void:
	if voice.car == 0 or not cars.has(voice.car):
		voice.car = 0
		for layer in ["low", "on", "off", "tyre", "skid"]:
			if voice[layer].playing:
				voice[layer].stop()
		return
	var car: Dictionary = cars[voice.car]
	var shift = doppler(car.pos, car.velocity, listener, listener_velocity)
	var gains = layer_gains(car.rpm, car.load)
	for layer in ["low", "on", "off"]:
		voice[layer].global_position = car.pos
		_layer(voice[layer], "engine-%s-%s" % [car.engine, layer], gains[layer], car.rpm / (LOW_RPM if layer == "low" else HIGH_RPM) * shift, VOICE_ENGINE_DB)
	var surface = _surface(car, car.pos, get_process_delta_time())
	var forward = -car.node.global_transform.basis.z
	var slip = (car.velocity - forward * car.velocity.dot(forward)).length()
	voice.tyre.global_position = car.pos
	voice.skid.global_position = car.pos
	_layer(voice.tyre, "tyres-" + surface, tyre_gain(car.speed), (0.8 + 0.4 * clampf(car.speed / 30.0, 0.0, 1.0)) * shift, VOICE_TYRES_DB)
	_layer(voice.skid, skid_sound(surface), slip_gain(slip, car.speed) if surface != "water" else 0.0, shift, VOICE_TYRES_DB)

# Police opening and closing the stage and the ambulance drive with sirens.
func _update_sirens() -> void:
	var ranked: Array = []
	for id in cars:
		var car = cars[id]
		if car.on_stage and SIRENS.has(car.role) and car.speed > 1.0 and car.pos.distance_to(listener) < SIREN_REACH:
			ranked.append([car.pos.distance_to(listener), id])
	ranked.sort_custom(func(a, b): return a[0] < b[0])
	for i in range(sirens.size()):
		var id = ranked[i][1] if i < ranked.size() else 0
		siren_cars[i] = id
		var node = sirens[i]
		if id == 0:
			if node.playing:
				node.stop()
			continue
		var car: Dictionary = cars[id]
		node.global_position = car.pos + Vector3(0, 1.6, 0)
		_layer(node, SIRENS[car.role], 1.0, doppler(car.pos, car.velocity, listener, listener_velocity), -4.0)

# ---------------------------------------------------------------- events

# Doors open and close when anyone gets in or out; a driver starts the engine.
func _watch_seats() -> void:
	if game.in_car:
		seat_car = game.rides.vehicle()
	if was_in_car != null and was_in_car != game.in_car and is_instance_valid(seat_car):
		play_at("car-door", seat_car.global_position, -8.0, 4.0)
	was_in_car = game.in_car
	for id in game.room.peers:
		var peer = game.room.peers[id]
		if peer.state == null or not peer.has("car"):
			continue
		var seat = [bool(peer.state.get("in_car", false)), CarRides.driving(peer.state)]
		var before = peer_seats.get(id)
		peer_seats[id] = seat
		if before == null:
			continue
		var car_node = game.rides.car_node(str(peer.state.get("ride", ""))) if str(peer.state.get("ride", "")) != "" else peer.car
		if before[0] != seat[0] and car_node != null:
			play_at("car-door", car_node.global_position, -8.0, 4.0)
		if seat[1] and not before[1]:
			play_at("engine-start", peer.car.global_position, -10.0, 6.0)

func _watch_trunks_and_ropes() -> void:
	var opened: Dictionary = game.cargo.opened
	for owner in opened:
		var now = bool(opened[owner])
		if trunks.has(owner) and trunks[owner] != now:
			var node = game.rides.car_node(str(owner))
			if node != null:
				play_at("trunk-open" if now else "trunk-close", node.global_position, -9.0, 4.0)
		trunks[owner] = now
	var links: Array = game.recovery_links
	if links.size() > rope_count:
		var pos = links[links.size() - 1].get("pos", null)
		play_at("rope-hook", game.room.v(pos) if pos is Array else game.player_position(), -8.0, 5.0)
	rope_count = links.size()
