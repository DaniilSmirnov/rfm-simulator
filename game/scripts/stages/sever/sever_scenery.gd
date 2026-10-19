extends RefCounted
const Movable = preload("res://scripts/core/prop_registry.gd")
const Props = preload("res://scripts/core/props.gd")
const Records = preload("res://scripts/stages/stage_records.gd")
const MeshMerge = preload("res://scripts/core/mesh_merge.gd")
const Carpentry = preload("res://scripts/stages/sever/sever_carpentry.gd")
const Izba = preload("res://scripts/stages/sever/sever_izba.gd")
const Church = preload("res://scripts/stages/sever/sever_church.gd")
const Bridge = preload("res://scripts/stages/sever/sever_bridge.gd")
const LoadPacer = preload("res://scripts/core/load_pacer.gd")
# Static scenery of «Поречье»: izbas along the street with front-garden
# palisades, the tent-roofed church, a crane well, a log granary, the bridge
# over the stream gully, haystacks on poles in the fields, snow stakes and the
# birch and spruce groves. Positions are deterministic: every room member
# builds the same village.
const SNOW = Color("eef2f2")
const LOGS = Color("6c5a47")
const FENCE = Color("6f6150")

var stage
var biome
var rng = RandomNumberGenerator.new()
var counts := {}
var houses: Array[Node3D] = []
var posts: Array = []
var post_colors: Array = []
var rails: Array = []
var rail_colors: Array = []

func build(owner_stage, owner_biome, cooperative: bool = false) -> void:
	stage = owner_stage
	biome = owner_biome
	rng.seed = 19022026
	var root = Node3D.new()
	root.name = "SeverScenery"
	stage.add_child(root)
	for item in biome.HOUSES:
		if cooperative: await LoadPacer.tick(stage.get_tree())
		var house = Izba.build(stage, biome, root, item, rng)
		houses.append(house)
		_palisade(house, float(item[3]), float(item[4]))
	counts["houses"] = houses.size()
	if cooperative: await LoadPacer.tick(stage.get_tree())
	Church.build(stage, biome, root)
	_well(root)
	_granary(root)
	if cooperative: await LoadPacer.tick(stage.get_tree())
	Bridge.build(stage, biome, root, func(parent, name, poses, colors): _batch(parent, name, unit_box(), poses, colors))
	_village_sign(root)
	for item in biome.HAYSTACKS:
		_haystack(root, biome.place(item[0], item[1], item[2]))
	_roadside_posts(root)
	if cooperative: await LoadPacer.tick(stage.get_tree())
	_birches(root)
	if cooperative: await LoadPacer.tick(stage.get_tree())
	_spruces(root)
	if cooperative: await LoadPacer.tick(stage.get_tree())
	_batch(root, "FencePosts", unit_box(), posts, post_colors)
	_batch(root, "FenceRails", unit_box(), rails, rail_colors)
	for child in root.get_children():
		if cooperative: await LoadPacer.tick(stage.get_tree())
		if child is Node3D and not child.has_meta("unbatched"):
			MeshMerge.bake(child)
	stage.solids.index()

func _anchor(root: Node3D, name: String, at: Vector3, facing: Vector3) -> Node3D:
	var node = Node3D.new()
	node.name = name
	root.add_child(node)
	node.position = at
	node.rotation.y = atan2(facing.x, facing.z)
	return node

# ---------------------------------------------------------------- fences

# A front-garden palisade (палисадник) of pickets under the street windows.
func _palisade(house: Node3D, w: float, d: float) -> void:
	var front = d * 0.5 + 2.4
	var x = w * 0.5 + 0.35
	var corners = [Vector3(-x, 0, d * 0.5 + 0.3), Vector3(-x, 0, front), Vector3(x, 0, front), Vector3(x, 0, d * 0.5 + 0.3)]
	for i in range(3):
		_fence_run(house.position + house.basis * corners[i], house.position + house.basis * corners[i + 1])

