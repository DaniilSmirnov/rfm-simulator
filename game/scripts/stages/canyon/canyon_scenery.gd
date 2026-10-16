extends RefCounted
# Scenery of «Чарынский каньон» (canyon.gd): the Valley of Castles — fluted
# towers of red rock at the foot of the walls, on their benches and along the
# rim — the talus of fallen blocks under every cliff, the feather-grass
# steppe above, the ash grove and boulders of the dry bed, two yurt camps and
# the stone markers of the ledge road. Placement uses its own seeded
# generator, so every room member builds the same gorge and stage.rng is
# never disturbed.
const Props = preload("res://scripts/core/props.gd")
const Records = preload("res://scripts/stages/stage_records.gd")
const DetailLayer = preload("res://scripts/stages/detail_layer.gd")
const MeshMerge = preload("res://scripts/core/mesh_merge.gd")
const Yurt = preload("res://scripts/stages/canyon/yurt.gd")

# Station, side and distance of the two yurt camps: the big one on the steppe
# by the first spectator area, a small one on the floor of the gorge.
const STEPPE_CAMP = [150.0, 1.0, 34.0]
const GORGE_CAMP = [648.0, 1.0, 33.0]
# Station of the rock gate the road passes through on its way to the rim.
const GATE = 190.0

var stage
var biome
var rng = RandomNumberGenerator.new()
var reserved: Array[Dictionary] = []
var counts := {}

func build(owner_stage, owner_biome) -> void:
	stage = owner_stage
	biome = owner_biome
	rng.seed = 20261016
	_camps()
	_valley_towers()
	_bench_towers()
	_talus()
	_gate()
	_steppe_cover()
	_gorge_cover()
	_ash_grove()
	_ledge_markers()

func surface(p: Vector3) -> Vector3:
	p.y = stage.terrain_surface_height(p)
	return p

func random_point() -> Vector3:
	return Vector3(rng.randf_range(-190, 190), 0, rng.randf_range(-stage.LENGTH - 60, 50))

# Open ground away from the road, the spectator areas and the camps.
func open_ground(p: Vector3, road: float, padding: float) -> bool:
	if stage.road_distance(p) < road or stage.parks.contains(p, 4.0):
		return false
	for c in stage.clearings:
		if Vector2(p.x - c.x, p.z - c.z).length() < 9.0 + padding:
			return false
	for spot in reserved:
		if Vector2(p.x - spot.pos.x, p.z - spot.pos.z).length() < float(spot.radius) + padding:
			return false
	return true

# The flat steppe table above the gorge.
func on_steppe(p: Vector3) -> bool:
	return stage.terrain_surface_height(p) > biome.PLATEAU - 5.0

# The floor of the gorge, within a few metres of the bed.
func on_floor(p: Vector3) -> bool:
	return stage.terrain_surface_height(p) < biome.bed_level(stage.road_s(p)) + 4.5

func place(spot: Array) -> Vector3:
	var s: float = spot[0]
	return surface(stage.at(s) + stage.side(s) * float(spot[1]) * float(spot[2]))

# ---------------------------------------------------------------- camps

func _camps() -> void:
	var steppe = place(STEPPE_CAMP)
	var gorge = place(GORGE_CAMP)
	reserved.append({"pos": steppe, "radius": 17.0})
	reserved.append({"pos": gorge, "radius": 15.0})
	MeshMerge.bake(Yurt.camp(stage, steppe, stage.at(STEPPE_CAMP[0]) - steppe, 3, "SteppeYurtCamp"))
	MeshMerge.bake(Yurt.camp(stage, gorge, stage.at(GORGE_CAMP[0]) - gorge, 2, "GorgeYurtCamp"))

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

