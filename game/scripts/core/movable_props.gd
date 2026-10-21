extends RefCounted
# Host-owned rigid-body motion. Nodes keep their gameplay state.
const Specials = preload("res://scripts/core/prop_specials.gd")
const Registry = preload("res://scripts/core/prop_registry.gd")
const REACH = 2.5
# Only a car tips furniture over; a walker, running or jumping, just slides it.
const TIP_SECONDS = 1.0
# The campfire is fixed in place; the cauldron stand straddles it.
const FIXED_KINDS = ["firewood"]
const HEARTH_KINDS = ["firewood", "cauldron"]
# How far off the campfire a resting cauldron still counts as mounted on it.
const HEARTH_REACH = 0.55
const Body = preload("res://scripts/core/prop_body.gd")
const Motion = preload("res://scripts/net/snapshot_motion.gd")
var game
var stage_id = 0
var records: Dictionary = {}
var grips: Dictionary = {}
var pending: Array = []
var _sample_time = -INF
# How far behind the host's snapshot times they arrive here: the least recent
# delay, so uneven arrival never makes a prop speed up and slow down.
var _lag = INF
# How much later than that the latest snapshots came: props are drawn this
# much further behind so a late one never leaves them standing.
var _late = 0.0
var _behind = 0.0
var _drawn_at = -INF

func refresh() -> void:
	if game.stage == null:
		return
	if stage_id != game.stage.get_instance_id():
		stage_id = game.stage.get_instance_id()
		records.clear()
		grips.clear()
		pending.clear()
	var hearth: Array = []
	for item in game.packing.items():
		var key = "camp:%s:%s" % [item.kind, game.cargo.owner_of(item)]
		if item.kind == "flag":
			key += ":%d" % game.personal_flags[item.owner].find(item.node)
		_rekey(item.node, key)
		var fixed: bool = item.kind in FIXED_KINDS
		if fixed: item.node.set_meta("prop_fixed", true)
		Registry.register(game.stage.solids, item.node, 25.0 if item.kind in ["grill", "cauldron"] else 8.0, fixed, key)
		if item.kind in HEARTH_KINDS: hearth.append(item.node)
	game.stage.solids.movables.assign(game.stage.solids.movables.filter(func(r): return is_instance_valid(r.node)))
	for record in game.stage.solids.movables:
		if not is_instance_valid(record.node):
			continue
		if not records.has(record.key) or records[record.key].node != record.node:
			var state = record.duplicate()
			state.velocity = Vector3.ZERO
			state.spin = Vector3.ZERO
			state.changed = false
			records[record.key] = state
			state.body = Body.create(state, game.stage.solids, game)
	_share_hearth(hearth)
	Specials.refresh(game, records)
	for r in records.values():
		if r.has("tree") and not r.has("body"):
			r.body = Body.create(r, game.stage.solids, game)
	var removed = false
	for key in records.keys():
		if not is_instance_valid(records[key].node) or records[key].node.is_queued_for_deletion():
			records.erase(key)
			removed = true
	if removed: game.stage.solids.index()

func center(r: Dictionary) -> Vector3:
	return r.node.global_transform * r.box.get_center()

func nearest(pos: Vector3) -> String:
	var best = REACH
	var key = ""
	for r in records.values():
		if not is_instance_valid(r.node) or r.anchored:
			continue
		var distance = _distance(r, pos)
		if distance < best and game.stage.solids.hit(pos + Vector3.UP * 0.8, center(r), 0.04, true, Vector3.ZERO, r.node).is_empty():
			best = distance
			key = r.key
	return key

func nearby() -> bool:
	return nearest(game.walker) != ""

func knock(key: String, velocity: Vector3) -> bool:
	if not game.room.is_authority() or not records.has(key):
		return false
	var r: Dictionary = records[key]
	if r.node.get_meta("prop_fixed", false) or velocity.length() < (5.0 if r.anchored else 0.8):
		return false
	r.anchored = false
	r.node.set_meta("prop_anchored", false)
	r.changed = true
	if r.has("body"): r.body.allow_tip(TIP_SECONDS)
	r.velocity = (r.velocity + velocity * clampf(30.0 / r.mass, 0.08, 0.8)).limit_length(12.0)
	if r.mass < 300.0:
		r.spin = Vector3(velocity.z, 0, -velocity.x).limit_length(3.0)
	_move(r, 0)
	return true

