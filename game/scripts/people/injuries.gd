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
# Keys: "player:<id>" ("player:local" solo), "npc:<id>", "villager:<id>",
# "marshal:<id>", "judge:<index>".
const Props = preload("res://scripts/core/props.gd")
const Motion = preload("res://scripts/cars/vehicle_motion.gd")
# Reach (m) from a car centre: a little over the 1.55 m at which cars stop for people.
const HIT_RADIUS = 1.65
const VILLAGER_HIT_RADIUS = 2.2
const PLAYER_CAR_SPEED = 5.0
const CREW_SPEED = 2.0
const MAX_FLIGHT = 5.0
const MAX_LAUNCH = 13.0
const TREAT_SECONDS = 3.0
const Medics = preload("res://scripts/people/ambulance_medics.gd")
const CharacterRig = preload("res://scripts/people/character_rig.gd")
const Perches = preload("res://scripts/player/perches.gd")
const Navigation = preload("res://scripts/people/crowd_navigation.gd")
const Budget = preload("res://scripts/people/navigation_budget.gd")
const Loc = preload("res://scripts/ui/loc.gd")
const LIMP_SECONDS = 60.0
const LIMP_FACTOR = 0.55
# Terrain collision under a flight: PATCH × PATCH vertices, one metre apart.
const PATCH = 33
const BODY_LAYER = 1 << 9
const GROUND_LAYER = 1 << 10
# StageSolids boxes keep Godot's default layer.
const SOLID_LAYER = 1
# Avatar origin (feet) from the centre of the flying capsule.
const BODY_OFFSET = Vector3(0, -0.85, 0)
# Ambulance ids, clear of crews (1..), service cars (101..) and pass 2 (201..).
const AMBULANCE_ID = 500

var game
var medics = Medics.new()
var play = preload("res://scripts/people/people_play.gd").new()
# Host: key -> {"phase": "flying"|"lying"|"limp", "pos", "rot", "time", "body",
# "patch", "station", "ambulance", "treat", "limp", "home"}.
var records: Dictionary = {}
# Healed NPCs remain under our control until they walk back to their post.
var returning: Dictionary = {}
var return_budget = Budget.new()
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
	return entry != null and str(entry.phase) in ["flying", "lying"]

# People lying on the ground after a hit, as something to climb onto
# (perches.gd); never yourself.
func lying_avatars() -> Array:
	var result: Array = []
	for source in [records, targets]:
		for key in source:
			if key != local_key() and str(source[key].get("phase", "")) == "lying":
				var avatar = avatar_of(key)
				if avatar != null and not result.has(avatar):
					result.append(avatar)
	return result

# This avatar's pose is driven from here this frame.
func holds(avatar: Node) -> bool:
	return avatar != null and _held.has(avatar.get_instance_id())

func red_flag() -> bool:
	for racer in game.racers:
		if racer.get("role", "") == "ambulance":
			return true
	for key in records:
		if records[key].phase != "limp" and not records[key].get("play", false):
			return true
	return false

func nearby_person() -> bool:
	play.injuries = self
	return play.nearest(game.walker, local_key()) != ""

func walk_factor() -> float:
	return 0.0 if down else (LIMP_FACTOR if limp > 0.0 else 1.0)

# ---------------------------------------------------------------- people

# Everybody who can be hit: {"key", "pos" (feet), "avatar"}.
func people() -> Array:
	var result: Array = []
	if not game.in_car:
		result.append({"key": local_key(), "pos": game.walker, "avatar": local_avatar, "riding": not game.player.perches.stand.is_empty()})
	for id in game.room.peers:
		var peer = game.room.peers[id]
		if peer.state != null and not peer.state.in_car:
			result.append({"key": "player:%s" % id, "pos": game.room.v(peer.state.pos), "avatar": peer.get("avatar"), "riding": str(peer.state.get("stand", "")) != ""})
	if game.spectators != null:
		for person in game.spectators.people:
			result.append({"key": "npc:%d" % person.id, "pos": person.avatar.position, "avatar": person.avatar})
	var life = game.stage.life if game.stage != null and "life" in game.stage else null
	if life != null and "walkers" in life:
		for walker in life.walkers:
			result.append({"key": "villager:%d" % int(walker.id), "pos": walker.node.position, "avatar": walker.node})
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
		var feet: Vector3 = person.pos
		if is_down(person.key) or Perches.riding_above(feet, previous):
			continue
		var radius = VILLAGER_HIT_RADIUS if str(person.key).begins_with("villager:") else HIT_RADIUS
		if Motion.swept_hit(previous + Vector3(0, 0.7, 0), next + Vector3(0, 0.7, 0), feet + Vector3(0, 0.7, 0), radius):
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