# A castle of the valley: a fluted, terraced tower that keeps the strata of
# the wall it was cut from and narrows towards a broken top.
func _tower(st: SurfaceTool, origin: Vector3, height: float, radius: float, seed_index: int) -> void:
	var sectors = 11
	var rings = 8
	for ring in range(rings):
		var low = float(ring) / rings
		var high = float(ring + 1) / rings
		var lower = radius * _taper(low, seed_index)
		var upper = radius * _taper(high, seed_index)
		var color = _tower_color(origin + Vector3.UP * (low * height), seed_index)
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

# A skirt of fallen talus at the foot, a body that narrows to a broken spire
# and the terraces the softer marl weathers into.
func _taper(t: float, seed_index: int) -> float:
	var skirt = 1.0 + 0.4 * exp(-t * 8.0)
	var body = 1.0 - 0.64 * smoothstep(0.0, 1.0, t)
	return skirt * body * (1.0 + 0.07 * sin(t * 12.0 + seed_index))

# The strata of a tower: the same rock as the wall, but read from a narrow
# palette — hard bands on a small shape look like paint, not stone.
func _tower_color(point: Vector3, seed_index: int) -> Color:
	var stone = Color("b0704a").lerp(Color("9a6043"), float(seed_index % 5) / 4.0)
	return stone.lightened(sin(point.y * 0.9 + seed_index) * 0.05 + sin(point.y * 0.21) * 0.07)

# Deep vertical gullies down the face of the tower.
func _flute(angle: float, seed_index: int) -> Vector3:
	var groove = 1.0 + sin(angle * 5.0 + seed_index) * 0.17 + cos(angle * 9.0 - seed_index * 0.4) * 0.07
	return Vector3(cos(angle) * groove, 0, sin(angle) * groove)

# The towers of the Valley of Castles: a crowd of them at the foot of both
# walls, taller outliers standing back on the rim.
func _valley_towers() -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var built = 0
	for i in range(74):
		var s = 214.0 + i * 7.6
		var side = 1.0 if i % 2 == 0 else -1.0
		var half: float = biome.floor_half(s)
		var rim = i % 3 == 0
		var reach = half + biome.wall_run(s, side) + rng.randf_range(6.0, 26.0) if rim else half - rng.randf_range(0.0, 7.0)
		var p = stage.at(s) + stage.side(s) * side * reach
		if absf(p.x) > 188.0 or not open_ground(p, 16.0, 3.0):
			continue
		p = surface(p)
		if rim:
			if not on_steppe(p):
				continue
		elif not on_floor(p):
			continue
		var height = rng.randf_range(9.0, 17.0) if rim else rng.randf_range(12.0, 34.0)
		var radius = height * rng.randf_range(0.17, 0.3)
		_tower(st, p - Vector3.UP * 1.2, height, radius, i)
		stage.rocks.append(Records.rock(p, radius * 0.82, height))
		built += 1
	_rock_node(st, "CanyonValleyTowers")
	counts["towers"] = built

# Two tall rocks the road threads between on its way to the rim.
func _gate() -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		var p = surface(stage.at(GATE) + stage.side(GATE) * side * 13.0)
		_tower(st, p - Vector3.UP * 1.5, 26.0, 5.6, int(side) + 3)
		stage.rocks.append(Records.rock(p, 5.0, 26.0))
	_rock_node(st, "CanyonGate")

# Pinnacles left standing on the benches of the wall, halfway up the cliff,
# where the softer marl has weathered back from a harder block.
func _bench_towers() -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var built = 0
	for i in range(64):
		var s = 424.0 + i * 4.9
		var side = 1.0 if i % 2 == 0 else -1.0
		var run: float = biome.wall_run(s, side)
		var foot: float = biome.wall_foot(s, biome.floor_half(s))
		var p = stage.at(s) + stage.side(s) * side * (foot + run * rng.randf_range(0.26, 0.38))
		if absf(p.x) > 192.0 or not open_ground(p, 16.0, 2.0) or not _level_enough(p, 2.4):
			continue
		p = surface(p)
		var height = rng.randf_range(5.0, 13.0)
		_tower(st, p - Vector3.UP * 1.0, height, height * rng.randf_range(0.16, 0.26), i + 7)
		stage.rocks.append(Records.rock(p, height * 0.16, height))
		built += 1
	_rock_node(st, "CanyonBenchTowers")
	counts["bench_towers"] = built

