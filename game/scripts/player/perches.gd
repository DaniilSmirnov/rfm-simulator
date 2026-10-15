extends RefCounted
# Everything a walker can climb onto besides the ground and authored floors:
# cars, camp tables and chairs, people lying on the ground, solid boxes
# (stage_solids.gd) and rocks. One rule for all of them: a top the feet can
# reach is a floor, a higher one is a wall.
#   walking: a top up to STEP_UP above the feet is stepped onto
#   rising in a jump: only a top already below the feet
#   coming down: a top up to LEDGE above the feet (knees up, pulled onto it)
# A jump lifts the feet JUMP_SPEED² / 2g ≈ 0.84 m, so with LEDGE the highest
# top reachable from the ground is ≈ 1.2 m: a car bonnet, a table, a garden
# wall, and from the bonnet the roof; a van or a house stays a wall.
#
# Objects join by mark(node): the shape is read from the node's own meshes
# into a height field (one per mesh set, shared by identical cars), so a new
# kind of object needs no shape of its own. Solid ones (cars) also block a
# walker below their top; the others (furniture, a lying person) are walked
# through on the ground as before and only carry someone who lands on them.
#
# A walker standing on a node moves with it (a driven car, a racer); the
# room state names the node (`stand`, a key every client resolves to its own
# copy) and the feet in its frame (`stand_at`), so everybody sees the person
# on the car rather than a lagging position beside it.
const GROUP = "perch"
const CELL = 0.1
const STEP_UP = 0.25
const LEDGE = 0.35
const FOOT_RADIUS = 0.12
const BODY_RADIUS = 0.3
const BODY_HEIGHT = 1.8
const REACH = 3.0
# A person whose feet are this far above a car's base rides on it: that car
# does not run them over, block on them or knock them down.
const RIDE_CLEARANCE = 0.75
const EMPTY = -1000000.0

static var _fields: Dictionary = {}

var game
# Gathered for this frame near the walker: {"frame", "inverse", "field" |
# "box" | "disc", "solid", "node"}.
var nearby: Array = []
# Where the walker stands: {"node", "key", "local", "world"}; empty on the
# ground. Kept through a jump so a leap on a moving car stays with it.
var stand: Dictionary = {}
# The perch entry under the feet after the last support() query.
var supporting: Dictionary = {}

static func mark(node: Node3D, solid: bool = true) -> Node3D:
	node.add_to_group(GROUP)
	node.set_meta("perch_solid", solid)
	return node

static func unmark(node: Node3D) -> void:
	node.remove_from_group(GROUP)

# ---------------------------------------------------------------- shapes

# The node's meshes as a grid of tops in `frame` (the node itself when it
# stands upright; a level frame at the node for one lying on its side).
static func field(node: Node3D, frame: Transform3D) -> Dictionary:
	var meshes: Array = []
	var signature = PackedStringArray()
	var to_frame = frame.affine_inverse()
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_node: MeshInstance3D = child
		if mesh_node.mesh == null or mesh_node.get_meta("perch_ignore", false) or not mesh_node.is_visible_in_tree():
			continue
		var pose = to_frame * mesh_node.global_transform
		meshes.append([mesh_node.mesh, pose])
		# Where each mesh sits, not how it is turned: a rolling wheel or an open
		# lid keeps the car's field, so every car of a model shares one.
		signature.append("%d:%s" % [mesh_node.mesh.get_instance_id(), str(pose.origin.snapped(Vector3.ONE * 0.01))])
	signature.sort()
	var key = ",".join(signature)
	if not _fields.has(key):
		_fields[key] = _rasterize(meshes)
	return _fields[key]

static func _rasterize(meshes: Array) -> Dictionary:
	var triangles = PackedVector3Array()
	for item in meshes:
		var mesh: Mesh = item[0]
		var pose: Transform3D = item[1]
		for surface in range(mesh.get_surface_count()):
			if mesh is ArrayMesh and mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arrays = mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices = arrays[Mesh.ARRAY_INDEX]
			var count = indices.size() if indices != null and indices.size() > 0 else vertices.size()
			for i in range(count - count % 3):
				triangles.append(pose * vertices[indices[i] if indices != null and indices.size() > 0 else i])
	if triangles.is_empty():
		return {}
	var low = Vector2(INF, INF)
	var high = Vector2(-INF, -INF)
	for p in triangles:
		low = low.min(Vector2(p.x, p.z))
		high = high.max(Vector2(p.x, p.z))
	var origin = low - Vector2.ONE * CELL
	var size = Vector2i(ceili((high.x - origin.x) / CELL) + 2, ceili((high.y - origin.y) / CELL) + 2)
	var raw = PackedFloat32Array()
	raw.resize(size.x * size.y)
	raw.fill(EMPTY)
	for t in range(0, triangles.size(), 3):
		_triangle(raw, size, origin, triangles[t], triangles[t + 1], triangles[t + 2])
	var radius = maxf(maxf(origin.length(), (origin + Vector2(size) * CELL).length()), maxf(Vector2(origin.x + size.x * CELL, origin.y).length(), Vector2(origin.x, origin.y + size.y * CELL).length()))
	return {"origin": origin, "size": size, "raw": raw, "tops": _level(_open(raw, size), size), "radius": radius}