func _fence_run(a: Vector3, b: Vector3) -> void:
	var length = Vector2(b.x - a.x, b.z - a.z).length()
	var pickets = maxi(2, int(length / 0.17))
	var across = (b - a).normalized().cross(Vector3.UP).normalized()
	for i in range(pickets + 1):
		var p = a.lerp(b, float(i) / pickets)
		p.y = stage.ground(p)
		var post = i % 10 == 0 or i == pickets
		var size = Vector3(0.12, 1.25, 0.12) if post else Vector3(0.09, 1.05, 0.025)
		posts.append(Transform3D(Basis((b - a).normalized() * size.x, Vector3.UP * size.y, across * size.z), p + Vector3.UP * (size.y * 0.5 - 0.05)))
		post_colors.append(FENCE.lightened(0.04 * sin(i * 1.7)) if not post else FENCE.darkened(0.15))
		if post:
			stage.rocks.append(Records.rock(p, 0.1, 1.2, Records.BARRIER))
	for y in [0.3, 0.8]:
		var pa = a + Vector3.UP * (stage.ground(a) - a.y + y)
		var pb = b + Vector3.UP * (stage.ground(b) - b.y + y)
		var along = pb - pa
		# Backed onto the pickets and 1.25 cm proud of the posts' faces.
		rails.append(Transform3D(Basis(along, Vector3.UP * 0.07, across * 0.06), (pa + pb) * 0.5 - across * 0.0425))
		rail_colors.append(FENCE.darkened(0.1))

# ---------------------------------------------------------------- landmarks

# Crane well (колодец-журавль): a log curb, a forked upright, the sweep beam
# pivoting on it with a counterweight on the short end, and the pole hanging
# from the long end down to the bucket above the curb.
func _well(root: Node3D) -> void:
	var pos = biome.place(biome.WELL.s, biome.WELL.side, biome.WELL.offset)
	var node = _anchor(root, "CraneWell", pos, stage.at(biome.WELL.s) - pos)
	node.position.y = stage.ground(pos)
	Carpentry.log_frame(node, Vector3(0, -0.3, 0), 1.2, 1.2, 1.25, LOGS)
	Props.box(node, Vector3(0, 0.98, 0), Vector3(1.0, 0.04, 1.0), Color("2b2723"))
	var pivot = Vector3(0, 4.1, -4.0)
	Props.box(node, Vector3(0, pivot.y * 0.5 - 0.2, pivot.z), Vector3(0.26, pivot.y + 0.4, 0.26), Color("5e4a35"))
	for sx in [-0.12, 0.12]:
		Props.box(node, pivot + Vector3(sx, 0.25, 0), Vector3(0.06, 0.5, 0.2), Color("5e4a35"))
	var angle = 0.42
	var dir = Vector3(0, sin(angle), cos(angle))
	var long_end = pivot + dir * (-pivot.z / cos(angle))
	var short_end = pivot - dir * 2.6
	Carpentry.log_between(node, short_end, long_end, 0.08, Color("6a5640"))
	Props.box(node, short_end + Vector3(0, -0.25, 0), Vector3(0.45, 0.5, 0.45), Color("55504a"))
	var bucket = Vector3(0, 1.45, 0)
	Carpentry.log_between(node, long_end, bucket + Vector3(0, 0.14, 0), 0.035, Color("7a6650"))
	Props.cylinder(node, bucket, 0.15, 0.18, 0.32, Color("8f9497"), 8)
	stage.solids.solid(node, Vector3(0, 0.5, 0), Vector3(1.5, 1.0, 1.5), "landmark")
	stage.rocks.append(Records.rock(node.position + node.basis * Vector3(0, 0, pivot.z), 0.2, pivot.y, Records.BARRIER))

# Log granary (амбар) on stone blocks, gable to the road, with a gallery under
# the front overhang of the roof.
func _granary(root: Node3D) -> void:
	var b = biome.BARN
	var pos = biome.place(b.s, b.side, b.offset)
	var node = _anchor(root, "VillageBarn", pos, stage.at(b.s) - pos)
	node.position.y = stage.ground(pos) + 0.45
	for x in [-2.2, 2.2]:
		for z in [-1.8, 0.0, 1.8]:
			Props.box(node, Vector3(x, -0.4, z), Vector3(0.5, 0.9, 0.5), Color("7c7a74"))
	Carpentry.log_frame(node, Vector3.ZERO, 5.0, 4.0, 2.9, Color("6f5f4c"))
	var ridge = Carpentry.gable_roof(node, 2.9, 5.0, -2.5, 3.6, 0.7, Color("5a5751"), 0.55)
	Carpentry.gable(node, 2.15, 5.0, 2.9, ridge - 0.1, 0.2, Color("7c6a54"))
	Carpentry.ridge_log(node, ridge, -2.5, 3.6, Color("4f4336"))
	for x in [-2.3, 2.3]:
		Props.box(node, Vector3(x, 1.3, 3.3), Vector3(0.16, 3.5, 0.16), Color("5e4a35"))
	Props.box(node, Vector3(0, 0.02, 2.8), Vector3(5.2, 0.12, 1.4), Color("7a6650"))
	Props.box(node, Vector3(0, 1.0, 2.15), Vector3(1.1, 1.8, 0.08), Color("4a3b2c"))
	stage.solids.solid(node, Vector3(0, 1.2, 0.5), Vector3(5.4, 3.0, 5.2), "building")