func knock(key: String, feet: Vector3, velocity: Vector3, car: Vector3, playful: bool = false) -> bool:
	if not authority() or is_down(key):
		return false
	var away = feet - car
	away.y = 0
	away = away.normalized() if away.length() > 0.05 else Vector3(velocity.x, 0, velocity.z).normalized()
	var launch = Vector3(velocity.x, 0, velocity.z) * 0.75 + away * 2.5
	launch = launch.limit_length(MAX_LAUNCH)
	launch.y = 3.0 + launch.length() * 0.25
	var record = {"phase": "flying", "time": 0.0, "pos": feet, "rot": Vector3.ZERO, "treat": 0.0, "limp": 0.0, "ambulance": -1}
	record.start = feet
	record.body = _launch(feet, launch, key.hash())
	record.patch = _ground_patch(feet)
	record.station = game.race_station(feet)
	var avatar = avatar_of(key)
	if avatar != null:
		record.home = _home(key, avatar.position)
		record.home_yaw = avatar.rotation.y
		if returning.has(key):
			record.home = returning[key].goal
			record.home_yaw = returning[key].home_yaw
			returning.erase(key)
		if avatar.has_meta("solid_record"):
			# Officials are rocks for cars and walkers; a casualty is not.
			avatar.get_meta("solid_record").pos.y = -1000.0
	if key.begins_with("villager:"):
		_set_villager_knocked(key, true)
	record.play = playful
	records[key] = record
	if playful:
		if key == local_key():
			_go_down()
		game.toast("Человек упал! Удерживай T: стой, чтобы поднять, иди, чтобы тащить. Пробел — встать.")
		return true
	_assign(record, key)
	# Broadcast the emergency immediately, not only on the next update tick.
	game.course.red_flag = true
	_knocked(key)
	return true

func _launch(feet: Vector3, launch: Vector3, seed: int) -> RigidBody3D:
	var body = RigidBody3D.new()
	body.name = "KnockedBody"
	body.mass = 75.0
	body.linear_damp = 0.2
	body.angular_damp = 1.2
	body.collision_layer = BODY_LAYER
	# Terrain patch plus the stage's solid boxes (houses, walls, lamp posts):
	# a body thrown at a house bounces off its wall instead of entering it.
	body.collision_mask = GROUND_LAYER | SOLID_LAYER
	body.continuous_cd = true
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
		if racer.get("role", "") == "ambulance" and (float(racer.s) < float(record.station) - 6.0 or _reachable(racer, record)):
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
	if medics.active.has(int(racer.id)):
		return
	var best = INF
	var target_key = ""
	for key in records:
		var r: Dictionary = records[key]
		if int(r.ambulance) == racer.id and r.phase != "limp" and (float(r.station) >= float(racer.s) - 1.0 or _reachable(racer, r)) and float(r.station) < best:
			best = float(r.station)
			target_key = key
	racer.target_key = target_key
	racer.target_s = best if target_key != "" else -1.0
	if target_key == "":
		racer.bias = 0.0
	# A parked ambulance moves on once its medics are done.
	if racer.state == "parked":
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
		var station = game.stage.road_s(r.pos)
		var room = maxf(0.0, game.stage.road_width(station) * 0.5 + game.stage.shoulder(station) - 1.2)
		racer.bias = clampf(lateral, -room, room)
	# Yielding to the casualty must still allow treatment from a safe stop.
	var safe_stop = racer.node.position.distance_to(r.pos) <= 8.0 and float(racer.get("drive_speed", 0.0)) <= 0.2
	if safe_stop or (float(racer.s) >= target - 4.5 and _ambulance_at_casualty(racer, r)):
		racer.state = "parked"
		racer.drive_speed = 0.0