# Highest point of the triangle over every cell centre it covers, and at its
# corners (thin parts smaller than a cell).
static func _triangle(raw: PackedFloat32Array, size: Vector2i, origin: Vector2, a: Vector3, b: Vector3, c: Vector3) -> void:
	for p in [a, b, c]:
		var cell = Vector2i(floori((p.x - origin.x) / CELL), floori((p.z - origin.y) / CELL))
		var i = cell.y * size.x + cell.x
		raw[i] = maxf(raw[i], p.y)
	var denominator = (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
	if absf(denominator) < 0.000001:
		return
	var x0 = maxi(0, floori((minf(a.x, minf(b.x, c.x)) - origin.x) / CELL))
	var x1 = mini(size.x - 1, floori((maxf(a.x, maxf(b.x, c.x)) - origin.x) / CELL))
	var z0 = maxi(0, floori((minf(a.z, minf(b.z, c.z)) - origin.y) / CELL))
	var z1 = mini(size.y - 1, floori((maxf(a.z, maxf(b.z, c.z)) - origin.y) / CELL))
	for z in range(z0, z1 + 1):
		var pz = origin.y + (z + 0.5) * CELL
		for x in range(x0, x1 + 1):
			var px = origin.x + (x + 0.5) * CELL
			var u = ((b.z - c.z) * (px - c.x) + (c.x - b.x) * (pz - c.z)) / denominator
			var v = ((c.z - a.z) * (px - c.x) + (a.x - c.x) * (pz - c.z)) / denominator
			if u < -0.001 or v < -0.001 or u + v > 1.001:
				continue
			var i = z * size.x + x
			raw[i] = maxf(raw[i], a.y * u + b.y * v + c.y * (1.0 - u - v))

# Tops narrower than three cells (a bottle on a table, a chair back, a
# mirror) cannot be stood on: a morphological opening keeps only surfaces.
static func _open(raw: PackedFloat32Array, size: Vector2i) -> PackedFloat32Array:
	var eroded = _filter(raw, size, true)
	return _filter(eroded, size, false)

# Nor slopes steeper than 45° (glass, a car's flank): a cell differing from a
# neighbour by more than a cell's width is no floor, only a wall.
static func _level(tops: PackedFloat32Array, size: Vector2i) -> PackedFloat32Array:
	var out = tops.duplicate()
	for z in range(size.y):
		for x in range(size.x):
			var h = tops[z * size.x + x]
			if h <= EMPTY * 0.5:
				continue
			for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n = Vector2i(x, z) + offset
				if n.x < 0 or n.y < 0 or n.x >= size.x or n.y >= size.y:
					continue
				var other = tops[n.y * size.x + n.x]
				if other > EMPTY * 0.5 and absf(other - h) > CELL * 1.05:
					out[z * size.x + x] = EMPTY
					break
	return out

static func _filter(source: PackedFloat32Array, size: Vector2i, minimum: bool) -> PackedFloat32Array:
	var out = PackedFloat32Array()
	out.resize(source.size())
	for z in range(size.y):
		for x in range(size.x):
			var value = INF if minimum else EMPTY
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var nx = x + dx
					var nz = z + dz
					var h = source[nz * size.x + nx] if nx >= 0 and nz >= 0 and nx < size.x and nz < size.y else EMPTY
					value = minf(value, h) if minimum else maxf(value, h)
			out[z * size.x + x] = value
	return out

# ---------------------------------------------------------------- gathering

func _pose(node: Node3D) -> Transform3D:
	return game.global_transform.affine_inverse() * node.global_transform

var _gathered_frame = -1
var _gathered_at = Vector3.INF

# Gathered again unless this frame already did it close by.
func near(center: Vector3) -> void:
	if _gathered_frame != Engine.get_process_frames() or _gathered_at.distance_to(center) > 0.5:
		gather(center)

# Everything within reach of `center`, once per frame (walk() substeps reuse it).
func gather(center: Vector3) -> void:
	nearby.clear()
	_gathered_frame = Engine.get_process_frames()
	_gathered_at = center
	var flat = Vector2(center.x, center.z)
	for node in game.get_tree().get_nodes_in_group(GROUP):
		if not node is Node3D or not node.is_visible_in_tree():
			continue
		_add_node(node, flat, bool(node.get_meta("perch_solid", true)))
	for avatar in game.injuries.lying_avatars():
		_add_node(avatar, flat, false)
	var stage = game.stage
	for rock in stage.rocks_in_bounds(flat - Vector2.ONE * REACH, flat + Vector2.ONE * REACH):
		nearby.append({"frame": Transform3D(Basis.IDENTITY, rock.pos), "disc": float(rock.radius), "top": float(rock.height), "solid": true})
	var solids = stage.solids
	if not solids.obstacles.is_empty():
		for id in solids.candidates(center, center, REACH):
			var object: Dictionary = solids.obstacles[id]
			if not is_instance_valid(object.body): continue
			if object.get("movable", false):
				var pose: Transform3D = solids.relative_pose(object.body)
				nearby.append({"frame": pose, "inverse": pose.affine_inverse(), "box": object.half, "solid": true})
				continue
			if object.body is RigidBody3D:
				_add_node(object.body, flat, true)
				continue
			nearby.append({"frame": object.collision_pose, "inverse": object.collision_inverse, "box": object.half, "solid": true})

# Upright objects are measured once (their meshes do not change shape; the
# wheels turn below the body); one lying down again whenever it is moved.
func _cached_field(node: Node3D, pose: Transform3D, frame: Transform3D) -> Dictionary:
	var lying = frame != pose
	if node.has_meta("perch_field") and node.get_meta("perch_lying") == lying and (not lying or _same_pose(node.get_meta("perch_pose"), pose)):
		return node.get_meta("perch_field")
	var shape = field(node, game.global_transform * frame)
	node.set_meta("perch_field", shape)
	node.set_meta("perch_pose", pose)
	node.set_meta("perch_lying", lying)
	return shape

static func _same_pose(a: Transform3D, b: Transform3D) -> bool:
	return a.origin.distance_to(b.origin) < 0.02 and a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion()) < 0.03

