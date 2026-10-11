extends RefCounted
# People knocked down by cars. Any moving rally crew or service car, and any
# player's car above PLAYER_CAR_SPEED, throws a person it hits: players on
# foot, spectators, marshals and judges. The body flies on the engine's physics
# (a RigidBody3D capsule over a patch of terrain collision), then lies where it
# lands. An ambulance drives from the start of the stage; the stage is
# red-flagged (no new crews start) while it is out. When it has parked beside
# the casualty, the medics take TREAT_SECONDS, then the person stands up;
# players limp for LIMP_SECONDS (no running or jumping, slower walking).
#
# The host (or a solo game) owns everything here. Guests get "injuries" in the
# world snapshot and pose the bodies from it; the ambulance travels as a course
# vehicle (role "ambulance") with the other racers.
#
# Keys: "player:<id>" ("player:local" solo), "npc:<id>", "marshal:<id>",
# "judge:<index>".
const Props = preload("res://scripts/props.gd")
const Motion = preload("res://scripts/vehicle_motion.gd")
# Reach (m) from a car centre: a little over the 1.55 m at which cars stop for people.
const HIT_RADIUS = 1.65
const PLAYER_CAR_SPEED = 5.0
const CREW_SPEED = 2.0
const MAX_FLIGHT = 5.0
const MAX_LAUNCH = 13.0
const TREAT_SECONDS = 5.0
const LIMP_SECONDS = 60.0
const LIMP_FACTOR = 0.55
# Terrain collision under a flight: PATCH × PATCH vertices, one metre apart.
const PATCH = 33
const BODY_LAYER = 1 << 9
const GROUND_LAYER = 1 << 10
# Avatar origin (feet) from the centre of the flying capsule.
const BODY_OFFSET = Vector3(0, -0.85, 0)
# Ambulance ids, clear of crews (1..), service cars (101..) and pass 2 (201..).
const AMBULANCE_ID = 500

var game
# Host: key -> {"phase": "flying"|"lying"|"limp", "pos", "rot", "time", "body",
# "patch", "station", "ambulance", "treat", "limp", "home"}.
var records: Dictionary = {}
# Guest: key -> last snapshot entry.
var targets: Dictionary = {}
# The local player is flying or lying, and limps for this many more seconds.
var down = false
var limp = 0.0
var local_avatar: Node3D
var _serial = 0
var _held: Dictionary = {}

func local_key() -> String:
	return "player:" + (str(game.room.player_id) if game.room.connected else "local")

func authority() -> bool:
	return game.room.is_authority()

# The person is flying or lying (not limping): cars pass, helpers skip them.
func is_down(key: String) -> bool:
	var entry = records.get(key, targets.get(key))
	return entry != null and str(entry.phase) != "limp"

# This avatar's pose is driven from here this frame.
func holds(avatar: Node) -> bool:
	return avatar != null and _held.has(avatar.get_instance_id())

func red_flag() -> bool:
	for racer in game.racers:
		if racer.get("role", "") == "ambulance":
			return true
	for key in records:
		if records[key].phase != "limp":
			return true
	return false

func walk_factor() -> float:
	return 0.0 if down else (LIMP_FACTOR if limp > 0.0 else 1.0)

# ---------------------------------------------------------------- people

# Everybody who can be hit: {"key", "pos" (feet), "avatar"}.
func people() -> Array:
	var result: Array = []
	if not game.in_car:
		result.append({"key": local_key(), "pos": game.walker, "avatar": local_avatar})
	for id in game.room.peers:
		var peer = game.room.peers[id]
		if peer.state != null and not peer.state.in_car:
			result.append({"key": "player:%s" % id, "pos": game.room.v(peer.state.pos), "avatar": peer.get("avatar")})
	if game.spectators != null:
		for person in game.spectators.people:
			result.append({"key": "npc:%d" % person.id, "pos": person.avatar.position, "avatar": person.avatar})
	var officials = game.stage.officials if game.stage != null and "officials" in game.stage else null
	if officials != null:
		for person in officials.people:
			result.append({"key": "marshal:%d" % person.id, "pos": person.avatar.position, "avatar": person.avatar})
		for i in range(officials.judges.size()):
			result.append({"key": "judge:%d" % i, "pos": officials.judges[i].position, "avatar": officials.judges[i]})
	return result

