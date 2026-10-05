extends Node3D
class_name RallyStage

const LENGTH = 840.0
const STEP = 4.0
const WIDTH = 7.4
const TREE_CELL_SIZE = 16.0
const STAGES = ["Лесной перевал · гравий", "Зимний Турини · снег и лёд"]
var variant = 0
var winter = false
var points: PackedVector3Array = []
var clearings: Array[Vector3] = []
var trails: Array[Dictionary] = []
var trees: Array[Vector3] = []
var forest_data: Array[Dictionary] = []
var forest_layers: Array[MultiMesh] = []
var tree_cells: Dictionary = {}
var indexed_tree_count = -1
var fallen: Dictionary = {}
var rng = RandomNumberGenerator.new()

func _init(selected: int = 0) -> void:
	variant = clampi(selected, 0, STAGES.size() - 1)
	winter = variant == 1
	for i in range(int(LENGTH / STEP) + 1):
		var s = i * STEP
		if winter:
			points.append(Vector3(sin(s / 48.0) * 58.0 + sin(s / 115.0) * 14.0, 18.0 + s * 0.085 + sin(s / 36.0) * 5.0, -s))
		else:
			points.append(Vector3(sin(s / 90.0) * 38.0 + sin(s / 38.0) * 9.0, 5.0 + s * 0.024 + sin(s / 58.0) * 3.7, -s))
	for s in [140.0, 310.0, 505.0, 690.0]:
		var direction_sign = 1.0 if s < 500 else -1.0
		var lookout = at(s) + side(s) * direction_sign * 27.0
		# The spectator clearings sit above the road. A short switchback makes
		# them reachable on foot without opening a large treeless corridor.
		lookout.y = at(s).y + (5.2 if not winter else 4.0) + sin(s * 0.03) * 0.8
		clearings.append(lookout)
		var road_entry = at(s) + side(s) * direction_sign * (WIDTH * 0.5 + 1.8)
		var first_turn = at(s - 9.0) + side(s) * direction_sign * 10.5
		first_turn.y = at(s - 9.0).y + 1.7
		var second_turn = at(s + 7.0) + side(s) * direction_sign * 19.0
		second_turn.y = at(s + 7.0).y + (3.3 if not winter else 2.5)
		trails.append({"points": [road_entry, first_turn, second_turn, lookout], "width": 2.2})

func at(s: float) -> Vector3:
	s = clampf(s, 0, LENGTH - 0.001)
	var index = int(s / STEP)
	return points[index].lerp(points[index + 1], fmod(s, STEP) / STEP)

func direction(s: float) -> Vector3:
	return (at(minf(s + 2, LENGTH - 0.01)) - at(maxf(s - 2, 0))).normalized()

func side(s: float) -> Vector3:
	return direction(s).cross(Vector3.UP).normalized()

func road_s(pos: Vector3) -> float:
	return clampf(-pos.z, 0, LENGTH)

func road_distance(pos: Vector3) -> float:
	var p = at(road_s(pos))
	return Vector2(pos.x - p.x, pos.z - p.z).length()

func roughness(s: float) -> float:
	# Broad crests plus broken ruts; deterministic across all room members.
	return sin(s * 0.46) * 0.075 + sin(s * 1.13) * 0.035 + pow(maxf(0, cos((s - 32.0) * TAU / 46.0)), 10) * 0.55

func grip(pos: Vector3) -> float:
	if winter:
		if road_distance(pos) > WIDTH * 0.55:
			return 0.32
		return 0.22 if int(road_s(pos) / 32) % 3 == 1 else 0.47
	if road_distance(pos) > WIDTH * 0.55:
		return 0.48
	return 0.42 if int(road_s(pos) / STEP) % 13 == 7 else 0.78

func ground(pos: Vector3) -> float:
	var s = road_s(pos)
	var p = at(s)
	var distance = road_distance(pos)
	var slope = maxf(0, distance - 10.0)
	var height = p.y + roughness(s) * (1.0 - smoothstep(3.7, 8.0, distance)) + sin(pos.x * 0.07 + s * 0.013) * slope * 0.08 + slope * 0.20
	if winter:
		height += slope * 0.42 + sin(s / 85.0) * slope * 0.15
	for clearing in clearings:
		var d = Vector2(pos.x - clearing.x, pos.z - clearing.z).length()
		height = lerpf(clearing.y, height, smoothstep(5.5, 11.5, d))
	for trail in trails:
		var trail_sample = _trail_sample(pos, trail)
		if trail_sample.distance < trail.width:
			var blend = 1.0 - smoothstep(trail.width * 0.55, trail.width, trail_sample.distance)
			height = lerpf(height, trail_sample.height, blend)
	return height

