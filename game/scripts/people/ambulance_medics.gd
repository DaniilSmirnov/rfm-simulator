extends RefCounted
# One authoritative medic per ambulance. The van stays parked until boarding
# finishes; only the patient at the medic's feet can accumulate treatment time.
const Navigation = preload("res://scripts/people/crowd_navigation.gd")
const Model = preload("res://scripts/people/medic_model.gd")
const Budget = preload("res://scripts/people/navigation_budget.gd")
const CarOccupants = preload("res://scripts/cars/car_occupants.gd")
const WALK_RADIUS = 20.0
# Road distance (m) within which a stopped van is level with a casualty.
const STATION_TOLERANCE = 6.0
# Getting out: the door opens, the doctor turns on the seat towards it, swings
# the legs out and climbs down, and shuts the door. Getting in runs backwards.
const OPEN_SECONDS = 0.4
const CLIMB_SECONDS = 1.0
const DOOR_SECONDS = 1.8
const CharacterRig = preload("res://scripts/people/character_rig.gd")
const REACH = 1.3
# A doctor who cannot find the way back boards anyway: the van never leaves
# with its doctor outside.
const RETURN_GIVE_UP = 20.0
var _owner: WeakRef
var injuries:
	get:
		return _owner.get_ref() if _owner != null else null
	set(value):
		_owner = weakref(value)
var active: Dictionary = {}
var targets: Dictionary = {}
var budget = Budget.new()

func claimed(key: String) -> bool:
	for medic in active.values():
		if medic.key == key:
			return true
	return false

func _ground(pos: Vector3) -> Vector3:
	pos.y = injuries.game.stage.ground(pos)
	return pos

func _create(id: int, pos: Vector3) -> Dictionary:
	var avatar = Model.create(injuries.game.stage.outfit)
	injuries.game.add_child(avatar)
	avatar.position = pos
	var medic = {"id": id, "avatar": avatar, "helper": -1, "navigation_budget": budget, "key": "", "state": "exiting", "time": 0.0, "clock": 0.0, "moving": false}
	active[id] = medic
	return medic

# Try both doors. Never put the medic inside scenery or make them walk through
# the van. The door itself is outside the van's collision envelope.
func start(van: Dictionary, key: String) -> void:
	if active.has(int(van.id)) or claimed(key):
		return
	var patient: Vector3 = injuries.records[key].pos
	var side: Vector3 = van.node.basis.x
	# The passenger's door first: that is where the doctor sits.
	var seat = CarOccupants.passenger_seat(van.node)
	var preferred: float = seat.get("side", 1.0)
	for sign in [preferred, -preferred]:
		var door = _ground(van.node.position + side * sign * 1.85 - van.node.basis.z * 0.65)
		var exit_from = _ground(door - side * sign * 0.3)
		var probe = {"avatar": van.node}
		var ctx = Navigation.context(injuries.game, probe, exit_from, door, false)
		if not Navigation.clear(injuries.game, exit_from, door, ctx):
			continue
		var medic = _create(int(van.id), door)
		medic.door = door
		medic.exit_from = exit_from
		medic.key = key
		if not _plan_patient(medic, patient):
			_remove(int(van.id))
			continue
		medic.avatar.position = medic.exit_from
		van.state = "parked"
		van.drive_speed = 0.0
		van.treating = key
		return

func _plan_patient(medic: Dictionary, patient: Vector3) -> bool:
	var start: Vector3 = medic.avatar.position
	var toward = Navigation.flat(start - patient).normalized()
	var angle = atan2(toward.y, toward.x)
	for i in range(8):
		var a = angle + i * TAU / 8.0
		var goal = _ground(patient + Vector3(cos(a), 0, sin(a)) * 0.9)
		var ctx = Navigation.context(injuries.game, medic, start, goal, false)
		var route = Navigation.plan(injuries.game, start, goal, ctx)
		if not route.is_empty():
			medic.goal = goal
			medic.patient = patient
			medic.navigation = {"goal": goal, "route": route, "retry": 0.0}
			return true
	return false

