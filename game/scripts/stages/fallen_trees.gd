extends RefCounted
# Felled trees: the angle a trunk comes to rest at and its rendered pose.

# How far a felled trunk turns from upright: it comes to rest along the ground
# it falls onto, past level downhill and short of it uphill, instead of lying
# level and being left to a rigid body that rolled it down the slope.
const MAX_LIE_PITCH = 0.7
static func lie_angle(stage, base: Vector3, direction: Vector3, length: float) -> float:
	var rise: float = stage.ground(base + direction * length) - stage.ground(base)
	return PI * 0.5 - clampf(atan2(rise, length), -MAX_LIE_PITCH, MAX_LIE_PITCH)

# Turns the rendered trunk and crown of every felled tree to its pose.
static func update(stage, delta: float) -> void:
	for index in stage.fallen:
		var tree_data: Dictionary = stage.forest_data[index]
		var f: Dictionary = stage.fallen[index]
		f.age = minf(1.3, f.age + delta)
		var basis = stage.fallen_basis(index)
		if f.get("rendered_age", -1.0) == f.age and f.get("basis", Basis.IDENTITY).is_equal_approx(basis):
			continue
		f.rendered_age = f.age
		f.basis = basis
		if stage.detail_tree_visuals.has(index):
			for part in stage.detail_tree_visuals[index]:
				var pose: Transform3D = part.pose
				pose.origin = stage.trees[index] + basis * (pose.origin - f.origin) - part.center
				pose.basis = basis * pose.basis
				part.mesh.set_instance_transform(part.instance, pose)
			continue
		var h: float = tree_data.height
		for layer in range(stage.forest_layers.size()):
			var radius = 0.2 if layer == 0 else h * (0.28 - (layer - 1) * 0.055)
			var height = h * (0.64 if layer == 0 else 0.49)
			var y = h * (0.32 if layer == 0 else 0.47 + (layer - 1) * 0.18)
			var slot: Vector2i = stage.forest_chunk_slots[index]
			stage.forest_layers[layer][slot.x].set_instance_transform(slot.y, Transform3D(basis * Basis.from_scale(Vector3(radius, height, radius)), stage.trees[index] - stage.forest_chunk_centers[slot.x] + Vector3(0, 0.2, 0) + basis * Vector3(0, y, 0)))
