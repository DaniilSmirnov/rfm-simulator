extends Node3D
class_name RallyStage

var officials: Node3D
const Officials = preload("res://scripts/course_officials.gd")

const City = preload("res://scripts/vineyard.gd")
var city: Node3D
const LENGTH = 840.0
const STEP = 4.0
const WIDTH = 7.4
const TREE_CELL_SIZE = 16.0
const STAGES = ["Лесной перевал · гравий", "Зимний Турини · снег и лёд", "Виноградники · европейская деревня"]
var variant = 0
var winter = false
var urban = false
var points: PackedVector3Array = []
var clearings: Array[Vector3] = []
var trails: Array[Dictionary] = []
var woodland_details: Dictionary = {}
var collectibles: Array[Dictionary] = []
var harvested: Dictionary = {}
var collectible_parts: Dictionary = {}
var rocks: Array[Dictionary] = []
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
	urban = variant == 2
	for i in range(int(LENGTH / STEP) + 1):
		var s = i * STEP
		if winter:
			points.append(Vector3(sin(s / 48.0) * 58.0 + sin(s / 115.0) * 14.0, 18.0 + s * 0.085 + sin(s / 36.0) * 5.0, -s))
		elif urban:
			points.append(urban_at(s))
		else:
			points.append(Vector3(sin(s / 90.0) * 38.0 + sin(s / 38.0) * 9.0, 5.0 + s * 0.024 + sin(s / 58.0) * 3.7, -s))
	for s in [140.0, 310.0, 505.0, 690.0]:
		if winter:
			clearings.append(at(s) + side(s) * (13.0 if s < 500 else -13.0))
			continue
		if urban:
			var parking_s = [140.0, 310.0, 505.0, 770.0][clearings.size()]
			var parking_side = 1.0 if clearings.is_empty() else -1.0
			var parking = at(parking_s) + side(parking_s) * parking_side * 10.5
			parking.y = at(parking_s).y + 0.08
			clearings.append(parking)
			continue
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
	if urban:
		return sin(s * 3.4) * 0.014 if village(s) else sin(s * 0.8) * 0.018
	# Broad crests plus broken ruts; deterministic across all room members.
	return sin(s * 0.46) * 0.075 + sin(s * 1.13) * 0.035 + pow(maxf(0, cos((s - 32.0) * TAU / 46.0)), 10) * 0.55

func grip(pos: Vector3) -> float:
	if urban:
		return (0.86 if village(road_s(pos)) else 1.02) if road_distance(pos) < WIDTH * 0.55 else 0.58
	if winter:
		if road_distance(pos) > WIDTH * 0.55:
			return 0.32
		return 0.22 if int(road_s(pos) / 32) % 3 == 1 else 0.47
	if road_distance(pos) > WIDTH * 0.55:
		return 0.48
	return 0.42 if int(road_s(pos) / STEP) % 13 == 7 else 0.78