func avatar_of(key: String) -> Node3D:
	if key == local_key():
		return local_avatar
	for person in people():
		if person.key == key:
			return person.avatar
	return null

# ---------------------------------------------------------------- hits

# A car swept from previous to next: knock everyone in its way. Returns true
# when somebody was hit. Only the host decides.
func vehicle_sweep(previous: Vector3, next: Vector3, velocity: Vector3, min_speed: float) -> bool:
	if not authority() or Vector2(velocity.x, velocity.z).length() < min_speed:
		return false
	var hit = false
	for person in people():
		if is_down(person.key):
			continue
		var feet: Vector3 = person.pos
		if Motion.swept_hit(previous + Vector3(0, 0.7, 0), next + Vector3(0, 0.7, 0), feet + Vector3(0, 0.7, 0), HIT_RADIUS):
			hit = knock(person.key, feet, velocity, previous) or hit
	return hit

# A car simulated elsewhere (a guest's) ran into somebody at `at`.
func knock_near(at: Vector3, velocity: Vector3, car: Vector3) -> bool:
	var best = 1.0
	var found: Dictionary = {}
	for person in people():
		var distance = Vector2(person.pos.x - at.x, person.pos.z - at.z).length()
		if distance < best and not is_down(person.key):
			best = distance
			found = person
	return not found.is_empty() and knock(found.key, found.pos, velocity, car)

func knock(key: String, feet: Vector3, velocity: Vector3, car: Vector3) -> bool:
	if not authority() or is_down(key):
		return false
	var away = feet - car
	away.y = 0
	away = away.normalized() if away.length() > 0.05 else Vector3(velocity.x, 0, velocity.z).normalized()
	var launch = Vector3(velocity.x, 0, velocity.z) * 0.75 + away * 2.5
	launch = launch.limit_length(MAX_LAUNCH)
	launch.y = 3.0 + launch.length() * 0.25
	var record = {"phase": "flying", "time": 0.0, "pos": feet, "rot": Vector3.ZERO, "treat": 0.0, "limp": 0.0, "ambulance": -1}
	record.body = _launch(feet, launch, key.hash())
	record.patch = _ground_patch(feet)
	record.station = game.race_station(feet)
	var avatar = avatar_of(key)
	if avatar != null:
		record.home = avatar.position
		if avatar.has_meta("solid_record"):
			# Officials are rocks for cars and walkers; a casualty is not.
			avatar.get_meta("solid_record").pos.y = -1000.0
	records[key] = record
	_assign(record, key)
	_knocked(key)
	return true

func _launch(feet: Vector3, launch: Vector3, seed: int) -> RigidBody3D:
	var body = RigidBody3D.new()
	body.name = "KnockedBody"
	body.mass = 75.0
	body.linear_damp = 0.2
	body.angular_damp = 1.2
	body.collision_layer = BODY_LAYER
	body.collision_mask = GROUND_LAYER
	var material = PhysicsMaterial.new()
	material.friction = 0.9
	material.bounce = 0.15
	body.physics_material_override = material
	var shape = CollisionShape3D.new()
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.7
	shape.shape = capsule
	body.add_child(shape)
	game.add_child(body)
	body.global_position = feet - BODY_OFFSET
	body.rotation.y = atan2(-launch.x, -launch.z)
	body.linear_velocity = launch
	# Tumble head over heels away from the car, with a little spin.
	var axis = Vector3(launch.z, 0, -launch.x).normalized()
	body.angular_velocity = axis * 5.0 + Vector3(0, float(seed % 7 - 3) * 0.6, 0)
	return body

