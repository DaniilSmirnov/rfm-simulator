extends RefCounted
# Planted and natural scenery around the Provençal village: lavender on the
# plateau, terraced vineyards with collectible grapes, olive groves, plane
# trees, cypresses and holm oaks, dry-stone walls, beehives, wild flowers on
# the verges and a horizon with Mont Ventoux. Every layer is an instanced batch.
const Props = preload("res://scripts/props.gd")
const Layout = preload("res://scripts/village_layout.gd")
const DetailLayer = preload("res://scripts/detail_layer.gd")
const LAVENDER_TEXTURE = preload("res://textures/nature/lavender.svg")
const Farmland = preload("res://scripts/village_farmland.gd")
const Records = preload("res://scripts/stage_records.gd")

var village
var stage
var solids
var architecture
var rng = RandomNumberGenerator.new()
# Crop footprints indexed in 8 m cells, so trees and flowers keep clear of rows.
var crop_cells: Dictionary = {}
var lavender_count = 0
var vine_count = 0
var wall_count = 0
var tree_count = 0
var fig_count = 0
var beehives: Array[Vector3] = []
var harvest_rows: Array[Dictionary] = []
var lavender_positions: Array[Vector3] = []
var farmland

func _init(owner) -> void:
	village = owner
	stage = owner.stage
	solids = stage.solids
	architecture = owner.architecture
	rng.seed = 21062026

func build(cooperative: bool = false) -> void:
	_plane_avenue()
	_dry_stone_walls()
	await village.pause(cooperative)
	await _lavender(cooperative)
	await _vineyards(cooperative)
	_harvest_crates()
	_beehives()
	await village.pause(cooperative)
	# The patchwork beyond the roadside crops; it plants olives and windbreaks.
	farmland = Farmland.new(self)
	await farmland.build(cooperative)
	_trees()
	await village.pause(cooperative)
	_figs()
	await _ground_cover(cooperative)
	_horizon()

# ---------------------------------------------------------------- helpers

func free_spot(p: Vector3, padding: float, road_clearance: float = 7.0) -> bool:
	if absf(p.x) > 196.0 or p.z > 76.0 or p.z < -916.0:
		return false
	var nearest: Dictionary = stage.route_nearest(p)
	if nearest.distance < village.road_width(nearest.s) * 0.5 + road_clearance:
		return false
	for flat in village.flats:
		if village._flat_weight(flat, p) > 0.0:
			return false
	for clearing in stage.clearings:
		if Vector2(p.x - clearing.x, p.z - clearing.z).length() < 11.0 + padding:
			return false
	return architecture.open_ground(p, padding)

# A row point exists only where the offset line does not fold over itself:
# the nearest road point must be the station it was offset from.
func row_point(s: float, lateral: float) -> Vector3:
	var p = village.anchor(s, lateral)
	var nearest: Dictionary = stage.route_nearest(p)
	if absf(float(nearest.s) - s) > 2.5 or absf(float(nearest.distance) - absf(lateral)) > 0.8:
		return Vector3.INF
	return p

func register_crop(p: Vector3) -> void:
	var key = Vector2i(floori(p.x / 8.0), floori(p.z / 8.0))
	if not crop_cells.has(key):
		crop_cells[key] = []
	crop_cells[key].append(p)

func crop_clear(p: Vector3, clearance: float) -> bool:
	var key = Vector2i(floori(p.x / 8.0), floori(p.z / 8.0))
	var reach = ceili(clearance / 8.0)
	for x in range(-reach, reach + 1):
		for z in range(-reach, reach + 1):
			for plant in crop_cells.get(key + Vector2i(x, z), []):
				if Vector2(p.x - plant.x, p.z - plant.z).length_squared() < clearance * clearance:
					return false
	return true

func surface(p: Vector3) -> Vector3:
	p.y = stage.terrain_surface_height(p)
	return p

# ---------------------------------------------------------------- crops

