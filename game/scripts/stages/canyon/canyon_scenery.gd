extends RefCounted
# Scenery of «Чарынский каньон» (canyon.gd), placed on the land that
# canyon_form.gd describes: the castles of the Valley of Castles standing at
# the foot of the walls, on their benches and along the rim, the talus of
# fallen blocks below every cliff, feather grass on the table above, tamarisk
# and river stones on the gravel floor, the relict ash grove above the Ili,
# two yurt camps and the whitewashed blocks along the edge of the descent.
# Placement uses its own seeded generator, so every room member builds the
# same gorge and stage.rng is never disturbed.
const Props = preload("res://scripts/core/props.gd")
const Records = preload("res://scripts/stages/stage_records.gd")
const DetailLayer = preload("res://scripts/stages/detail_layer.gd")
const MeshMerge = preload("res://scripts/core/mesh_merge.gd")
const Form = preload("res://scripts/stages/canyon/canyon_form.gd")
const Yurt = preload("res://scripts/stages/canyon/yurt.gd")

# Station, side and distance of the two yurt camps: the herders' camp on the
# steppe by the rim road, and the warden's camp in the grove by the river.
const STEPPE_CAMP = [96.0, -1.0, 44.0]
const GROVE_CAMP = [744.0, 1.0, 40.0]
# Where the road is a shelf and its edge is marked with whitewashed blocks.
const LEDGE_BEGIN = 262.0
const LEDGE_END = 566.0
# The reach of the gorge the castles stand in.
const CASTLE_BEGIN = -120.0
const CASTLE_END = -540.0

var stage
var biome
var rng = RandomNumberGenerator.new()
var reserved: Array[Dictionary] = []
var counts := {}

func build(owner_stage, owner_biome) -> void:
	stage = owner_stage
	biome = owner_biome
	rng.seed = 20261017
	_camps()
	_castles()
	_talus()
	_steppe_cover()
	_floor_cover()
	_ash_grove()
	_ledge_markers()

func surface(p: Vector3) -> Vector3:
	p.y = stage.terrain_surface_height(p)
	return p

func random_point() -> Vector3:
	return Vector3(rng.randf_range(-196, 196), 0, rng.randf_range(-910, 60))

# A point somewhere on the gravel floor between the walls.
func random_floor_point(from_z: float, to_z: float) -> Vector3:
	var z = rng.randf_range(to_z, from_z)
	var half: float = Form.floor_half(z)
	return Vector3(Form.axis_x(z) + rng.randf_range(-half, half) * 1.05, 0.0, z)

# Open ground away from the road, the spectator areas and the camps.
func open_ground(p: Vector3, road: float, padding: float) -> bool:
	if stage.road_distance(p) < road or stage.parks.contains(p, 6.0):
		return false
	for c in stage.clearings:
		if Vector2(p.x - c.x, p.z - c.z).length() < 10.0 + padding:
			return false
	for spot in reserved:
		if Vector2(p.x - spot.pos.x, p.z - spot.pos.z).length() < float(spot.radius) + padding:
			return false
	return true

# The steppe table above the gorge.
func on_steppe(p: Vector3) -> bool:
	return stage.terrain_surface_height(p) > Form.rim_level(p) - 5.0

# The gravel floor of the gorge.
func on_floor(p: Vector3) -> bool:
	return stage.terrain_surface_height(p) < Form.bed_level(p.z) + 4.0

func place(spot: Array) -> Vector3:
	var s: float = spot[0]
	return surface(stage.at(s) + stage.side(s) * float(spot[1]) * float(spot[2]))

# ---------------------------------------------------------------- camps

func _camps() -> void:
	var steppe = place(STEPPE_CAMP)
	var grove = place(GROVE_CAMP)
	reserved.append({"pos": steppe, "radius": 17.0})
	reserved.append({"pos": grove, "radius": 16.0})
	MeshMerge.bake(Yurt.camp(stage, steppe, stage.at(STEPPE_CAMP[0]) - steppe, 3, "SteppeYurtCamp"))
	MeshMerge.bake(Yurt.camp(stage, grove, stage.at(GROVE_CAMP[0]) - grove, 2, "GroveYurtCamp"))

# ---------------------------------------------------------------- rock

func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	for point in [a, b, c]:
		st.set_color(color)
		st.add_vertex(point)

