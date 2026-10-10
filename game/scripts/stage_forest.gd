extends RefCounted
# The one forest generator of all stages: conifers and roadside rocks planted
# from the biome hooks (stage_biome.gd), the woodland floor (grass, pebbles,
# boulders, bushes, berries, mushrooms, ant hills) and the instanced detail
# layers every stage draws its vegetation with (detail_layer.gd). State stays
# on the stage: trees[], rocks[], collectibles[], woodland_details.
const BakedVillage = preload("res://scripts/baked_village.gd")
const DetailLayer = preload("res://scripts/detail_layer.gd")
const NATURE_BERRY = preload("res://models/nature/berry.tres")
const NATURE_BOULDER = preload("res://models/nature/boulder.tres")
const NATURE_BUSH = preload("res://models/nature/bush.tres")
const NATURE_BUSH_STEM = preload("res://models/nature/bush_stem.tres")
const NATURE_GRASS = preload("res://models/nature/grass.obj")
const NATURE_MUSHROOM_CAP = preload("res://models/nature/mushroom_cap.tres")
const NATURE_MUSHROOM_STEM = preload("res://models/nature/mushroom_stem.tres")
const NATURE_STONE = preload("res://models/nature/stone.tres")
const Records = preload("res://scripts/stage_records.gd")

var stage

# The shared conifer forest and roadside rocks; stages without a forest (the
# village builds its own groves, the canyon has none) plant zero trees.
func plant_forest(cooperative: bool = false) -> void:
	var tree_count = stage.biome.forest_tree_count()
	if tree_count <= 0:
		return
	var max_height = stage.biome.forest_tree_max_height()
	var clearing_radius = stage.biome.forest_clearing_radius()
	var forest: Array[Dictionary] = []
	for i in range(tree_count):
		if cooperative and i % 400 == 0:
			await stage.get_tree().process_frame
		var p = Vector3(stage.rng.randf_range(-150, 150), 0, stage.rng.randf_range(-stage.LENGTH - 65, 50))
		if stage.road_distance(p) < 9:
			continue
		if stage.biome.tree_blocked(p):
			continue
		var in_clearing = false
		for c in stage.clearings:
			if Vector2(p.x - c.x, p.z - c.z).length() < clearing_radius:
				in_clearing = true
		for c in stage.snow_glades:
			if Vector2(p.x - c.x, p.z - c.z).length() < stage.GLADE_FLAT + 3.0:
				in_clearing = true
		if in_clearing:
			continue
		p.y = stage.terrain_surface_height(p) - 0.03
		stage.trees.append(p)
		forest.append({"position": p, "height": stage.rng.randf_range(6, max_height), "shade": stage.rng.randf_range(-0.025, 0.045)})
	stage.forest_data = forest
	stage._rebuild_tree_index()
	_build_forest(forest)
	for i in range(100):
		var s = stage.rng.randf_range(20, stage.LENGTH - 15)
		var p = stage.at(s) + stage.side(s) * stage.rng.randf_range(-6, 6)
		if stage.road_distance(p) < 4.3:
			continue
		if stage.biome.roadside_rock_blocked(p):
			continue
		p.y = stage.ground(p)
		var radius = stage.rng.randf_range(0.3, 1)
		var rock = RallyProps.cylinder(stage, p + Vector3(0, 0.2, 0), radius, 0.18, 0.65, Color("7d8070"), 5)
		stage.rocks.append(Records.rock(p, radius, 0.75))
		rock.rotation.z = stage.rng.randf_range(-0.3, 0.3)

# Four instanced draw calls for the forest instead of thousands of nodes.
# Collision positions remain in `trees`, matching the original gameplay.
func shared_tree_mesh(layer: int) -> CylinderMesh:
	return stage.NATURE_TREE_MESHES[layer]

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
	return NATURE_STONE

func shared_stone_pose(position: Vector3, radius: float, yaw: float = 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(radius * 2.0, radius, radius * 1.7)), position)

func shared_stone_color(lightness: float = 0.0) -> Color:
	return Color("7e806e").lightened(clampf(lightness, -0.10, 0.12))