func update(players: Dictionary, occupied: Dictionary, delta: float) -> Dictionary:
	refresh()
	if not game.room.is_authority():
		return occupied
	for r in records.values():
		if r.has("body"):
			r.body.pull_velocity = Vector3.ZERO
			r.body.righting = false
	var used: Dictionary = {}
	for id in grips.keys():
		if not players.has(id) or occupied.has(str(id)) or not _eligible(str(id), players[id]):
			grips.erase(id)
		else:
			used[grips[id]] = id
	for id in players:
		var p: Dictionary = players[id]
		if occupied.has(str(id)) or not _eligible(str(id), p):
			grips.erase(id)
			continue
		var pos: Vector3 = game.room.v(p.pos)
		var key: String = grips.get(id, nearest(pos))
		if not records.has(key) or (used.has(key) and used[key] != id):
			grips.erase(id)
			continue
		var r: Dictionary = records[key]
		if _distance(r, pos) > REACH + 1.0:
			grips.erase(id)
			continue
		grips[id] = key
		used[key] = id
		occupied[str(id)] = true
		var offset: Vector3 = pos - center(r)
		offset.y = 0
		var slack = maxf(0.9, minf(r.box.size.x, r.box.size.z) * 0.5 + 0.4)
		var speed = clampf(35.0 / r.mass, 0.25, 3.0)
		r.velocity = offset.normalized() * minf(speed, maxf(0.0, offset.length() - slack) / maxf(delta, 0.001))
		r.spin = Vector3.ZERO
		if r.has("body"):
			_unseat(r)
			r.body.wake()
			r.body.pull_velocity = r.velocity
			r.body.righting = true
			r.velocity = Vector3.ZERO
		r.changed = true
	_push_walkers(players, occupied, delta)
	_return_to_hearth()
	for r in records.values():
		if r.changed and not r.anchored:
			_move(r, delta)
	return occupied

# Walkers use swept collision rather than native bodies; transmit the same contact.
func _push_walkers(players: Dictionary, occupied: Dictionary, delta: float) -> void:
	for id in players:
		var p: Dictionary = players[id]
		if occupied.has(str(id)) or p.get("in_car", true) or p.get("seated", false) or p.get("airborne", false) or int(p.get("beers", 0)) >= 30: continue
		var intent: Vector3 = game.room.v(p.get("push", [0, 0, 0]))
		if intent.length_squared() < 0.01 or game.injuries.is_down("player:" + str(id)): continue
		var pos: Vector3 = game.room.v(p.pos)
		var hit: Dictionary = game.stage.solids.hit(pos, pos + intent * game.WALK_SPEED * minf(delta, 0.05), 0.3)
		var r: Dictionary = records.get(hit.get("prop", ""), {})
		if r.is_empty() or r.anchored or not r.has("body"): continue
		r.body.wake()
		r.body.apply_central_impulse(intent.limit_length(1.0) * minf(350.0, r.mass * 8.0) * delta)

# A cauldron knocked off its campfire glides back over the fire once it comes
# to rest. One a player drags or sets down elsewhere stays where it is.
func _return_to_hearth() -> void:
	var fire: Dictionary = {}
	for r in records.values():
		if r.key.begins_with("camp:firewood:") and is_instance_valid(r.node): fire = r
	for r in records.values():
		if not r.key.begins_with("camp:cauldron:") or not r.has("body"): continue
		var body = r.body
		if fire.is_empty() or grips.values().has(r.key):
			body.home = null
			continue
		if not body.sleeping or body.returning(): continue
		var offset: Vector3 = r.node.global_position - fire.node.global_position
		offset.y = 0
		if offset.length() < HEARTH_REACH and r.node.global_basis.y.normalized().angle_to(Vector3.UP) < Body.GUARD_ANGLE:
			body.home = r.node.global_transform
		elif body.home != null:
			body.return_to(body.home)

# Contacts between a fixed campfire and the cauldron mounted over it would
# shove the pot (or, before, flip the fire); the stand straddles the logs.
func _share_hearth(nodes: Array) -> void:
	var bodies: Array = []
	for r in records.values():
		if r.has("body") and r.node in nodes: bodies.append(r.body)
	for a in bodies:
		for b in bodies:
			if a != b and not a.get_collision_exceptions().has(b):
				a.add_collision_exception_with(b)