# Speed cap for an ambulance closing on its stop (m/s), see Traffic.speed_limit.
static func ambulance_speed(racer: Dictionary, s: float) -> float:
	var target = float(racer.get("target_s", -1.0))
	if target < 0.0:
		return INF
	# Reserve four metres for a safe stop so lateral positioning can finish
	# without the ambulance rolling past the casualty's station.
	return sqrt(2.0 * 4.0 * maxf(0.0, target - s - 4.0))

# ---------------------------------------------------------------- frame

func update(delta: float) -> void:
	medics.injuries = self
	play.injuries = self
	_held.clear()
	if authority():
		_update_host(delta)
		_update_returning(delta)
	else:
		_update_guest(delta)
	medics.update(delta)
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
				if r.get("play", false):
					_pose(key, r.pos, r.rot, 1.0)
					if not str(key).begins_with("player:") and r.time > 12.0 and not play.grabbed(key):
						play.stand(key)
					continue
				var ambulance = _ambulance(int(r.ambulance))
				if ambulance.is_empty():
					_assign(r, key)
				elif not medics.active.has(int(ambulance.id)):
					# A landing can move the casualty behind the van. Dispatch a
					# replacement if it is too far to reach on foot; never abandon it.
					if float(r.station) < float(ambulance.s) - 1.0 and not _reachable(ambulance, r):
						r.ambulance = -1
						_retarget(ambulance)
						_assign(r, key)
					elif str(ambulance.get("target_key", "")) == key and _ambulance_at_casualty(ambulance, r):
						r.rescue_retry = maxf(0.0, float(r.get("rescue_retry", 0.0)) - delta)
						if r.rescue_retry <= 0.0:
							r.rescue_retry = 1.0
							medics.start(ambulance, key)
			"limp":
				r.limp = maxf(0.0, float(r.limp) - delta)
				if r.limp <= 0.0:
					records.erase(key)
				continue
		_pose(key, r.pos, r.rot, 1.0)
	game.course.red_flag = red_flag()

# A casualty is reachable on foot from a van that is close or level with them
# along the road, however far off the road they lie.
func _reachable(ambulance: Dictionary, record: Dictionary) -> bool:
	return ambulance.node.position.distance_to(record.pos) <= Medics.WALK_RADIUS or absf(float(ambulance.s) - float(record.station)) <= Medics.STATION_TOLERANCE

func _ambulance_at_casualty(ambulance: Dictionary, record: Dictionary) -> bool:
	# Route progress is only a dispatch hint. An impact can displace a casualty
	# off the road, so station values can differ even when the ambulance is
	# physically stopped beside them; what counts is being stopped and reachable.
	return float(ambulance.get("drive_speed", 0.0)) <= 0.2 and _reachable(ambulance, record)

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
	var spot = _clear_spot(body.global_position, r.get("start", body.global_position))
	spot.y = game.stage.ground(spot)
	body.queue_free()
	r.patch.queue_free()
	r.erase("body")
	r.erase("patch")
	r.phase = "lying"
	r.pos = spot + Vector3(0, 0.25, 0)
	r.rot = Vector3(0, yaw, PI / 2)
	r.station = game.race_station(spot)

# Never lie inside a building: walk back towards the impact until clear.
func _clear_spot(spot: Vector3, start: Vector3) -> Vector3:
	for i in range(21):
		var candidate = spot.lerp(start, i / 20.0)
		candidate.y = game.stage.ground(candidate) + 0.3
		if game.stage.solids.clear(candidate, 0.35):
			return candidate
	return start