func ground(pos: Vector3) -> float:
	if urban:
		var s = road_s(pos)
		var p = at(s)
		var distance = road_distance(pos)
		if village(s):
			var junction = absf(s - 370.0) <= 3.0 or absf(s - 500.0) <= 3.0
			return 2.36 if not junction and distance > 3.75 and distance < 6.45 else 2.0
		var hillside = maxf(distance - 6.0, 0) * 0.12
		var height = p.y + hillside + sin(pos.x * 0.075 + s * 0.025) * minf(hillside * 0.2, 1.5)
		for parking in clearings:
			var d = flat(pos).distance_to(flat(parking))
			height = lerpf(parking.y, height, smoothstep(5.0, 11.0, d))
		return height + roughness(s) * (1.0 - smoothstep(3.5, 8.0, distance))
	var s = road_s(pos)
	var p = at(s)
	var distance = road_distance(pos)
	var slope = maxf(0, distance - 10.0)
	var height = p.y + roughness(s) * (1.0 - smoothstep(3.7, 8.0, distance)) + sin(pos.x * 0.07 + s * 0.013) * slope * 0.08 + slope * (0.08 if urban else 0.20)
	if variant == 0:
		height += forest_relief(pos, distance)
	if urban:
		height = p.y + sin(pos.x * 0.12 + s * 0.04) * 0.025 + slope * 0.08
	if winter:
		height += slope * 0.42 + sin(s / 85.0) * slope * 0.15
	for clearing in clearings:
		var d = Vector2(pos.x - clearing.x, pos.z - clearing.z).length()
		height = lerpf(clearing.y, height, smoothstep(7.0 if winter else 5.5, 16.0 if winter else 11.5, d))
	if not winter:
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
	for i in range(100 if urban else (520 if winter else 7600)):
		var p = Vector3(rng.randf_range(-150, 150), 0, rng.randf_range(-LENGTH - 65, 50))
		if urban:
			continue
		if road_distance(p) < 9:
			continue
		if not winter and trail_distance(p) < 3.2:
			continue
		var in_clearing = false
		for c in clearings:
			if Vector2(p.x - c.x, p.z - c.z).length() < (11.0 if winter else 8.5):
				in_clearing = true
		if in_clearing:
			continue
		p.y = ground(p)
		trees.append(p)
		forest.append({"position": p, "height": rng.randf_range(6, 13 if winter else 17), "shade": rng.randf_range(-0.025, 0.045)})
	forest_data = forest
	_rebuild_tree_index()
	_build_forest(forest)
	for i in range(0 if urban else 100):
		var s = rng.randf_range(20, LENGTH - 15)
		var p = at(s) + side(s) * rng.randf_range(-6, 6)
		if road_distance(p) < 4.3:
			continue
		p.y = ground(p)
		var radius = rng.randf_range(0.3, 1)
		var rock = RallyProps.cylinder(self, p + Vector3(0, 0.2, 0), radius, 0.18, 0.65, Color("7d8070"), 5)
		rocks.append({"pos": p, "radius": radius, "height": 0.75})
		rock.rotation.z = rng.randf_range(-0.3, 0.3)
	if variant == 0:
		_build_woodland_details()
	if urban:
		_build_city()
	for i in range(clearings.size()):
		var c = clearings[i]
		if urban:
			# Vineyard spectator spots are ordinary roadside/courtyard places.
			# Keep the gameplay positions, but do not build a separate parking entity.
			continue
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
	for i in range(0 if urban else 18):
		var p = Vector3((-1 if i % 2 == 0 else 1) * rng.randf_range(220, 340), 30, -i * 65.0)
		RallyProps.cylinder(self, p, rng.randf_range(120, 180), 0, rng.randf_range(220, 340) if winter else rng.randf_range(130, 210), Color("c3d1db") if winter else Color("697d70"), 5)

	officials = Officials.new()
	officials.stage = self
	add_child(officials)
	officials.build()

func _build_city() -> void:
	city = City.new()
	city.stage = self
	add_child(city)
	city.build()