# Continuous rounded flowering bands with a fine texture, in culling tiles.
func _lavender(cooperative: bool) -> void:
	var builders = {}
	var profile = [Vector2(-0.62, 0.02), Vector2(-0.45, 0.30), Vector2(-0.22, 0.52), Vector2(0, 0.58), Vector2(0.22, 0.52), Vector2(0.45, 0.30), Vector2(0.62, 0.02)]
	for side_sign in [-1.0, 1.0]:
		for row in range(19):
			await village.pause(cooperative and row % 3 == 0)
			var lateral = side_sign * (village.road_width(0) * 0.5 + 6.0 + row * 2.9)
			var previous: Array[Vector3] = []
			var station = Layout.LAVENDER.x + (1.0 if row % 2 else 0.0)
			while station < Layout.LAVENDER.y:
				var p = row_point(station, lateral)
				if p == Vector3.INF or not free_spot(p, 0.8, 5.0):
					previous.clear()
					station += 2.0
					continue
				p = surface(p)
				register_crop(p)
				lavender_positions.append(p)
				if lavender_count % 9 == 0:
					village.add_anchor("lavender", p)
				lavender_count += 1
				var across = village.side(station)
				var section: Array[Vector3] = []
				for shape in profile:
					var vertex = surface(p + across * shape.x)
					vertex.y += shape.y * (1.0 + sin(station * 0.47 + row) * 0.04)
					section.append(vertex)
				if not previous.is_empty():
					var tile = Vector2i(floori(p.x / 64.0), floori(p.z / 64.0))
					if not builders.has(tile):
						var builder = SurfaceTool.new()
						builder.begin(Mesh.PRIMITIVE_TRIANGLES)
						builders[tile] = builder
					var builder: SurfaceTool = builders[tile]
					for strip in range(profile.size() - 1):
						var tint = Color("53684a") if strip == 0 or strip == profile.size() - 2 else Color("8257b8").lerp(Color("b496d6"), (sin(station * 0.08 + row) + 1.0) * 0.15)
						for vertex in [previous[strip], section[strip + 1], section[strip], previous[strip], previous[strip + 1], section[strip + 1]]:
							builder.set_color(tint)
							builder.set_uv(Vector2(vertex.x, vertex.z) * 0.85)
							builder.add_vertex(vertex)
				previous = section
				station += 2.0
	var material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.albedo_texture = LAVENDER_TEXTURE
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var tiles = builders.keys()
	tiles.sort()
	for tile in tiles:
		var builder: SurfaceTool = builders[tile]
		builder.index()
		builder.generate_normals()
		var node = MeshInstance3D.new()
		node.name = "LavenderBands_%d_%d" % [tile.x, tile.y]
		node.mesh = builder.commit()
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stage.add_child(node)
	stage.woodland_details.LavenderBands = lavender_count