func _trail_sample(pos: Vector3, trail: Dictionary) -> Dictionary:
	var nearest_distance = INF
	var nearest_height = pos.y
	var trail_points: Array = trail.points
	for i in range(trail_points.size() - 1):
		var a: Vector3 = trail_points[i]
		var b: Vector3 = trail_points[i + 1]
		var a2 = Vector2(a.x, a.z)
		var b2 = Vector2(b.x, b.z)
		var p2 = Vector2(pos.x, pos.z)
		var segment = b2 - a2
		var ratio = clampf((p2 - a2).dot(segment) / maxf(segment.length_squared(), 0.001), 0.0, 1.0)
		var closest = a2.lerp(b2, ratio)
		var distance = p2.distance_to(closest)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_height = lerpf(a.y, b.y, ratio)
	return {"distance": nearest_distance, "height": nearest_height}

func trail_distance(pos: Vector3) -> float:
	var distance = INF
	for trail in trails:
		distance = minf(distance, float(_trail_sample(pos, trail).distance))
	return distance

func build() -> void:
	rng.seed = 7102026 + variant * 971
	_build_terrain()
	_build_road()
	var forest: Array[Dictionary] = []
	for i in range(520 if winter else 2200):
		var p = Vector3(rng.randf_range(-150, 150), 0, rng.randf_range(-LENGTH - 65, 50))
		if road_distance(p) < 9:
			continue
		if trail_distance(p) < 3.2:
			continue
		var in_clearing = false
		for c in clearings:
			if Vector2(p.x - c.x, p.z - c.z).length() < 8.5:
				in_clearing = true
		if in_clearing:
			continue
		p.y = ground(p)
		trees.append(p)
		forest.append({"position": p, "height": rng.randf_range(6, 13), "shade": rng.randf_range(-0.025, 0.045)})
	forest_data = forest
	_rebuild_tree_index()
	_build_forest(forest)
	for i in range(100):
		var s = rng.randf_range(20, LENGTH - 15)
		var p = at(s) + side(s) * rng.randf_range(-6, 6)
		if road_distance(p) < 4.3:
			continue
		p.y = ground(p)
		var rock = RallyProps.cylinder(self, p + Vector3(0, 0.2, 0), rng.randf_range(0.3, 1), 0.18, 0.65, Color("7d8070"), 5)
		rock.rotation.z = rng.randf_range(-0.3, 0.3)
	for i in range(clearings.size()):
		var c = clearings[i]
		RallyProps.cylinder(self, c + Vector3(0, 1.2, 0), 0.07, 0.07, 2.4, Color("d5bc8e"), 5)
		var sign = RallyProps.box(self, c + Vector3(0, 2.15, 0), Vector3(2, 0.65, 0.12), Color("e5d9b9"))
		var label = Label3D.new()
		sign.add_child(label)
		label.position = Vector3(0, 0, 0.075)
		label.text = "ПОЛЯНА %d" % (i + 1)
		label.font_size = 42
		label.pixel_size = 0.005
		label.modulate = Color("344537")
		label.outline_size = 0
	# Distant angular ridges, original meshes.
	for i in range(18):
		var p = Vector3((-1 if i % 2 == 0 else 1) * rng.randf_range(220, 340), 30, -i * 65.0)
		RallyProps.cylinder(self, p, rng.randf_range(120, 180), 0, rng.randf_range(220, 340) if winter else rng.randf_range(130, 210), Color("c3d1db") if winter else Color("697d70"), 5)

