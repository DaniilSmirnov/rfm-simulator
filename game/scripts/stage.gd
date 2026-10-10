extends Node3D
class_name RallyStage

const NATURE_TREE_MESHES = [
	preload("res://models/nature/tree_trunk.tres"),
	preload("res://models/nature/tree_crown_lower.tres"),
	preload("res://models/nature/tree_crown_middle.tres"),
	preload("res://models/nature/tree_crown_top.tres")
]
const NATURE_GRASS = preload("res://models/nature/grass.obj")
const NATURE_STONE = preload("res://models/nature/stone.tres")
const NATURE_BOULDER = preload("res://models/nature/boulder.tres")
const NATURE_BUSH = preload("res://models/nature/bush.tres")
const NATURE_BUSH_STEM = preload("res://models/nature/bush_stem.tres")
const NATURE_BERRY = preload("res://models/nature/berry.tres")
const NATURE_MUSHROOM_CAP = preload("res://models/nature/mushroom_cap.tres")
const NATURE_MUSHROOM_STEM = preload("res://models/nature/mushroom_stem.tres")


var officials: Node3D
const Officials = preload("res://scripts/course_officials.gd")

const DeepSnow = preload("res://scripts/deep_snow.gd")
var snow = DeepSnow.new()
const Snowbanks = preload("res://scripts/snowbanks.gd")
const StageRegistry = preload("res://scripts/stage_registry.gd")
const StageSolids = preload("res://scripts/stage_solids.gd")
const WorldSync = preload("res://scripts/world_sync.gd")
# Everything that differs between stages lives in the biome (stage_biome.gd);
# this file is the shared machinery around it.
var biome
# Shared features a biome switches on.
var has_snow = false
var water: RefCounted # lakes (water.gd), null on dry stages
# Read-only views of the biome, kept for its own helper scripts, tools and tests.
var canyon: RefCounted:
	get: return biome if stage_id == "canyon" else null
var finnish_forest: RefCounted:
	get: return biome if stage_id == "lakes" else null
var alpine: RefCounted:
	get: return biome if stage_id == "winter" else null
var village: RefCounted:
	get: return biome if stage_id == "provence" else null
var forest_life: RefCounted:
	get: return biome.get("forest_life") if biome != null else null
var alpine_life: RefCounted:
	get: return biome.get("alpine_life") if biome != null else null
# Stage identity for tools and tests; gameplay code asks the biome instead.
var stage_id = ""
var winter: bool:
	get: return stage_id == "winter"
var provence: bool:
	get: return stage_id == "provence"
var desert: bool:
	get: return stage_id == "canyon"
var lakeland: bool:
	get: return stage_id == "lakes"
# Static and destructible scenery (houses, walls, lamps); empty on most stages.
var solids: Node3D
var life: RefCounted
const BakedVillage = preload("res://scripts/baked_village.gd")
var baked_scene_path = "res://generated/village.scn"
var loaded_baked = false
var snow_camps: Array[Vector3] = []
var snow_glades: Array[Vector3] = []
const GLADE_COUNT = 6
const GLADE_OFFSET = 14.0
const GLADE_FLAT = 6.5
const GLADE_BLEND = 12.0
const GLADE_STRAIGHT = 18.0
const GLADE_MAX_TURN = 0.45
const GLADE_SPACING = 30.0
var snowbank_cells: Dictionary = {}
# Used only by the offline baker/tests; ordinary gameplay retains no CPU copy.
var capture_bake_buffers = false
const LENGTH = 840.0
const STEP = 4.0
const WIDTH = 7.4
# Five side-lane rows spaced 0.8 m apart, each stone 0.76 m wide.
const SIDE_LANE_WIDTH = 3.96
const TREE_CELL_SIZE = 16.0
# Menu captions of every stage, in content_id order (res://data/stages.json).
static var STAGES: Array = StageRegistry.captions()
var variant = 0
var points: PackedVector3Array = []
# Nearest-segment index of a winding route (stations are not -z there).
var route_segment_step = STEP
# Winding routes find stations by searching the index (see stage_biome.gd).
var winding = false
var _last_route_group = 0
var road_segment_starts = PackedVector2Array()
var road_segment_deltas = PackedVector2Array()
var road_segment_inverse_lengths = PackedFloat64Array()
var road_group_low = PackedVector2Array()
var road_group_high = PackedVector2Array()
const ROAD_GROUP_SIZE = 8
var clearings: Array[Vector3] = []
var trails: Array[Dictionary] = []
var woodland_details: Dictionary = {}
var collectibles: Array[Dictionary] = []
const COLLECTIBLE_CELL_SIZE = 8.0
var collectible_cells: Dictionary = {}
var indexed_collectible_count = -1
var harvested: Dictionary = {}
var collectible_parts: Dictionary = {}
var rocks: Array[Dictionary] = []
var rock_cells: Dictionary = {}
var dynamic_rock_ids: Array = []
var indexed_rock_count = -1
const ROCK_CELL_SIZE = 16.0
var trees: Array[Vector3] = []
var forest_data: Array[Dictionary] = []
var detail_tree_groups: Dictionary = {}
var detail_tree_visuals: Dictionary = {}
var forest_layers: Array[Array] = []
var forest_chunk_slots: Array[Vector2i] = []
var forest_chunk_centers: Array[Vector3] = []
const FOREST_RENDER_CELL = 64.0
var tree_cells: Dictionary = {}
var indexed_tree_count = -1
var fallen: Dictionary = {}
var rng = RandomNumberGenerator.new()