# Trellised vine rows parallel to the road, every three metres, with leaves and
# collectible bunches. On the slope every fourth row stands on a stone terrace.
func _vineyards(cooperative: bool) -> void:
	var leaves: Array = []
	var leaf_colors: Array = []
	var fruit: Array = []
	var fruit_colors: Array = []
	var terraces = Node3D.new()
	terraces.name = "VineyardTerraces"
	stage.add_child(terraces)
	for side_sign in [-1.0, 1.0]:
		for row in range(17):
			await village.pause(cooperative and row % 2 == 0)
			var lateral = side_sign * (village.road_width(Layout.VINES.x) * 0.5 + 6.5 + row * 3.0)
			var station = Layout.VINES.x + (3.0 if row % 2 else 0.0)
			while station < Layout.VINES.y:
				var p = row_point(station, lateral)
				station += 6.0
				if p == Vector3.INF or not free_spot(p, 1.2, 5.5) or not crop_clear(p, 2.2):
					continue
				p = surface(p)
				p.y -= 0.02
				register_crop(p)
				vine_count += 1
				var s = station - 6.0
				var pose = Transform3D(stage.terrain_basis(p, village.yaw_at(s)), p)
				var section = Node3D.new()
				terraces.add_child(section)
				section.transform = pose
				Props.cylinder(section, Vector3(0, 0.75, 0), 0.06, 0.05, 1.5, Color("7b6a52"), 6)
				Props.cylinder(section, Vector3(0, 0.45, 0.9), 0.07, 0.05, 0.9, Color("5e4a35"), 5)
				for y in [0.7, 1.05, 1.4]:
					Props.box(section, Vector3(0, y, 0), Vector3(0.016, 0.016, 6.0), Color("7b7d68"))
				# Overlapping foliage forms a continuous trained hedge along the wires.
				for offset in [-2.25, -0.75, 0.75, 2.25]:
					var position = pose * Vector3(0, 1.12 + sin(s + offset) * 0.06, -offset)
					leaves.append(Transform3D(pose.basis.scaled(Vector3(0.62, 0.66, 2.1)), position))
					leaf_colors.append(Color("4f6b30").lerp(Color("7e8a3a"), float(int(s + row) % 5) * 0.08))
				var indices: Array = []
				var purple = row % 4 != 1
				for cluster in [-1.4, 0.6]:
					for berry in range(12):
						var tier = berry / 4
						var angle = berry * 2.4
						var radius = 0.11 - tier * 0.022
						var position = pose * Vector3(0.36 * (1.0 if berry % 2 else -1.0) + cos(angle) * radius * 0.4, 0.82 - tier * 0.1, -cluster + sin(angle) * radius)
						indices.append(fruit.size())
						fruit.append(Transform3D(Basis.from_scale(Vector3.ONE * 0.11), position))
						fruit_colors.append(Color("4a2a4f") if purple else Color("b5bd62"))
				stage.collectibles.append(Records.collectible("berries", p, 3, {"VineyardGrapes": indices}, "виноград"))
				# Dry-stone terrace wall under every fourth row on the slope.
				if village.section(s).id == "terraces" and row % 4 == 3 and absf(village.direction(s).angle_to(village.direction(s + 6.0))) < 0.15:
					Props.box(section, Vector3(1.4, 0.12, 0), Vector3(0.5, 0.42, 6.1), Color("9d9584"))
					for k in range(5):
						Props.box(section, Vector3(1.4 + sin(k * 2.1) * 0.05, 0.36, -2.4 + k * 1.2), Vector3(0.48, 0.14, 1.1), Color("a9a191").darkened(k % 2 * 0.06))
					wall_count += 1
				if village.section(s).id == "valley" and row < 6:
					harvest_rows.append({"pos": pose * Vector3(1.5, 0, 0), "yaw": village.yaw_at(s), "side": side_sign})
					village.add_anchor("harvest", {"pos": pose * Vector3(1.5, 0, 0), "yaw": village.yaw_at(s), "row": row})
	village.batcher.collect(terraces, Transform3D.IDENTITY)
	terraces.free()
	var sphere = architecture._sphere(1.0, 8, 4)
	stage.detail_batch("VineyardLeaves", sphere, leaves, leaf_colors, DetailLayer.tiled())
	stage.detail_batch("VineyardGrapes", sphere, fruit, fruit_colors, DetailLayer.tiled(70.0).harvestable())

# Grape harvest: full crates waiting at the row ends in the valley.
func _harvest_crates() -> void:
	var root = Node3D.new()
	root.name = "VineyardHarvest"
	stage.add_child(root)
	var placed = 0
	for i in range(0, harvest_rows.size(), 5):
		var item: Dictionary = harvest_rows[i]
		var p = surface(item.pos)
		if not free_spot(p, 0.8, 4.5):
			continue
		var stack = Node3D.new()
		root.add_child(stack)
		stack.position = p
		stack.rotation.y = item.yaw
		for k in range(3):
			var crate = Vector3(0, 0.19 + k * 0.38, 0) if k < 2 else Vector3(0.62, 0.19, 0)
			Props.box(stack, crate, Vector3(0.58, 0.36, 0.42), Color("b08a5a"))
			Props.box(stack, crate + Vector3(0, 0.15, 0), Vector3(0.5, 0.08, 0.36), Color("4a2a4f"))
		placed += 1
	village.counts["harvest_crates"] = placed
	village.batcher.collect(root, Transform3D.IDENTITY)
	root.free()