func _build_terrain() -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in range(-920, 81, 4):
		for x in range(-204, 204, 4):
			var a = Vector3(x, 0, z)
			var b = Vector3(x + 4, 0, z)
			var c = Vector3(x, 0, z + 4)
			var d = Vector3(x + 4, 0, z + 4)
			for v in [a, b, c, b, d, c]:
				v.y = ground(v) - 0.25
				st.set_color((Color("b6c9d3") if winter else Color(0.32, 0.38, 0.25)).lightened(rng.randf_range(-0.07, 0.07)))
				st.add_vertex(v)
	st.generate_normals()
	var n = MeshInstance3D.new()
	n.mesh = st.commit()
	var mat = RallyProps.material(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	n.material_override = mat
	add_child(n)

func _build_road() -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(int(LENGTH)):
		var s = float(i)
		var a = at(s) + side(s) * WIDTH / 2
		var b = at(s) - side(s) * WIDTH / 2
		var c = at(s + 1) + side(s + 1) * WIDTH / 2
		var d = at(s + 1) - side(s + 1) * WIDTH / 2
		for v in [a, b, c, b, d, c]:
			st.set_color((Color("708a9c") if winter else Color("9d896b")).lightened(rng.randf_range(-0.065, 0.045)))
			v.y = ground(v) + 0.04
			st.add_vertex(v)
		# Broken muddy wheel tracks, shallow puddles.
		if i % 12 == 0:
			for offset in [-1.0, 1.0]:
				var p = at(s) + side(s) * offset
				p.y = ground(p)
				var rut = RallyProps.box(self, p + Vector3(0, 0.07, 0), Vector3(0.5, 0.025, 2.7), Color("586974") if winter else Color("77654c"))
				rut.rotation.y = atan2(-direction(s).x, -direction(s).z)
		if i % 52 == 28:
			var p = at(s) + side(s) * 1.5
			p.y = ground(p)
			var puddle = RallyProps.cylinder(self, p + Vector3(0, 0.10, 0), 1.1, 1.1, 0.025, Color("56645d"), 9)
			puddle.scale.z = 1.7
		if winter and i % 8 == 0:
			for offset in [-4.7, 4.7]:
				var p = at(s) + side(s) * offset
				p.y = ground(p)
				var bank = RallyProps.box(self, p + Vector3(0, 0.23, 0), Vector3(1.7, 0.65, 9.0), Color("e1edf1"))
				bank.rotation.y = atan2(-direction(s).x, -direction(s).z)
	st.generate_normals()
	var n = MeshInstance3D.new()
	n.mesh = st.commit()
	var mat = RallyProps.material(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	n.material_override = mat
	add_child(n)

# Four instanced draw calls for the forest instead of thousands of nodes.
# Collision positions remain in `trees`, matching the original gameplay.
func _build_forest(forest: Array[Dictionary]) -> void:
	for layer in range(4):
		var mesh = CylinderMesh.new()
		mesh.bottom_radius = 1.0
		mesh.top_radius = 0.65 if layer == 0 else 0.0
		mesh.height = 1.0
		mesh.radial_segments = 5 if layer == 0 else 6
		var mat = RallyProps.material(Color.WHITE)
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		mesh.material = mat
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = forest.size()
		forest_layers.append(mm)
		for i in range(forest.size()):
			var tree_data = forest[i]
			var h: float = tree_data.height
			var radius = 0.2 if layer == 0 else h * (0.28 - (layer - 1) * 0.055)
			var height = h * (0.64 if layer == 0 else 0.49)
			var y = h * (0.32 if layer == 0 else 0.47 + (layer - 1) * 0.18)
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(radius, height, radius)), tree_data.position + Vector3(0, y, 0)))
			var shade: float = tree_data.shade
			mm.set_instance_color(i, Color("67543d") if layer == 0 else ((Color("78958a") if layer == 1 else Color("b8cdd3")).lightened(shade) if winter else Color(0.17 + shade, 0.28 + shade, 0.21 + shade)))
		var instance = MultiMeshInstance3D.new()
		instance.name = "ForestLayer%d" % layer
		instance.multimesh = mm
		add_child(instance)

func _rebuild_tree_index() -> void:
	tree_cells.clear()
	for index in range(trees.size()):
		var key = _tree_cell(trees[index])
		if not tree_cells.has(key):
			tree_cells[key] = []
		tree_cells[key].append(index)
	indexed_tree_count = trees.size()

func _tree_cell(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / TREE_CELL_SIZE), floori(pos.z / TREE_CELL_SIZE))

func fell(index: int, direction_hint: Vector3) -> bool:
	if index < 0 or index >= trees.size() or fallen.has(index):
		return false
	var dir = Vector3(direction_hint.x, 0, direction_hint.z).normalized()
	if dir.length_squared() < 0.5:
		dir = Vector3.FORWARD
	fallen[index] = {"direction": dir, "age": 0.0}
	return true

