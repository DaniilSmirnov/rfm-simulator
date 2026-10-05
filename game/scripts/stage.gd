extends Node3D
class_name RallyStage

const LENGTH = 840.0
const STEP = 4.0
const WIDTH = 7.4
var points: PackedVector3Array = []
var clearings: Array[Vector3] = []
var trees: Array[Vector3] = []
var rng = RandomNumberGenerator.new()

func _init() -> void:
	for i in range(int(LENGTH / STEP) + 1):
		var s = i * STEP
		points.append(Vector3(sin(s / 90.0) * 38.0 + sin(s / 38.0) * 9.0, 5.0 + s * 0.024 + sin(s / 58.0) * 3.7, -s))
	for s in [140.0, 310.0, 505.0, 690.0]:
		clearings.append(at(s) + side(s) * (13.0 if s < 500 else -13.0))

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
	if road_distance(pos) > WIDTH * 0.55:
		return 0.48
	return 0.42 if int(road_s(pos) / STEP) % 13 == 7 else 0.78

func ground(pos: Vector3) -> float:
	var s = road_s(pos)
	var p = at(s)
	var distance = road_distance(pos)
	var slope = maxf(0, distance - 10.0)
	var height = p.y + roughness(s) * (1.0 - smoothstep(3.7, 8.0, distance)) + sin(pos.x * 0.07 + s * 0.013) * slope * 0.08 + slope * 0.20
	for clearing in clearings:
		var d = Vector2(pos.x - clearing.x, pos.z - clearing.z).length()
		height = lerpf(clearing.y, height, smoothstep(7, 16, d))
	return height

func build() -> void:
	rng.seed = 7102026
	_build_terrain()
	_build_road()
	var forest: Array[Dictionary] = []
	for i in range(780):
		var p = Vector3(rng.randf_range(-150, 150), 0, rng.randf_range(-LENGTH - 65, 50))
		if road_distance(p) < 9:
			continue
		var in_clearing = false
		for c in clearings:
			if Vector2(p.x - c.x, p.z - c.z).length() < 11:
				in_clearing = true
		if in_clearing:
			continue
		p.y = ground(p)
		trees.append(p)
		forest.append({"position": p, "height": rng.randf_range(6, 13), "shade": rng.randf_range(-0.025, 0.045)})
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
		RallyProps.cylinder(self, p, rng.randf_range(120, 180), 0, rng.randf_range(130, 210), Color("697d70"), 5)

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
				st.set_color(Color(0.32, 0.38, 0.25).lightened(rng.randf_range(-0.07, 0.07)))
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
			st.set_color(Color("9d896b").lightened(rng.randf_range(-0.065, 0.045)))
			v.y = ground(v) + 0.04
			st.add_vertex(v)
		# Broken muddy wheel tracks, shallow puddles.
		if i % 12 == 0:
			for offset in [-1.0, 1.0]:
				var p = at(s) + side(s) * offset
				p.y = ground(p)
				var rut = RallyProps.box(self, p + Vector3(0, 0.07, 0), Vector3(0.5, 0.025, 2.7), Color("77654c"))
				rut.rotation.y = atan2(-direction(s).x, -direction(s).z)
		if i % 52 == 28:
			var p = at(s) + side(s) * 1.5
			p.y = ground(p)
			var puddle = RallyProps.cylinder(self, p + Vector3(0, 0.10, 0), 1.1, 1.1, 0.025, Color("56645d"), 9)
			puddle.scale.z = 1.7
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
		for i in range(forest.size()):
			var tree_data = forest[i]
			var h: float = tree_data.height
			var radius = 0.2 if layer == 0 else h * (0.28 - (layer - 1) * 0.055)
			var height = h * (0.64 if layer == 0 else 0.49)
			var y = h * (0.32 if layer == 0 else 0.47 + (layer - 1) * 0.18)
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(radius, height, radius)), tree_data.position + Vector3(0, y, 0)))
			var shade: float = tree_data.shade
			mm.set_instance_color(i, Color("67543d") if layer == 0 else Color(0.17 + shade, 0.28 + shade, 0.21 + shade))
		var instance = MultiMeshInstance3D.new()
		instance.name = "ForestLayer%d" % layer
		instance.multimesh = mm
		add_child(instance)