func _beehives() -> void:
	var root = Node3D.new()
	root.name = "LavenderBeehives"
	stage.add_child(root)
	for s in [60.0, 196.0]:
		for i in range(4):
			var p = surface(village.anchor(s + i * 1.8, -(village.road_width(s) * 0.5 + 4.2)))
			if not architecture.open_ground(p, 0.5):
				continue
			var hive = Node3D.new()
			root.add_child(hive)
			hive.position = p
			hive.rotation.y = village.yaw_at(s)
			Props.box(hive, Vector3(0, 0.25, 0), Vector3(0.55, 0.5, 0.5), Color("e8dcc0"))
			Props.box(hive, Vector3(0, 0.62, 0), Vector3(0.6, 0.24, 0.55), Color("6fa0b5") if i % 2 else Color("e0c35a"))
			Props.box(hive, Vector3(0, 0.78, 0), Vector3(0.7, 0.06, 0.65), Color("8c8f86"))
			solids.solid(hive, Vector3(0, 0.4, 0), Vector3(0.6, 0.8, 0.55), "street_furniture")
			beehives.append(p)
			village.add_anchor("beehives", p)
	# The root keeps the hives' collision bodies; only the meshes are batched.
	village.batcher.collect(root, Transform3D.IDENTITY)

# ---------------------------------------------------------------- trees

# Plane trees close to the road with white reflective bands, as on old French
# departmental roads. They are solid: a car leaving the road stops against them.
func _plane_avenue() -> void:
	var root = Node3D.new()
	root.name = "PlaneTreeAvenue"
	stage.add_child(root)
	var s = Layout.PLANE_AVENUE.x
	while s < Layout.PLANE_AVENUE.y:
		for side_sign in [-1.0, 1.0]:
			var p = village.anchor(s, side_sign * (village.road_width(s) * 0.5 + 2.4))
			p.y = stage.ground(p) - 0.05
			var tree = Node3D.new()
			root.add_child(tree)
			tree.position = p
			architecture.plane_tree(tree, Vector3.ZERO, 1.25)
			Props.cylinder(tree, Vector3(0, 0.9, 0), 0.44, 0.44, 0.35, Color("f1efe6"), 8)
			tree_count += 1
		s += 9.0
	village.batcher.collect(root, Transform3D.IDENTITY)