func _init(selected: int = 0) -> void:
	variant = clampi(selected, 0, STAGES.size() - 1)
	stage_id = StageRegistry.entry(variant).id
	# Joins the scene only when the world is built: the menu stays empty.
	solids = StageSolids.new()
	solids.name = "StageSolids"
	solids.stage = self
	biome = StageRegistry.make_biome(variant)
	biome.attach(self)
	has_snow = biome.has_snow()
	water = biome.make_water()
	if water != null:
		water.stage = self
	for i in range(int(LENGTH / STEP) + 1):
		points.append(biome.route(i * STEP))
	winding = biome.winding_route()
	if winding:
		# Index the fine route table: corners and hairpins need metre samples.
		var samples = PackedVector3Array()
		for i in range(int(LENGTH) + 1):
			samples.append(biome.route(float(i)))
		_index_route(samples, 1.0)
	biome.configure()

func at(s: float) -> Vector3:
	s = clampf(s, 0, LENGTH - 0.001)
	if winding:
		return biome.route(s)
	var index = int(s / STEP)
	return points[index].lerp(points[index + 1], fmod(s, STEP) / STEP)

func direction(s: float) -> Vector3:
	return (at(minf(s + 2, LENGTH - 0.01)) - at(maxf(s - 2, 0))).normalized()

func side(s: float) -> Vector3:
	return direction(s).cross(Vector3.UP).normalized()

func road_s(pos: Vector3) -> float:
	if winding:
		return float(route_nearest(pos).s)
	return clampf(-pos.z, 0, LENGTH)

func road_distance(pos: Vector3) -> float:
	if winding:
		return float(route_nearest(pos).distance)
	var p = at(road_s(pos))
	return Vector2(pos.x - p.x, pos.z - p.z).length()

func grip(pos: Vector3) -> float:
	return biome.grip(pos)

# Walking floor: jetty decks, wading and floating swimmers on lake stages.
func walk_floor(pos: Vector3, ground_height: float) -> float:
	return biome.walk_floor(pos, ground_height)

func vehicle_ground(pos: Vector3) -> float:
	return biome.vehicle_ground(pos)

# Top surface: the land, dug snow floors and snowbanks.
func ground(pos: Vector3) -> float:
	return biome.ground(pos)

# Feet break through loose snow; tyre tracks and excavations hold the walker up.
func walking_ground(pos: Vector3) -> float:
	return biome.walking_ground(pos)

func snow_sink(pos: Vector3) -> float:
	return maxf(0.0, ground(pos) - walking_ground(pos))

# Analytic land height, before snow.
func base_ground(pos: Vector3) -> float:
	return biome.base_ground(pos)

# Spectator clearings are level: blend the land towards each one.
func blend_clearings(pos: Vector3, height: float, inner: float, outer: float) -> float:
	for clearing in clearings:
		var d = Vector2(pos.x - clearing.x, pos.z - clearing.z).length()
		height = lerpf(clearing.y, height, smoothstep(inner, outer, d))
	return height

# Footpaths to the clearings are cut into the slope.
func blend_trails(pos: Vector3, height: float) -> float:
	for trail in trails:
		if not _trail_near(pos, trail, float(trail.width)):
			continue
		var trail_sample = _trail_sample(pos, trail)
		if trail_sample.distance < trail.width:
			var blend = 1.0 - smoothstep(trail.width * 0.55, trail.width, trail_sample.distance)
			height = lerpf(height, trail_sample.height, blend)
	return height

# Trees must touch the *rendered* terrain, not the continuous ground()
# function. Terrain is triangulated in 4 m cells (2 m near forest roads)
# and its vertices are 0.25 m below ground(). Reproduce that interpolation
# exactly to avoid suspended trunks on slopes and relief crests.
# The 2 m roadside tiles meet 4 m terrain tiles at T-junctions.
# On those boundaries, snap the fine tile's midpoint to the coarse edge.
# Otherwise the ground() midpoint can be above/below the straight 4 m edge,
# creating visible cracks (and floating trees).
# The village is baked offline: memoise tile steps and vertex heights while its
# terrain, road and planting are generated (cleared after the build).
var terrain_cache_enabled = false
var _tile_step_cache: Dictionary = {}
var _vertex_height_cache: Dictionary = {}

func _set_terrain_cache(enabled: bool) -> void:
	terrain_cache_enabled = enabled
	_tile_step_cache.clear()
	_vertex_height_cache.clear()

func terrain_tile_step(cell_x: float, cell_z: float) -> float:
	if terrain_cache_enabled:
		var key = Vector2(cell_x, cell_z)
		if not _tile_step_cache.has(key):
			_tile_step_cache[key] = _terrain_tile_step(cell_x, cell_z)
		return _tile_step_cache[key]
	return _terrain_tile_step(cell_x, cell_z)

func _terrain_tile_step(cell_x: float, cell_z: float) -> float:
	return biome.terrain_tile_step(Vector3(cell_x + 2.0, 0, cell_z + 2.0))

func terrain_base_vertex_height(x: float, z: float) -> float:
	var p = Vector3(x, 0, z)
	return base_ground(p) - 0.25

func terrain_vertex_height(x: float, z: float) -> float:
	if terrain_cache_enabled:
		var key = Vector2(x, z)
		if not _vertex_height_cache.has(key):
			_vertex_height_cache[key] = _terrain_vertex_height(x, z)
		return _vertex_height_cache[key]
	return _terrain_vertex_height(x, z)