func _build_terrain() -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in range(-920, 81, 4):
		for x in range(-204, 204, 4):
			# Resolve narrow roadside ditches without subdividing the whole map.
			var step = 2 if variant == 0 and road_distance(Vector3(x + 2, 0, z + 2)) < 12 else 4
			for dz in range(0, 4, step):
				for dx in range(0, 4, step):
					var a = Vector3(x + dx, 0, z + dz)
					var b = a + Vector3(step, 0, 0)
					var c = a + Vector3(0, 0, step)
					var d = a + Vector3(step, 0, step)
					for v in [a, b, c, b, d, c]:
						v.y = ground(v) - 0.25
						var color = Color("b6c9d3") if winter else Color(0.32, 0.38, 0.25)
						if variant == 0:
							var patch = (sin(v.x * 0.065) * sin(v.z * 0.041) + 1.0) * 0.5
							color = Color("514a32").lerp(Color("485c36"), patch)
							if road_distance(v) > 4.5 and road_distance(v) < 8:
								color = color.darkened(0.16)
						st.set_color(color.lightened(rng.randf_range(-0.07, 0.07)))
						st.add_vertex(v)
	st.generate_normals()
	var n = MeshInstance3D.new()
	n.mesh = st.commit()
	var mat = RallyProps.material(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	n.material_override = mat
	add_child(n)

func draw_base_road_surface(s: float) -> bool:
	# The village has its own explicit cobblestone mesh; do not leave asphalt
	# underneath it where it can show through between individual stones.
	return not village(s)

func _build_road() -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(int(LENGTH)):
		var s = float(i)
		var a = at(s) + side(s) * WIDTH / 2
		var b = at(s) - side(s) * WIDTH / 2
		var c = at(s + 1) + side(s + 1) * WIDTH / 2
		var d = at(s + 1) - side(s + 1) * WIDTH / 2
		if draw_base_road_surface(s):
			for v in [a, b, c, b, d, c]:
				st.set_color((Color("708a9c") if winter else (Color("525757") if urban else Color("9d896b"))).lightened(rng.randf_range(-0.065, 0.045)))
				v.y = ground(v) + 0.04
				st.add_vertex(v)
		# Broken muddy wheel tracks, shallow puddles.
		if not urban and i % 12 == 0:
			for offset in [-1.0, 1.0]:
				var p = at(s) + side(s) * offset
				p.y = ground(p)
				var rut = RallyProps.box(self, p + Vector3(0, 0.07, 0), Vector3(0.5, 0.025, 2.7), Color("586974") if winter else Color("77654c"))
				rut.rotation.y = atan2(-direction(s).x, -direction(s).z)
		if not urban and i % 52 == 28:
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
func shared_tree_mesh(layer: int) -> CylinderMesh:
	var mesh = CylinderMesh.new()
	mesh.bottom_radius = 1.0
	mesh.top_radius = 0.65 if layer == 0 else 0.0
	mesh.height = 1.0
	mesh.radial_segments = 5 if layer == 0 else 6
	mesh.rings = 1
	return mesh

func shared_tree_pose(position: Vector3, height_value: float, layer: int, basis: Basis = Basis.IDENTITY) -> Transform3D:
	var radius = 0.2 if layer == 0 else height_value * (0.28 - (layer - 1) * 0.055)
	var layer_height = height_value * (0.64 if layer == 0 else 0.49)
	var y = height_value * (0.32 if layer == 0 else 0.47 + (layer - 1) * 0.18)
	return Transform3D(basis * Basis.from_scale(Vector3(radius, layer_height, radius)), position + basis * Vector3(0, y, 0))

func shared_tree_color(layer: int, shade: float = 0.0, snowy: bool = false) -> Color:
	if layer == 0:
		return Color("67543d")
	if snowy:
		return (Color("78958a") if layer == 1 else Color("b8cdd3")).lightened(shade)
	return Color(0.17 + shade, 0.28 + shade, 0.21 + shade)

func shared_grass_color(value: float) -> Color:
	return Color("4f6634").lerp(Color("91905a"), clampf(value, 0.0, 1.0) * 0.7)

func shared_stone_mesh() -> SphereMesh:
	var mesh = SphereMesh.new()
	mesh.radial_segments = 5
	mesh.rings = 2
	return mesh

func shared_stone_pose(position: Vector3, radius: float, yaw: float = 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(radius * 2.0, radius, radius * 1.7)), position)

func shared_stone_color(lightness: float = 0.0) -> Color:
	return Color("7e806e").lightened(clampf(lightness, -0.10, 0.12))

func _build_forest(forest: Array[Dictionary]) -> void:
	for layer in range(4):
		var mesh = shared_tree_mesh(layer)
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
			mm.set_instance_transform(i, shared_tree_pose(tree_data.position, float(tree_data.height), layer))
			mm.set_instance_color(i, shared_tree_color(layer, float(tree_data.shade), winter))
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