func _trees() -> void:
	var trunk = architecture._sphere(1.0, 6, 3)
	var cone = CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.5
	cone.height = 1.0
	cone.radial_segments = 8
	cone.rings = 2
	var stick = CylinderMesh.new()
	stick.top_radius = 0.35
	stick.bottom_radius = 0.5
	stick.height = 1.0
	stick.radial_segments = 6
	stick.rings = 1
	var crown = architecture._sphere(1.0, 9, 5)
	# Olive groves around the plane avenue and the plateau edge.
	var olives: Array = []
	for grove in [[205.0, 1.0], [220.0, -1.0], [262.0, -1.0], [300.0, 1.0]]:
		for row in range(4):
			for k in range(5):
				var s: float = grove[0] + k * 7.0 + (3.5 if row % 2 else 0.0)
				var p = village.anchor(s, grove[1] * (village.road_width(s) * 0.5 + 14.0 + row * 7.0))
				if not free_spot(p, 2.5, 10.0) or not crop_clear(p, 3.0):
					continue
				olives.append({"base": surface(p) - Vector3.UP * 0.05, "height": rng.randf_range(3.6, 5.0), "yaw": rng.randf() * TAU, "shade": rng.randf_range(-0.05, 0.06)})
	olives.append_array(farmland.olives if farmland != null else [])
	stage.woodland.tree_layers("OliveTree", olives, [
		{"mesh": stick, "scale": Vector3(0.08, 0.42, 0.08), "y": 0.2, "tilt": 0.18, "color": "6d5f4c"},
		{"mesh": crown, "scale": Vector3(0.62, 0.34, 0.58), "y": 0.55, "dx": 0.12, "color": "8a9a6e"},
		{"mesh": crown, "scale": Vector3(0.5, 0.3, 0.48), "y": 0.72, "dx": -0.15, "color": "9aa87c"},
	])
	# Cypresses: cemetery, farms and windbreaks along the vineyard tracks.
	var cypresses: Array = []
	var cypress_spots: Array = village.hints.get("cypress", []).duplicate()
	for item in [[Layout.DISTILLERY.s, Layout.DISTILLERY.lateral], [Layout.DOMAINE.s, Layout.DOMAINE.lateral], [Layout.COOPERATIVE.s, Layout.COOPERATIVE.lateral]]:
		for k in range(4):
			cypress_spots.append(village.anchor(item[0] - 14.0 + k * 3.2, item[1] + 13.0 * signf(item[1])))
	for k in range(9):
		cypress_spots.append(village.anchor(560.0 + k * 4.0, 52.0))
		cypress_spots.append(village.anchor(740.0 + k * 4.5, -60.0))
	for p in cypress_spots:
		if not free_spot(p, 1.0, 8.0) or not crop_clear(p, 1.2):
			continue
		cypresses.append({"base": surface(p) - Vector3.UP * 0.05, "height": rng.randf_range(8.0, 12.5), "yaw": rng.randf() * TAU, "shade": rng.randf_range(-0.04, 0.05)})
	stage.woodland.tree_layers("Cypress", cypresses, [
		{"mesh": stick, "scale": Vector3(0.03, 0.12, 0.03), "y": 0.06, "color": "5b4a35"},
		{"mesh": crown, "scale": Vector3(0.17, 0.62, 0.17), "y": 0.36, "color": "2f4a30"},
		{"mesh": cone, "scale": Vector3(0.2, 0.42, 0.2), "y": 0.68, "color": "35522f"},
	])
	# Holm oaks grow in small copses on uncultivated ground; a few umbrella
	# pines stand out on the outer hills against the sky.
	var oaks: Array = []
	var pines: Array = []
	for copse in range(40):
		var center = Vector3(rng.randf_range(-185, 185), 0, rng.randf_range(-870, 30))
		if not free_spot(center, 6.0, 16.0):
			continue
		for k in range(rng.randi_range(3, 7)):
			var p = center + Vector3(rng.randf_range(-7, 7), 0, rng.randf_range(-7, 7))
			if not free_spot(p, 2.5, 12.0) or not crop_clear(p, 4.0):
				continue
			oaks.append({"base": surface(p) - Vector3.UP * 0.05, "height": rng.randf_range(5.5, 9.0), "yaw": rng.randf() * TAU, "shade": rng.randf_range(-0.05, 0.05)})
	for attempt in range(200):
		var p = Vector3(rng.randf_range(110, 192) * (1.0 if attempt % 2 else -1.0), 0, rng.randf_range(-880, 40))
		if not free_spot(p, 4.0, 20.0) or not crop_clear(p, 5.0):
			continue
		pines.append({"base": surface(p) - Vector3.UP * 0.05, "height": rng.randf_range(11.0, 15.0), "yaw": rng.randf() * TAU, "shade": rng.randf_range(-0.05, 0.03)})
		if pines.size() >= 18:
			break
	stage.woodland.tree_layers("HolmOak", oaks, [
		{"mesh": stick, "scale": Vector3(0.05, 0.5, 0.05), "y": 0.25, "color": "5a4a3a"},
		{"mesh": crown, "scale": Vector3(0.62, 0.48, 0.62), "y": 0.62, "color": "3e5532"},
		{"mesh": crown, "scale": Vector3(0.42, 0.32, 0.42), "y": 0.84, "dx": 0.1, "color": "4b6538"},
	])
	stage.woodland.tree_layers("UmbrellaPine", pines, [
		{"mesh": stick, "scale": Vector3(0.03, 0.8, 0.03), "y": 0.4, "tilt": 0.08, "color": "7a5a44"},
		{"mesh": crown, "scale": Vector3(0.7, 0.16, 0.7), "y": 0.84, "color": "3f5a37"},
		{"mesh": crown, "scale": Vector3(0.48, 0.12, 0.48), "y": 0.93, "dx": 0.06, "color": "4c6a3f"},
	])
	tree_count += olives.size() + cypresses.size() + oaks.size() + pines.size()
	village.counts["olives"] = olives.size()
	village.counts["cypresses"] = cypresses.size()
	village.counts["oaks"] = oaks.size()
	village.counts["pines"] = pines.size()