func _stand(key: String, r: Dictionary) -> void:
	var spot: Vector3 = r.pos
	spot.y = game.stage.ground(spot)
	var avatar = avatar_of(key)
	_pose(key, spot, Vector3(0, float(r.rot.y), 0), 1.0)
	if avatar != null and avatar.has_meta("solid_record"):
		avatar.get_meta("solid_record").pos = avatar.position
	if key.begins_with("player:"):
		r.phase = "limp"
		r.limp = LIMP_SECONDS
		r.pos = spot
		r.rot = Vector3(0, float(r.rot.y), 0)
		if key == local_key():
			_stand_local(spot, bool(r.get("play", false)))
	else:
		if avatar != null:
			returning[key] = {"avatar": avatar, "navigation_budget": return_budget, "goal": r.get("home", _home(key, spot)), "home_yaw": r.get("home_yaw", avatar.rotation.y), "clock": 0.0, "moving": false}
		records.erase(key)

func _home(key: String, fallback: Vector3) -> Vector3:
	if key.begins_with("npc:"):
		for person in game.spectators.people:
			if key == "npc:%d" % person.id:
				return person.home
	if key.begins_with("marshal:"):
		for person in game.stage.officials.people:
			if key == "marshal:%d" % person.id:
				return person.home
	return fallback

func _update_returning(delta: float) -> void:
	return_budget.advance(delta)
	for key in returning.keys():
		var person: Dictionary = returning[key]
		var avatar: Node3D = person.avatar
		var before = avatar.position
		# A casualty may have landed on either side of the road: allow crossing
		# back, while retaining the shared obstacle and vehicle avoidance.
		Navigation.move(game, person, person.goal, delta, false)
		var motion = avatar.position - before
		person.moving = Navigation.flat(motion).length() > 0.001
		person.clock += delta
		if person.moving:
			avatar.rotation.y = atan2(-motion.x, -motion.z)
		_pose_returning(key, person)
		if Navigation.flat(avatar.position).distance_to(Navigation.flat(person.goal)) < 0.2:
			avatar.rotation.y = person.home_yaw
			if key.begins_with("villager:"):
				_set_villager_knocked(key, false)
			returning.erase(key)

func _pose_returning(key: String, person: Dictionary) -> void:
	var avatar: Node3D = person.avatar
	_held[avatar.get_instance_id()] = true
	CharacterRig.pose(avatar, {"gait": 1 if person.moving else 0, "time": person.clock, "arms": "clipboard" if key.begins_with("judge:") else ""})
	if avatar.has_meta("solid_record"):
		avatar.get_meta("solid_record").pos = avatar.position

# ---------------------------------------------------------------- guests

func _update_guest(delta: float) -> void:
	for key in targets:
		var entry: Dictionary = targets[key]
		if str(entry.phase) == "limp":
			continue
		_pose(key, Vector3(entry.pos[0], entry.pos[1], entry.pos[2]), Vector3(entry.rot[0], entry.rot[1], entry.rot[2]), 1.0 - exp(-delta * 12.0))
		if str(entry.phase) == "returning":
			var avatar = avatar_of(key)
			if avatar != null:
				_pose_returning(key, {"avatar": avatar, "moving": entry.get("moving", false), "clock": entry.get("clock", 0.0)})

func snapshot() -> Array:
	var result: Array = []
	for key in records:
		var r: Dictionary = records[key]
		var p: Vector3 = r.pos
		var rot: Vector3 = r.rot
		var entry = {"key": key, "phase": r.phase, "pos": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)], "rot": [snappedf(rot.x, 0.01), snappedf(rot.y, 0.01), snappedf(rot.z, 0.01)]}
		entry.play = r.get("play", false)
		if r.phase == "limp":
			entry.limp = snappedf(float(r.limp), 0.1)
		else:
			entry.eta = snappedf(eta(key), 1.0)
			if float(r.treat) > 0.0:
				entry.treat = true
		result.append(entry)
	for key in returning:
		var person: Dictionary = returning[key]
		var pos: Vector3 = person.avatar.position
		result.append({"key": key, "phase": "returning", "pos": [pos.x, pos.y, pos.z], "rot": [0, person.avatar.rotation.y, 0], "moving": person.moving, "clock": person.clock, "goal": [person.goal.x, person.goal.y, person.goal.z], "home_yaw": person.home_yaw})
	return result