func _village_sign(root: Node3D) -> void:
	var pos = biome.place(biome.SIGN_S, 1.0, 5.5)
	var node = _anchor(root, "VillageSign", pos, stage.at(biome.SIGN_S) - pos)
	node.position.y = stage.ground(pos)
	for x in [-1.1, 1.1]:
		Props.cylinder(node, Vector3(x, 1.0, 0), 0.08, 0.08, 2.0, Color("4f4336"), 6)
	var board = Props.box(node, Vector3(0, 1.75, 0), Vector3(2.8, 0.7, 0.1), Color("e4ddc8"))
	Props.label_3d(board, Vector3(0, 0.08, 0.06), "ПОРЕЧЬЕ", 72, 0.0055, Color("2f4a34"))
	Props.label_3d(board, Vector3(0, -0.2, 0.06), "вологодская застава", 28, 0.0035, Color("4a4238"))
	Movable.register(stage.solids, node, 18, true)

# A haystack (стог) stacked round a pole, as left in the fields for winter.
func _haystack(root: Node3D, pos: Vector3) -> void:
	pos.y = stage.ground(pos)
	var node = Node3D.new()
	node.name = "Haystack"
	root.add_child(node)
	node.position = pos
	var height = rng.randf_range(3.0, 3.8)
	var radius = rng.randf_range(1.5, 1.8)
	var hay = Color("8d7650").lightened(rng.randf_range(-0.05, 0.05))
	Props.cylinder(node, Vector3(0, height * 0.22, 0), radius, radius * 1.05, height * 0.44, hay, 10)
	Props.faceted(node, Vector3(0, height * 0.52, 0), Vector3(radius * 2.08, height * 0.72, radius * 2.08), hay, 10, 6)
	Props.faceted(node, Vector3(0, height * 0.8, 0), Vector3(radius * 1.3, height * 0.24, radius * 1.3), SNOW, 10, 5)
	Props.cylinder(node, Vector3(0, height * 0.6, 0), 0.06, 0.04, height * 1.2, Color("5e4a35"), 5)
	stage.rocks.append(Records.rock(pos, radius, height))

# Wooden snow stakes mark the road edge where the fields are open.
func _roadside_posts(root: Node3D) -> void:
	var poses: Array = []
	var colors: Array = []
	for station in range(10, int(biome.LENGTH) - 10, 22):
		if biome.in_village(float(station)) or absf(float(station) - biome.BRIDGE_S) < 20.0:
			continue
		for side in [-1.0, 1.0]:
			var s = float(station)
			var p = stage.at(s) + stage.side(s) * side * (biome.road_width(s) * 0.5 + 2.4)
			if biome.reserved(p, 1.0):
				continue
			p.y = stage.base_ground(p)
			poses.append(Transform3D(Basis.from_scale(Vector3(0.06, 1.8, 0.06)), p + Vector3.UP * 0.75))
			colors.append(Color("5c4c38"))
	_batch(root, "SnowStakes", unit_box(), poses, colors)

# ---------------------------------------------------------------- batching

static func unit_box() -> BoxMesh:
	var mesh = BoxMesh.new()
	mesh.size = Vector3.ONE
	return mesh

static var _vertex_material: StandardMaterial3D

static func _batch(root: Node3D, name: String, mesh: Mesh, poses: Array, colors: Array) -> void:
	if poses.is_empty():
		return
	if _vertex_material == null:
		_vertex_material = StandardMaterial3D.new()
		_vertex_material.vertex_color_use_as_albedo = true
		_vertex_material.roughness = 0.9
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = poses.size()
	for i in range(poses.size()):
		mm.set_instance_transform(i, poses[i])
		mm.set_instance_color(i, colors[i])
	var node = MultiMeshInstance3D.new()
	node.name = name
	node.multimesh = mm
	node.material_override = _vertex_material
	node.set_meta("unbatched", true)
	root.add_child(node)

# ---------------------------------------------------------------- trees

func _grove(spread: float, clearance: float, per_grove: Vector2i, heights: Vector2) -> Array:
	var trees: Array = []
	for grove in _grove_centers():
		for k in range(rng.randi_range(per_grove.x, per_grove.y)):
			var p = grove + Vector3(rng.randf_range(-spread, spread), 0, rng.randf_range(-spread, spread))
			if stage.road_distance(p) < clearance or biome.reserved(p, 1.5) or biome.gully(p) > 0.0:
				continue
			p.y = stage.terrain_surface_height(p) - 0.05
			trees.append({"base": p, "height": rng.randf_range(heights.x, heights.y), "yaw": rng.randf() * TAU, "shade": rng.randf_range(-0.05, 0.06)})
	return trees