func _eligible(id: String, p: Dictionary) -> bool:
	return p.get("tow", false) and not p.get("in_car", true) and not p.get("seated", false) and not p.get("airborne", false) and int(p.get("beers", 0)) < 30 and not game.injuries.is_down("player:" + id) and not game.cargo.held.has(id)

func _distance(r: Dictionary, pos: Vector3) -> float:
	var box: AABB = r.box
	var local: Vector3 = r.node.global_transform.affine_inverse() * (pos + Vector3.UP * 0.8)
	return (r.node.global_transform * local.clamp(box.position, box.end)).distance_to(pos + Vector3.UP * 0.8)

func _move(r: Dictionary, delta: float) -> void:
	if r.velocity.length_squared() < 0.00001 and r.spin.length_squared() < 0.00001 and not r.get("settling", false):
		return
	if r.has("lamp"):
		Specials.move_lamp(game, r)
		return
	_unseat(r)
	var body: RigidBody3D = r.body
	if r.velocity.length_squared() > 0.00001 or r.spin.length_squared() > 0.00001:
		body.wake()
		body.apply_central_impulse(r.velocity * r.mass)
		body.apply_torque_impulse(r.spin * r.mass * 0.15)
		r.velocity = Vector3.ZERO
		r.spin = Vector3.ZERO

func snapshot() -> Array:
	refresh()
	var result: Array = []
	for r in records.values():
		if r.changed and not r.has("lamp"):
			var rotation: Vector3 = r.node.global_rotation
			var item = {"key": r.key, "pos": game.room.a(r.node.global_position), "rot": [rotation.x, rotation.y, rotation.z], "anchored": r.anchored}
			# A flying prop's velocity lets guests draw it where it is now.
			if r.has("body") and not r.has("tree") and not r.body.freeze and not r.body.sleeping and r.body.linear_velocity.length_squared() > 0.01:
				item.velocity = game.room.a(r.body.linear_velocity)
			result.append(item)
	return result

# `sample_time`: the host's time of the snapshot (server clock); -1 for world
# collision ahead of a replay, -INF unknown (drawn on arrival).
func apply_snapshot(data: Array, sample_time: float = -INF) -> void:
	refresh()
	pending = data
	_sample_time = sample_time
	apply_pending()

# Camp providers may create nodes after collision snapshots arrive.
func apply_pending() -> void:
	refresh()
	var waiting: Array = []
	for item in pending:
		if not records.has(str(item.get("key", ""))):
			waiting.append(item)
			continue
		var r: Dictionary = records[str(item.key)]
		if r.node.global_position.distance_to(game.room.v(item.pos)) > 0.02: _unseat(r)
		if not r.node.global_position.is_equal_approx(game.room.v(item.pos)) or not r.node.global_rotation.is_equal_approx(game.room.v(item.rot)):
			game.stage.solids.indexed_obstacle_count = -1
		if r.has("body"):
			r.body.freeze = true
			r.body.global_transform = Transform3D(Basis.from_euler(game.room.v(item.rot)), game.room.v(item.pos))
		_show(r, game.room.v(item.pos), game.room.v(item.rot), game.room.v(item.velocity) if item.has("velocity") else null)
		r.node.set_meta("prop_dynamic", true)
		r.anchored = bool(item.get("anchored", false))
		r.node.set_meta("prop_anchored", r.anchored)
		r.changed = true
		if r.has("tree"): Specials.move_tree(game.stage, r)
	pending = waiting

