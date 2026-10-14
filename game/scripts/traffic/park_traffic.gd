extends RefCounted
# The cars of the convoy and the crews in the service parks. Before the stage
# opens every car stands in its bay in the park at the start. In turn, each one
# pulls out, drives under the arch and waits at the end of the road; when the
# timetable starts it (rally_crews.gd spawn_racer / spawn_course_car take it
# from here), it races. At the finish it carries on into the other park and
# backs into its bay there, so pass 2 starts from that park and finishes in
# the first one.
#
# The host drives the park cars; guests get the parked ones in the "parks"
# section and the moving ones' poses in the hot "park_movers" field. Cars in a
# park are not game.racers: those are the vehicles on the stage.
const Props = preload("res://scripts/core/props.gd")
const Motion = preload("res://scripts/cars/vehicle_motion.gd")
const SnapshotMotion = preload("res://scripts/net/snapshot_motion.gd")
const Parks = preload("res://scripts/traffic/service_parks.gd")
# Seconds before the stage opens (either pass) that the first car pulls up.
const PULL_LEAD = 25.0
const STEP = 1.0 / 30.0
const ACCEL = 2.5
const BRAKE = 3.5

var game
# Per park (0 at the start of the route, 1 at its end): key -> parked car node.
var parked: Array[Dictionary] = [{}, {}]
# Cars on the move in a park: {key, node, state (to_start, at_start, to_park),
# path, lengths, d, speed, motion, park_end}.
var movers: Array[Dictionary] = []
# Keys already called to the start line in the current pass.
var called: Dictionary = {}
var called_pass = 1
# Guests: smoothed poses of the host's moving park cars, by key.
var guest_motion: Dictionary = {}

func parks():
	return game.stage.parks if game.stage != null else null

func pass_now() -> int:
	return 2 if game.course.pass_index == 2 or game.course.phase == "intermission" else 1

func start_end() -> int:
	return 0 if pass_now() == 1 else 1

func finish_end() -> int:
	return 1 if game.course.pass_index == 1 else 0

# ---------------------------------------------------------------- keys

static func role_of(key: String) -> String:
	if key == "police_open":
		return "opening_police"
	if key == "police_close":
		return "closing_police"
	return "zero" if key.begins_with("zero") else "racer"

static func zero_of(key: String) -> int:
	return int(key.trim_prefix("zero")) if key.begins_with("zero") else 0

static func crew_of(key: String) -> int:
	return int(key.trim_prefix("crew")) if key.begins_with("crew") else -1

# The park key of a vehicle on the stage, "" for one without a bay (ambulance).
static func key_of(racer: Dictionary) -> String:
	match str(racer.get("role", "racer")):
		"opening_police": return "police_open"
		"closing_police": return "police_close"
		"zero": return "zero%d" % int(racer.get("zero_index", 0))
		"racer": return "crew%d" % (posmod(int(racer.id), 200) - 1)
	return ""

static func build_car(key: String) -> Node3D:
	if crew_of(key) >= 0:
		return Props.rally_car(Props.RallyCarModel.spawn_variant(crew_of(key)))
	return Props.course_car(role_of(key), zero_of(key))

# ---------------------------------------------------------------- parked cars

# A new day: every car in its bay at the start of the route.
func reset() -> void:
	called.clear()
	called_pass = 1
	for entry in movers:
		if is_instance_valid(entry.node):
			entry.node.queue_free()
	movers.clear()
	for index in range(2):
		for key in parked[index].keys():
			unpark(index, key)
	if parks() == null:
		return
	for key in Parks.KEYS:
		park(0, key)

func park(index: int, key: String, node: Node3D = null) -> void:
	if parked[index].has(key) and is_instance_valid(parked[index][key]):
		if node != null and node != parked[index][key]:
			node.queue_free()
		return
	# Parked cars belong to the stage and go with it; moving ones to the game.
	if node == null:
		node = build_car(key)
		game.stage.add_child(node)
	elif node.get_parent() != game.stage:
		node.reparent(game.stage)
	var pose: Transform3D = parks().slot_pose(index, key)
	node.position = pose.origin
	var motion = Motion.new()
	motion.suspension(node, game.stage, 0.0, pose.basis.get_euler().y)
	parked[index][key] = node

func unpark(index: int, key: String) -> void:
	var node = parked[index].get(key)
	parked[index].erase(key)
	if is_instance_valid(node):
		node.queue_free()

# Every car standing or moving in a park, for collisions with people and cars.
func car_positions() -> Array:
	var result: Array = []
	for index in range(2):
		for node in parked[index].values():
			if is_instance_valid(node):
				result.append(node.position)
	for entry in movers:
		if is_instance_valid(entry.node):
			result.append(entry.node.position)
	return result

# ---------------------------------------------------------------- the start

func mover(key: String) -> Dictionary:
	for entry in movers:
		if entry.key == key:
			return entry
	return {}

func line_busy() -> bool:
	for entry in movers:
		if entry.state in ["to_start", "at_start"]:
			return true
	return false