func update_fallen(delta: float) -> void:
	for index in fallen:
		var tree_data: Dictionary = forest_data[index]
		var f: Dictionary = fallen[index]
		f.age = minf(1.3, f.age + delta)
		var angle = smoothstep(0, 1.3, f.age) * PI * 0.5
		var basis = Basis(Vector3.UP.cross(f.direction).normalized(), angle)
		f.basis = basis
		var h: float = tree_data.height
		for layer in range(forest_layers.size()):
			var radius = 0.2 if layer == 0 else h * (0.28 - (layer - 1) * 0.055)
			var height = h * (0.64 if layer == 0 else 0.49)
			var y = h * (0.32 if layer == 0 else 0.47 + (layer - 1) * 0.18)
			forest_layers[layer].set_instance_transform(index, Transform3D(basis * Basis.from_scale(Vector3(radius, height, radius)), trees[index] + Vector3(0, 0.2, 0) + basis * Vector3(0, y, 0)))

func tree_snapshot() -> Array:
	var result = []
	for index in fallen:
		var f: Dictionary = fallen[index]
		result.append({"id": index, "dir": [f.direction.x, 0, f.direction.z], "age": f.age})
	return result

func apply_trees(snapshot: Array) -> void:
	for f in snapshot:
		var index = int(f.id)
		if index < 0 or index >= trees.size():
			continue
		fell(index, Vector3(f.dir[0], 0, f.dir[2]))
		fallen[index].direction = Vector3(f.dir[0], 0, f.dir[2]).normalized()
		fallen[index].age = maxf(fallen[index].age, float(f.age))
	update_fallen(0)

static func flat(pos: Vector3) -> Vector2:
	return Vector2(pos.x, pos.z)

func obstacle_hit(start: Vector3, end: Vector3, radius: float, allow_escape: bool = false) -> int:
	var a = flat(start)
	var b = flat(end)
	var candidates: Array = []
	if tree_cells.is_empty() or indexed_tree_count != trees.size():
		# Tests and external callers may append a temporary tree directly.
		for index in range(trees.size()):
			candidates.append(index)
	else:
		# Fallen trunks can extend up to roughly half a tree height from their
		# base, so include a generous one-cell safety border around the sweep.
		var padding = 12.0 + radius
		var min_cell = _tree_cell(Vector3(minf(a.x, b.x) - padding, 0, minf(a.y, b.y) - padding))
		var max_cell = _tree_cell(Vector3(maxf(a.x, b.x) + padding, 0, maxf(a.y, b.y) + padding))
		for cell_x in range(min_cell.x, max_cell.x + 1):
			for cell_z in range(min_cell.y, max_cell.y + 1):
				var nearby = tree_cells.get(Vector2i(cell_x, cell_z), [])
				for index in nearby:
					candidates.append(index)
	for index in candidates:
		var c = flat(trees[index])
		var d = c
		var width = 0.2
		if fallen.has(index):
			var f: Dictionary = fallen[index]
			d += flat(f.direction) * forest_data[index].height * 0.64 * sin(smoothstep(0, 1.3, f.age) * PI * 0.5)
			width = 0.35
		var padding = radius + width
		# A growing fallen trunk can overlap a parked car. Permit motion out of
		# that volume, while retaining swept collision when approaching it.
		if allow_escape:
			var nearest = Geometry2D.get_closest_point_to_segment(a, c, d)
			var outward = a - nearest
			var start_distance = outward.length()
			var end_distance = b.distance_to(Geometry2D.get_closest_point_to_segment(b, c, d))
			if start_distance < padding and end_distance > start_distance + 0.0000001 and outward.dot(b - a) >= 0:
				continue
		if maxf(a.x, b.x) + padding < minf(c.x, d.x) or minf(a.x, b.x) - padding > maxf(c.x, d.x) or maxf(a.y, b.y) + padding < minf(c.y, d.y) or minf(a.y, b.y) - padding > maxf(c.y, d.y):
			continue
		if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
			return index
		var distance = minf(a.distance_to(Geometry2D.get_closest_point_to_segment(a, c, d)), b.distance_to(Geometry2D.get_closest_point_to_segment(b, c, d)))
		distance = minf(distance, c.distance_to(Geometry2D.get_closest_point_to_segment(c, a, b)))
		distance = minf(distance, d.distance_to(Geometry2D.get_closest_point_to_segment(d, a, b)))
		if distance < radius + width:
			return index
	return -1