func _rock_node(st: SurfaceTool, node_name: String) -> void:
	st.generate_normals()
	var node = MeshInstance3D.new()
	node.name = node_name
	node.mesh = st.commit()
	var mat = Props.material(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = mat
	stage.add_child(node)

# A castle: a fluted tower, stepped where the softer marl has weathered back,
# standing on a skirt of its own debris and narrowing to a broken top.
func _tower(st: SurfaceTool, origin: Vector3, height: float, radius: float, seed_index: int) -> void:
	var sectors = 13
	var rings = 11
	for ring in range(rings):
		var low = float(ring) / rings
		var high = float(ring + 1) / rings
		var lower = radius * _taper(low, seed_index)
		var upper = radius * _taper(high, seed_index)
		var color = _tower_color(origin.y + low * height, seed_index)
		for sector in range(sectors):
			var angle = sector * TAU / sectors
			var next_angle = (sector + 1) * TAU / sectors
			var u = _flute(angle, seed_index)
			var v = _flute(next_angle, seed_index)
			var a = origin + u * lower + Vector3.UP * low * height
			var b = origin + v * lower + Vector3.UP * low * height
			var c = origin + u * upper + Vector3.UP * high * height
			var d = origin + v * upper + Vector3.UP * high * height
			_triangle(st, a, b, c, color)
			_triangle(st, b, d, c, color)
			if ring == rings - 1:
				_triangle(st, c, origin + Vector3.UP * height, d, color.lightened(0.07))

func _taper(t: float, seed_index: int) -> float:
	var skirt = 1.0 + 0.7 * exp(-t * 6.0)
	var body = 1.0 - 0.52 * smoothstep(0.0, 1.0, t)
	# Terraces where the softer beds have weathered back out of the tower.
	var steps = 1.0 + 0.1 * sin(t * 17.0 + seed_index) + 0.05 * sin(t * 41.0)
	return skirt * body * steps

# Deep vertical gullies down the face of the tower.
func _flute(angle: float, seed_index: int) -> Vector3:
	var groove = 1.0 + sin(angle * 5.0 + seed_index) * 0.24 + cos(angle * 9.0 - seed_index * 0.4) * 0.11
	return Vector3(cos(angle) * groove, 0, sin(angle) * groove)

# One tower's banding: the strata of the wall, read from a narrow palette —
# hard bands on a small shape look like paint rather than stone.
func _tower_color(height: float, seed_index: int) -> Color:
	var stone = Color("b0704a").lerp(Color("9a6043"), float(seed_index % 5) / 4.0)
	return stone.lightened(sin(height * 0.9 + seed_index) * 0.05 + sin(height * 0.21) * 0.07)

# The castles: a crowd of them at the foot of both walls through the Valley of
# Castles, more standing back on the benches and along the rim.
func _castles() -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var built = 0
	var index = 0
	var z = CASTLE_BEGIN
	while z > CASTLE_END:
		for side in [-1.0, 1.0]:
			index += 1
			if _castle(st, z, side, index):
				built += 1
		z -= 7.0
	_rock_node(st, "CanyonValleyTowers")
	counts["towers"] = built

# One castle beside the gorge at z: at the foot of the wall, on a bench of it
# or back on the rim, whichever this one is.
func _castle(st: SurfaceTool, z: float, side: float, index: int) -> bool:
	var run: float = Form.wall_run(z, side)
	var foot: float = Form.wall_foot(z, side)
	var kind = index % 3
	var reach = foot - rng.randf_range(0.0, 5.0)
	if kind == 1:
		reach = foot + run * rng.randf_range(0.2, 0.42)
	elif kind == 2:
		reach = Form.rim_edge(z, side) + rng.randf_range(3.0, 22.0)
	var p = Vector3(Form.axis_x(z) + side * reach, 0.0, z)
	if absf(p.x) > 192.0 or not open_ground(p, 15.0, 3.0):
		return false
	p = surface(p)
	if not _level_enough(p, 2.6 if kind != 0 else 4.5):
		return false
	var height = rng.randf_range(10.0, 30.0) if kind == 0 else rng.randf_range(6.0, 15.0)
	var radius = height * rng.randf_range(0.13, 0.22)
	_tower(st, p - Vector3.UP * 1.2, height, radius, index)
	stage.rocks.append(Records.rock(p, radius * 0.8, height))
	return true

# Ground flat enough for a block to have been left standing on it.
func _level_enough(p: Vector3, limit: float) -> bool:
	var height = stage.terrain_surface_height(p)
	for offset in [Vector3(2.5, 0, 0), Vector3(-2.5, 0, 0), Vector3(0, 0, 2.5), Vector3(0, 0, -2.5)]:
		if absf(stage.terrain_surface_height(p + offset) - height) > limit:
			return false
	return true

# Blocks that have come off the cliffs and piled up at their feet.
func _talus() -> void:
	var poses: Array = []
	var colors: Array = []
	for i in range(1100):
		var z = rng.randf_range(-700.0, -60.0)
		var side = 1.0 if i % 2 == 0 else -1.0
		var foot: float = Form.wall_foot(z, side)
		var p = Vector3(Form.axis_x(z) + side * (foot + rng.randf_range(-11.0, 6.0)), 0.0, z)
		if absf(p.x) > 196.0 or not open_ground(p, 9.0, 0.0):
			continue
		p = surface(p)
		if p.y > Form.bed_level(z) + 9.0 or not _level_enough(p, 2.0):
			continue
		var radius = rng.randf_range(0.4, 2.4)
		poses.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(radius * 1.3, radius * 0.9, radius * 1.1)), p + Vector3.UP * radius * 0.3))
		colors.append(biome.rock_color(p).lightened(rng.randf_range(-0.08, 0.08)))
		if radius > 1.2:
			stage.rocks.append(Records.rock(p, radius * 0.85, radius * 1.5, Records.FOREST))
	stage.detail_batch("CanyonTalus", stage.NATURE_BOULDER, poses, colors, DetailLayer.tiled(260.0))
	counts["talus"] = poses.size()