# Earliest swept horizontal circle contact. Height allows cars to jump over rocks.
# Escape handling prevents an overlapping spawn or a low-speed bump from trapping a car.
func rock_hit(start: Vector3, end: Vector3, radius: float, allow_escape: bool = true) -> Dictionary:
	var a = flat(start)
	var b = flat(end)
	var travel = b - a
	var best: Dictionary = {}
	var earliest = INF
	for rock in rocks:
		if minf(start.y, end.y) > rock.pos.y + rock.height:
			continue
		var center = flat(rock.pos)
		var padding: float = rock.radius + radius
		var offset = a - center
		var distance = offset.length()
		var t = 0.0
		if distance < padding:
			if allow_escape and (b - center).length() > distance + 0.0000001 and offset.dot(travel) >= 0:
				continue
		else:
			var length_squared = travel.length_squared()
			if length_squared < 0.00000001:
				continue
			var projection = offset.dot(travel)
			var discriminant = projection * projection - length_squared * (offset.length_squared() - padding * padding)
			if discriminant < 0:
				continue
			t = (-projection - sqrt(discriminant)) / length_squared
			if t < 0 or t > 1:
				continue
		if lerpf(start.y, end.y, t) > rock.pos.y + rock.height:
			continue
		if t >= earliest:
			continue
		var point = a + travel * t
		var normal = (point - center).normalized()
		if normal.length_squared() < 0.01:
			normal = -travel.normalized() if travel.length_squared() > 0.000001 else Vector2.RIGHT
		point = center + normal * (padding + 0.025)
		var position = start.lerp(end, t)
		position.x = point.x
		position.z = point.y
		earliest = t
		best = {"position": position, "normal": Vector3(normal.x, 0, normal.y), "time": t}
	return best

func forest_relief(pos: Vector3, distance: float) -> float:
	var hills = (sin(pos.x * 0.043 + pos.z * 0.017) * 1.5 + sin(pos.z * 0.063 - pos.x * 0.031) * 0.85 + sin(pos.x * 0.115) * sin(pos.z * 0.087) * 0.55) * smoothstep(10.0, 24.0, distance)
	var ditch = (1.0 - smoothstep(0.45, 1.9, absf(distance - 6.4))) * 0.85
	ditch *= smoothstep(2.2, 4.0, trail_distance(pos))
	return hills - ditch

func woodland_spot(pos: Vector3, padding: float = 0.0) -> bool:
	if road_distance(pos) < 9.0 + padding or trail_distance(pos) < 3.2 + padding:
		return false
	for clearing in clearings:
		if flat(pos).distance_to(flat(clearing)) < 8.5 + padding:
			return false
	return true