func _terrain_vertex_height(x: float, z: float) -> float:
	return biome.terrain_vertex_height(x, z)

# Vertex height with fine roadside tiles snapped to the coarse neighbouring edge.
func snapped_vertex_height(x: float, z: float) -> float:
	var cell_x = floorf(x / 4.0) * 4.0
	var cell_z = floorf(z / 4.0) * 4.0
	if not is_equal_approx(x, cell_x) and is_equal_approx(z, cell_z):
		var edge_step = maxf(terrain_tile_step(cell_x, z - 4), terrain_tile_step(cell_x, z))
		var begin = floorf(x / edge_step) * edge_step
		return lerpf(terrain_base_vertex_height(begin, z), terrain_base_vertex_height(begin + edge_step, z), (x - begin) / edge_step)
	elif not is_equal_approx(z, cell_z) and is_equal_approx(x, cell_x):
		var edge_step = maxf(terrain_tile_step(x - 4, cell_z), terrain_tile_step(x, cell_z))
		var begin = floorf(z / edge_step) * edge_step
		return lerpf(terrain_base_vertex_height(x, begin), terrain_base_vertex_height(x, begin + edge_step), (z - begin) / edge_step)
	return terrain_base_vertex_height(x, z)

func terrain_surface_height(pos: Vector3) -> float:
	var cell_x = floorf(pos.x / 4.0) * 4.0
	var cell_z = floorf(pos.z / 4.0) * 4.0
	var step = terrain_tile_step(cell_x, cell_z)
	var x = cell_x + floorf((pos.x - cell_x) / step) * step
	var z = cell_z + floorf((pos.z - cell_z) / step) * step
	var u = clampf((pos.x - x) / step, 0.0, 1.0)
	var v = clampf((pos.z - z) / step, 0.0, 1.0)
	var a = terrain_vertex_height(x, z)
	var b = terrain_vertex_height(x + step, z)
	var c = terrain_vertex_height(x, z + step)
	var d = terrain_vertex_height(x + step, z + step)
	if u + v <= 1.0:
		return a + (b - a) * u + (c - a) * v
	return d + (c - d) * (1.0 - u) + (b - d) * (1.0 - v)

func terrain_basis(pos: Vector3, yaw: float, sampler: Callable = Callable()) -> Basis:
	var heights = sampler if sampler.is_valid() else terrain_surface_height
	var dx: float = heights.call(pos + Vector3(0.2, 0, 0)) - heights.call(pos - Vector3(0.2, 0, 0))
	var dz: float = heights.call(pos + Vector3(0, 0, 0.2)) - heights.call(pos - Vector3(0, 0, 0.2))
	var up = Vector3(-dx / 0.4, 1.0, -dz / 0.4).normalized()
	var forward = Basis(Vector3.UP, yaw).z
	var right = up.cross(forward).normalized()
	return Basis(right, up, right.cross(up).normalized())

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

func _trail_near(pos: Vector3, trail: Dictionary, padding: float) -> bool:
	if not trail.has("bounds"):
		var low = flat(trail.points[0])
		var high = low
		for point in trail.points:
			low = low.min(flat(point))
			high = high.max(flat(point))
		trail.bounds = Rect2(low, high - low)
	var bounds: Rect2 = trail.bounds
	var p = flat(pos)
	return p.distance_squared_to(p.clamp(bounds.position, bounds.end)) <= padding * padding

func trail_distance(pos: Vector3, cutoff: float = INF) -> float:
	var distance = cutoff
	for trail in trails:
		if cutoff != INF and not _trail_near(pos, trail, cutoff):
			continue
		distance = minf(distance, float(_trail_sample(pos, trail).distance))
	return distance

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(solids) and solids.get_parent() == null:
		solids.free()

func _attach_solids() -> void:
	if solids.get_parent() == null:
		add_child(solids)

func build(use_baked: bool = true) -> void:
	_attach_solids()
	if biome.uses_baked_scene() and use_baked and BakedVillage.load_into(self, baked_scene_path):
		biome.after_baked_load()
		_build_finish()
		return
	rng.seed = 7102026 + variant * 971
	_set_terrain_cache(biome.cache_terrain())
	_build_terrain()
	_build_road()
	_build_nature()
	_build_details()
	_set_terrain_cache(false)
	_build_finish()

func build_async(progress: Callable) -> void:
	_attach_solids()
	if biome.uses_baked_scene() and ResourceLoader.exists(baked_scene_path):
		await progress.call("Загрузка спецучастка", 0)
		if await BakedVillage.load_into_async(self, baked_scene_path, progress):
			biome.after_baked_load()
			await progress.call("Судьи и указатели", 75)
			_build_finish()
			return
	rng.seed = 7102026 + variant * 971
	_set_terrain_cache(biome.cache_terrain())
	await progress.call("Рельеф", 0)
	await _build_terrain(true)
	await progress.call("Дорога", 30)
	_build_road()
	await progress.call(str(StageRegistry.value(variant, "loading")), 40)
	await _build_nature(true)
	await progress.call("Объекты спецучастка", 55)
	await _build_details(true)
	_set_terrain_cache(false)
	await progress.call("Судьи и указатели", 75)
	_build_finish()

