extends Node3D
# Solid scenery shared by every stage: static boxes (walls, houses, furniture),
# destructible lamp posts, walkable floors inside accessible buildings and the
# church bell. Cars, walkers, gravel, NPCs and course officials all query the
# same swept-box collision through hit(); a stage without solids answers {}.
const Props = preload("res://scripts/props.gd")
const COLLISION_CELL = 16.0

var stage: Node3D
var obstacles: Array[Dictionary] = []
var lamps: Array[Dictionary] = []
var lamp_targets: Dictionary = {}
# Floors, stairs and roof terraces people can walk on (never car contact).
var walk_surfaces: Array[Dictionary] = []
# Hollow buildings: keep scenery generation out of their interiors.
var interior_footprints: Array[Dictionary] = []
var viewpoints: Array[Dictionary] = []
var bell: Node3D
var collision_cells: Dictionary = {}
var moving_obstacle_ids: Array[int] = []
var indexed_obstacle_count = -1
var collision_radius_factor = 1.0

func solid(parent: Node3D, center: Vector3, size: Vector3, kind: String) -> StaticBody3D:
	var body = StaticBody3D.new()
	parent.add_child(body)
	body.position = center
	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	obstacles.append({"body": body, "half": size / 2, "kind": kind, "id": -1})
	return body

# A cast-iron lantern post. It stands anchored until a car knocks it over;
# the fall is simulated by the host and replicated through snapshot().
func lamp(p: Vector3, yaw: float) -> RigidBody3D:
	var body = RigidBody3D.new()
	body.name = "StageLamp_%d" % lamps.size()
	stage.add_child(body)
	body.position = p + Vector3(0, 2.0, 0)
	body.rotation.y = yaw
	body.mass = 28
	body.freeze = true
	body.continuous_cd = true
	var material = PhysicsMaterial.new()
	material.friction = 0.75
	material.bounce = 0.08
	body.physics_material_override = material
	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(0.34, 4.0, 0.34)
	shape.shape = box
	body.add_child(shape)
	var iron = Color("2f3b36")
	Props.cylinder(body, Vector3(0, -1.75, 0), 0.22, 0.16, 0.5, iron, 8)
	Props.cylinder(body, Vector3(0, -1.45, 0), 0.12, 0.12, 0.12, iron, 8)
	Props.cylinder(body, Vector3(0, 0.2, 0), 0.07, 0.05, 3.4, iron, 8)
	Props.cylinder(body, Vector3(0, 1.62, 0), 0.10, 0.18, 0.1, iron, 6)
	# Four-sided lantern with a small cap, as on Provençal village squares.
	var glass = Props.box(body, Vector3(0, 1.82, 0), Vector3(0.30, 0.38, 0.30), Color("efdca0"))
	Props.unique_material(glass)
	glass.material_override.emission_enabled = true
	glass.material_override.emission = Color("c9a85e")
	glass.material_override.emission_energy_multiplier = 0.35
	glass.set_meta("unbatched", true)
	Props.cylinder(body, Vector3(0, 2.08, 0), 0.26, 0.04, 0.22, iron, 4)
	for corner in [Vector3(0.15, 1.82, 0.15), Vector3(-0.15, 1.82, 0.15), Vector3(0.15, 1.82, -0.15), Vector3(-0.15, 1.82, -0.15)]:
		Props.box(body, corner, Vector3(0.035, 0.42, 0.035), iron)
	lamps.append({"body": body, "fallen": false})
	obstacles.append({"body": body, "half": Vector3(0.17, 2.0, 0.17), "kind": "lamp", "id": lamps.size() - 1})
	return body

func relative_pose(node: Node3D) -> Transform3D:
	var pose = node.transform
	var parent = node.get_parent()
	while parent != stage and parent is Node3D:
		pose = parent.transform * pose
		parent = parent.get_parent()
	return pose