# Ground flat enough for a block to be left standing on it.
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
	for i in range(900):
		var s = rng.randf_range(206.0, 790.0)
		var side = 1.0 if i % 2 == 0 else -1.0
		var foot: float = biome.wall_foot(s, biome.floor_half(s))
		var p = stage.at(s) + stage.side(s) * side * (foot + rng.randf_range(-9.0, 7.0))
		if absf(p.x) > 196.0 or not open_ground(p, 9.0, 0.0):
			continue
		p = surface(p)
		if p.y > biome.bed_level(stage.road_s(p)) + 7.0 or not _level_enough(p, 1.8):
			continue
		var radius = rng.randf_range(0.4, 2.4)
		poses.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(radius * 1.3, radius * 0.9, radius * 1.1)), p + Vector3.UP * radius * 0.3))
		colors.append(biome.rock_color(p).lightened(rng.randf_range(-0.08, 0.08)))
		if radius > 1.1:
			stage.rocks.append(Records.rock(p, radius * 0.85, radius * 1.5, Records.FOREST))
	stage.detail_batch("CanyonTalus", stage.NATURE_BOULDER, poses, colors, DetailLayer.tiled(260.0))
	counts["talus"] = poses.size()

# ---------------------------------------------------------------- plants

# Feather grass, wormwood and sun-bleached stones of the open steppe.
func _steppe_cover() -> void:
	var feather_p: Array = []
	var feather_c: Array = []
	var wormwood_p: Array = []
	var wormwood_c: Array = []
	var stone_p: Array = []
	var stone_c: Array = []
	for i in range(15000):
		var p = random_point()
		if not open_ground(p, 5.0, 0.0):
			continue
		p = surface(p)
		if not on_steppe(p):
			continue
		var yaw = rng.randf() * TAU
		if i % 7 == 0:
			var bush = rng.randf_range(0.4, 1.1)
			wormwood_p.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(bush, bush * rng.randf_range(0.4, 0.7), bush)), p))
			wormwood_c.append(Color("7c7b55").lerp(Color("9a9468"), rng.randf()))
		elif i % 23 == 0:
			var radius = rng.randf_range(0.2, 0.6)
			stone_p.append(stage.woodland.shared_stone_pose(p, radius, yaw))
			stone_c.append(Color("ab9a80").lightened(rng.randf_range(-0.06, 0.08)))
		else:
			var size = rng.randf_range(0.8, 1.7)
			feather_p.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(size, rng.randf_range(0.9, 1.8), size)), p))
			feather_c.append(Color("d7c891").lerp(Color("b2a771"), rng.randf()))
	stage.detail_batch("SteppeFeatherGrass", stage.NATURE_GRASS, feather_p, feather_c, DetailLayer.tiled(170.0))
	stage.detail_batch("SteppeWormwood", stage.NATURE_BUSH, wormwood_p, wormwood_c, DetailLayer.tiled(210.0))
	stage.detail_batch("SteppeStones", stage.NATURE_STONE, stone_p, stone_c, DetailLayer.tiled(200.0))
	counts["feather_grass"] = feather_p.size()