func update(delta: float) -> void:
	if injuries == null:
		return
	budget.advance(delta)
	if not injuries.authority():
		_update_guest(delta)
		return
	for id in active.keys():
		var medic: Dictionary = active[id]
		var van = injuries._ambulance(id)
		if van.is_empty():
			_remove(id)
			continue
		# No route update (including a new knockdown) may release the van
		# while its doctor is outside.
		van.state = "parked"
		van.drive_speed = 0.0
		var before: Vector3 = medic.avatar.position
		_step(medic, van, delta)
		if active.has(id):
			medic.moving = Navigation.flat(before).distance_to(Navigation.flat(medic.avatar.position)) > 0.001
			medic.clock += delta
			Model.pose(medic, delta)
			_cabin(medic, van.node, true)

func _step(medic: Dictionary, van: Dictionary, delta: float) -> void:
	var record: Dictionary = injuries.records.get(medic.key, {})
	if medic.state in ["exiting", "walking", "treating"] and (record.is_empty() or record.phase != "lying"):
		_return(medic, van)
	match str(medic.state):
		"exiting":
			medic.time += delta
			if medic.time >= DOOR_SECONDS:
				medic.state = "walking"
		"walking":
			# A helper can move a casualty after the doctor has planned a route.
			if record.pos.distance_to(medic.get("patient", record.pos)) > 0.6:
				if not _plan_patient(medic, record.pos):
					_return(medic, van)
					return
			Navigation.move(injuries.game, medic, medic.goal, delta, false)
			_face(medic, record.pos)
			if Navigation.flat(medic.avatar.position).distance_to(Navigation.flat(medic.goal)) < 0.2 and _patient_distance(medic, record.pos) <= REACH:
				medic.state = "treating"
				medic.time = 0.0
				record.treat = 0.0
		"treating":
			if _patient_distance(medic, record.pos) > REACH:
				record.treat = 0.0
				_return(medic, van)
				return
			_face(medic, record.pos)
			record.treat += delta
			if float(record.treat) + 0.000001 >= injuries.TREAT_SECONDS:
				injuries._stand(medic.key, record)
				_next(medic, van, record.pos)
		"returning":
			medic.time += delta
			if medic.time >= RETURN_GIVE_UP:
				medic.avatar.position = medic.door
			Navigation.move(injuries.game, medic, medic.door, delta, false)
			_face(medic, medic.door)
			if Navigation.flat(medic.avatar.position).distance_to(Navigation.flat(medic.door)) < 0.2:
				medic.state = "entering"
				medic.time = 0.0
		"entering":
			medic.time += delta
			if medic.time >= DOOR_SECONDS:
				_remove(int(van.id))
				van.treating = ""
				injuries._retarget(van)

# Kneeling lowers the visual root. Treatment reach must use the grounded
# navigation position, otherwise a slope can cancel treatment on the next tick.
func _patient_distance(medic: Dictionary, patient: Vector3) -> float:
	return _ground(medic.avatar.position).distance_to(patient)

func _next(medic: Dictionary, van: Dictionary, origin: Vector3) -> void:
	medic.key = ""
	var choices: Array = []
	for key in injuries.records:
		var record: Dictionary = injuries.records[key]
		var distance: float = origin.distance_to(record.pos)
		if record.phase == "lying" and not record.get("play", false) and distance <= WALK_RADIUS and not claimed(key):
			choices.append({"key": key, "distance": distance})
	choices.sort_custom(func(a, b): return a.distance < b.distance)
	for candidate in choices:
		var record: Dictionary = injuries.records[candidate.key]
		if not _plan_patient(medic, record.pos):
			continue
		record.ambulance = van.id
		medic.key = candidate.key
		medic.state = "walking"
		van.treating = medic.key
		injuries._retarget_all()
		return
	_return(medic, van)

func _return(medic: Dictionary, van: Dictionary) -> void:
	medic.key = ""
	medic.state = "returning"
	medic.time = 0.0
	medic.erase("navigation")
	van.treating = ""

func _face(medic: Dictionary, pos: Vector3) -> void:
	var direction: Vector3 = pos - medic.avatar.position
	if Navigation.flat(direction).length() > 0.01:
		medic.avatar.rotation.y = atan2(-direction.x, -direction.z)

func _remove(id: int) -> void:
	if active.has(id):
		active[id].avatar.queue_free()
		active.erase(id)
		var car = _van_node(id)
		CarOccupants.passenger_aboard(car, true)
		CarOccupants.door_open(car, 0.0)

func _van_node(id: int) -> Node3D:
	var van = injuries._ambulance(id) if injuries != null else {}
	if van.get("node") is Node3D and is_instance_valid(van.node):
		return van.node
	return null

