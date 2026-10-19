extends RefCounted
# Sample real feet, not the corners of a rotated enclosing box. Cache the
# low vertices once: moving the placement ghost must not rebuild its meshes.
static func height(node: Node3D, spot: Vector3, basis: Basis, ground: Callable) -> float:
	if not node.has_meta("camp_feet"):
		var vertices = PackedVector3Array()
		_collect(node, Transform3D.IDENTITY, vertices)
		var bottom = INF
		for point in vertices: bottom = minf(bottom, point.y)
		var feet = PackedVector3Array()
		var seen: Dictionary = {}
		for point in vertices:
			if point.y > bottom + 0.03 or seen.has(point): continue
			feet.append(point)
			seen[point] = true
		node.set_meta("camp_feet", feet)
	var result = -INF
	for point in node.get_meta("camp_feet"):
		var offset: Vector3 = basis * point
		result = maxf(result, ground.call(spot + offset) - offset.y)
	return ground.call(spot) if result == -INF else result

static func _collect(node: Node3D, pose: Transform3D, vertices: PackedVector3Array) -> void:
	for child in node.get_children():
		if not child is Node3D or child is CollisionObject3D or not child.visible: continue
		var transform: Transform3D = pose * child.transform
		if child is MeshInstance3D and child.mesh != null:
			for point in child.mesh.get_faces(): vertices.append(transform * point)
		_collect(child, transform, vertices)