# Terrain under the flight as a height map: the stage itself has no physics.
func _ground_patch(center: Vector3) -> StaticBody3D:
	var origin = Vector3(roundf(center.x), 0, roundf(center.z))
	var half = (PATCH - 1) / 2
	var heights = PackedFloat32Array()
	for z in range(PATCH):
		for x in range(PATCH):
			heights.append(game.stage.ground(origin + Vector3(x - half, 0, z - half)))
	var shape = HeightMapShape3D.new()
	shape.map_width = PATCH
	shape.map_depth = PATCH
	shape.map_data = heights
	var patch = StaticBody3D.new()
	patch.name = "KnockdownGround"
	patch.collision_layer = GROUND_LAYER
	patch.collision_mask = 0
	var collider = CollisionShape3D.new()
	collider.shape = shape
	patch.add_child(collider)
	game.add_child(patch)
	patch.global_position = origin
	return patch

func _knocked(key: String) -> void:
	if key == local_key():
		_go_down()
		game.toast("Тебя сбила машина! Лежи — скорая уже выехала со старта.")
	elif key.begins_with("player:"):
		game.toast("Сбили участника компании! Красный флаг, вызвана скорая.")
	else:
		game.toast("Машина сбила человека! Красный флаг, вызвана скорая.")

# ---------------------------------------------------------------- ambulance

# The nearest ambulance still behind the casualty takes it; otherwise a new
# one leaves the start.
func _assign(record: Dictionary, key: String) -> void:
	for racer in game.racers:
		if racer.get("role", "") == "ambulance" and float(racer.s) < float(record.station) - 6.0:
			record.ambulance = racer.id
			_retarget(racer)
			return
	_serial += 1
	var id = AMBULANCE_ID + _serial
	game.spawn_course_car("ambulance", id)
	for racer in game.racers:
		if racer.id == id:
			racer.pace = 0.9
			racer.target_s = -1.0
			record.ambulance = id
			_retarget(racer)

# Head for the nearest casualty ahead that this ambulance looks after.
func _retarget(racer: Dictionary) -> void:
	var best = INF
	var target_key = ""
	for key in records:
		var r: Dictionary = records[key]
		if int(r.ambulance) == racer.id and r.phase != "limp" and float(r.station) >= float(racer.s) - 1.0 and float(r.station) < best:
			best = float(r.station)
			target_key = key
	racer.target_key = target_key
	racer.target_s = best if target_key != "" else -1.0
	if target_key == "":
		racer.bias = 0.0
	# A parked ambulance moves on once its medics are done.
	if racer.state == "parked" and str(racer.get("treating", "")) == "":
		racer.state = "racing"

# Called by rally_crews for an ambulance on the move: slow down onto the
# casualty's side of the road and park beside them.
func ambulance_step(racer: Dictionary) -> void:
	var target = float(racer.get("target_s", -1.0))
	if target < 0.0 or not records.has(str(racer.get("target_key", ""))):
		return
	var r: Dictionary = records[racer.target_key]
	if target - float(racer.s) < 45.0:
		var lateral = (r.pos - game.race_at(target)).dot(game.race_side(target))
		var room = maxf(0.0, game.stage.road_width(game.stage.road_s(r.pos)) * 0.5 - 1.2)
		racer.bias = clampf(lateral, -room, room)
	# Yielding to the casualty must still allow treatment from a safe stop.
	var safe_stop = racer.node.position.distance_to(r.pos) <= 8.0 and float(racer.get("drive_speed", 0.0)) <= 0.2
	if float(racer.s) >= target - 0.5 or (float(racer.s) >= target - 6.0 and safe_stop):
		racer.state = "parked"
		racer.drive_speed = 0.0
		racer.treating = racer.target_key

# Speed cap for an ambulance closing on its stop (m/s), see Traffic.speed_limit.
static func ambulance_speed(racer: Dictionary, s: float) -> float:
	var target = float(racer.get("target_s", -1.0))
	if target < 0.0:
		return INF
	return maxf(1.5, sqrt(2.0 * 4.0 * maxf(0.0, target - s)))

# ---------------------------------------------------------------- frame

func update(delta: float) -> void:
	_held.clear()
	if authority():
		_update_host(delta)
	else:
		_update_guest(delta)
	if limp > 0.0 and not down:
		limp = maxf(0.0, limp - delta)

