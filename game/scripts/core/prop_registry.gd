extends RefCounted
# Explicit opt-in. Interiors and tabletop detail never register independently.
const Merge = preload("res://scripts/core/mesh_merge.gd")

static func bounds(node: Node3D) -> AABB:
	var result = AABB()
	for child in node.get_children():
		if not child is Node3D or child.has_meta("prop_key"):
			continue
		var box = AABB()
		if child is MeshInstance3D and child.mesh != null:
			box = child.mesh.get_aabb()
		else:
			box = bounds(child)
		if box.size.length_squared() > 0:
			box = child.transform * box
			result = box if result.size == Vector3.ZERO else result.merge(box)
	return result

static func register(solids, node: Node3D, mass: float = 15.0, anchored: bool = false, key: String = "") -> Dictionary:
	if node.has_meta("prop_key"):
		return {}
	if key == "":
		key = _scene_key(solids, node)
	var box = bounds(node)
	if box.size == Vector3.ZERO:
		return {}
	node.set_meta("unbatched", true)
	node.set_meta("prop_key", key)
	node.set_meta("prop_anchored", anchored)
	var record = {"node": node, "key": key, "mass": mass, "anchored": anchored, "box": box}
	solids.movables.append(record)
	var found = false
	for obstacle in solids.obstacles:
		if is_instance_valid(obstacle.body) and node.is_ancestor_of(obstacle.body):
			obstacle.movable = true
			obstacle.prop = key
			found = true
	if not found:
		if node.has_meta("prop_collision_meshes"):
			for mesh in node.get_meta("prop_collision_meshes"):
				var part: AABB = mesh.transform * mesh.mesh.get_aabb()
				var body = solids.solid(node, part.get_center(), part.size.max(Vector3.ONE * 0.03), "prop")
				var collider: CollisionShape3D = body.get_child(0)
				collider.shape = mesh.mesh.create_convex_shape()
				collider.transform = Transform3D(Basis.IDENTITY, -part.get_center()) * mesh.transform
				solids.obstacles.back().movable = true
				solids.obstacles.back().prop = key
			solids.indexed_obstacle_count = -1
			return record
		var parts: Array[AABB] = []
		if node.has_meta("prop_shapes"):
			parts.assign(node.get_meta("prop_shapes"))
		else:
			for child in node.get_children():
				if child is MeshInstance3D and child.mesh != null:
					parts.append(child.transform * child.mesh.get_aabb())
		if parts.is_empty() or parts.size() > 12: parts.assign([box])
		for part in parts:
			solids.solid(node, part.get_center(), part.size.max(Vector3.ONE * 0.03), "prop")
			solids.obstacles.back().movable = true
			solids.obstacles.back().prop = key
	solids.indexed_obstacle_count = -1
	return record

# Keep authored siblings as one independent object, outside scenery batching.
static func group(solids, parent: Node3D, first: int, mass: float = 15.0, anchored: bool = false) -> Node3D:
	var children = parent.get_children().slice(first)
	var node = Node3D.new()
	node.name = "Movable_%d" % solids.movables.size()
	parent.add_child(node)
	for child in children:
		parent.remove_child(child)
		node.add_child(child)
	register(solids, node, mass, anchored)
	Merge.bake(node)
	return node

static func _scene_key(solids, node: Node) -> String:
	var parent = node
	while parent != null:
		if str(parent.name).begins_with("ServicePark_") or str(parent.name) == "CourseOfficials":
			var index = int(parent.get_meta("prop_count", 0))
			parent.set_meta("prop_count", index + 1)
			return "%s:%d" % [parent.name, index]
		parent = parent.get_parent()
	var key = "scene:%d" % solids.next_prop_id
	solids.next_prop_id += 1
	return key