# Static solids are indexed once into a coarse grid; lamps keep live transforms.
func index() -> void:
	collision_cells.clear()
	moving_obstacle_ids.clear()
	collision_radius_factor = 1.0
	for id in range(obstacles.size()):
		var object: Dictionary = obstacles[id]
		if object.body is RigidBody3D:
			moving_obstacle_ids.append(id)
			continue
		var pose = relative_pose(object.body)
		object["collision_pose"] = pose
		object["collision_inverse"] = pose.affine_inverse()
		var bounds = pose * AABB(-object.half, object.half * 2.0)
		var expansion = pose.basis.x.abs() + pose.basis.y.abs() + pose.basis.z.abs()
		collision_radius_factor = maxf(collision_radius_factor, maxf(expansion.x, maxf(expansion.y, expansion.z)))
		for x in range(floori(bounds.position.x / COLLISION_CELL), floori(bounds.end.x / COLLISION_CELL) + 1):
			for z in range(floori(bounds.position.z / COLLISION_CELL), floori(bounds.end.z / COLLISION_CELL) + 1):
				var key = Vector2i(x, z)
				if not collision_cells.has(key):
					collision_cells[key] = []
				collision_cells[key].append(id)
	indexed_obstacle_count = obstacles.size()

func candidates(start: Vector3, end: Vector3, radius: float) -> Array:
	if indexed_obstacle_count != obstacles.size():
		index()
	var padding = radius * collision_radius_factor
	var low = start.min(end) - Vector3.ONE * padding
	var high = start.max(end) + Vector3.ONE * padding
	var seen: Dictionary = {}
	for x in range(floori(low.x / COLLISION_CELL), floori(high.x / COLLISION_CELL) + 1):
		for z in range(floori(low.z / COLLISION_CELL), floori(high.z / COLLISION_CELL) + 1):
			for id in collision_cells.get(Vector2i(x, z), []):
				seen[id] = true
	for id in moving_obstacle_ids:
		seen[id] = true
	var ids = seen.keys()
	ids.sort()
	return ids

# Earliest swept-sphere contact against every solid box, in world space.
func hit(start: Vector3, end: Vector3, radius: float, escape: bool = true, center_offset: Vector3 = Vector3(0, 0.35, 0)) -> Dictionary:
	if obstacles.is_empty():
		return {}
	var result = {}
	var earliest = INF
	for id in candidates(start + center_offset, end + center_offset, radius):
		var object: Dictionary = obstacles[id]
		var pose: Transform3D = relative_pose(object.body) if object.body is RigidBody3D else object.collision_pose
		var inverse: Transform3D = pose.affine_inverse() if object.body is RigidBody3D else object.collision_inverse
		var a: Vector3 = inverse * (start + center_offset)
		var b: Vector3 = inverse * (end + center_offset)
		var half: Vector3 = object.half + Vector3.ONE * radius
		var travel = b - a
		var inside = absf(a.x) < half.x and absf(a.y) < half.y and absf(a.z) < half.z
		if inside and escape and b.length_squared() > a.length_squared() + 0.0000001 and a.dot(travel) >= 0:
			continue
		var near = 0.0
		var far = 1.0
		var normal = Vector3.ZERO
		var valid = true
		for axis in range(3):
			if absf(travel[axis]) < 0.0000001:
				if absf(a[axis]) > half[axis]:
					valid = false
					break
				continue
			var first = (-half[axis] - a[axis]) / travel[axis]
			var last = (half[axis] - a[axis]) / travel[axis]
			var n = Vector3.ZERO
			n[axis] = -signf(travel[axis])
			if first > last:
				var swap = first
				first = last
				last = swap
			if first > near:
				near = first
				normal = n
			far = minf(far, last)
			if near > far:
				valid = false
				break
		if not valid or near < 0 or near > 1 or near >= earliest:
			continue
		if normal.length_squared() < 0.1:
			normal = -travel.normalized() if travel.length_squared() > 0.000001 else Vector3.RIGHT
		normal = (pose.basis * normal).normalized()
		earliest = near
		result = {"position": start.lerp(end, near) + normal * 0.035, "normal": normal, "kind": object.kind, "id": object.id}
	return result