func _update_host(delta: float) -> void:
	for key in records.keys():
		var r: Dictionary = records[key]
		r.time += delta
		match str(r.phase):
			"flying":
				_fly(r)
				if r.phase == "lying":
					_retarget_all()
			"lying":
				var ambulance = _ambulance(int(r.ambulance))
				if ambulance.is_empty():
					_assign(r, key)
				elif ambulance.state == "parked" and ambulance.get("treating", "") == key:
					r.treat += delta
					if r.treat >= TREAT_SECONDS:
						_stand(key, r)
						ambulance.treating = ""
						_retarget(ambulance)
						continue
			"limp":
				r.limp = maxf(0.0, float(r.limp) - delta)
				if r.limp <= 0.0:
					records.erase(key)
				continue
		_pose(key, r.pos, r.rot, 1.0)
	game.course.red_flag = red_flag()

func _retarget_all() -> void:
	for racer in game.racers:
		if racer.get("role", "") == "ambulance":
			_retarget(racer)

func _ambulance(id: int) -> Dictionary:
	for racer in game.racers:
		if racer.id == id:
			return racer
	return {}

# Follow the flying body; land once it rests, leaves its patch or time is up.
func _fly(r: Dictionary) -> void:
	var body: RigidBody3D = r.body
	var xform: Transform3D = body.global_transform * Transform3D(Basis.IDENTITY, BODY_OFFSET)
	r.pos = xform.origin
	r.rot = xform.basis.get_euler()
	var centre = body.global_position
	var ground: float = game.stage.ground(centre)
	var outside = Vector2(centre.x - r.patch.global_position.x, centre.z - r.patch.global_position.z).length() > (PATCH - 1) * 0.5 - 1.0
	var resting = r.time > 0.5 and (body.sleeping or body.linear_velocity.length() < 0.3)
	if resting or outside or centre.y < ground - 1.0 or r.time > MAX_FLIGHT:
		_land(r)

func _land(r: Dictionary) -> void:
	var body: RigidBody3D = r.body
	var forward: Vector3 = -body.global_basis.y
	forward.y = 0
	var yaw = atan2(-forward.x, -forward.z) if forward.length() > 0.1 else body.rotation.y
	var spot = body.global_position
	spot.y = game.stage.ground(spot)
	body.queue_free()
	r.patch.queue_free()
	r.erase("body")
	r.erase("patch")
	r.phase = "lying"
	r.pos = spot + Vector3(0, 0.25, 0)
	r.rot = Vector3(0, yaw, PI / 2)
	r.station = game.race_station(spot)

func _stand(key: String, r: Dictionary) -> void:
	var spot: Vector3 = r.pos
	spot.y = game.stage.ground(spot)
	var avatar = avatar_of(key)
	if key.begins_with("judge:") and r.has("home"):
		spot = r.home
	_pose(key, spot, Vector3(0, float(r.rot.y), 0), 1.0)
	if avatar != null and avatar.has_meta("solid_record"):
		avatar.get_meta("solid_record").pos = avatar.position
	if key.begins_with("player:"):
		r.phase = "limp"
		r.limp = LIMP_SECONDS
		r.pos = spot
		r.rot = Vector3(0, float(r.rot.y), 0)
		if key == local_key():
			_stand_local(spot)
	else:
		records.erase(key)

# ---------------------------------------------------------------- guests

func _update_guest(delta: float) -> void:
	for key in targets:
		var entry: Dictionary = targets[key]
		if str(entry.phase) == "limp":
			continue
		_pose(key, Vector3(entry.pos[0], entry.pos[1], entry.pos[2]), Vector3(entry.rot[0], entry.rot[1], entry.rot[2]), 1.0 - exp(-delta * 12.0))

func snapshot() -> Array:
	var result: Array = []
	for key in records:
		var r: Dictionary = records[key]
		var p: Vector3 = r.pos
		var rot: Vector3 = r.rot
		var entry = {"key": key, "phase": r.phase, "pos": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)], "rot": [snappedf(rot.x, 0.01), snappedf(rot.y, 0.01), snappedf(rot.z, 0.01)]}
		if r.phase == "limp":
			entry.limp = snappedf(float(r.limp), 0.1)
		else:
			entry.eta = snappedf(eta(key), 1.0)
			if float(r.treat) > 0.0:
				entry.treat = true
		result.append(entry)
	return result