# A guest's collision body takes the host's pose at once; the visible prop
# follows the snapshots a short delay behind (SnapshotMotion) instead of jumping
# to each one (up to 10 a second on the server path).
func _show(r: Dictionary, pos: Vector3, rot: Vector3, velocity = null) -> void:
	var clock: float = game.room.transport.view_clock if game.room.transport != null else -INF
	if r.has("tree") or clock == -INF:
		r.node.global_position = pos
		r.node.global_rotation = rot
		r.erase("motion")
		return
	if _sample_time < 0.0 and _sample_time > -INF:
		# World collision ahead of a replay (-1): the visible pose follows with
		# the same snapshot and its time.
		return
	if not r.has("motion"):
		if r.node.global_position.is_equal_approx(pos) and r.node.global_rotation.is_equal_approx(rot):
			return
		r.motion = Motion.new()
		r.motion.hold = true
		# With the host's velocity the prop is drawn where it is now, falling
		# while ahead; new snapshots fade their difference out (as for cars).
		r.motion.predictive = velocity is Vector3
		r.motion.gravity = 9.8 if r.motion.predictive else 0.0
		var seed_time = (_sample_time if _sample_time >= 0.0 else clock) - r.motion.average_interval
		r.motion.push(seed_time, r.node.global_position, r.node.global_rotation, false, Vector3.ZERO)
		if r.motion.predictive: r.motion.render(seed_time)
	var newest: Dictionary = r.motion.latest()
	if newest.position.is_equal_approx(pos) and newest.rotation.is_equal_approx(rot):
		return
	r.shown_at = clock
	if r.motion.predictive:
		var stamp = _sample_time if _sample_time >= 0.0 else clock
		r.motion.push(maxf(stamp, float(newest.time) + 0.001), pos, rot, false, velocity if velocity is Vector3 else Vector3.ZERO)
		return
	var at = clock
	if _sample_time >= 0.0:
		var lag = clock - _sample_time
		# A step down shortens one interval; spread over several snapshots.
		_lag = lag if _lag == INF else (maxf(lag, _lag - 0.005) if lag < _lag else lerpf(_lag, lag, 0.02))
		at = minf(clock, _sample_time + _lag)
		_late = maxf(clock - at + 0.02, _late * 0.99)
	r.motion.push(maxf(at, float(newest.time) + 0.001), pos, rot)

# Every frame on a guest: moves each prop still catching up with its snapshots.
func render_guest() -> void:
	var clock: float = game.room.transport.view_clock if game.room.transport != null else -INF
	# The drawing delay changes at 10 % of the clock's pace: a sudden step held
	# every prop still for a frame (SnapshotMotion never goes back).
	if _drawn_at > -INF:
		_behind = move_toward(_behind, minf(_late, 0.25), clampf(clock - _drawn_at, 0.0, 0.1) * 0.1)
	_drawn_at = clock
	for r in records.values():
		if not r.has("motion") or not is_instance_valid(r.node):
			continue
		var pose: Dictionary = r.motion.render(clock if r.motion.predictive else clock - _behind)
		if r.motion.predictive:
			pose.position.y = maxf(pose.position.y, minf(game.stage.ground(pose.position), r.motion.latest().position.y))
		r.node.global_position = pose.position
		r.node.global_rotation = pose.rotation
		# A second after the last snapshot the prop lies exactly where the host
		# left it, whatever the clocks did meanwhile.
		if clock - float(r.get("shown_at", clock)) > 1.0:
			r.node.global_position = r.motion.latest().position
			r.node.global_rotation = r.motion.latest().rotation
			r.erase("motion")

func solid_hit(contact: Dictionary, velocity: Vector3) -> void:
	refresh()
	if contact.get("prop", "") != "":
		knock(contact.prop, velocity)
		return
	if contact.get("kind", "") != "lamp" or velocity.length() <= 5:
		return
	if game.room.is_guest():
		game.lamp_requests[int(contact.id)] = velocity
	else:
		game.stage.solids.knock_lamp(int(contact.id), velocity)

func _unseat(r: Dictionary) -> void:
	if game.seated and game.personal_chairs.get(game.chair_owner()) == r.node:
		game.stand_up()

func _rekey(node: Node3D, key: String) -> void:
	var old = str(node.get_meta("prop_key", key))
	if old == key: return
	node.set_meta("prop_key", key)
	for r in game.stage.solids.movables:
		if r.node == node: r.key = key
	for obstacle in game.stage.solids.obstacles:
		if is_instance_valid(obstacle.body) and node.is_ancestor_of(obstacle.body): obstacle.prop = key
	if records.has(old) and records[old].node == node:
		var r: Dictionary = records[old]
		records.erase(old)
		r.key = key
		records[key] = r
	for id in grips:
		if grips[id] == old: grips[id] = key