func apply_snapshot(entries: Array) -> void:
	var previous_targets = targets.duplicate()
	var seen: Dictionary = {}
	for entry in entries:
		if not entry is Dictionary or not entry.get("pos") is Array or not entry.get("rot") is Array:
			continue
		seen[str(entry.key)] = true
		targets[str(entry.key)] = entry
		if str(entry.get("phase", "")) == "returning":
			var avatar = avatar_of(str(entry.key))
			if avatar != null:
				avatar.rotation = Vector3(0, float(entry.rot[1]), 0)
	for key in targets.keys():
		if not seen.has(key):
			targets.erase(key)
	for key in previous_targets:
		if not seen.has(key) and not str(key).begins_with("player:"):
			var avatar = avatar_of(str(key))
			if avatar != null:
				avatar.rotation = Vector3(0, avatar.rotation.y, 0)
				var previous: Dictionary = previous_targets[key]
				if previous.get("phase", "") == "returning" and previous.get("goal") is Array:
					avatar.position = Vector3(previous.goal[0], previous.goal[1], previous.goal[2])
					avatar.rotation.y = float(previous.get("home_yaw", avatar.rotation.y))
				avatar.position.y = game.stage.ground(avatar.position)
		if str(key).begins_with("villager:") and not seen.has(key):
			_set_villager_knocked(str(key), false)
	for entry in entries:
		var key = str(entry.get("key", "")) if entry is Dictionary else ""
		if key.begins_with("villager:") and str(entry.get("phase", "")) != "limp":
			_set_villager_knocked(key, true)
	var mine = targets.get(local_key())
	var was_down = down
	if mine != null and str(mine.phase) != "limp":
		if not down:
			_go_down()
	elif was_down:
		var spot = game.walker
		if mine != null:
			spot = Vector3(mine.pos[0], mine.pos[1], mine.pos[2])
		_stand_local(spot, bool(previous_targets.get(local_key(), {}).get("play", false)))
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

func _stand_local(spot: Vector3, playful: bool = false) -> void:
	down = false
	limp = 0.0 if playful else LIMP_SECONDS
	game.walker = spot
	game.jump_height = 0.0
	game.jump_velocity = 0.0
	if local_avatar != null:
		local_avatar.queue_free()
		local_avatar = null
	game.toast("Ты снова на ногах." if playful else "Медики помогли подняться. Пока без бега и прыжков.")

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
		if records.get(local_key(), targets.get(local_key(), {})).get("play", false):
			return "ТЫ УПАЛ · ПРОБЕЛ — ВСТАТЬ · ДРУГ МОЖЕТ ПОМОЧЬ (T)"
		if treating(local_key()):
			return Loc.t("МЕДИКИ ОКАЗЫВАЮТ ПОМОЩЬ")
		var metres = eta(local_key())
		return Loc.t("ТЕБЯ СБИЛИ · СКОРАЯ В ПУТИ · %d М") % int(metres) if metres >= 0.0 else Loc.t("ТЕБЯ СБИЛИ · СКОРАЯ ВЫЕЗЖАЕТ")
	if limp > 0.0:
		return Loc.t("ХРОМАЕШЬ · БЕЗ БЕГА И ПРЫЖКОВ · %d С") % ceili(limp)
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
	# A casualty lies with arms and legs relaxed, whatever they were doing;
	# standing up again starts from a neutral pose (judges keep the clipboard).
	var lying = absf(rot.x) + absf(rot.z) > 0.1
	CharacterRig.pose(avatar, {"arms": "limp" if lying else ("clipboard" if key.begins_with("judge:") else "")})
	var goal = Basis.from_euler(rot)
	avatar.position = avatar.position.lerp(pos, weight)
	avatar.quaternion = avatar.quaternion.slerp(goal.get_rotation_quaternion(), weight)

func _set_villager_knocked(key: String, knocked: bool) -> void:
	if game.stage == null or not "life" in game.stage or game.stage.life == null:
		return
	var id = key.get_slice(":", 1).to_int()
	game.stage.life.set_walker_knocked(id, knocked)