func next_key() -> String:
	if called_pass != pass_now():
		called_pass = pass_now()
		called.clear()
	for key in Parks.KEYS:
		if not called.has(key) and parked[start_end()].has(key):
			return key
	return ""

# Host, from the timetable: call the next car to the line when it is free and
# drive the cars in the parks.
func update(delta: float) -> void:
	if parks() == null:
		return
	var remaining = delta
	while remaining > 0.000001:
		var dt = minf(remaining, STEP)
		remaining -= dt
		if game.course.phase != "complete" and not line_busy() and (game.course.phase not in ["countdown", "intermission"] or game.course.remaining - (delta - remaining) <= PULL_LEAD):
			pull_up()
		for entry in movers.duplicate():
			step(entry, dt)

func pull_up() -> void:
	var key = next_key()
	if key == "":
		return
	var index = start_end()
	var node: Node3D = parked[index][key]
	parked[index].erase(key)
	called[key] = true
	node.reparent(game)
	movers.append(_entry(key, node, "to_start", parks().leave_path(index, key), 0.0))

func _entry(key: String, node: Node3D, state: String, path: Array, speed: float) -> Dictionary:
	var lengths: Array[float] = [0.0]
	for i in range(1, path.size()):
		lengths.append(lengths[-1] + Vector2(path[i].p.x - path[i - 1].p.x, path[i].p.z - path[i - 1].p.z).length())
	return {"key": key, "node": node, "state": state, "path": path, "lengths": lengths, "d": 0.0, "speed": speed, "motion": Motion.new(), "park_end": finish_end()}

# The node of the car the timetable starts now: the one waiting at the line
# (or still pulling up), else none (the caller builds one at the line). A car
# still parked is taken out of its bay so it does not appear twice.
func take(key: String) -> Node3D:
	if key == "":
		return null
	called[key] = true
	var waiting = mover(key)
	if not waiting.is_empty() and waiting.state in ["to_start", "at_start"]:
		movers.erase(waiting)
		return waiting.node
	for index in range(2):
		if parked[index].has(key):
			unpark(index, key)
	return null

# ---------------------------------------------------------------- the finish

# A car crossing the end of the road drives on into its bay; false for a car
# without one, which leaves the stage as before. The caller drops the racer.
func arrive(racer: Dictionary) -> bool:
	var key = key_of(racer)
	if parks() == null or not Parks.KEYS.has(key) or not mover(key).is_empty():
		return false
	var index = finish_end()
	if parked[index].has(key):
		return false
	var node: Node3D = racer.node
	var path = parks().arrive_path(index, key, node.position, game.race_direction(racer.s))
	var entry = _entry(key, node, "to_park", path, float(racer.get("drive_speed", Parks.CRUISE)))
	entry.park_end = index
	entry.motion = racer.motion
	movers.append(entry)
	return true

# Between the passes: every car that did not make it (stranded, recovered,
# still rolling in) is brought to the park at the end of the route, ready for
# pass 2. Cars already called to the line for pass 2 stay where they are.
func settle() -> void:
	var fresh = called_pass != 2
	if fresh:
		called_pass = 2
		called.clear()
	for racer in game.racers.duplicate():
		game.racers.erase(racer)
		var key = key_of(racer)
		if Parks.KEYS.has(key) and not parked[1].has(key) and not called.has(key) and mover(key).is_empty():
			park(1, key, racer.node)
		elif is_instance_valid(racer.node):
			racer.node.queue_free()
	for entry in movers.duplicate():
		if entry.state == "to_park" or fresh:
			movers.erase(entry)
			park(1, entry.key, entry.node)
	for key in Parks.KEYS:
		if not called.has(key) and mover(key).is_empty():
			park(1, key)
		if parked[0].has(key):
			unpark(0, key)

# ---------------------------------------------------------------- driving

func step(entry: Dictionary, delta: float) -> void:
	var node: Node3D = entry.node
	if not is_instance_valid(node):
		movers.erase(entry)
		return
	if entry.state == "at_start":
		return
	var path: Array = entry.path
	var lengths: Array = entry.lengths
	var total: float = lengths[-1]
	var d: float = entry.d
	var i = _index_at(lengths, d)
	var stop = _stop_after(path, lengths, i)
	var desired = minf(Parks.REVERSE if path[i + 1].reverse else Parks.CRUISE, sqrt(2.0 * BRAKE * maxf(0.0, stop - d)) + 0.3)
	if _blocked(node, node.position, path[mini(i + 12, path.size() - 1)].p):
		desired = 0.0
	var speed = float(entry.speed)
	speed = move_toward(speed, desired, delta * (BRAKE * 2.0 if desired < speed else ACCEL))
	entry.speed = speed
	d = minf(stop, d + speed * delta)
	if stop - d < 0.02 and stop < total:
		d = stop + 0.03 # turn round at the change of direction
	entry.d = d
	i = _index_at(lengths, d)
	var a: Vector3 = path[i].p
	var b: Vector3 = path[i + 1].p
	var t = clampf((d - lengths[i]) / maxf(0.001, lengths[i + 1] - lengths[i]), 0.0, 1.0)
	var at = a.lerp(b, t)
	var motion = (a - b) if path[i + 1].reverse else (b - a)
	var yaw = atan2(-motion.x, -motion.z) if Vector2(motion.x, motion.z).length() > 0.001 else node.rotation.y
	node.position.x = at.x
	node.position.z = at.z
	entry.motion.suspension(node, game.stage, delta, lerp_angle(node.rotation.y, yaw, minf(1.0, delta * 12.0)))
	if d >= total - 0.02:
		_arrived(entry)