func _build_forest(forest: Array[Dictionary]) -> void:
	var groups: Array[Array] = []
	var cells: Dictionary = {}
	stage.forest_chunk_slots.resize(forest.size())
	for index in range(forest.size()):
		var p: Vector3 = forest[index].position
		var cell = Vector2i(floori(p.x / stage.FOREST_RENDER_CELL), floori(p.z / stage.FOREST_RENDER_CELL))
		if not cells.has(cell):
			cells[cell] = groups.size()
			groups.append([])
			stage.forest_chunk_centers.append(Vector3((cell.x + 0.5) * stage.FOREST_RENDER_CELL, 0, (cell.y + 0.5) * stage.FOREST_RENDER_CELL))
		var chunk: int = cells[cell]
		stage.forest_chunk_slots[index] = Vector2i(chunk, groups[chunk].size())
		groups[chunk].append(index)
	for layer in range(4):
		var mesh = shared_tree_mesh(layer)
		var mat = RallyProps.material(Color.WHITE)
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		mesh.material = mat
		var chunks: Array = []
		for chunk in range(groups.size()):
			var mm = MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = mesh
			mm.instance_count = groups[chunk].size()
			chunks.append(mm)
			for local in range(groups[chunk].size()):
				var tree_data: Dictionary = forest[groups[chunk][local]]
				var pose = shared_tree_pose(tree_data.position, float(tree_data.height), layer)
				pose.origin -= stage.forest_chunk_centers[chunk]
				mm.set_instance_transform(local, pose)
				mm.set_instance_color(local, shared_tree_color(layer, float(tree_data.shade), stage.has_snow))
			var instance = MultiMeshInstance3D.new()
			instance.name = "ForestLayer%d_Chunk%d" % [layer, chunk]
			instance.position = stage.forest_chunk_centers[chunk]
			instance.multimesh = mm
			stage.add_child(instance)
		stage.forest_layers.append(chunks)

func woodland_spot(pos: Vector3, padding: float = 0.0) -> bool:
	if stage.road_distance(pos) < 9.0 + padding or stage.trail_distance(pos) < 3.2 + padding:
		return false
	if stage.biome.woodland_blocked(pos, padding):
		return false
	for clearing in stage.clearings:
		if stage.flat(pos).distance_to(stage.flat(clearing)) < 8.5 + padding:
			return false
	return true

# An instanced decorative layer; `layer` (detail_layer.gd) says whether it is
# tiled, collectible or part of a fallable tree.
func detail_batch(name: String, mesh: Mesh, poses: Array, colors: Array, layer: DetailLayer = null) -> void:
	if layer == null:
		layer = DetailLayer.plain()
	var group: String = layer.tree_group
	var indices: Array = []
	if not layer.tree_bases.is_empty():
		var ids: Array = []
		for i in range(poses.size()):
			ids.append(stage.trees.size())
			stage.trees.append(layer.tree_bases[i])
			stage.forest_data.append({"height": float(layer.tree_heights[i])})
		stage.detail_tree_groups[group] = ids
		stage._rebuild_tree_index()
	if group != "":
		indices = stage.detail_tree_groups[group]
	stage.woodland_details[name] = poses.size()
	if not layer.tiles:
		_detail_node(name, name, mesh, poses, colors, layer, indices, false)
		return
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
		_detail_node(prefix + "_%d_%d" % [key.x, key.y], name, mesh, cells[key].poses, cells[key].colors, layer, cells[key].indices, true)

