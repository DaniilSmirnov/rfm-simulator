extends RefCounted
# Host-owned movement over sampled terrain. Nodes keep their gameplay state.
const Specials = preload("res://scripts/core/prop_specials.gd")
const Registry = preload("res://scripts/core/prop_registry.gd")
const REACH = 2.5
var game
var stage_id = 0
var records: Dictionary = {}
var grips: Dictionary = {}
var pending: Array = []

func refresh() -> void:
	if game.stage == null:
		return
	if stage_id != game.stage.get_instance_id():
		stage_id = game.stage.get_instance_id()
		records.clear()
		grips.clear()
		pending.clear()
	for item in game.packing.items():
		var key = "camp:%s:%s" % [item.kind, game.cargo.owner_of(item)]
		if item.kind == "flag":
			key += ":%d" % game.personal_flags[item.owner].find(item.node)
		_rekey(item.node, key)
		Registry.register(game.stage.solids, item.node, 25.0 if item.kind in ["grill", "cauldron"] else 8.0, false, key)
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
	Specials.refresh(game, records)
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
	if velocity.length() < (5.0 if r.anchored else 0.8):
		return false
	r.anchored = false
	r.changed = true
	r.velocity = (r.velocity + velocity * clampf(30.0 / r.mass, 0.08, 0.8)).limit_length(12.0)
	if r.mass < 300.0:
		r.spin = Vector3(velocity.z, 0, -velocity.x).limit_length(3.0)
	return true

func update(players: Dictionary, occupied: Dictionary, delta: float) -> Dictionary:
	refresh()
	if not game.room.is_authority():
		return occupied
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
		r.changed = true
	for r in records.values():
		if r.changed and not r.anchored:
			_move(r, delta)
	return occupied

func _eligible(id: String, p: Dictionary) -> bool:
	return p.get("tow", false) and not p.get("in_car", true) and not p.get("seated", false) and not p.get("airborne", false) and int(p.get("beers", 0)) < 30 and not game.injuries.is_down("player:" + id) and not game.cargo.held.has(id)

func _distance(r: Dictionary, pos: Vector3) -> float:
	var box: AABB = r.box
	var local: Vector3 = r.node.global_transform.affine_inverse() * (pos + Vector3.UP * 0.8)
	return (r.node.global_transform * local.clamp(box.position, box.end)).distance_to(pos + Vector3.UP * 0.8)

func _move(r: Dictionary, delta: float) -> void:
	if r.velocity.length_squared() < 0.00001 and r.spin.length_squared() < 0.00001:
		return
	if r.has("lamp"):
		Specials.move_lamp(game, r)
		return
	_unseat(r)
	var start = center(r)
	var step: Vector3 = r.velocity * minf(delta, 0.05)
	var radius = clampf(minf(r.box.size.x, r.box.size.z) * 0.45, 0.12, 1.2)
	var next = start + step
	var hit: Dictionary = game.stage.solids.hit(start, next, radius, true, Vector3.ZERO, r.node)
	if not hit.is_empty() or _corners_blocked(r, step) or not game.stage.rock_hit(start, next, radius).is_empty() or game.stage.obstacle_hit(start, next, radius, true, int(r.get("tree", -1))) >= 0:
		r.velocity = Vector3.ZERO
		next = start
	var rotation: Vector3 = r.node.global_rotation + r.spin * minf(delta, 0.05)
	var basis = Basis.from_euler(rotation)
	var bounds: AABB = Transform3D(basis, Vector3.ZERO) * r.box
	var floor_y: float = game.stage.solids.walking_floor(next, start.y)
	var origin = next - basis * r.box.get_center()
	origin.y = floor_y - bounds.position.y
	r.node.global_transform = Transform3D(basis, origin)
	r.velocity = r.velocity.move_toward(Vector3.ZERO, delta * 4.0)
	r.spin = r.spin.move_toward(Vector3.ZERO, delta * 3.0)
	if r.has("tree"): Specials.move_tree(game.stage, r)

func snapshot() -> Array:
	refresh()
	var result: Array = []
	for r in records.values():
		if r.changed and not r.has("lamp") and not r.has("tree"):
			result.append({"key": r.key, "pos": game.room.a(r.node.global_position), "rot": game.room.a(r.node.global_rotation), "anchored": r.anchored})
	return result

func apply_snapshot(data: Array) -> void:
	refresh()
	pending = data
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
		r.node.global_position = game.room.v(item.pos)
		r.node.global_rotation = game.room.v(item.rot)
		r.anchored = bool(item.get("anchored", false))
		r.changed = true
	pending = waiting

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

# Sweep the footprint too: a long table must not drag its far end through a wall.
func _corners_blocked(r: Dictionary, step: Vector3) -> bool:
	for x in [r.box.position.x, r.box.end.x]:
		for z in [r.box.position.z, r.box.end.z]:
			var point: Vector3 = r.node.global_transform * Vector3(x, r.box.get_center().y, z)
			if not game.stage.solids.hit(point, point + step, 0.05, true, Vector3.ZERO, r.node).is_empty():
				return true
	return false

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