func _add_node(node: Node3D, flat: Vector2, solid: bool) -> void:
	var pose = _pose(node)
	if Vector2(pose.origin.x, pose.origin.z).distance_to(flat) > REACH + 6.0:
		return
	# An upright object keeps its height field in its own frame (cars tilt
	# with it); one on its side is measured in a level frame where it lies.
	var frame = pose
	if pose.basis.y.normalized().dot(Vector3.UP) < 0.8:
		frame = Transform3D(Basis(Vector3.UP, pose.basis.get_euler().y), pose.origin)
	var shape = _cached_field(node, pose, frame)
	if shape.is_empty() or Vector2(pose.origin.x, pose.origin.z).distance_to(flat) > REACH + float(shape.radius):
		return
	nearby.append({"frame": frame, "inverse": frame.affine_inverse(), "field": shape, "solid": solid, "node": node})

# ---------------------------------------------------------------- queries

# How far above the feet a top may be in the walker's state.
func allowance() -> float:
	if game.jump_height <= 0.001 and game.jump_velocity <= 0.0:
		return STEP_UP
	return LEDGE if game.jump_velocity <= 0.0 else 0.0

# Tops of `entry` within `radius` of p as world heights: `raw` cells for
# walls, opened ones for floors.
func _tops(entry: Dictionary, p: Vector3, radius: float, raw: bool) -> PackedFloat32Array:
	var result = PackedFloat32Array()
	var inverse: Transform3D = entry.get("inverse", Transform3D.IDENTITY)
	if entry.has("disc"):
		var centre: Vector3 = entry.frame.origin
		if Vector2(p.x - centre.x, p.z - centre.z).length() <= float(entry.disc) + radius * 0.5:
			result.append(centre.y + float(entry.top))
		return result
	var local = inverse * p
	if entry.has("box"):
		var half: Vector3 = entry.box
		if absf(local.x) <= half.x + radius * 0.5 and absf(local.z) <= half.z + radius * 0.5:
			result.append((entry.frame * Vector3(clampf(local.x, -half.x, half.x), half.y, clampf(local.z, -half.z, half.z))).y)
		return result
	var shape: Dictionary = entry.field
	var cells: PackedFloat32Array = shape.raw if raw else shape.tops
	var size: Vector2i = shape.size
	var origin: Vector2 = shape.origin
	var x0 = maxi(0, floori((local.x - radius - origin.x) / CELL))
	var x1 = mini(size.x - 1, floori((local.x + radius - origin.x) / CELL))
	var z0 = maxi(0, floori((local.z - radius - origin.y) / CELL))
	var z1 = mini(size.y - 1, floori((local.z + radius - origin.y) / CELL))
	var reach = (radius + CELL * 0.5) * (radius + CELL * 0.5)
	for z in range(z0, z1 + 1):
		var cz = origin.y + (z + 0.5) * CELL
		for x in range(x0, x1 + 1):
			var h = cells[z * size.x + x]
			var cx = origin.x + (x + 0.5) * CELL
			if h <= EMPTY * 0.5 or (cx - local.x) * (cx - local.x) + (cz - local.z) * (cz - local.z) > reach:
				continue
			result.append((entry.frame * Vector3(cx, h, cz)).y)
	return result