# True when the ground footprint around p (padded) is outside every solid and
# hollow interior. Height is ignored (solids only turn about the vertical axis),
# so callers may test points before sampling the ground.
func clear(p: Vector3, padding: float = 0.0) -> bool:
	for area in interior_footprints:
		var local: Vector3 = area.inverse * p
		if absf(local.x) <= area.half.x + padding and absf(local.z) <= area.half.y + padding:
			return false
	for id in candidates(Vector3(p.x, 0, p.z), Vector3(p.x, 0, p.z), padding + 0.5):
		var object: Dictionary = obstacles[id]
		var pose: Transform3D = relative_pose(object.body) if object.body is RigidBody3D else object.collision_pose
		var local = pose.affine_inverse() * p
		if absf(local.x) <= object.half.x + padding and absf(local.z) <= object.half.z + padding:
			return false
	return true

func knock_lamp(index_value: int, direction: Vector3) -> bool:
	if index_value < 0 or index_value >= lamps.size() or lamps[index_value].fallen:
		return false
	lamps[index_value].fallen = true
	var body: RigidBody3D = lamps[index_value].body
	body.freeze = false
	body.sleeping = false
	var dir = Vector3(direction.x, 0, direction.z).normalized()
	if dir.length_squared() < 0.1:
		dir = Vector3.RIGHT
	body.apply_impulse(dir * 160 + Vector3(0, 25, 0), Vector3(0, 1.6, 0))
	return true

func _physics_process(delta: float) -> void:
	if lamps.is_empty():
		return
	var game = stage.get_parent()
	var simulate = true
	if game != null and game.has_method("player_position"):
		simulate = game.playing and not game.paused and not game.dead and not game.finished and (not game.room.connected or game.room.is_host)
	for i in range(lamps.size()):
		var lamp_state = lamps[i]
		lamp_state.body.freeze = not (simulate and lamp_state.fallen)
		if not simulate and lamp_targets.has(i):
			var target = lamp_targets[i]
			var weight = 1.0 - exp(-delta * 16.0)
			lamp_state.body.position = lamp_state.body.position.lerp(target.pos, weight)
			for axis in range(3):
				lamp_state.body.rotation[axis] = lerp_angle(lamp_state.body.rotation[axis], target.rot[axis], weight)

func snapshot() -> Array:
	var result = []
	for i in range(lamps.size()):
		if not lamps[i].fallen:
			continue
		var body = lamps[i].body
		result.append({"id": i, "pos": [body.position.x, body.position.y, body.position.z], "rot": [body.rotation.x, body.rotation.y, body.rotation.z]})
	return result

func apply_snapshot(data: Array) -> void:
	for item in data:
		var i = int(item.id)
		if i < 0 or i >= lamps.size():
			continue
		var first = not lamps[i].fallen
		lamps[i].fallen = true
		var body = lamps[i].body
		body.freeze = true
		var target = {"pos": Vector3(item.pos[0], item.pos[1], item.pos[2]), "rot": Vector3(item.rot[0], item.rot[1], item.rot[2])}
		lamp_targets[i] = target
		if first:
			body.position = target.pos
			body.rotation = target.rot

# Floors are queried only for walkers, never for road/car suspension. The
# height limit prevents a roof or an overlapping flight teleporting a person
# underneath it upwards. Without an authored floor the stage ground applies.
func walking_floor(pos: Vector3, feet_height: float) -> float:
	var result = -INF
	for surface in walk_surfaces:
		if absf(pos.x - surface.pose.origin.x) > surface.reach or absf(pos.z - surface.pose.origin.z) > surface.reach:
			continue
		var local: Vector3 = surface.inverse * pos
		if absf(local.x) > surface.half.x or absf(local.z) > surface.half.y:
			continue
		var progress = clampf(local.z / (surface.half.y * 2.0) + 0.5, 0.0, 1.0)
		var steps = int(surface.get("steps", 0))
		if steps > 0:
			progress = ceilf(progress * steps) / steps
		var height: float = surface.pose.origin.y + surface.rise * progress
		if height <= feet_height + 0.45:
			result = maxf(result, height)
	return result if is_finite(result) else stage.walking_ground(pos)
