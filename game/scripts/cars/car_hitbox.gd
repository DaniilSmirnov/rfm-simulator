extends RefCounted
# Closed-model bounds, measured before mesh batching or suspension animation.
# Queries sweep an oriented box, so bumpers and sides keep their actual reach.
static var player_bounds: Dictionary = {}

static func measure(node: Node3D, pose: Transform3D = Transform3D.IDENTITY) -> AABB:
	var bounds = AABB()
	if node is MeshInstance3D and node.mesh != null:
		bounds = pose * node.mesh.get_aabb()
	for child in node.get_children():
		if child is Node3D and child.visible:
			var part = measure(child, pose * child.transform)
			if part.size != Vector3.ZERO:
				bounds = part if bounds.size == Vector3.ZERO else bounds.merge(part)
	return bounds

static func bounds(node: Node3D) -> AABB:
	if not node.has_meta("car_hitbox"):
		node.set_meta("car_hitbox", measure(node))
	return node.get_meta("car_hitbox")

static func player(model: int) -> AABB:
	if not player_bounds.has(model):
		var node: Node3D = load("res://scripts/core/props.gd").player_car(model, false)
		player_bounds[model] = bounds(node)
		node.free()
	return player_bounds[model]

static func shape(box: AABB, yaw: float) -> Dictionary:
	var basis = Basis(Vector3.UP, yaw)
	return {"basis": basis, "offset": basis * box.get_center(), "half": box.size * 0.5}

# Continuous SAT on both boxes' face normals and their edge cross products.
# Returns first time of contact; no substep sampling or tunnelling at speed.
static func sweep(start: Vector3, end: Vector3, car: Dictionary, pose: Transform3D, half: Vector3, escape: bool = true, slide_overlap: bool = false) -> Dictionary:
	var axes: Array = [car.basis.x, car.basis.y, car.basis.z]
	for axis in [pose.basis.x, pose.basis.y, pose.basis.z]:
		axes.append(axis.normalized())
		for side in [car.basis.x, car.basis.y, car.basis.z]:
			if axis.cross(side).length_squared() > 0.0000001:
				axes.append(axis.cross(side).normalized())
	var relative: Vector3 = start + car.offset - pose.origin
	var travel = end - start
	var near = 0.0
	var far = 1.0
	var normal = -travel.normalized()
	var inside = true
	var shallowest = INF
	var escape_normal = Vector3.ZERO
	for axis in axes:
		var radius = 0.0
		for i in range(3):
			radius += absf(axis.dot(car.basis[i])) * car.half[i] + absf(axis.dot(pose.basis[i])) * half[i]
		var distance: float = relative.dot(axis)
		var speed: float = travel.dot(axis)
		if slide_overlap and radius - absf(distance) < shallowest:
			shallowest = radius - absf(distance)
			escape_normal = axis * signf(distance)
		if absf(distance) > radius: inside = false
		if absf(speed) < 0.0000001:
			if absf(distance) > radius: return {}
			continue
		var first = (-radius - distance) / speed
		var last = (radius - distance) / speed
		if first > last:
			var swap = first
			first = last
			last = swap
		if first > near:
			near = first
			normal = -signf(speed) * axis
		far = minf(far, last)
		if near > far: return {}
	# A falling log may overlap the chassis. Let the car slide along or
	# away from its shallowest contact instead of cancelling every tick.
	if inside and slide_overlap and travel.length_squared() > 0.0000000000000001 and escape_normal.dot(travel) >= -0.0000000001: return {}
	if inside and escape and relative.dot(travel) >= 0 and travel.length_squared() > 0.0000001: return {}
	if near < 0 or near > 1: return {}
	return {"time": near, "position": start.lerp(end, near) + normal * 0.035, "normal": normal}

static func solids(solids, start: Vector3, end: Vector3, car: Dictionary, ignored: Array) -> Dictionary:
	var best: Dictionary = {}
	for id in solids.candidates(start + car.offset, end + car.offset, car.half.length()):
		var object: Dictionary = solids.obstacles[id]
		if not is_instance_valid(object.body) or ignored.any(func(node): return node == object.body or node.is_ancestor_of(object.body)): continue
		var live = object.body is RigidBody3D or object.get("movable", false)
		if live: solids._cache_live_pose(object)
		var pose: Transform3D = object.live_pose if live else object.collision_pose
		var half: Vector3 = object.half
		if apart(start + car.offset, end + car.offset, pose.origin, car.half.length() + pose.basis.x.length() * half.x + pose.basis.y.length() * half.y + pose.basis.z.length() * half.z): continue
		var hit = sweep(start, end, car, pose, half)
		if hit.is_empty() or (not best.is_empty() and hit.time >= best.time): continue
		hit.merge({"kind": object.kind, "id": object.id, "prop": object.get("prop", "")})
		best = hit
	return best