# Fig trees in the walled gardens; their ripe figs can be picked.
func _figs() -> void:
	var leaves: Array = []
	var leaf_colors: Array = []
	var stems: Array = []
	var stem_colors: Array = []
	var figs: Array = []
	var fig_colors: Array = []
	var crown = architecture._sphere(1.0, 8, 4)
	for p in village.hints.get("fig", []):
		p = surface(p)
		stems.append(Transform3D(Basis.from_scale(Vector3(0.14, 1.6, 0.14)), p + Vector3.UP * 0.8))
		stem_colors.append(Color("8d8577"))
		var indices: Array = []
		for k in range(4):
			var angle = k * TAU / 4.0 + p.x
			var center = p + Vector3(cos(angle) * 0.7, 2.0 + (k % 2) * 0.35, sin(angle) * 0.7)
			leaves.append(Transform3D(Basis(Vector3.UP, angle).scaled(Vector3(1.6, 1.1, 1.5)), center))
			leaf_colors.append(Color("5f8a3c").lightened(k * 0.03))
			for f in range(3):
				var fig = center + Vector3(cos(angle + f * 2.1) * 0.7, -0.35, sin(angle + f * 2.1) * 0.65)
				indices.append(figs.size())
				figs.append(Transform3D(Basis.from_scale(Vector3(0.09, 0.11, 0.09)), fig))
				fig_colors.append(Color("5a3150"))
		stage.collectibles.append(Records.collectible("berries", p, 3, {"GardenFigs": indices}, "инжир"))
		fig_count += 1
	stage.detail_batch("GardenFigTrunks", architecture._sphere(1.0, 6, 3), stems, stem_colors)
	stage.detail_batch("GardenFigLeaves", crown, leaves, leaf_colors)
	stage.detail_batch("GardenFigs", crown, figs, fig_colors, DetailLayer.plain().harvestable())

# ---------------------------------------------------------------- walls

# Low dry-stone walls along the plateau road and around the farmyards.
func _dry_stone_walls() -> void:
	var root = Node3D.new()
	root.name = "DryStoneWalls"
	stage.add_child(root)
	for run in [[24.0, 92.0, 1.0], [40.0, 118.0, -1.0], [152.0, 236.0, -1.0], [168.0, 238.0, 1.0], [560.0, 612.0, 1.0], [712.0, 776.0, 1.0]]:
		var s: float = run[0]
		while s < run[1]:
			var lateral = run[2] * (village.road_width(s) * 0.5 + 3.4)
			var p = village.anchor(s + 1.5, lateral)
			if architecture.open_ground(p, 0.6) and not _near_clearing(p, 7.0) and fposmod(s, 27.0) < 21.0:
				p.y = stage.ground(p)
				var wall = Node3D.new()
				root.add_child(wall)
				wall.position = p
				wall.rotation.y = village.yaw_at(s + 1.5)
				var height = 0.5 + sin(s * 0.7) * 0.06
				Props.box(wall, Vector3(0, height * 0.5 - 0.1, 0), Vector3(0.55, height + 0.2, 3.0), Color("a49c8a").darkened(fposmod(s * 0.37, 1.0) * 0.1))
				# Rough capping stones set on edge.
				for k in range(4):
					Props.box(wall, Vector3(sin(s + k) * 0.04, height + 0.08, -1.1 + k * 0.74), Vector3(0.5, 0.2, 0.62), Color("b2aa98").darkened(k % 2 * 0.07))
				solids.solid(wall, Vector3(0, height * 0.5, 0), Vector3(0.55, height, 3.0), "wall")
				wall_count += 1
			s += 3.0
	village.batcher.collect(root, Transform3D.IDENTITY)

func _near_clearing(p: Vector3, radius: float) -> bool:
	for clearing in stage.clearings:
		if Vector2(p.x - clearing.x, p.z - clearing.z).length() < radius:
			return true
	return false

# ---------------------------------------------------------------- ground