# How far out of the seat the doctor is: 0 seated, 1 standing at the door.
static func climb(medic: Dictionary) -> float:
	var t = clampf((float(medic.time) - OPEN_SECONDS) / CLIMB_SECONDS, 0.0, 1.0)
	match str(medic.state):
		"exiting":
			return t
		"entering":
			return 1.0 - t
	return 1.0

# The door, the seat and the doctor between them while getting out or in. The
# host also places the doctor; a guest gets the position from the snapshot.
func _cabin(medic: Dictionary, car: Node3D, place: bool) -> void:
	var stepping = medic.state in ["exiting", "entering"]
	var t = float(medic.time)
	var door = 0.0
	if stepping:
		door = clampf(t / OPEN_SECONDS, 0.0, 1.0) * (1.0 - clampf((t - OPEN_SECONDS - CLIMB_SECONDS) / (DOOR_SECONDS - OPEN_SECONDS - CLIMB_SECONDS), 0.0, 1.0))
	var u = climb(medic)
	# In the seat (before the climb out, after the climb in) the cabin's own
	# seated doctor shows; the walking one is hidden.
	var seated = stepping and u <= 0.0
	CarOccupants.passenger_aboard(car, seated)
	CarOccupants.door_open(car, door)
	var avatar: Node3D = medic.avatar
	avatar.visible = not seated
	var seat = CarOccupants.passenger_seat(car)
	if not stepping or seat.is_empty():
		avatar.scale = Vector3.ONE
		return
	var feet: Vector3 = car.global_transform * seat.feet
	var out: Vector3 = medic.door if medic.has("door") else _ground(car.global_transform * (seat.feet + Vector3(float(seat.side) * 1.4, 0, 0)))
	# Turn on the seat to face the door, slide to the sill with the legs out,
	# then step down and grow from the cabin's scale to full size.
	var turn = smoothstep(0.0, 0.3, u)
	var slide = smoothstep(0.15, 0.7, u)
	var drop = smoothstep(0.45, 1.0, u)
	var outward = Vector3(out.x - feet.x, 0, out.z - feet.z)
	var forward_yaw: float = car.global_rotation.y
	var door_yaw = atan2(-outward.x, -outward.z)
	avatar.scale = Vector3.ONE * lerpf(float(seat.scale), 1.0, smoothstep(0.3, 1.0, u))
	if place:
		var pos = feet.lerp(out, slide)
		pos.y = lerpf(feet.y, out.y, drop)
		avatar.position = pos
		avatar.rotation.y = lerp_angle(forward_yaw, door_yaw, turn)
	if u < 0.55:
		CharacterRig.pose(avatar, {"seat": CarOccupants.SEAT, "arms": "lap"})
	else:
		CharacterRig.pose(avatar, {"gait": 1, "time": float(medic.clock)})

func snapshot() -> Array:
	var result: Array = []
	for medic in active.values():
		var pos: Vector3 = medic.avatar.position
		result.append({"id": medic.id, "pos": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(pos.z, 0.01)], "yaw": snappedf(medic.avatar.rotation.y, 0.01), "state": medic.state, "moving": medic.moving, "clock": snappedf(medic.clock, 0.01), "time": snappedf(medic.time, 0.01)})
	return result

func apply_snapshot(entries: Array) -> void:
	# Snapshots may arrive before the first injury update.
	targets.clear()
	for entry in entries:
		if entry is Dictionary and entry.get("pos") is Array and entry.pos.size() == 3 and entry.has("id"):
			targets[int(entry.id)] = entry
	for id in active.keys():
		if not targets.has(id):
			_remove(id)

func _update_guest(delta: float) -> void:
	for id in targets:
		var entry: Dictionary = targets[id]
		var pos = Vector3(entry.pos[0], entry.pos[1], entry.pos[2])
		var medic: Dictionary = active[id] if active.has(id) else _create(id, pos)
		var weight = 1.0 - exp(-delta * 12.0)
		medic.avatar.position = medic.avatar.position.lerp(pos, weight)
		medic.avatar.rotation.y = lerp_angle(medic.avatar.rotation.y, float(entry.yaw), weight)
		medic.state = str(entry.state)
		medic.moving = bool(entry.get("moving", false))
		medic.clock = float(entry.get("clock", 0.0))
		medic.time = float(entry.get("time", 0.0))
		Model.pose(medic, delta)
		_cabin(medic, _van_node(id), false)