# ---------------------------------------------------------------- plants

# Feather grass, wormwood and sun-bleached stones of the open steppe.
func _steppe_cover() -> void:
	var feather_p: Array = []
	var feather_c: Array = []
	var bush_p: Array = []
	var bush_c: Array = []
	var stone_p: Array = []
	var stone_c: Array = []
	for i in range(16000):
		var p = random_point()
		if not open_ground(p, 5.0, 0.0):
			continue
		p = surface(p)
		if not on_steppe(p):
			continue
		var yaw = rng.randf() * TAU
		if i % 7 == 0:
			var bush = rng.randf_range(0.4, 1.1)
			bush_p.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(bush, bush * rng.randf_range(0.4, 0.7), bush)), p))
			bush_c.append(Color("7c7b55").lerp(Color("9a9468"), rng.randf()))
		elif i % 23 == 0:
			var radius = rng.randf_range(0.2, 0.6)
			stone_p.append(stage.woodland.shared_stone_pose(p, radius, yaw))
			stone_c.append(Color("ab9a80").lightened(rng.randf_range(-0.06, 0.08)))
		else:
			var size = rng.randf_range(0.8, 1.7)
			feather_p.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(size, rng.randf_range(0.9, 1.8), size)), p))
			feather_c.append(Color("d7c891").lerp(Color("b2a771"), rng.randf()))
	stage.detail_batch("SteppeFeatherGrass", stage.NATURE_GRASS, feather_p, feather_c, DetailLayer.tiled(170.0))
	stage.detail_batch("SteppeWormwood", stage.NATURE_BUSH, bush_p, bush_c, DetailLayer.tiled(210.0))
	stage.detail_batch("SteppeStones", stage.NATURE_STONE, stone_p, stone_c, DetailLayer.tiled(200.0))
	counts["feather_grass"] = feather_p.size()

# Tamarisk, dry reeds, river stones and the soft grass of the grove glades.
func _floor_cover() -> void:
	var bush_p: Array = []
	var bush_c: Array = []
	var grass_p: Array = []
	var grass_c: Array = []
	var stone_p: Array = []
	var stone_c: Array = []
	for i in range(9000):
		var p = random_floor_point(-40.0, -860.0)
		if absf(p.x) > 196.0 or not open_ground(p, 6.0, 0.0):
			continue
		p = surface(p)
		if not on_floor(p):
			continue
		var yaw = rng.randf() * TAU
		var green: float = Form.grove(p.z)
		if i % 5 == 0:
			var size = rng.randf_range(0.6, 1.9)
			bush_p.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(size, size * rng.randf_range(0.6, 1.1), size * 0.9)), p))
			bush_c.append(Color("6c6f45").lerp(Color("7f8a43"), green))
		elif i % 3 == 0:
			var radius = rng.randf_range(0.25, 1.15)
			stone_p.append(stage.woodland.shared_stone_pose(p, radius, yaw))
			stone_c.append(Color("9a8b78").lightened(rng.randf_range(-0.08, 0.1)))
			if radius > 0.95:
				stage.rocks.append(Records.rock(p, radius * 0.8, radius * 1.4, Records.FOREST))
		else:
			var size = rng.randf_range(0.7, 1.4)
			grass_p.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(size, rng.randf_range(1.0, 2.1), size)), p))
			grass_c.append(Color("c3b07a").lerp(Color("8a9a4e"), green).lerp(Color("948b5c"), rng.randf() * 0.5))
	stage.detail_batch("CanyonTamarisk", stage.NATURE_BUSH, bush_p, bush_c, DetailLayer.tiled(190.0))
	stage.detail_batch("CanyonReeds", stage.NATURE_GRASS, grass_p, grass_c, DetailLayer.tiled(150.0))
	stage.detail_batch("CanyonRiverStones", stage.NATURE_STONE, stone_p, stone_c, DetailLayer.tiled(210.0))
	counts["river_stones"] = stone_p.size()