# The shared conifer forest and roadside rocks; stages without a forest (the
# village builds its own groves, the canyon has none) plant zero trees.
func _build_nature(cooperative: bool = false) -> void:
	var tree_count = biome.forest_tree_count()
	if tree_count <= 0:
		return
	var max_height = biome.forest_tree_max_height()
	var clearing_radius = biome.forest_clearing_radius()
	var forest: Array[Dictionary] = []
	for i in range(tree_count):
		if cooperative and i % 400 == 0:
			await get_tree().process_frame
		var p = Vector3(rng.randf_range(-150, 150), 0, rng.randf_range(-LENGTH - 65, 50))
		if road_distance(p) < 9:
			continue
		if biome.tree_blocked(p):
			continue
		var in_clearing = false
		for c in clearings:
			if Vector2(p.x - c.x, p.z - c.z).length() < clearing_radius:
				in_clearing = true
		for c in snow_glades:
			if Vector2(p.x - c.x, p.z - c.z).length() < GLADE_FLAT + 3.0:
				in_clearing = true
		if in_clearing:
			continue
		p.y = terrain_surface_height(p) - 0.03
		trees.append(p)
		forest.append({"position": p, "height": rng.randf_range(6, max_height), "shade": rng.randf_range(-0.025, 0.045)})
	forest_data = forest
	_rebuild_tree_index()
	_build_forest(forest)
	for i in range(100):
		var s = rng.randf_range(20, LENGTH - 15)
		var p = at(s) + side(s) * rng.randf_range(-6, 6)
		if road_distance(p) < 4.3:
			continue
		if biome.roadside_rock_blocked(p):
			continue
		p.y = ground(p)
		var radius = rng.randf_range(0.3, 1)
		var rock = RallyProps.cylinder(self, p + Vector3(0, 0.2, 0), radius, 0.18, 0.65, Color("7d8070"), 5)
		rocks.append({"pos": p, "radius": radius, "height": 0.75})
		rock.rotation.z = rng.randf_range(-0.3, 0.3)

func _build_details(cooperative: bool = false) -> void:
	await biome.build_details(cooperative)

func _build_finish() -> void:
	if biome.clearing_signs():
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
	biome.build_horizon()

	officials = Officials.new()
	officials.stage = self
	add_child(officials)
	officials.build()

# Distant angular ridges, original meshes (forest stages).
func build_ridges() -> void:
	for i in range(18):
		var p = Vector3((-1 if i % 2 == 0 else 1) * rng.randf_range(220, 340), 30, -i * 65.0)
		RallyProps.cylinder(self, p, rng.randf_range(120, 180), 0, rng.randf_range(130, 210), Color("697d70"), 5)