func apply_snapshot(entries: Array) -> void:
	var seen: Dictionary = {}
	for entry in entries:
		if not entry is Dictionary or not entry.get("pos") is Array or not entry.get("rot") is Array:
			continue
		seen[str(entry.key)] = true
		targets[str(entry.key)] = entry
	for key in targets.keys():
		if not seen.has(key):
			targets.erase(key)
	var mine = targets.get(local_key())
	var was_down = down
	if mine != null and str(mine.phase) != "limp":
		if not down:
			_go_down()
	elif was_down:
		var spot = game.walker
		if mine != null:
			spot = Vector3(mine.pos[0], mine.pos[1], mine.pos[2])
		_stand_local(spot)
	if mine != null and str(mine.phase) == "limp":
		limp = float(mine.get("limp", limp))

# ---------------------------------------------------------------- local player

func _go_down() -> void:
	down = true
	game.seated = false
	game.eat_time = -1.0
	if game.drink_time >= 0:
		game._cancel_drink()
	if local_avatar == null:
		local_avatar = Props.player_avatar(game.avatar_variant)
		game.add_child(local_avatar)
		local_avatar.position = game.walker

func _stand_local(spot: Vector3) -> void:
	down = false
	limp = LIMP_SECONDS
	game.walker = spot
	game.jump_height = 0.0
	game.jump_velocity = 0.0
	if local_avatar != null:
		local_avatar.queue_free()
		local_avatar = null
	game.toast("Медики помогли подняться. Пока без бега и прыжков.")

# Metres the ambulance still has to drive to this casualty; -1 before it left.
func eta(key: String) -> float:
	if not records.has(key):
		var entry = targets.get(key)
		return float(entry.get("eta", -1.0)) if entry != null else -1.0
	var ambulance = _ambulance(int(records[key].ambulance))
	if ambulance.is_empty():
		return -1.0
	return maxf(0.0, float(records[key].station) - float(ambulance.s))

func treating(key: String) -> bool:
	if records.has(key):
		return float(records[key].treat) > 0.0
	return bool(targets.get(key, {}).get("treat", false))

# Status line for the HUD; empty when nothing applies.
func hud_line() -> String:
	if down:
		if treating(local_key()):
			return "МЕДИКИ ОКАЗЫВАЮТ ПОМОЩЬ"
		var metres = eta(local_key())
		return "ТЕБЯ СБИЛИ · СКОРАЯ В ПУТИ · %d М" % int(metres) if metres >= 0.0 else "ТЕБЯ СБИЛИ · СКОРАЯ ВЫЕЗЖАЕТ"
	if limp > 0.0:
		return "ХРОМАЕШЬ · БЕЗ БЕГА И ПРЫЖКОВ · %d С" % ceili(limp)
	return ""

# Third-person view of yourself lying, orbiting with the usual mouse look.
func update_camera(delta: float) -> void:
	if local_avatar == null:
		return
	var target = local_avatar.global_position + Vector3(0, 0.5, 0)
	var back = Vector3(sin(game.view_yaw), 0, cos(game.view_yaw))
	var desired = target + back * 3.6 + Vector3.UP * 2.4
	desired.y = maxf(desired.y, game.stage.ground(desired) + 0.8)
	game.camera.position = game.camera.position.lerp(desired, 1.0 - exp(-delta * 6.0))
	game.camera.look_at(target)

# ---------------------------------------------------------------- poses

func _pose(key: String, pos: Vector3, rot: Vector3, weight: float) -> void:
	var avatar = avatar_of(key)
	if key == local_key():
		game.walker = Vector3(pos.x, game.stage.ground(pos), pos.z)
	if avatar == null:
		return
	_held[avatar.get_instance_id()] = true
	var goal = Basis.from_euler(rot)
	avatar.position = avatar.position.lerp(pos, weight)
	avatar.quaternion = avatar.quaternion.slerp(goal.get_rotation_quaternion(), weight)