# Circle versus the rounded rectangle (Minkowski sum) of the car footprint.
static func circle(start: Vector3, end: Vector3, car: Dictionary, center: Vector3, radius: float) -> Dictionary:
	var inverse: Basis = car.basis.transposed()
	var a: Vector3 = inverse * (center - start - car.offset)
	var b: Vector3 = inverse * (center - end - car.offset)
	a.y = 0
	b.y = 0
	var half: Vector3 = car.half
	half.y = 10000
	if minf(a.x, b.x) > half.x + radius or maxf(a.x, b.x) < -half.x - radius or minf(a.z, b.z) > half.z + radius or maxf(a.z, b.z) < -half.z - radius: return {}
	var closest = a.clamp(-half, half)
	if a.distance_to(closest) < radius and b.length_squared() > a.length_squared() + 0.0000001 and a.dot(b - a) >= 0: return {}
	var best: Dictionary = {}
	# Two strips plus four circular corners give the exact rounded rectangle.
	for size in [Vector3(half.x + radius, 10000, half.z), Vector3(half.x, 10000, half.z + radius)]:
		var hit = sweep(a, b, shape(AABB(), 0), Transform3D.IDENTITY, size, false)
		if not hit.is_empty() and (best.is_empty() or hit.time < best.time): best = hit
	var travel = b - a
	for x in [-half.x, half.x]:
		for z in [-half.z, half.z]:
			var offset = a - Vector3(x, 0, z)
			var length_squared = travel.length_squared()
			var projection = offset.dot(travel)
			var discriminant = projection * projection - length_squared * (offset.length_squared() - radius * radius)
			var t = 0.0
			if offset.length_squared() > radius * radius:
				if length_squared < 0.0000001 or discriminant < 0: continue
				t = (-projection - sqrt(discriminant)) / length_squared
			if t < 0 or t > 1 or (not best.is_empty() and t >= best.time): continue
			best = {"time": t, "normal": (offset + travel * t).normalized()}
	if best.is_empty(): return {}
	var normal: Vector3 = -(car.basis * best.normal)
	return {"time": best.time, "position": start.lerp(end, best.time) + normal * 0.025, "normal": normal, "radius": radius}

static func rocks(stage, start: Vector3, end: Vector3, car: Dictionary) -> Dictionary:
	var padding: float = car.half.length() + car.offset.length()
	var a = Vector2(start.x, start.z)
	var b = Vector2(end.x, end.z)
	var best: Dictionary = {}
	for rock in stage.rocks_in_bounds(a.min(b) - Vector2.ONE * padding, a.max(b) + Vector2.ONE * padding):
		if minf(start.y, end.y) > rock.pos.y + rock.height: continue
		var hit = circle(start, end, car, rock.pos, rock.radius)
		if not hit.is_empty() and (best.is_empty() or hit.time < best.time): best = hit
	return best

static func tree(stage, start: Vector3, end: Vector3, car: Dictionary) -> int:
	var padding: float = car.half.length() + car.offset.length() + 12.0
	var low = stage._tree_cell(start.min(end) - Vector3.ONE * padding)
	var high = stage._tree_cell(start.max(end) + Vector3.ONE * padding)
	var candidates: Array = []
	if stage.tree_cells.is_empty() or stage.indexed_tree_count != stage.trees.size():
		candidates = range(stage.trees.size())
	else:
		for x in range(low.x, high.x + 1):
			for z in range(low.y, high.y + 1):
				candidates.append_array(stage.tree_cells.get(Vector2i(x, z), []))
	for index in candidates:
		if not stage.fallen.has(index):
			if not circle(start, end, car, stage.trees[index], 0.2).is_empty(): return index
		else:
			var f: Dictionary = stage.fallen[index]
			var length: float = stage.forest_data[index].height * 0.64
			var direction: Vector3 = f.direction
			var angle = smoothstep(0, 1.3, f.age) * PI * 0.5
			var basis = Basis(Vector3.UP.cross(direction).normalized(), angle)
			# Match the rendered trunk's pivot and tilt, including during its fall.
			# Raising the collider to car height traps a car above the log.
			var lift = Vector3.ZERO if stage.detail_tree_visuals.has(index) else Vector3(0, 0.2, 0)
			var pose = Transform3D(basis, stage.trees[index] + lift + basis * Vector3(0, length * 0.5, 0))
			if not sweep(start, end, car, pose, Vector3(0.35, length * 0.5, 0.35), true, true).is_empty(): return index
	return -1

static func contact(node: Node3D) -> Dictionary:
	return {"position": node.position, "yaw": node.rotation.y, "box": bounds(node)}

static func blocked(start: Vector3, end: Vector3, car: Dictionary, other: Dictionary) -> bool:
	var position: Vector3 = other.position
	if other.get("person", false):
		if minf(start.y, end.y) > position.y + 1.5: return false
		return not circle(start, end, car, position, 0.3).is_empty()
	var box: AABB = other.get("box", player(0))
	var basis = Basis(Vector3.UP, float(other.get("yaw", 0)))
	var center = position + basis * box.get_center()
	if apart(start + car.offset, end + car.offset, center, car.half.length() + box.size.length() * 0.5): return false
	return not sweep(start, end, car, Transform3D(basis, center), box.size * 0.5).is_empty()

# Bounding spheres: true when a car centre moving start -> end stays farther
# than `reach` from `center`, so the exact sweep cannot report a contact.
# Cheap enough to run before every sweep; most candidates are rejected here.
static func apart(start: Vector3, end: Vector3, center: Vector3, reach: float) -> bool:
	var segment = end - start
	var t = clampf((center - start).dot(segment) / maxf(segment.length_squared(), 0.0000001), 0.0, 1.0)
	reach += 0.05
	return (start + segment * t).distance_squared_to(center) > reach * reach