# Tamarisk, dry reeds and river boulders on the floor of the gorge.
func _gorge_cover() -> void:
	var bush_p: Array = []
	var bush_c: Array = []
	var reed_p: Array = []
	var reed_c: Array = []
	var stone_p: Array = []
	var stone_c: Array = []
	for i in range(8000):
		var p = random_point()
		if not open_ground(p, 6.0, 0.0):
			continue
		p = surface(p)
		if not on_floor(p):
			continue
		var yaw = rng.randf() * TAU
		if i % 5 == 0:
			var size = rng.randf_range(0.6, 1.9)
			bush_p.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(size, size * rng.randf_range(0.6, 1.1), size * 0.9)), p))
			bush_c.append(Color("6c6f45").lerp(Color("8d7a52"), rng.randf()))
		elif i % 3 == 0:
			var radius = rng.randf_range(0.25, 1.15)
			stone_p.append(stage.woodland.shared_stone_pose(p, radius, yaw))
			stone_c.append(Color("9a8b78").lightened(rng.randf_range(-0.08, 0.1)))
			if radius > 0.9:
				stage.rocks.append(Records.rock(p, radius * 0.8, radius * 1.4, Records.FOREST))
		else:
			var size = rng.randf_range(0.7, 1.4)
			reed_p.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(size, rng.randf_range(1.0, 2.1), size)), p))
			reed_c.append(Color("c3b07a").lerp(Color("948b5c"), rng.randf()))
	stage.detail_batch("CanyonTamarisk", stage.NATURE_BUSH, bush_p, bush_c, DetailLayer.tiled(190.0))
	stage.detail_batch("CanyonReeds", stage.NATURE_GRASS, reed_p, reed_c, DetailLayer.tiled(150.0))
	stage.detail_batch("CanyonRiverStones", stage.NATURE_STONE, stone_p, stone_c, DetailLayer.tiled(210.0))
	counts["river_stones"] = stone_p.size()

# The Sogdian ash grove of the park: broad, low crowns standing in the bed
# where the water still reaches their roots.
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
	for i in range(150):
		var s = rng.randf_range(552.0, 698.0)
		var side = 1.0 if i % 2 == 0 else -1.0
		var p = stage.at(s) + stage.side(s) * side * rng.randf_range(8.0, 27.0)
		if not open_ground(p, 8.5, 2.0):
			continue
		p = surface(p)
		if not on_floor(p):
			continue
		trees.append({"base": p - Vector3.UP * 0.05, "height": rng.randf_range(5.0, 8.5), "yaw": rng.randf() * TAU, "shade": rng.randf_range(-0.05, 0.06)})
	stage.woodland.tree_layers("AshTree", trees, [
		{"mesh": stick, "scale": Vector3(0.07, 0.4, 0.07), "y": 0.2, "tilt": 0.1, "color": "7a6b52"},
		{"mesh": crown, "scale": Vector3(0.66, 0.4, 0.62), "y": 0.6, "dx": 0.08, "color": "6c7c46"},
		{"mesh": crown, "scale": Vector3(0.5, 0.32, 0.48), "y": 0.8, "dx": -0.1, "color": "7a8a50"},
	])
	counts["ash_trees"] = trees.size()

# ---------------------------------------------------------------- road edge

# Whitewashed stone blocks along the drop side of the ledge, as on every
# mountain road: they mark the edge without hiding it.
func _ledge_markers() -> void:
	var markers = Node3D.new()
	markers.name = "LedgeMarkers"
	stage.add_child(markers)
	var s = 212.0
	while s < 412.0:
		var p = stage.at(s) - stage.side(s) * (stage.road_width(s) * 0.5 + 1.1)
		p.y = stage.ground(p) + 0.42
		var block = Props.box(markers, p, Vector3(0.44, 0.84, 0.44), Color("e7e2d4"))
		block.rotation.y = rng.randf_range(-0.2, 0.2)
		Props.box(markers, p + Vector3(0, 0.3, 0), Vector3(0.46, 0.2, 0.46), Color("a33a28"))
		stage.rocks.append(Records.rock(p, 0.3, 0.9, Records.BARRIER))
		s += 11.0
	MeshMerge.bake(markers)

# ---------------------------------------------------------------- horizon

# The snow line of the Tien Shan, far beyond the steppe to the south and
# ahead of the stage: blue with distance, with snow only on the summits.
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