func _detail_batch(name: String, mesh: Mesh, poses: Array, colors: Array, indices: Array = []) -> void:
	if name in ["ForestGrass", "ForestBushes", "ForestBerryBushes", "ForestBerries", "ForestBushStems", "VineyardGrapes", "VineyardLeaves", "VineyardRoadsideGrass", "VineyardRoadsideStones", "VineyardRoadsideBushes", "VillageForestTreeLayer0", "VillageForestTreeLayer1", "VillageForestTreeLayer2", "VillageForestTreeLayer3", "VillageForestGrass", "VillageForestStones", "VillageForestBoulders", "VillageForestBushes", "VillageForestBerryBushes", "VillageForestBerries", "VillageGrass", "VillageStones"]:
		var cells = {}
		for i in range(poses.size()):
			var origin: Vector3 = poses[i].origin
			var key = Vector2i(floori(origin.x / 64), floori(origin.z / 64))
			if not cells.has(key):
				cells[key] = {"poses": [], "colors": [], "indices": []}
			cells[key].poses.append(poses[i])
			cells[key].colors.append(colors[i])
			cells[key].indices.append(i if indices.is_empty() else indices[i])
		for key in cells:
			var prefix = "GrassTile" if name == "ForestGrass" else name + "_Tile"
			_detail_batch(prefix + "_%d_%d" % [key.x, key.y], mesh, cells[key].poses, cells[key].colors, cells[key].indices)
		woodland_details[name] = poses.size()
		return
	var mat = RallyProps.material(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mm = MultiMesh.new()
	if name in ["FlyAgaricCaps", "ToadstoolCaps"]:
		mat.albedo_texture = RallyProps.MUSHROOM_TEXTURES["fly_agaric" if name == "FlyAgaricCaps" else "toadstool"]
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = poses.size()
	var center = Vector3.ZERO
	if (name.begins_with("GrassTile") or name.contains("_Tile_")) and not poses.is_empty():
		center = poses[0].origin
	for i in range(poses.size()):
		var pose: Transform3D = poses[i]
		pose.origin -= center
		mm.set_instance_transform(i, pose)
		mm.set_instance_color(i, colors[i])
		var source = name.get_slice("_Tile", 0)
		if source in ["ForestBerries", "VillageForestBerries", "MushroomCaps", "FlyAgaricCaps", "ToadstoolCaps", "MushroomStems", "VineyardGrapes"]:
			if not collectible_parts.has(source):
				collectible_parts[source] = {}
			collectible_parts[source][i if indices.is_empty() else indices[i]] = {"mesh": mm, "instance": i, "pose": pose, "hidden": false}
	var node = MultiMeshInstance3D.new()
	node.name = name
	node.position = center
	if name.begins_with("GrassTile") or name.contains("_Tile_"):
		node.visibility_range_end = 70 if name.begins_with("VineyardGrapes") else 160
		node.visibility_range_end_margin = 15
	node.multimesh = mm
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	woodland_details[name] = poses.size()

func _grass_mesh() -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(5):
		var yaw = i * TAU / 5
		var base = Vector3(0.10, 0, 0).rotated(Vector3.UP, yaw)
		for v in [base + Vector3(-0.09, 0, 0).rotated(Vector3.UP, yaw), base + Vector3(0.09, 0, 0).rotated(Vector3.UP, yaw), base + Vector3(0.12, 0.75 + (i % 2) * 0.25, 0).rotated(Vector3.UP, yaw)]:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()

func _build_woodland_details() -> void:
	var detail_rng = RandomNumberGenerator.new()
	detail_rng.seed = 6022026
	var grass_poses: Array = []
	var grass_colors: Array = []
	var stone_poses: Array = []
	var stone_colors: Array = []
	var cap_poses: Array = []
	var cap_colors: Array = []
	var poison_caps = {"fly_agaric": [], "toadstool": []}
	var stem_poses: Array = []
	var stem_colors: Array = []
	var mound_poses: Array = []
	var mound_colors: Array = []
	var twig_poses: Array = []
	var twig_colors: Array = []
	var boulder_poses: Array = []
	var boulder_colors: Array = []
	for i in range(30000):
		var p = Vector3(detail_rng.randf_range(-145, 145), 0, detail_rng.randf_range(-LENGTH, 0))
		if not woodland_spot(p):
			continue
		p.y = ground(p) - 0.20
		var size = detail_rng.randf_range(0.25, 0.65)
		grass_poses.append(Transform3D(Basis(Vector3.UP, detail_rng.randf() * TAU).scaled(Vector3(size * 1.8, size, size * 1.8)), p))
		grass_colors.append(shared_grass_color(detail_rng.randf()))
	for i in range(4000):
		var along = detail_rng.randf_range(20, LENGTH - 20)
		var p = at(along) + side(along) * detail_rng.randf_range(13, 125) * (-1 if i % 2 else 1)
		var radius = detail_rng.randf_range(0.8, 2.4)
		if not woodland_spot(p, radius) or obstacle_hit(p, p, radius + 0.3) >= 0 or not rock_hit(p, p, radius, false).is_empty():
			continue
		p.y = ground(p)
		var height = detail_rng.randf_range(0.7, 2.5)
		boulder_poses.append(Transform3D(Basis(Vector3.UP, detail_rng.randf() * TAU).scaled(Vector3(radius * 2, height, radius * 1.7)), p + Vector3(0, height * 0.35, 0)))
		boulder_colors.append(Color("697064").lightened(detail_rng.randf_range(-0.12, 0.12)))
		rocks.append({"pos": p, "radius": radius, "height": height * 0.9, "forest": true})
		if boulder_poses.size() >= 240:
			break
	for i in range(1600):
		var p = Vector3(detail_rng.randf_range(-135, 135), 0, detail_rng.randf_range(-LENGTH, 0))
		if not woodland_spot(p):
			continue
		p.y = ground(p) - 0.18
		var radius = detail_rng.randf_range(0.12, 0.35)
		stone_poses.append(shared_stone_pose(p, radius, detail_rng.randf() * TAU))
		stone_colors.append(shared_stone_color(detail_rng.randf_range(-0.10, 0.12)))
	# Clumped undergrowth rather than an even carpet; berry bushes use the
	# same seeded generator on every client. Keep picnic spaces and paths open.
	var bush_poses: Array = []
	var bush_colors: Array = []
	var berry_bush_poses: Array = []
	var berry_bush_colors: Array = []
	var berry_poses: Array = []
	var berry_colors: Array = []
	var bush_stem_poses: Array = []
	var bush_stem_colors: Array = []
	for i in range(2000):
		var p = Vector3(detail_rng.randf_range(-140, 140), 0, detail_rng.randf_range(-LENGTH, 0))
		var patch = sin(p.x * 0.075 + p.z * 0.027) * sin(p.z * 0.054)
		if patch < -0.35 or not woodland_spot(p, 1.4) or not rock_hit(p, p, 1.1, false).is_empty():
			continue
		p.y = ground(p) - 0.22
		var height = detail_rng.randf_range(0.55, 1.35)
		var bearing = detail_rng.randf() * TAU
		var berry_bush = i % 3 == 0
		var berry_begin = berry_poses.size()
		bush_stem_poses.append(Transform3D(Basis.from_scale(Vector3(0.06, height * 0.7, 0.06)), p + Vector3(0, height * 0.35, 0)))
		bush_stem_colors.append(Color("635039"))
		for branch in range(3):
			var angle = bearing + branch * TAU / 3
			var center = p + Vector3(cos(angle) * height * 0.3, height * (0.55 + branch * 0.08), sin(angle) * height * 0.3)
			var pose = Transform3D(Basis(Vector3.UP, angle).scaled(Vector3(height * 0.95, height * 0.7, height * 0.85)), center)
			var color = Color("3c5830").lerp(Color("6c8040"), detail_rng.randf())
			if berry_bush:
				berry_bush_poses.append(pose)
				berry_bush_colors.append(color.darkened(0.08))
				for fruit in range(3):
					var fruit_angle = angle + fruit * 1.8
					var fruit_pos = center + Vector3(cos(fruit_angle) * height * 0.38, height * 0.18, sin(fruit_angle) * height * 0.34)
					berry_poses.append(Transform3D(Basis.from_scale(Vector3.ONE * 0.09), fruit_pos))
					berry_colors.append(Color("c34237") if i % 2 == 0 else Color("383353"))
			else:
				bush_poses.append(pose)
				bush_colors.append(color)
		if berry_bush:
			var fruit_indices: Array = []
			for fruit_index in range(berry_begin, berry_poses.size()):
				fruit_indices.append(fruit_index)
			collectibles.append({"kind": "berries", "pos": Vector3(p.x, ground(p), p.z), "quantity": 3, "parts": {"ForestBerries": fruit_indices}})
	var leaves = SphereMesh.new()
	leaves.radial_segments = 6
	leaves.rings = 2
	_detail_batch("ForestBushes", leaves, bush_poses, bush_colors)
	_detail_batch("ForestBerryBushes", leaves, berry_bush_poses, berry_bush_colors)
	var berry_mesh = SphereMesh.new()
	berry_mesh.radial_segments = 5
	berry_mesh.rings = 2
	_detail_batch("ForestBerries", berry_mesh, berry_poses, berry_colors)
	var bush_stem_mesh = CylinderMesh.new()
	bush_stem_mesh.height = 1
	bush_stem_mesh.bottom_radius = 1
	bush_stem_mesh.top_radius = 0.5
	bush_stem_mesh.radial_segments = 4
	bush_stem_mesh.rings = 1
	_detail_batch("ForestBushStems", bush_stem_mesh, bush_stem_poses, bush_stem_colors)
	for i in range(300):
		var along = detail_rng.randf_range(20, LENGTH - 20)
		var p = at(along) + side(along) * detail_rng.randf_range(10, 38) * (-1 if i % 2 else 1)
		if not woodland_spot(p) or not rock_hit(p, p, 0.5, false).is_empty():
			continue
		for j in range(3):
			var at = p + Vector3(detail_rng.randf_range(-0.45, 0.45), 0, detail_rng.randf_range(-0.45, 0.45))
			at.y = ground(at) + 0.02
			var size = detail_rng.randf_range(0.10, 0.22)
			var species = "fly_agaric" if i % 10 == 4 else ("toadstool" if i % 10 == 7 else "edible")
			var cap_layer = "FlyAgaricCaps" if species == "fly_agaric" else ("ToadstoolCaps" if species == "toadstool" else "MushroomCaps")
			var cap_index = cap_poses.size() if species == "edible" else poison_caps[species].size()
			collectibles.append({"kind": "mushrooms", "species": species, "name": "мухомор" if species == "fly_agaric" else ("поганка" if species == "toadstool" else "гриб"), "pos": Vector3(at.x, ground(at), at.z), "quantity": 1, "parts": {cap_layer: [cap_index], "MushroomStems": [stem_poses.size()]}})
			stem_poses.append(Transform3D(Basis.from_scale(Vector3(size * 0.20, size, size * 0.20)), at + Vector3(0, size * 0.5, 0)))
			stem_colors.append(Color("c5baa1"))
			var cap_pose = Transform3D(Basis.from_scale(Vector3(size * 1.4, size * 0.55, size * 1.4)), at + Vector3(0, size, 0))
			if species == "edible":
				cap_poses.append(cap_pose)
				cap_colors.append(Color("b87743"))
			else:
				poison_caps[species].append(cap_pose)
	for i in range(110):
		var along = detail_rng.randf_range(20, LENGTH - 20)
		var p = at(along) + side(along) * detail_rng.randf_range(12, 45) * (-1 if i % 2 else 1)
		if not woodland_spot(p, 0.8) or not rock_hit(p, p, 0.8, false).is_empty():
			continue
		p.y = ground(p) - 0.23
		var radius = detail_rng.randf_range(0.45, 0.9)
		var height = detail_rng.randf_range(0.35, 0.75)
		mound_poses.append(Transform3D(Basis.from_scale(Vector3(radius, height, radius)), p + Vector3(0, height * 0.5, 0)))
		mound_colors.append(Color("66513a").lightened(detail_rng.randf_range(-0.06, 0.06)))
		for j in range(4):
			var twig = p + Vector3(detail_rng.randf_range(-0.25, 0.25), height * 0.55, detail_rng.randf_range(-0.25, 0.25))
			twig_poses.append(Transform3D(Basis.from_euler(Vector3(0.9, detail_rng.randf() * TAU, 0.7)).scaled(Vector3(0.02, radius * 0.65, 0.02)), twig))
			twig_colors.append(Color("493c2b"))
	var boulder = SphereMesh.new()
	boulder.radial_segments = 7
	boulder.rings = 3
	_detail_batch("ForestBoulders", boulder, boulder_poses, boulder_colors)
	_detail_batch("ForestPebbles", shared_stone_mesh(), stone_poses, stone_colors)
	_detail_batch("ForestGrass", _grass_mesh(), grass_poses, grass_colors)
	var stem = CylinderMesh.new()
	stem.height = 1
	stem.bottom_radius = 1
	stem.top_radius = 0.7
	stem.radial_segments = 5
	stem.rings = 1
	_detail_batch("MushroomStems", stem, stem_poses, stem_colors)
	var cap = SphereMesh.new()
	cap.radial_segments = 12
	cap.rings = 6
	_detail_batch("MushroomCaps", cap, cap_poses, cap_colors)
	for species in poison_caps:
		var colors: Array = []
		colors.resize(poison_caps[species].size())
		colors.fill(Color.WHITE)
		_detail_batch("FlyAgaricCaps" if species == "fly_agaric" else "ToadstoolCaps", cap, poison_caps[species], colors)
	var mound = CylinderMesh.new()
	mound.height = 1
	mound.bottom_radius = 1
	mound.top_radius = 0.12
	mound.radial_segments = 9
	mound.rings = 1
	_detail_batch("AntHills", mound, mound_poses, mound_colors)
	var twig = CylinderMesh.new()
	twig.height = 1
	twig.bottom_radius = 1
	twig.top_radius = 0.4
	twig.radial_segments = 4
	twig.rings = 1
	_detail_batch("AntHillTwigs", twig, twig_poses, twig_colors)

func village(s: float) -> bool:
	return urban and s >= 300.0 and s <= 570.0

func urban_at(s: float) -> Vector3:
	var village_blend = smoothstep(260.0, 300.0, s) * (1.0 - smoothstep(570.0, 610.0, s))
	var country_x = sin(s / 85.0) * 34.0 + sin(s / 43.0) * 10.0
	var village_x = sin((s - 300.0) / 100.0) * 14.0
	var height = 2.0 + (1.0 - village_blend) * (7.0 + sin(s / 95.0) * 3.0 + s * 0.004)
	return Vector3(lerpf(country_x, village_x, village_blend), height, -s)

func urban_nearest(pos: Vector3) -> Dictionary:
	var best = INF
	var station = 0.0
	var p = flat(pos)
	for i in range(points.size() - 1):
		var a = flat(points[i])
		var segment = flat(points[i + 1]) - a
		var ratio = clampf((p - a).dot(segment) / maxf(segment.length_squared(), 0.000001), 0, 1)
		var distance = p.distance_squared_to(a + segment * ratio)
		if distance < best:
			best = distance
			station = (i + ratio) * STEP
	return {"s": station, "distance": sqrt(best)}

func rally_speed(s: float) -> float:
	if not urban:
		return 27.0
	return 15.0 if village(s) else 27.0

# Collectible identifiers follow deterministic generation order and are shared by
# every room member. Harvesting hides the existing instances without new nodes.
func nearest_collectible(pos: Vector3, reach: float = 1.8) -> int:
	var best = reach
	var found = -1
	for i in range(collectibles.size()):
		if harvested.has(i):
			continue
		var item: Dictionary = collectibles[i]
		var distance = flat(pos).distance_to(flat(item.pos))
		if distance < best and absf(pos.y - item.pos.y) < 2.0:
			best = distance
			found = i
	return found

func harvest(id: int) -> bool:
	if id < 0 or id >= collectibles.size() or harvested.has(id):
		return false
	harvested[id] = true
	var item: Dictionary = collectibles[id]
	for layer in item.parts:
		for index in item.parts[layer]:
			var part: Dictionary = collectible_parts.get(layer, {}).get(int(index), {})
			if not part.is_empty():
				var pose: Transform3D = part.pose
				pose.basis = Basis.from_scale(Vector3.ZERO)
				part.pose = pose
				part.hidden = true
				part.mesh.set_instance_transform(part.instance, pose)
	return true

func apply_harvested(ids: Array) -> void:
	for id in ids:
		harvest(int(id))