# The highest top under the feet at p not above `limit`, or -INF.
func support(p: Vector3, limit: float) -> float:
	var best = -INF
	supporting = {}
	for entry in nearby:
		for h in _tops(entry, p, FOOT_RADIUS, false):
			if h <= limit and h > best:
				best = h
				supporting = entry
	return best

# A solid object's top higher than `limit` stands in the body's way at `end`
# (moving out of one the walker is already inside is allowed). Objects whose
# base is above the head (a car on a bridge overhead) are not in the way.
func blocked(start: Vector3, end: Vector3, limit: float) -> bool:
	for entry in nearby:
		if not entry.solid or not entry.has("field") or entry.frame.origin.y > start.y + BODY_HEIGHT:
			continue
		if _above(entry, end, limit):
			var centre: Vector3 = entry.frame.origin
			var leaving = Vector2(end.x - centre.x, end.z - centre.z).length() > Vector2(start.x - centre.x, start.z - centre.z).length()
			if not (leaving and _above(entry, start, limit)):
				return true
	return false

func _above(entry: Dictionary, p: Vector3, limit: float) -> bool:
	for h in _tops(entry, p, BODY_RADIUS, true):
		if h > limit:
			return true
	return false

# ---------------------------------------------------------------- riding

# Before walking: a walker on a moving perch moves with it.
func carry() -> void:
	if stand.is_empty():
		return
	var node = stand.node
	if not is_instance_valid(node) or not node.is_inside_tree() or game.walker.distance_to(stand.world) > 0.001:
		stand = {}
		return
	game.walker = _pose(node) * stand.local
	stand.world = game.walker

# After walking: remember the perch under the feet (or keep the one jumped
# from while in the air).
func settle() -> void:
	var node = null
	if game.jump_height <= 0.001 and game.jump_velocity <= 0.0:
		if support(game.walker, game.walker.y + 0.03) > game.walker.y - 0.03:
			node = supporting.get("node")
		if node == null:
			stand = {}
			return
	if node != null and (stand.is_empty() or stand.node != node):
		stand = {"node": node, "key": key_of(node)}
	if stand.is_empty() or not is_instance_valid(stand.node):
		stand = {}
		return
	stand.local = _pose(stand.node).affine_inverse() * game.walker
	stand.world = game.walker

func clear() -> void:
	stand = {}
	supporting = {}
	nearby.clear()

# ---------------------------------------------------------------- network keys

# Moving perches every client has its own copy of: room members' cars and
# the course vehicles. Others (parked, furniture) sync by position.
func key_of(node: Node3D) -> String:
	if node == game.car:
		return "car:%s" % game.room.player_id
	for id in game.room.peers:
		if game.room.peers[id].car == node:
			return "car:%s" % id
	if node.has_meta("room_id"):
		return "racer:%d" % int(node.get_meta("room_id"))
	return ""

func find(key: String) -> Node3D:
	if key.begins_with("car:"):
		var id = key.trim_prefix("car:")
		if id == str(game.room.player_id):
			return game.car
		var peer = game.room.peers.get(id)
		if peer == null:
			for other in game.room.peers:
				if str(other) == id:
					peer = game.room.peers[other]
		return peer.car if peer != null else null
	if key.begins_with("racer:"):
		var id = key.trim_prefix("racer:").to_int()
		for racer in game.racers:
			if int(racer.id) == id and is_instance_valid(racer.node):
				return racer.node
	return null

# The walker's perch as room state fields (empty when not on a keyed one).
func state_fields() -> Dictionary:
	if stand.is_empty() or str(stand.get("key", "")) == "" or not stand.has("local") or game.in_car or game.seated:
		return {"stand": "", "stand_at": [0.0, 0.0, 0.0]}
	var local: Vector3 = stand.local
	return {"stand": stand.key, "stand_at": [snappedf(local.x, 0.001), snappedf(local.y, 0.001), snappedf(local.z, 0.001)]}

# Where a room member standing on a perch is on this client, or null.
func resolve(state: Dictionary):
	var key = str(state.get("stand", ""))
	var at = state.get("stand_at")
	if key == "" or not at is Array or at.size() != 3 or state.get("in_car", false):
		return null
	var node = find(key)
	if node == null or not node.is_inside_tree():
		return null
	return _pose(node) * Vector3(float(at[0]), float(at[1]), float(at[2]))

# A car at `car_base` passes under/through a person riding on top of it.
static func riding_above(feet: Vector3, car_base: Vector3) -> bool:
	return feet.y - car_base.y > RIDE_CLEARANCE