# Winter birches: white trunks with dark bases and leafless crowns of fine
# purple-brown twigs wrapped round the upper trunk.
func _birches(_root: Node3D) -> void:
	var trunk = CylinderMesh.new()
	trunk.top_radius = 0.2
	trunk.bottom_radius = 0.5
	trunk.height = 1.0
	trunk.radial_segments = 6
	var crown = SphereMesh.new()
	crown.radial_segments = 8
	crown.rings = 5
	var trees = _grove(7.0, 10.5, Vector2i(4, 9), Vector2(8.0, 13.0))
	stage.woodland.tree_layers("NorthBirch", trees, [
		{"mesh": trunk, "scale": Vector3(0.028, 0.94, 0.028), "y": 0.47, "color": "e6e2d8"},
		{"mesh": trunk, "scale": Vector3(0.03, 0.16, 0.03), "y": 0.08, "color": "4a4540"},
		{"mesh": crown, "scale": Vector3(0.17, 0.42, 0.17), "y": 0.6, "dx": 0.03, "color": "9b8f90"},
		{"mesh": crown, "scale": Vector3(0.13, 0.32, 0.13), "y": 0.74, "dx": -0.04, "color": "a39899"},
		{"mesh": crown, "scale": Vector3(0.09, 0.2, 0.09), "y": 0.9, "color": "aaa0a0"},
	])
	counts["birches"] = trees.size()

func _grove_centers() -> Array:
	var centers: Array = []
	for i in range(10):
		var s = 150.0 + i * 9.0
		centers.append(stage.at(s) + stage.side(s) * (36.0 if i % 2 == 0 else -40.0))
	for i in range(6):
		var s = 296.0 + i * 5.0
		centers.append(stage.at(s) + stage.side(s) * (20.0 if i % 2 == 0 else -22.0))
	for i in range(8):
		var s = 640.0 + i * 9.0
		centers.append(stage.at(s) + stage.side(s) * (30.0 if i % 2 == 0 else -34.0))
	return centers

func _spruces(_root: Node3D) -> void:
	var trunk = CylinderMesh.new()
	trunk.top_radius = 0.1
	trunk.bottom_radius = 0.17
	trunk.height = 1.0
	trunk.radial_segments = 6
	var lower = CylinderMesh.new()
	lower.top_radius = 0.0
	lower.bottom_radius = 1.0
	lower.height = 1.0
	lower.radial_segments = 7
	var upper = CylinderMesh.new()
	upper.top_radius = 0.0
	upper.bottom_radius = 0.7
	upper.height = 1.0
	upper.radial_segments = 7
	var cap = CylinderMesh.new()
	cap.top_radius = 0.0
	cap.bottom_radius = 0.22
	cap.height = 1.0
	cap.radial_segments = 6
	var trees = _grove(9.0, 12.0, Vector2i(2, 5), Vector2(8.0, 16.0))
	stage.woodland.tree_layers("NorthSpruce", trees, [
		{"mesh": trunk, "scale": Vector3(0.05, 0.42, 0.05), "y": 0.21, "color": "4a3a28"},
		{"mesh": lower, "scale": Vector3(0.24, 0.62, 0.24), "y": 0.5, "color": "23402c"},
		{"mesh": upper, "scale": Vector3(0.17, 0.46, 0.17), "y": 0.78, "color": "1d3826"},
		{"mesh": lower, "scale": Vector3(0.2, 0.26, 0.2), "y": 0.66, "color": "e4ebe8"},
		{"mesh": upper, "scale": Vector3(0.14, 0.2, 0.14), "y": 0.88, "color": "e4ebe8"},
		{"mesh": cap, "scale": Vector3(0.1, 0.18, 0.1), "y": 0.95, "color": "eef2ee"},
	])
	counts["spruces"] = trees.size()

# ---------------------------------------------------------------- horizon

# A low, hazy taiga line melting into the fog at the edge of the open fields;
# flat country, not peaks.
static func build_treeline(stage) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 1902
	var root = Node3D.new()
	root.name = "DistantTreeline"
	stage.add_child(root)
	for i in range(34):
		var z = lerpf(100.0, -980.0, float(i) / 33.0) + rng.randf_range(-25.0, 25.0)
		var side = -1.0 if i % 2 == 0 else 1.0
		var p = Vector3(side * rng.randf_range(170.0, 230.0), 0, z)
		var height = rng.randf_range(10.0, 20.0)
		Props.faceted(root, p + Vector3.UP * height * 0.5, Vector3(rng.randf_range(18.0, 30.0), height, 14.0), Color("27362c").lightened(rng.randf_range(-0.03, 0.05)), 7, 3)