func _build_terrain(cooperative: bool = false) -> void:
	var builders: Dictionary = {}
	# Shared vertices of neighbouring triangles are coloured once.
	var colors: Dictionary = {}
	var tiled = biome.terrain_tiled()
	for z in range(-920, 81, 4):
		if cooperative and (z + 920) % 64 == 0:
			await get_tree().process_frame
		for x in range(-204, 204, 4):
			var tile = Vector2i(floori(x / 64.0), floori(z / 64.0)) if tiled else Vector2i.ZERO
			if not builders.has(tile):
				var builder = SurfaceTool.new()
				builder.begin(Mesh.PRIMITIVE_TRIANGLES)
				builders[tile] = builder
			var st: SurfaceTool = builders[tile]
			# Resolve narrow roadside ditches without subdividing the whole map.
			var step = int(terrain_tile_step(x, z))
			for dz in range(0, 4, step):
				for dx in range(0, 4, step):
					var a = Vector3(x + dx, 0, z + dz)
					var b = a + Vector3(step, 0, 0)
					var c = a + Vector3(0, 0, step)
					var d = a + Vector3(step, 0, step)
					for v in [a, b, c, b, d, c]:
						v.y = terrain_vertex_height(v.x, v.z)
						var key = Vector2(v.x, v.z)
						if not colors.has(key):
							colors[key] = biome.terrain_color(v)
						var color: Color = colors[key]
						st.set_color(color.lightened(rng.randf_range(-0.07, 0.07)))
						st.add_vertex(v)
	var mat = RallyProps.material(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	for tile in builders:
		var st: SurfaceTool = builders[tile]
		st.generate_normals()
		var n = MeshInstance3D.new()
		n.name = "TerrainTile_%d_%d" % [tile.x, tile.y]
		n.mesh = st.commit()
		n.material_override = mat
		add_child(n)
		biome.terrain_chunk_built(tile, n)

func road_width(s: float) -> float:
	return biome.road_width(s)

func road_surface_vertex(s: float, lateral: float) -> Vector3:
	var p = at(s) + side(s) * lateral
	p.y = ground(p) + 0.04
	return p

func road_surface_color(p: Vector3, s: float) -> Color:
	return biome.road_color(p, s)

func road_surface_kind(s: float) -> String:
	return biome.road_surface_kind(s)

func _build_road() -> void:
	# One mesh per surface kind: the village cobbles carry a texture.
	var builders: Dictionary = {}
	# Strips share their edge vertices; sample ground and colour once per vertex.
	var vertices: Dictionary = {}
	var vertex = func(station: float, lateral: float) -> Vector3:
		var key = Vector2(station, lateral)
		if not vertices.has(key):
			vertices[key] = road_surface_vertex(station, lateral)
		return vertices[key]
	var colors: Dictionary = {}
	var color_of = func(v: Vector3, station: float) -> Color:
		if not colors.has(v):
			colors[v] = road_surface_color(v, station)
		return colors[v]
	var seam_shoulders = biome.road_seam_shoulders()
	for i in range(int(LENGTH)):
		var s = float(i)
		var kind = road_surface_kind(s)
		if not builders.has(kind):
			var builder = SurfaceTool.new()
			builder.begin(Mesh.PRIMITIVE_TRIANGLES)
			builders[kind] = builder
		var st: SurfaceTool = builders[kind]
		# Bound physical segment length as well as station length.
		var divisions = maxi(4, ceili(at(s).distance_to(at(s + 1.0)) / 0.75))
		for segment in range(divisions):
			var begin = s + float(segment) / divisions
			var end = s + float(segment + 1) / divisions
			var strips = biome.road_strips()
			for strip in range(strips):
				var width = road_width(s)
				var left = -width * 0.5 + width * float(strip) / strips
				var right = -width * 0.5 + width * float(strip + 1) / strips
				var a: Vector3 = vertex.call(begin, right)
				var b: Vector3 = vertex.call(begin, left)
				var c: Vector3 = vertex.call(end, right)
				var d: Vector3 = vertex.call(end, left)
				for v in [a, b, c, b, d, c]:
					st.set_color(color_of.call(v, s))
					st.set_uv(Vector2(v.x, v.z) * 0.45)
					st.add_vertex(v)
			if seam_shoulders:
				# A visible earth shoulder closes the road-to-terrain seam.
				# Keep the analytical tyre-contact surface unchanged.
				for edge_side in [-1.0, 1.0]:
					var a: Vector3 = vertex.call(begin, edge_side * road_width(s) * 0.5)
					var b: Vector3 = vertex.call(end, edge_side * road_width(s) * 0.5)
					var c = a
					var d = b
					c.y = terrain_surface_height(c)
					d.y = terrain_surface_height(d)
					for v in ([a, c, b, b, c, d] if edge_side > 0 else [a, b, c, b, d, c]):
						st.set_color(color_of.call(v, s).darkened(0.12))
						st.set_uv(Vector2(v.x, v.z) * 0.45)
						st.add_vertex(v)
		# Broken muddy wheel tracks, shallow puddles.
		var ruts = (i % 12 == 0 or i % 52 == 28) and biome.road_ruts(s)
		if ruts and i % 12 == 0:
			for offset in [-1.0, 1.0]:
				var p = at(s) + side(s) * offset
				p.y = ground(p)
				var rut = RallyProps.box(self, p + Vector3(0, 0.07, 0), Vector3(0.5, 0.025, 2.7), Color("77654c"))
				rut.rotation.y = atan2(-direction(s).x, -direction(s).z)
		if ruts and i % 52 == 28:
			var p = at(s) + side(s) * 1.5
			p.y = ground(p)
			var puddle = RallyProps.cylinder(self, p + Vector3(0, 0.10, 0), 1.1, 1.1, 0.025, Color("56645d"), 9)
			puddle.scale.z = 1.7
	var kinds = builders.keys()
	kinds.sort()
	for kind in kinds:
		var st: SurfaceTool = builders[kind]
		# Shared positions and colours allow smooth normals across strip joins.
		st.index()
		st.generate_normals()
		var n = MeshInstance3D.new()
		n.mesh = st.commit()
		var surface_material = biome.road_material(kind)
		if surface_material != null:
			n.material_override = surface_material
		else:
			var mat = RallyProps.material(Color.WHITE)
			mat.vertex_color_use_as_albedo = true
			mat.vertex_color_is_srgb = true
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			n.material_override = mat
		n.name = "StageRoadSurface" if kind == "default" else "StageRoadSurface_" + kind
		add_child(n)
	biome.after_road()


# Four instanced draw calls for the forest instead of thousands of nodes.
# Collision positions remain in `trees`, matching the original gameplay.
func shared_tree_mesh(layer: int) -> CylinderMesh:
	return NATURE_TREE_MESHES[layer]

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
	forest_chunk_slots.resize(forest.size())
	for index in range(forest.size()):
		var p: Vector3 = forest[index].position
		var cell = Vector2i(floori(p.x / FOREST_RENDER_CELL), floori(p.z / FOREST_RENDER_CELL))
		if not cells.has(cell):
			cells[cell] = groups.size()
			groups.append([])
			forest_chunk_centers.append(Vector3((cell.x + 0.5) * FOREST_RENDER_CELL, 0, (cell.y + 0.5) * FOREST_RENDER_CELL))
		var chunk: int = cells[cell]
		forest_chunk_slots[index] = Vector2i(chunk, groups[chunk].size())
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
				pose.origin -= forest_chunk_centers[chunk]
				mm.set_instance_transform(local, pose)
				mm.set_instance_color(local, shared_tree_color(layer, float(tree_data.shade), has_snow))
			var instance = MultiMeshInstance3D.new()
			instance.name = "ForestLayer%d_Chunk%d" % [layer, chunk]
			instance.position = forest_chunk_centers[chunk]
			instance.multimesh = mm
			add_child(instance)
		forest_layers.append(chunks)

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
		if f.get("rendered_age", -1.0) == f.age and f.get("rendered_direction", Vector3.ZERO) == f.direction:
			continue
		f.rendered_age = f.age
		f.rendered_direction = f.direction
		var angle = smoothstep(0, 1.3, f.age) * PI * 0.5
		var basis = Basis(Vector3.UP.cross(f.direction).normalized(), angle)
		f.basis = basis
		if detail_tree_visuals.has(index):
			for part in detail_tree_visuals[index]:
				var pose: Transform3D = part.pose
				pose.origin = trees[index] + basis * (pose.origin - trees[index]) - part.center
				pose.basis = basis * pose.basis
				part.mesh.set_instance_transform(part.instance, pose)
			continue
		var h: float = tree_data.height
		for layer in range(forest_layers.size()):
			var radius = 0.2 if layer == 0 else h * (0.28 - (layer - 1) * 0.055)
			var height = h * (0.64 if layer == 0 else 0.49)
			var y = h * (0.32 if layer == 0 else 0.47 + (layer - 1) * 0.18)
			var slot: Vector2i = forest_chunk_slots[index]
			forest_layers[layer][slot.x].set_instance_transform(slot.y, Transform3D(basis * Basis.from_scale(Vector3(radius, height, radius)), trees[index] - forest_chunk_centers[slot.x] + Vector3(0, 0.2, 0) + basis * Vector3(0, y, 0)))

# Shared-world providers this stage contributes to the room snapshot
# (see world_sync.gd). Collision-relevant parts are applied before a guest
# replays its own driving input.
func sync_providers(game) -> Array:
	var list: Array = []
	var lamps_snapshot = func() -> Dictionary:
		return {"city_lamps": solids.snapshot() if solids != null else [], "church_bell": solids.bell.snapshot() if solids != null and solids.bell != null else {}}
	var lamps_apply = func(f: Dictionary, _t: float) -> void:
		if solids == null:
			return
		solids.apply_snapshot(f.get("city_lamps", []))
		if solids.bell != null:
			solids.bell.apply_snapshot(f.get("church_bell", {}))
			for item in f.get("city_lamps", []):
				game.lamp_requests.erase(int(item.id))
	list.append(WorldSync.provider("city", "city", ["city_lamps", "church_bell"], lamps_snapshot, lamps_apply, true))
	list.append_array(biome.sync_providers(game))
	var trees_snapshot = func() -> Dictionary:
		return {"fallen": tree_snapshot()}
	var trees_apply = func(f: Dictionary, _t: float) -> void:
		apply_trees(f.get("fallen", []))
		for fallen_tree in f.get("fallen", []):
			game.tree_requests.erase(int(fallen_tree.id))
	list.append(WorldSync.provider("trees", "trees", ["fallen"], trees_snapshot, trees_apply, true))
	return list

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

func rocks_in_bounds(low: Vector2, high: Vector2) -> Array:
	if indexed_rock_count != rocks.size():
		rock_cells.clear()
		dynamic_rock_ids.clear()
		for id in range(rocks.size()):
			var rock: Dictionary = rocks[id]
			if rock.has("actor"):
				dynamic_rock_ids.append(id)
				continue
			var p = flat(rock.pos)
			var r = Vector2.ONE * float(rock.radius)
			for x in range(floori((p.x-r.x)/ROCK_CELL_SIZE), floori((p.x+r.x)/ROCK_CELL_SIZE)+1):
				for z in range(floori((p.y-r.y)/ROCK_CELL_SIZE), floori((p.y+r.y)/ROCK_CELL_SIZE)+1):
					var cell = Vector2i(x, z)
					if not rock_cells.has(cell):
						rock_cells[cell] = []
					rock_cells[cell].append(id)
		indexed_rock_count = rocks.size()
	var ids: Dictionary = {}
	for id in dynamic_rock_ids:
		ids[id] = true
	for x in range(floori(low.x/ROCK_CELL_SIZE), floori(high.x/ROCK_CELL_SIZE)+1):
		for z in range(floori(low.y/ROCK_CELL_SIZE), floori(high.y/ROCK_CELL_SIZE)+1):
			for id in rock_cells.get(Vector2i(x, z), []):
				ids[id] = true
	var ordered = ids.keys()
	ordered.sort()
	var result: Array = []
	for id in ordered:
		result.append(rocks[id])
	return result

# Earliest swept horizontal circle contact. Height allows cars to jump over rocks.
# Escape handling prevents an overlapping spawn or a low-speed bump from trapping a car.
func rock_hit(start: Vector3, end: Vector3, radius: float, allow_escape: bool = true) -> Dictionary:
	var a = flat(start)
	var b = flat(end)
	var travel = b - a
	var best: Dictionary = {}
	var earliest = INF
	for rock in rocks_in_bounds(a.min(b) - Vector2.ONE * radius, a.max(b) + Vector2.ONE * radius):
		var tyre_offset = 0.0
		if minf(start.y, end.y) - tyre_offset > rock.pos.y + rock.height:
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
		if lerpf(start.y, end.y, t) - tyre_offset > rock.pos.y + rock.height:
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

func woodland_spot(pos: Vector3, padding: float = 0.0) -> bool:
	if road_distance(pos) < 9.0 + padding or trail_distance(pos) < 3.2 + padding:
		return false
	if biome.woodland_blocked(pos, padding):
		return false
	for clearing in clearings:
		if flat(pos).distance_to(flat(clearing)) < 8.5 + padding:
			return false
	return true

# Instanced decorative layers. Options (all optional):
#   tiles: split into 64 m culling tiles named <name>_Tile_x_y ("GrassTile" for ForestGrass)
#   range: visibility range of tiles in metres (default 160)
#   tree: shared group id of a fallable tree; with tree_bases/tree_heights on
#         the first (trunk) layer, those trees join trees[] and collide with cars
#   collectible: remember instances so harvesting can hide them
#   texture: albedo texture of the layer
func _detail_batch(name: String, mesh: Mesh, poses: Array, colors: Array, options: Dictionary = {}) -> void:
	var group: String = options.get("tree", "")
	var indices: Array = []
	if options.has("tree_bases"):
		var ids: Array = []
		for i in range(poses.size()):
			ids.append(trees.size())
			trees.append(options.tree_bases[i])
			forest_data.append({"height": float(options.tree_heights[i])})
		detail_tree_groups[group] = ids
		_rebuild_tree_index()
	if group != "":
		indices = detail_tree_groups[group]
	woodland_details[name] = poses.size()
	if not options.get("tiles", false):
		_detail_node(name, name, mesh, poses, colors, options, indices, false)
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
		_detail_node(prefix + "_%d_%d" % [key.x, key.y], name, mesh, cells[key].poses, cells[key].colors, options, cells[key].indices, true)

func _detail_node(node_name: String, source: String, mesh: Mesh, poses: Array, colors: Array, options: Dictionary, indices: Array, tiled: bool) -> void:
	var group: String = options.get("tree", "")
	var collectible: bool = options.get("collectible", false)
	var mat = RallyProps.material(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if options.has("texture"):
		mat.albedo_texture = options.texture
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
			if not detail_tree_visuals.has(id): detail_tree_visuals[id] = []
			detail_tree_visuals[id].append({"mesh": mm, "instance": i, "pose": poses[i], "center": center})
		if collectible:
			if not collectible_parts.has(source):
				collectible_parts[source] = {}
			collectible_parts[source][id] = {"mesh": mm, "instance": i, "pose": pose, "hidden": false}
	var node = MultiMeshInstance3D.new()
	node.name = node_name
	node.position = center
	if tiled:
		node.visibility_range_end = float(options.get("range", 160.0))
		node.visibility_range_end_margin = 15
	node.multimesh = mm
	if capture_bake_buffers:
		BakedVillage.capture_instances(node, poses, colors, center)
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)

func _grass_mesh() -> Mesh:
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
			await get_tree().process_frame
		var p = Vector3(detail_rng.randf_range(-145, 145), 0, detail_rng.randf_range(-LENGTH, 0))
		if not woodland_spot(p):
			continue
		p.y = terrain_surface_height(p) - 0.015
		var size = detail_rng.randf_range(0.25, 0.65)
		grass_poses.append(Transform3D(Basis(Vector3.UP, detail_rng.randf() * TAU).scaled(Vector3(size * 1.8, size, size * 1.8)), p))
		grass_colors.append(shared_grass_color(detail_rng.randf()))
	for i in range(4000):
		if cooperative and i % 400 == 0:
			await get_tree().process_frame
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
		if cooperative and i % 400 == 0:
			await get_tree().process_frame
		var p = Vector3(detail_rng.randf_range(-135, 135), 0, detail_rng.randf_range(-LENGTH, 0))
		if not woodland_spot(p):
			continue
		var radius = detail_rng.randf_range(0.12, 0.35)
		p.y = terrain_surface_height(p) + radius * 0.35
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
			await get_tree().process_frame
		var p = Vector3(detail_rng.randf_range(-140, 140), 0, detail_rng.randf_range(-LENGTH, 0))
		var patch = sin(p.x * 0.075 + p.z * 0.027) * sin(p.z * 0.054)
		if patch < -0.35 or not woodland_spot(p, 1.4) or not rock_hit(p, p, 1.1, false).is_empty():
			continue
		p.y = ground(p) - 0.22
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
			collectibles.append({"kind": "berries", "pos": Vector3(p.x, ground(p), p.z), "quantity": 3, "parts": {"ForestBerries": fruit_indices}})
	var leaves = NATURE_BUSH
	_detail_batch("ForestBushes", leaves, bush_poses, bush_colors, {"tiles": true})
	_detail_batch("ForestBerryBushes", leaves, berry_bush_poses, berry_bush_colors, {"tiles": true})
	var berry_mesh = NATURE_BERRY
	_detail_batch("ForestBerries", berry_mesh, berry_poses, berry_colors, {"tiles": true, "collectible": true})
	var bush_stem_mesh = NATURE_BUSH_STEM
	_detail_batch("ForestBushStems", bush_stem_mesh, bush_stem_poses, bush_stem_colors, {"tiles": true})
	for i in range(300):
		if cooperative and i % 400 == 0:
			await get_tree().process_frame
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
		if cooperative and i % 400 == 0:
			await get_tree().process_frame
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
	var boulder = NATURE_BOULDER
	_detail_batch("ForestBoulders", boulder, boulder_poses, boulder_colors)
	# Filter after rocks and undergrowth exist, so ground details cannot overlap them.
	for group in [{"poses": grass_poses, "colors": grass_colors}, {"poses": stone_poses, "colors": stone_colors}]:
		for index in range(group.poses.size() - 1, -1, -1):
			var pose: Transform3D = group.poses[index]
			var point = pose.origin
			point.y = terrain_surface_height(point)
			var padding = maxf(pose.basis.x.length(), pose.basis.z.length()) * 0.5
			var blocked = obstacle_hit(point, point, padding) >= 0 or not rock_hit(point, point, padding, false).is_empty()
			var cell = Vector2i(floori(point.x / 4.0), floori(point.z / 4.0))
			for x in range(-1, 2):
				for z in range(-1, 2):
					for bush in ground_exclusions.get(cell + Vector2i(x, z), []):
						blocked = blocked or flat(point).distance_to(flat(bush.pos)) < padding + bush.radius
			if blocked:
				group.poses.remove_at(index)
				group.colors.remove_at(index)
	_detail_batch("ForestPebbles", shared_stone_mesh(), stone_poses, stone_colors, {"tiles": true})
	_detail_batch("ForestGrass", _grass_mesh(), grass_poses, grass_colors, {"tiles": true})
	var stem = NATURE_MUSHROOM_STEM
	_detail_batch("MushroomStems", stem, stem_poses, stem_colors, {"collectible": true})
	var cap = NATURE_MUSHROOM_CAP
	_detail_batch("MushroomCaps", cap, cap_poses, cap_colors, {"collectible": true})
	for species in poison_caps:
		var colors: Array = []
		colors.resize(poison_caps[species].size())
		colors.fill(Color.WHITE)
		_detail_batch("FlyAgaricCaps" if species == "fly_agaric" else "ToadstoolCaps", cap, poison_caps[species], colors, {"collectible": true, "texture": RallyProps.MUSHROOM_TEXTURES[species]})
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

# Spatial index of a winding route given as samples every `step` stations.
func _index_route(samples: PackedVector3Array, step: float) -> void:
	route_segment_step = step
	road_segment_starts.clear()
	road_segment_deltas.clear()
	road_segment_inverse_lengths.clear()
	road_group_low.clear()
	road_group_high.clear()
	for i in range(samples.size() - 1):
		var a = flat(samples[i])
		var b = flat(samples[i + 1])
		road_segment_starts.append(a)
		road_segment_deltas.append(b - a)
		road_segment_inverse_lengths.append(1.0 / maxf((b - a).length_squared(), 0.000001))
		var group = int(i / ROAD_GROUP_SIZE)
		if i % ROAD_GROUP_SIZE == 0:
			road_group_low.append(a.min(b))
			road_group_high.append(a.max(b))
		else:
			road_group_low[group] = road_group_low[group].min(a).min(b)
			road_group_high[group] = road_group_high[group].max(a).max(b)

# Nearest station and plan distance on the indexed route. Every segment that
# could win is tested, so perpendicular streets and hairpins stay exact.
func route_nearest(pos: Vector3) -> Dictionary:
	if road_segment_starts.is_empty():
		_index_route(points, STEP)
	var best = INF
	var station = 0.0
	var p = flat(pos)
	# Successive queries are spatially coherent: start from the last winning group.
	var seed = clampi(_last_route_group, 0, road_group_low.size() - 1)
	# Visit the likely group first, then reject others by a conservative bound.
	for pass_index in range(road_group_low.size() + 1):
		var group = seed if pass_index == 0 else pass_index - 1
		if pass_index > 0 and group == seed:
			continue
		if p.distance_squared_to(p.clamp(road_group_low[group], road_group_high[group])) > best:
			continue
		for i in range(group * ROAD_GROUP_SIZE, mini((group + 1) * ROAD_GROUP_SIZE, road_segment_starts.size())):
			var a = road_segment_starts[i]
			var segment = road_segment_deltas[i]
			var ratio = clampf((p - a).dot(segment) * road_segment_inverse_lengths[i], 0.0, 1.0)
			var distance = p.distance_squared_to(a + segment * ratio)
			var candidate = (i + ratio) * route_segment_step
			if distance < best or (distance == best and candidate < station):
				best = distance
				station = candidate
	_last_route_group = int(station / route_segment_step) / ROAD_GROUP_SIZE
	return {"s": station, "distance": sqrt(best)}

func rally_speed(s: float) -> float:
	return biome.rally_speed(s)

# How far beyond the road edge crews may run when cutting or overtaking.
func shoulder(s: float) -> float:
	return biome.shoulder(s)

# Loose surfaces throw gravel from spinning tyres; village asphalt and cobbles do not.
func loose_surface(pos: Vector3) -> bool:
	return biome.loose_surface(pos)

# Local, unsynchronised scenery life (animals, villagers, wind).
func update_life(delta: float, focus: Vector3) -> void:
	biome.update_life(delta, focus)

# Collectible identifiers follow deterministic generation order and are shared by
# every room member. Harvesting hides the existing instances without new nodes.
func nearby_collectibles(pos: Vector3, reach: float) -> Array:
	# Static generated positions; harvesting does not change IDs or cells.
	# Rebuild when callers/tests append or clear the public collection.
	if indexed_collectible_count != collectibles.size():
		collectible_cells.clear()
		for id in range(collectibles.size()):
			var p: Vector3 = collectibles[id].pos
			var cell = Vector2i(floori(p.x / COLLECTIBLE_CELL_SIZE), floori(p.z / COLLECTIBLE_CELL_SIZE))
			if not collectible_cells.has(cell):
				collectible_cells[cell] = []
			collectible_cells[cell].append(id)
		indexed_collectible_count = collectibles.size()
	var found: Array = []
	for x in range(floori((pos.x - reach) / COLLECTIBLE_CELL_SIZE), floori((pos.x + reach) / COLLECTIBLE_CELL_SIZE) + 1):
		for z in range(floori((pos.z - reach) / COLLECTIBLE_CELL_SIZE), floori((pos.z + reach) / COLLECTIBLE_CELL_SIZE) + 1):
			found.append_array(collectible_cells.get(Vector2i(x, z), []))
	# Preserve original generation order for equally near targets.
	found.sort()
	return found

func nearest_collectible(pos: Vector3, reach: float = 1.8) -> int:
	var best = reach
	var found = -1
	for i in nearby_collectibles(pos, reach):
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
