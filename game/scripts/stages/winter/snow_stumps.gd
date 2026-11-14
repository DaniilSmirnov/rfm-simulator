extends RefCounted
# Trees on snowy stages stand on the snow surface. Where the shovel clears a
# triangle under one, its trunk goes on down to the pit floor instead of
# hanging in the air: one instanced draw of trunk pieces, rebuilt only when
# the set of dug triangles changes. The forest above the snow is untouched.

const STUMP_MESH_NAME = "SnowTrunkStumps"
const FOREST_TRUNK_RADIUS = 0.2
const FOREST_TRUNK_COLOR = Color("67543d")

# [{"base": Vector3, "floor": float, "radius": float, "color": Color}] for every
# tree whose trunk foot lies over a dug triangle.
static func collect(stage, snow) -> Array:
	var found: Dictionary = {}
	for key in snow.dug:
		var low = Vector2(key.x, key.y)
		var high = low + Vector2(key.z, key.z)
		for index in stage.trees_near(low, high, 0.5):
			if found.has(index) or index >= stage.trees.size():
				continue
			var base: Vector3 = stage.fallen[index].get("origin", stage.trees[index]) if stage.fallen.has(index) else stage.trees[index]
			if base.x < low.x - 1.0 or base.x > high.x + 1.0 or base.z < low.y - 1.0 or base.z > high.y + 1.0:
				continue
			var look = trunk_look(stage, index)
			var floor_y = INF
			for offset in [Vector3.ZERO, Vector3(look.radius, 0, 0), Vector3(-look.radius, 0, 0), Vector3(0, 0, look.radius), Vector3(0, 0, -look.radius)]:
				var sample: Vector3 = base + offset
				if snow.is_dug(stage, sample):
					floor_y = minf(floor_y, snow.floor_height(stage, sample))
			if floor_y < base.y - 0.05:
				found[index] = {"base": base, "floor": floor_y, "radius": look.radius, "color": look.color}
	return found.values()

# Radius and colour of a tree's lowest trunk piece.
static func trunk_look(stage, index: int) -> Dictionary:
	var look = {"radius": FOREST_TRUNK_RADIUS, "color": FOREST_TRUNK_COLOR}
	if not stage.detail_tree_visuals.has(index):
		return look
	var lowest = INF
	for part in stage.detail_tree_visuals[index]:
		var multimesh: MultiMesh = part.mesh
		if not multimesh.mesh is CylinderMesh:
			continue
		var pose: Transform3D = part.pose
		if pose.origin.y >= lowest:
			continue
		lowest = pose.origin.y
		look.radius = maxf(0.05, multimesh.mesh.bottom_radius * pose.basis.x.length())
		if multimesh.use_colors:
			look.color = multimesh.get_instance_color(part.instance)
	return look

static func rebuild(stage, snow) -> void:
	if stage == null or not stage.is_inside_tree():
		return
	var node: MultiMeshInstance3D = stage.get_node_or_null(STUMP_MESH_NAME)
	var stumps = collect(stage, snow)
	if stumps.is_empty():
		if node != null:
			node.multimesh.instance_count = 0
		return
	if node == null:
		node = MultiMeshInstance3D.new()
		node.name = STUMP_MESH_NAME
		var mesh = CylinderMesh.new()
		mesh.top_radius = 1.0
		mesh.bottom_radius = 1.0
		mesh.height = 1.0
		mesh.radial_segments = 6
		mesh.rings = 1
		var material = RallyProps.material(Color.WHITE)
		material.vertex_color_use_as_albedo = true
		material.vertex_color_is_srgb = true
		mesh.material = material
		node.multimesh = MultiMesh.new()
		node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		node.multimesh.use_colors = true
		node.multimesh.mesh = mesh
		stage.add_child(node)
	node.multimesh.instance_count = stumps.size()
	for i in range(stumps.size()):
		var stump: Dictionary = stumps[i]
		# Reaches a little into the trunk above and below the pit floor.
		var top: float = stump.base.y + 0.05
		var bottom: float = stump.floor - 0.1
		var origin = Vector3(stump.base.x, (top + bottom) * 0.5, stump.base.z)
		node.multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(stump.radius, top - bottom, stump.radius)), origin))
		node.multimesh.set_instance_color(i, stump.color)