# Dry grass, poppies and cornflowers on the verges, garrigue shrubs on the
# uncultivated slopes, and pale limestone pebbles in the vineyards.
func _ground_cover(cooperative: bool) -> void:
	var grass: Array = []
	var grass_colors: Array = []
	var flowers: Array = []
	var flower_colors: Array = []
	var shrubs: Array = []
	var shrub_colors: Array = []
	var pebbles: Array = []
	var pebble_colors: Array = []
	for i in range(14000):
		if i % 700 == 0:
			await village.pause(cooperative)
		var s = rng.randf_range(4.0, 836.0)
		var lateral = rng.randf_range(4.0, 70.0) * (1.0 if i % 2 else -1.0)
		var p = village.anchor(s, lateral)
		if not free_spot(p, 0.3, 0.6) or not crop_clear(p, 1.0):
			continue
		p = surface(p)
		var size = rng.randf_range(0.22, 0.48)
		grass.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size * 1.8, size, size * 1.8)), p - Vector3.UP * 0.02))
		grass_colors.append(Color("66733a").lerp(Color("9a9152"), rng.randf()))
		if absf(lateral) < 18.0 and rng.randf() < 0.35:
			for k in range(3):
				var bloom = p + Vector3(rng.randf_range(-0.4, 0.4), 0.32 + rng.randf() * 0.15, rng.randf_range(-0.4, 0.4))
				flowers.append(Transform3D(Basis.from_scale(Vector3(0.08, 0.05, 0.08)), bloom))
				flower_colors.append(Color("d8342a") if rng.randf() < 0.75 else Color("5a73c8"))
	for i in range(1800):
		var p = Vector3(rng.randf_range(-190, 190), 0, rng.randf_range(-880, 40))
		if not free_spot(p, 1.2, 9.0) or not crop_clear(p, 2.0):
			continue
		p = surface(p)
		var size = rng.randf_range(0.45, 1.0)
		shrubs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size, size * 0.7, size)), p + Vector3.UP * size * 0.25))
		shrub_colors.append(Color("6f7a55").lerp(Color("8f9470"), rng.randf()))
	for i in range(4000):
		var s = rng.randf_range(Layout.VINES.x, Layout.VINES.y)
		var p = village.anchor(s, rng.randf_range(6.0, 60.0) * (1.0 if i % 2 else -1.0))
		if not free_spot(p, 0.2, 4.0):
			continue
		p = surface(p)
		var radius = rng.randf_range(0.06, 0.16)
		pebbles.append(stage.shared_stone_pose(p + Vector3.UP * radius * 0.2, radius, rng.randf() * TAU))
		pebble_colors.append(Color("d8cfbd").darkened(rng.randf() * 0.12))
	stage.detail_batch("VillageGrass", stage.woodland.grass_mesh(), grass, grass_colors, DetailLayer.tiled())
	stage.detail_batch("VergeFlowers", architecture._sphere(1.0, 5, 2), flowers, flower_colors, DetailLayer.tiled(110.0))
	stage.detail_batch("GarrigueShrubs", preload("res://models/nature/roadside_bush.tres"), shrubs, shrub_colors, DetailLayer.tiled(220.0))
	stage.detail_batch("VineyardPebbles", stage.shared_stone_mesh(), pebbles, pebble_colors, DetailLayer.tiled(110.0))

# Distant ridges of garrigue and the bald limestone summit of Mont Ventoux.
func _horizon() -> void:
	var root = Node3D.new()
	root.name = "ProvenceHorizon"
	stage.add_child(root)
	for i in range(18):
		var side_sign = -1.0 if i % 2 == 0 else 1.0
		var ridge = Props.cylinder(root, Vector3(side_sign * (330.0 + (i % 3) * 70.0), -14.0, 120.0 - i * 62.0), 1.0, 0.3, 1.0, Color("5e6f50").lerp(Color("74858a"), (i % 3) * 0.3), 10)
		ridge.scale = Vector3(150.0 + (i % 4) * 30.0, 42.0 + (i % 5) * 7.0, 110.0)
	for i in range(5):
		var far = Props.cylinder(root, Vector3(-360.0 + i * 170.0, -20.0, -1020.0 - (i % 2) * 60.0), 1.0, 0.2, 1.0, Color("8193a0"), 10)
		far.scale = Vector3(260.0, 70.0 + (i % 3) * 12.0, 130.0)
	var ventoux = Vector3(560.0, -20.0, -1020.0)
	var mountain = Props.cylinder(root, ventoux + Vector3(0, 60, 0), 1.0, 0.14, 1.0, Color("6e8090"), 14)
	mountain.scale = Vector3(330.0, 150.0, 240.0)
	var summit = Props.cylinder(root, ventoux + Vector3(0, 146, 0), 1.0, 0.1, 1.0, Color("b9b8b0"), 14)
	summit.scale = Vector3(48.0, 24.0, 38.0)
	village.batcher.collect(root, Transform3D.IDENTITY)
	root.free()