func _detail_node(node_name: String, source: String, mesh: Mesh, poses: Array, colors: Array, layer: DetailLayer, indices: Array, tiled: bool) -> void:
	var group: String = layer.tree_group
	var collectible: bool = layer.collectible
	var mat = RallyProps.material(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if layer.texture != null:
		mat.albedo_texture = layer.texture
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = poses.size()
	var center = poses[0].origin if tiled and not poses.is_empty() else Vector3.ZERO
	for i in range(poses.size()):
		var pose: Transform3D = poses[i]
		pose.origin -= center
		mm.set_instance_transform(i, pose)
		mm.set_instance_color(i, colors[i])
		var id: int = i if indices.is_empty() else indices[i]
		if group != "":
			if not stage.detail_tree_visuals.has(id): stage.detail_tree_visuals[id] = []
			stage.detail_tree_visuals[id].append({"mesh": mm, "instance": i, "pose": poses[i], "center": center})
		if collectible:
			if not stage.collectible_parts.has(source):
				stage.collectible_parts[source] = {}
			stage.collectible_parts[source][id] = {"mesh": mm, "instance": i, "pose": pose, "hidden": false}
	var node = MultiMeshInstance3D.new()
	node.name = node_name
	node.position = center
	if tiled:
		node.visibility_range_end = layer.range_end
		node.visibility_range_end_margin = 15
	node.multimesh = mm
	if stage.capture_bake_buffers:
		BakedVillage.capture_instances(node, poses, colors, center)
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(node)

func grass_mesh() -> Mesh:
	return NATURE_GRASS

# Shared woodland floor: grass, pebbles, boulders, berry bushes, mushrooms and
# ant hills, used by every forest stage.
func build_woodland(cooperative: bool = false) -> void:
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
		if cooperative and i % 400 == 0:
			await stage.get_tree().process_frame
		var p = Vector3(detail_rng.randf_range(-145, 145), 0, detail_rng.randf_range(-stage.LENGTH, 0))
		if not woodland_spot(p):
			continue
		p.y = stage.terrain_surface_height(p) - 0.015
		var size = detail_rng.randf_range(0.25, 0.65)
		grass_poses.append(Transform3D(Basis(Vector3.UP, detail_rng.randf() * TAU).scaled(Vector3(size * 1.8, size, size * 1.8)), p))
		grass_colors.append(shared_grass_color(detail_rng.randf()))
	for i in range(4000):
		if cooperative and i % 400 == 0:
			await stage.get_tree().process_frame
		var along = detail_rng.randf_range(20, stage.LENGTH - 20)
		var p = stage.at(along) + stage.side(along) * detail_rng.randf_range(13, 125) * (-1 if i % 2 else 1)
		var radius = detail_rng.randf_range(0.8, 2.4)
		if not woodland_spot(p, radius) or stage.obstacle_hit(p, p, radius + 0.3) >= 0 or not stage.rock_hit(p, p, radius, false).is_empty():
			continue
		p.y = stage.ground(p)
		var height = detail_rng.randf_range(0.7, 2.5)
		boulder_poses.append(Transform3D(Basis(Vector3.UP, detail_rng.randf() * TAU).scaled(Vector3(radius * 2, height, radius * 1.7)), p + Vector3(0, height * 0.35, 0)))
		boulder_colors.append(Color("697064").lightened(detail_rng.randf_range(-0.12, 0.12)))
		stage.rocks.append(Records.rock(p, radius, height * 0.9, Records.FOREST))
		if boulder_poses.size() >= 240:
			break
	for i in range(1600):
		if cooperative and i % 400 == 0:
			await stage.get_tree().process_frame
		var p = Vector3(detail_rng.randf_range(-135, 135), 0, detail_rng.randf_range(-stage.LENGTH, 0))
		if not woodland_spot(p):
			continue
		var radius = detail_rng.randf_range(0.12, 0.35)
		p.y = stage.terrain_surface_height(p) + radius * 0.35
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
	var ground_exclusions = {}
	for i in range(2000):
		if cooperative and i % 400 == 0:
			await stage.get_tree().process_frame
		var p = Vector3(detail_rng.randf_range(-140, 140), 0, detail_rng.randf_range(-stage.LENGTH, 0))
		var patch = sin(p.x * 0.075 + p.z * 0.027) * sin(p.z * 0.054)
		if patch < -0.35 or not woodland_spot(p, 1.4) or not stage.rock_hit(p, p, 1.1, false).is_empty():
			continue
		p.y = stage.ground(p) - 0.22
		var height = detail_rng.randf_range(0.55, 1.35)
		var cell = Vector2i(floori(p.x / 4.0), floori(p.z / 4.0))
		if not ground_exclusions.has(cell):
			ground_exclusions[cell] = []
		ground_exclusions[cell].append({"pos": p, "radius": height * 0.9})
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
			stage.collectibles.append(Records.collectible("berries", Vector3(p.x, stage.ground(p), p.z), 3, {"ForestBerries": fruit_indices}))
	var leaves = NATURE_BUSH
	detail_batch("ForestBushes", leaves, bush_poses, bush_colors, DetailLayer.tiled())
	detail_batch("ForestBerryBushes", leaves, berry_bush_poses, berry_bush_colors, DetailLayer.tiled())
	var berry_mesh = NATURE_BERRY
	detail_batch("ForestBerries", berry_mesh, berry_poses, berry_colors, DetailLayer.tiled().harvestable())
	var bush_stem_mesh = NATURE_BUSH_STEM
	detail_batch("ForestBushStems", bush_stem_mesh, bush_stem_poses, bush_stem_colors, DetailLayer.tiled())
	for i in range(300):
		if cooperative and i % 400 == 0:
			await stage.get_tree().process_frame
		var along = detail_rng.randf_range(20, stage.LENGTH - 20)
		var p = stage.at(along) + stage.side(along) * detail_rng.randf_range(10, 38) * (-1 if i % 2 else 1)
		if not woodland_spot(p) or not stage.rock_hit(p, p, 0.5, false).is_empty():
			continue
		for j in range(3):
			var at = p + Vector3(detail_rng.randf_range(-0.45, 0.45), 0, detail_rng.randf_range(-0.45, 0.45))
			at.y = stage.ground(at) + 0.02
			var size = detail_rng.randf_range(0.10, 0.22)
			var species = "fly_agaric" if i % 10 == 4 else ("toadstool" if i % 10 == 7 else "edible")
			var cap_layer = "FlyAgaricCaps" if species == "fly_agaric" else ("ToadstoolCaps" if species == "toadstool" else "MushroomCaps")
			var cap_index = cap_poses.size() if species == "edible" else poison_caps[species].size()
			stage.collectibles.append(Records.collectible("mushrooms", Vector3(at.x, stage.ground(at), at.z), 1, {cap_layer: [cap_index], "MushroomStems": [stem_poses.size()]}, "мухомор" if species == "fly_agaric" else ("поганка" if species == "toadstool" else "гриб"), species))
			stem_poses.append(Transform3D(Basis.from_scale(Vector3(size * 0.20, size, size * 0.20)), at + Vector3(0, size * 0.5, 0)))
			stem_colors.append(Color("c5baa1"))
			var cap_pose = Transform3D(Basis.from_scale(Vector3(size * 1.4, size * 0.55, size * 1.4)), at + Vector3(0, size, 0))
			if species == "edible":
				cap_poses.append(cap_pose)
				cap_colors.append(Color("b87743"))
			else:
				poison_caps[species].append(cap_pose)
	for i in range(110):
		if cooperative and i % 400 == 0:
			await stage.get_tree().process_frame
		var along = detail_rng.randf_range(20, stage.LENGTH - 20)
		var p = stage.at(along) + stage.side(along) * detail_rng.randf_range(12, 45) * (-1 if i % 2 else 1)
		if not woodland_spot(p, 0.8) or not stage.rock_hit(p, p, 0.8, false).is_empty():
			continue
		p.y = stage.ground(p) - 0.23
		var radius = detail_rng.randf_range(0.45, 0.9)
		var height = detail_rng.randf_range(0.35, 0.75)
		mound_poses.append(Transform3D(Basis.from_scale(Vector3(radius, height, radius)), p + Vector3(0, height * 0.5, 0)))
		mound_colors.append(Color("66513a").lightened(detail_rng.randf_range(-0.06, 0.06)))
		for j in range(4):
			var twig = p + Vector3(detail_rng.randf_range(-0.25, 0.25), height * 0.55, detail_rng.randf_range(-0.25, 0.25))
			twig_poses.append(Transform3D(Basis.from_euler(Vector3(0.9, detail_rng.randf() * TAU, 0.7)).scaled(Vector3(0.02, radius * 0.65, 0.02)), twig))
			twig_colors.append(Color("493c2b"))
	var boulder = NATURE_BOULDER
	detail_batch("ForestBoulders", boulder, boulder_poses, boulder_colors)
	# Filter after rocks and undergrowth exist, so ground details cannot overlap them.
	for group in [{"poses": grass_poses, "colors": grass_colors}, {"poses": stone_poses, "colors": stone_colors}]:
		for index in range(group.poses.size() - 1, -1, -1):
			var pose: Transform3D = group.poses[index]
			var point = pose.origin
			point.y = stage.terrain_surface_height(point)
			var padding = maxf(pose.basis.x.length(), pose.basis.z.length()) * 0.5
			var blocked = stage.obstacle_hit(point, point, padding) >= 0 or not stage.rock_hit(point, point, padding, false).is_empty()
			var cell = Vector2i(floori(point.x / 4.0), floori(point.z / 4.0))
			for x in range(-1, 2):
				for z in range(-1, 2):
					for bush in ground_exclusions.get(cell + Vector2i(x, z), []):
						blocked = blocked or stage.flat(point).distance_to(stage.flat(bush.pos)) < padding + bush.radius
			if blocked:
				group.poses.remove_at(index)
				group.colors.remove_at(index)
	detail_batch("ForestPebbles", shared_stone_mesh(), stone_poses, stone_colors, DetailLayer.tiled())
	detail_batch("ForestGrass", grass_mesh(), grass_poses, grass_colors, DetailLayer.tiled())
	var stem = NATURE_MUSHROOM_STEM
	detail_batch("MushroomStems", stem, stem_poses, stem_colors, DetailLayer.plain().harvestable())
	var cap = NATURE_MUSHROOM_CAP
	detail_batch("MushroomCaps", cap, cap_poses, cap_colors, DetailLayer.plain().harvestable())
	for species in poison_caps:
		var colors: Array = []
		colors.resize(poison_caps[species].size())
		colors.fill(Color.WHITE)
		detail_batch("FlyAgaricCaps" if species == "fly_agaric" else "ToadstoolCaps", cap, poison_caps[species], colors, DetailLayer.plain().harvestable().textured(RallyProps.MUSHROOM_TEXTURES[species]))
	var mound = CylinderMesh.new()
	mound.height = 1
	mound.bottom_radius = 1
	mound.top_radius = 0.12
	mound.radial_segments = 9
	mound.rings = 1
	detail_batch("AntHills", mound, mound_poses, mound_colors)
	var twig = CylinderMesh.new()
	twig.height = 1
	twig.bottom_radius = 1
	twig.top_radius = 0.4
	twig.radial_segments = 4
	twig.rings = 1
	detail_batch("AntHillTwigs", twig, twig_poses, twig_colors)

# Fallable trees drawn as instanced layers (trunk, crowns): one record per
# tree, one layer description per part. Layer 0 is the trunk that collides.
func tree_layers(name: String, trees: Array, layers: Array) -> void:
	# trees: [{"base": Vector3, "height": float, "yaw": float, "shade": float}]
	if trees.is_empty():
		return
	var bases: Array = []
	var heights: Array = []
	for tree in trees:
		bases.append(tree.base)
		heights.append(tree.height)
	for index in range(layers.size()):
		var layer: Dictionary = layers[index]
		var poses: Array = []
		var colors: Array = []
		for tree in trees:
			var h: float = tree.height
			var basis = Basis(Vector3.UP, float(tree.yaw)) * Basis.from_euler(Vector3(layer.get("tilt", 0.0), 0, 0))
			var scale: Vector3 = layer.scale * h
			poses.append(Transform3D(basis.scaled(scale), tree.base + basis * Vector3(layer.get("dx", 0.0) * h, layer.y * h, 0)))
			colors.append(Color(layer.color).lightened(float(tree.shade)))
		var detail = DetailLayer.tiled(260.0).tree(name, bases, heights) if index == 0 else DetailLayer.tiled(260.0).tree(name)
		detail_batch("%s%d" % [name, index], layer.mesh, poses, colors, detail)