func _arrived(entry: Dictionary) -> void:
	if entry.state == "to_start":
		var pose: Transform3D = parks().line_pose(start_end())
		entry.node.position.x = pose.origin.x
		entry.node.position.z = pose.origin.z
		entry.node.rotation.y = pose.basis.get_euler().y
		entry.state = "at_start"
		entry.speed = 0.0
	elif entry.state == "to_park":
		movers.erase(entry)
		park(int(entry.park_end), str(entry.key), entry.node)

# Last path point at or before distance d (the segment that holds it).
static func _index_at(lengths: Array, d: float) -> int:
	var low = 0
	var high = lengths.size() - 2
	while low < high:
		var middle = (low + high + 1) / 2
		if lengths[middle] <= d:
			low = middle
		else:
			high = middle - 1
	return maxi(0, low)

# Distance along the path of the next stop: a change of direction or the end.
static func _stop_after(path: Array, lengths: Array, index: int) -> float:
	var direction: bool = path[index + 1].reverse
	for i in range(index + 1, path.size()):
		if path[i].reverse != direction:
			return lengths[i - 1]
	return lengths[-1]

# Somebody (or something) in the way ahead: wait for them to step aside.
func _blocked(node: Node3D, from: Vector3, ahead: Vector3) -> bool:
	var others: Array = [game.car.position]
	if not game.in_car:
		others.append(game.walker)
	for peer in game.room.peers.values():
		if peer.state != null:
			others.append(game.room.v(peer.state.car))
			if not peer.state.in_car:
				others.append(game.room.v(peer.state.pos))
	for racer in game.racers:
		others.append(racer.node.position)
	for entry in movers:
		if entry.node != node:
			others.append(entry.node.position)
	var start = from + (ahead - from).normalized() * 1.2
	for point in others:
		if Motion.swept_hit(start, ahead, point, 1.9):
			return true
	return false

# ---------------------------------------------------------------- the way home

# The day ends when everybody sits in a car, their own or a friend's, standing
# in a service park, either one. A car left on the stage (a broken one whose
# owner came with a friend) does not hold the day up.
func everyone_home() -> bool:
	if parks() == null or not game.in_car or parks().park_at(game.player_position()) < 0:
		return false
	for peer in game.room.peers.values():
		if peer.state == null or not peer.state.in_car or parks().park_at(game.rides.seat_of(peer.state)) < 0:
			return false
	return true

# ---------------------------------------------------------------- sync

func snapshot() -> Dictionary:
	return {"parked": [parked[0].keys(), parked[1].keys()]}

func apply_snapshot(data: Dictionary) -> void:
	if parks() == null:
		return
	var lists: Array = data.get("parked", [[], []])
	for index in range(2):
		var wanted: Array = lists[index] if index < lists.size() else []
		for key in parked[index].keys():
			if not wanted.has(key):
				unpark(index, key)
		for key in wanted:
			if Parks.KEYS.has(str(key)):
				park(index, str(key))

# Hot: where the moving park cars are now.
func movers_snapshot() -> Array:
	var result: Array = []
	for entry in movers:
		result.append({"key": entry.key, "pos": game.room.a(entry.node.position), "rot": game.room.a(entry.node.rotation)})
	return result

func apply_movers(list: Array, sample_time: float) -> void:
	var present: Dictionary = {}
	for item in list:
		var key = str(item.get("key", ""))
		if not Parks.KEYS.has(key):
			continue
		present[key] = true
		var entry = mover(key)
		if entry.is_empty():
			var node = build_car(key)
			game.add_child(node)
			node.position = game.room.v(item.pos)
			entry = {"key": key, "node": node, "state": "guest"}
			movers.append(entry)
			guest_motion[key] = SnapshotMotion.new()
		guest_motion[key].push(sample_time, game.room.v(item.pos), game.room.v(item.rot))
	for entry in movers.duplicate():
		if not present.has(entry.key):
			movers.erase(entry)
			guest_motion.erase(entry.key)
			if is_instance_valid(entry.node):
				entry.node.queue_free()

func render_guest(clock: float, frozen: bool) -> void:
	for entry in movers:
		if guest_motion.has(entry.key) and is_instance_valid(entry.node):
			var pose = guest_motion[entry.key].render(clock, frozen)
			entry.node.position = pose.position
			entry.node.rotation = pose.rotation