# The relict Sogdian ash: broad, low crowns standing far apart on the gravel
# flats above the Ili, with soft grass between them and no undergrowth.
func _ash_grove() -> void:
	var stick = CylinderMesh.new()
	stick.top_radius = 0.34
	stick.bottom_radius = 0.5
	stick.height = 1.0
	stick.radial_segments = 6
	stick.rings = 1
	var crown = SphereMesh.new()
	crown.radial_segments = 9
	crown.rings = 5
	var trees: Array = []
	for i in range(1400):
		var p = random_floor_point(Form.GROVE_BEGIN, Form.GROVE_END)
		if absf(p.x) > 196.0 or Form.grove(p.z) < 0.3 or not open_ground(p, 9.0, 2.5):
			continue
		p = surface(p)
		if not on_floor(p) or not _level_enough(p, 1.2):
			continue
		var crowded = false
		for tree in trees:
			crowded = crowded or Vector2(p.x - tree.base.x, p.z - tree.base.z).length() < 7.0
		if crowded:
			continue
		trees.append({"base": p - Vector3.UP * 0.05, "height": rng.randf_range(5.5, 9.5), "yaw": rng.randf() * TAU, "shade": rng.randf_range(-0.05, 0.06)})
	stage.woodland.tree_layers("AshTree", trees, [
		{"mesh": stick, "scale": Vector3(0.07, 0.4, 0.07), "y": 0.2, "tilt": 0.1, "color": "7a6b52"},
		{"mesh": crown, "scale": Vector3(0.7, 0.42, 0.66), "y": 0.6, "dx": 0.08, "color": "6c7c46"},
		{"mesh": crown, "scale": Vector3(0.52, 0.34, 0.5), "y": 0.82, "dx": -0.1, "color": "7a8a50"},
	])
	counts["ash_trees"] = trees.size()

# ---------------------------------------------------------------- road edge

# Whitewashed blocks along the drop side of the shelf, as on every mountain
# road: they mark the edge without hiding it.
func _ledge_markers() -> void:
	var markers = Node3D.new()
	markers.name = "LedgeMarkers"
	stage.add_child(markers)
	var s = LEDGE_BEGIN
	while s < LEDGE_END:
		var p = stage.at(s) - stage.side(s) * (stage.road_width(s) * 0.5 + 1.2)
		p.y = stage.ground(p) + 0.42
		var block = Props.box(markers, p, Vector3(0.44, 0.84, 0.44), Color("e7e2d4"))
		block.rotation.y = rng.randf_range(-0.2, 0.2)
		Props.box(markers, p + Vector3(0, 0.3, 0), Vector3(0.46, 0.2, 0.46), Color("a33a28"))
		stage.rocks.append(Records.rock(p, 0.3, 0.9, Records.BARRIER))
		s += 11.0
	MeshMerge.bake(markers)

# ---------------------------------------------------------------- horizon

# The snow line of the Tien Shan, far beyond the steppe: blue with distance,
# with snow only on the summits.
func horizon() -> void:
	for i in range(11):
		var far = i % 3 == 2
		var p = Vector3(stage.rng.randf_range(430, 660), 30, -i * 96.0 + 20.0) if not far else Vector3(stage.rng.randf_range(-620, 620), 30, -1120.0 - stage.rng.randf_range(0, 200))
		var height = stage.rng.randf_range(120, 250)
		var radius = stage.rng.randf_range(190, 330)
		# cylinder() centres its mesh: the snow cap sits on the cone's own taper.
		var cap = height * 0.18
		RallyProps.cylinder(stage, p, radius, 0, height, Color("6f8296"), 6)
		RallyProps.cylinder(stage, p + Vector3.UP * (height - cap) * 0.5, radius * cap / height, 0, cap, Color("dbe6ee"), 6)
