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
const Canyon = preload("res://scripts/canyon.gd")
var canyon: RefCounted
var desert = false

const City = preload("res://scripts/vineyard.gd")
var city: Node3D
const BakedVillage = preload("res://scripts/baked_village.gd")
var baked_scene_path = "res://generated/village.scn"
var loaded_baked = false
# Used only by the offline baker/tests; ordinary gameplay retains no CPU copy.
var capture_bake_buffers = false
const LENGTH = 840.0
const STEP = 4.0
const WIDTH = 7.4
# Five side-lane rows spaced 0.8 m apart, each stone 0.76 m wide.
const SIDE_LANE_WIDTH = 3.96
const TREE_CELL_SIZE = 16.0
const STAGES = ["Лесной перевал · гравий", "Зимний Турини · снег и лёд", "Виноградники · европейская деревня", "Красный каньон · пустынный грунт"]
var variant = 0
var winter = false
var urban = false
var village_church_center = Vector3.ZERO
var points: PackedVector3Array = []
var gravel_landform_frames: Array[Dictionary] = []
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
	winter = variant == 1
	urban = variant == 2
	desert = variant == 3
	if desert:
		canyon = Canyon.new()
	if urban:
		village_church_center = village_main_at(435.0) + village_main_side(435.0) * 43.0
	for i in range(int(LENGTH / STEP) + 1):
		var s = i * STEP
		if desert:
			points.append(canyon.route(s))
		elif winter:
			points.append(Vector3(sin(s / 48.0) * 58.0 + sin(s / 115.0) * 14.0, 18.0 + s * 0.085 + sin(s / 36.0) * 5.0, -s))
		elif urban:
			points.append(urban_at(s))
		else:
			points.append(Vector3(sin(s / 90.0) * 38.0 + sin(s / 38.0) * 9.0, 5.0 + s * 0.024 + sin(s / 58.0) * 3.7, -s))
	if urban:
		_index_urban_route()
		for crest in [Vector3(423.0, 1.05, 36.0), Vector3(450.0, 0.75, 32.0)]:
			var forward = flat(direction(crest.x)).normalized()
			gravel_landform_frames.append({"centre": flat(at(crest.x)), "forward": forward, "across": Vector2(-forward.y, forward.x), "height": crest.y, "length": crest.z})
	if desert:
		canyon.configure(self)
		return
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
	if urban:
		return float(urban_nearest(pos).s)
	return clampf(-pos.z, 0, LENGTH)

func road_distance(pos: Vector3) -> float:
	if urban:
		return float(urban_nearest(pos).distance)
	var p = at(road_s(pos))
	return Vector2(pos.x - p.x, pos.z - p.z).length()

func roughness(s: float) -> float:
	if urban:
		return (sin(s * 0.55) * 0.045 + sin(s * 1.7) * 0.018) if village_forest_detour(s) else (sin(s * 3.4) * 0.014 if village(s) else sin(s * 0.8) * 0.018)
	# Broad crests plus broken ruts; deterministic across all room members.
	return sin(s * 0.46) * 0.075 + sin(s * 1.13) * 0.035 + pow(maxf(0, cos((s - 32.0) * TAU / 46.0)), 10) * 0.55

# Compact smooth profiles keep junctions and village paving untouched.
func gravel_profile(s: float, center: float, half_length: float) -> float:
	var t = absf(s - center) / half_length
	return (1.0 + cos(t * PI)) * 0.5 if t < 1.0 else 0.0

func village_gravel_landform(pos: Vector3) -> float:
	# The road crosses a broad hill, rather than sitting on a narrow ramp.
	# World-space profiles are shared by tyre contact and surrounding terrain.
	var height = 0.0
	for frame in gravel_landform_frames:
		var offset = flat(pos) - frame.centre
		var along = offset.dot(frame.forward)
		var lateral = offset.dot(frame.across)
		height += gravel_profile(along, 0.0, frame.length) * gravel_profile(lateral, 0.0, 24.0) * frame.height
	return height

func gravel_relief(pos: Vector3, s: float) -> float:
	if not village_forest_detour(s):
		return 0.0
	var lateral = (pos - at(s)).dot(side(s))
	var edge = 1.0 - smoothstep(road_width(s) * 0.45, road_width(s) * 0.75, absf(lateral))
	var blend = smoothstep(386.0, 398.0, s) * (1.0 - smoothstep(474.0, 484.0, s))
	var bank = lateral * sin(s * 0.095) * 0.10
	var bumps = sin(s * 0.65) * 0.025 + sin(s * 0.32 + lateral * 0.75) * 0.035
	var wheel_rut = exp(-pow((absf(lateral) - 0.80) / 0.24, 2.0))
	var ruts = -wheel_rut * (0.09 + 0.04 * sin(s * 0.6))
	var puddles = -gravel_profile(s, 407.0, 2.2) * 0.13 * exp(-pow((lateral - 0.5) / 0.7, 2.0))
	puddles -= gravel_profile(s, 469.0, 2.2) * 0.14 * exp(-pow((lateral + 0.5) / 0.7, 2.0))
	puddles -= gravel_profile(s, 412.0, 2.4) * 0.16 * exp(-pow((lateral + 0.55) / 0.8, 2.0))
	puddles -= gravel_profile(s, 463.0, 2.6) * 0.18 * exp(-pow((lateral - 0.55) / 0.8, 2.0))
	return (bank + bumps + ruts + puddles) * edge * blend + village_gravel_landform(pos) * smoothstep(382.0, 390.0, s) * (1.0 - smoothstep(480.0, 488.0, s))

func grip(pos: Vector3) -> float:
	if desert:
		return 0.48 if road_distance(pos) > road_width(road_s(pos)) * 0.5 or (road_s(pos) > 550.0 and road_s(pos) < 670.0) else 0.74
	if urban:
		var nearest = urban_nearest(pos)
		var s: float = nearest.s
		if nearest.distance >= road_width(s) * 0.55:
			return 0.58
		var base = 0.62 if village_forest_detour(s) else (0.86 if village(s) else 1.02)
		if village_forest_detour(s):
			var lateral = (pos - at(s)).dot(side(s))
			var wet = gravel_profile(s, 407.0, 2.2) * exp(-pow((lateral - 0.5) / 0.7, 2.0))
			wet += gravel_profile(s, 469.0, 2.2) * exp(-pow((lateral + 0.5) / 0.7, 2.0))
			wet += gravel_profile(s, 412.0, 2.4) * exp(-pow((lateral + 0.55) / 0.8, 2.0))
			wet += gravel_profile(s, 463.0, 2.6) * exp(-pow((lateral - 0.55) / 0.8, 2.0))
			return lerpf(base, 0.38, clampf(wet, 0.0, 1.0))
		return base
	if winter:
		if DeepSnow.depth(self, pos) > 0.02:
			return lerpf(0.24, 0.50, snow.packed(pos))
		if road_distance(pos) > WIDTH * 0.55:
			return 0.32
		return 0.22 if int(road_s(pos) / 32) % 3 == 1 else 0.47
	if road_distance(pos) > WIDTH * 0.55:
		return 0.48
	return 0.42 if int(road_s(pos) / STEP) % 13 == 7 else 0.78

func vehicle_ground(pos: Vector3) -> float:
	return snow.contact(self, pos) if winter else ground(pos)

func ground(pos: Vector3) -> float:
	if desert:
		return canyon.ground(self, pos)
	if urban:
		# Level foundation beneath the hollow church; keep terrain out of its nave.
		var church_offset = pos - village_church_center
		if absf(church_offset.z) < 5.6 and church_offset.x > -14.6 and church_offset.x < 10.8:
			return 2.0
		var paved_height = village_paved_height(pos)
		if paved_height != INF:
			return paved_height
		var nearest = urban_nearest(pos)
		var s: float = nearest.s
		var p = at(s)
		var distance: float = nearest.distance
		var road_height = p.y + roughness(s)
		if village_forest_detour(s):
			road_height += gravel_relief(pos, s)
		if s > 370.0 and s < 500.0:
			var connection = smoothstep(382.0, 390.0, s) * (1.0 - smoothstep(480.0, 488.0, s))
			road_height = lerpf(2.0775, road_height, connection)
		# The distant landscape must not change elevation when the nearest road
		# switches from the countryside to the lower village forest bypass.
		var height = lerpf(road_height, village_hill_height(pos), smoothstep(road_width(s) * 0.5 + 1.0, 24.0, distance))
		for parking in clearings:
			var d = flat(pos).distance_to(flat(parking))
			height = lerpf(parking.y, height, smoothstep(5.0, 16.0, d))
		return height
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
			if not _trail_near(pos, trail, float(trail.width)):
				continue
			var trail_sample = _trail_sample(pos, trail)
			if trail_sample.distance < trail.width:
				var blend = 1.0 - smoothstep(trail.width * 0.55, trail.width, trail_sample.distance)
				height = lerpf(height, trail_sample.height, blend)
	return height

func village_country_relief(s: float) -> float:
	return gravel_profile(s, 94.0, 32.0) * 0.65 - gravel_profile(s, 126.0, 28.0) * 0.35 + gravel_profile(s, 224.0, 36.0) * 0.80 + gravel_profile(s, 620.0, 34.0) * 0.70 + gravel_profile(s, 748.0, 30.0) * 0.95 - gravel_profile(s, 786.0, 32.0) * 0.35

func village_forest_microrelief(pos: Vector3) -> float:
	# Geographic mask, independent of nearest route segment: no switching cliffs.
	var s = -pos.z
	var edge = absf(pos.x - village_main_at(clampf(s, 0, LENGTH)).x)
	var mask = smoothstep(270.0, 310.0, s) * (1.0 - smoothstep(570.0, 620.0, s)) * smoothstep(36.0, 58.0, edge)
	return (sin(pos.x * 0.13) * sin(pos.z * 0.15) * 0.28 + sin(pos.x * 0.31 + pos.z * 0.16) * 0.14 + sin(pos.z * 0.035 + pos.x * 0.02) * 0.45) * mask

func village_hill_height(pos: Vector3) -> float:
	var station = clampf(-pos.z, 0.0, LENGTH - 0.001)
	var axis = village_main_at(station)
	var distance = absf(pos.x - axis.x)
	var excess = maxf(distance - 8.0, 0.0)
	var hillside = (sqrt(excess * excess + 1296.0) - 36.0) * 0.045
	var village_blend = smoothstep(250.0, 320.0, station) * (1.0 - smoothstep(550.0, 640.0, station))
	var road_blend = smoothstep(190.0, 300.0, station) * (1.0 - smoothstep(570.0, 710.0, station))
	var axis_height = axis.y - (1.0 - road_blend) * (sin(station / 14.0) * 0.32 + gravel_profile(station, 178.0, 14.0) * 1.1 + gravel_profile(station, 686.0, 16.0) * 1.25)
	return axis_height + hillside * (1.0 - village_blend) + sin(pos.x * 0.016 + pos.z * 0.010) * minf(hillside * 0.08, 0.20) * (1.0 - village_blend) + village_forest_microrelief(pos) + village_gravel_landform(pos)

# Trees must touch the *rendered* terrain, not the continuous ground()
# function. Terrain is triangulated in 4 m cells (2 m near forest roads)
# and its vertices are 0.25 m below ground(). Reproduce that interpolation
# exactly to avoid suspended trunks on slopes and relief crests.
# The 2 m roadside tiles meet 4 m terrain tiles at T-junctions.
# On those boundaries, snap the fine tile's midpoint to the coarse edge.
# Otherwise the ground() midpoint can be above/below the straight 4 m edge,
# creating visible cracks (and floating trees).
func terrain_tile_step(cell_x: float, cell_z: float) -> float:
	var p = Vector3(cell_x + 2.0, 0, cell_z + 2.0)
	var nearest = urban_nearest(p) if urban else {}
	if urban and nearest.distance < road_width(nearest.s) * 0.5 + 4.0:
		return 1.0
	return 2.0 if ((variant == 0 or urban) and road_distance(p) < 12.0) or (winter and road_distance(p) < 30.0) else 4.0

func terrain_base_vertex_height(x: float, z: float) -> float:
	var p = Vector3(x, 0, z)
	var margin = 0.25
	if urban:
		var nearest = urban_nearest(p)
		margin = lerpf(0.20, 0.25, smoothstep(road_width(nearest.s) * 0.5, road_width(nearest.s) * 0.5 + 3.0, nearest.distance))
	return ground(p) - margin

func terrain_vertex_height(x: float, z: float) -> float:
	if desert:
		return canyon.base_ground(self, Vector3(x, 0, z)) - 0.25
	var value = terrain_base_vertex_height(x, z)
	if variant != 0 and not urban and not winter:
		return value
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
	return value

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

func build(use_baked: bool = true) -> void:
	if urban and use_baked and BakedVillage.load_into(self, baked_scene_path):
		_build_finish()
		return
	rng.seed = 7102026 + variant * 971
	_build_terrain()
	_build_road()
	_build_nature()
	_build_details()
	_build_finish()

func build_async(progress: Callable) -> void:
	if urban and ResourceLoader.exists(baked_scene_path):
		await progress.call("Загрузка спецучастка", 0)
		if await BakedVillage.load_into_async(self, baked_scene_path, progress):
			await progress.call("Судьи и указатели", 75)
			_build_finish()
			return
	rng.seed = 7102026 + variant * 971
	await progress.call("Рельеф", 0)
	await _build_terrain(true)
	await progress.call("Дорога", 30)
	_build_road()
	await progress.call("Скалы и окружение" if desert else "Лес и окружение", 40)
	await _build_nature(true)
	await progress.call("Объекты спецучастка", 55)
	await _build_details(true)
	await progress.call("Судьи и указатели", 75)
	_build_finish()

func _build_nature(cooperative: bool = false) -> void:
	if desert:
		return
	var forest: Array[Dictionary] = []
	for i in range(100 if urban else (520 if winter else 7600)):
		if cooperative and i % 400 == 0:
			await get_tree().process_frame
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
		p.y = terrain_surface_height(p) - 0.03
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

func _build_details(cooperative: bool = false) -> void:
	if desert:
		canyon.build(self)
		return
	if variant == 0:
		if cooperative:
			await _build_woodland_details(true)
		else:
			_build_woodland_details()
	if urban:
		if cooperative:
			await _build_city(true)
		else:
			_build_city()

func _build_finish() -> void:
	for i in range(clearings.size()):
		var c = clearings[i]
		if urban or desert:
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
	for i in range(0 if urban or desert else 18):
		var p = Vector3((-1 if i % 2 == 0 else 1) * rng.randf_range(220, 340), 30, -i * 65.0)
		RallyProps.cylinder(self, p, rng.randf_range(120, 180), 0, rng.randf_range(220, 340) if winter else rng.randf_range(130, 210), Color("c3d1db") if winter else Color("697d70"), 5)

	officials = Officials.new()
	officials.stage = self
	add_child(officials)
	officials.build()

func _build_city(cooperative: bool = false) -> void:
	city = City.new()
	city.stage = self
	add_child(city)
	if cooperative:
		await city.build(true)
	else:
		city.build()

func _build_terrain(cooperative: bool = false) -> void:
	var builders: Dictionary = {}
	for z in range(-920, 81, 4):
		if cooperative and (z + 920) % 64 == 0:
			await get_tree().process_frame
		for x in range(-204, 204, 4):
			var tile = Vector2i(floori(x / 64.0), floori(z / 64.0)) if urban or winter else Vector2i.ZERO
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
						var color = Color("b6c9d3") if winter else Color(0.32, 0.38, 0.25)
						if desert:
							color = Color("b56443").lerp(Color("dfac74"), (sin(v.y * 0.65) + 1.0) * 0.5)
						if variant == 0:
							var patch = (sin(v.x * 0.065) * sin(v.z * 0.041) + 1.0) * 0.5
							color = Color("514a32").lerp(Color("485c36"), patch)
							if road_distance(v) > 4.5 and road_distance(v) < 8:
								color = color.darkened(0.16)
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
		if winter:
			snow.register_chunk(self, tile, n)

func draw_base_road_surface(s: float) -> bool:
	# The village has its own explicit cobblestone mesh; do not leave asphalt
	# underneath it where it can show through between individual stones.
	return not village(s) or (urban and ((s >= 381.0 and s <= 488.0) or s >= 569.0))

func road_width(s: float) -> float:
	if desert:
		var narrow = smoothstep(230.0, 265.0, s) * (1.0 - smoothstep(405.0, 435.0, s))
		var wash = smoothstep(540.0, 565.0, s) * (1.0 - smoothstep(655.0, 680.0, s))
		return WIDTH - narrow * 1.2 + wash * 1.6
	return SIDE_LANE_WIDTH if urban and s > 370.0 and s < 500.0 else WIDTH

func road_surface_vertex(s: float, lateral: float) -> Vector3:
	var p = at(s) + side(s) * lateral
	var surface_lift = 0.04
	if urban and s > 370.0 and s < 500.0:
		surface_lift *= smoothstep(382.0, 386.0, s) * (1.0 - smoothstep(484.0, 488.0, s))
	if urban and s >= 569.0 and s <= 573.0:
		# Overlap the final cobblestone row, then meet the vineyard road smoothly.
		surface_lift = lerpf(-0.015, 0.04, smoothstep(569.0, 573.0, s))
	p.y = ground(p) + surface_lift
	return p

func road_surface_color(p: Vector3, s: float) -> Color:
	if desert:
		return Color("d4a475").lightened(sin(p.z * 0.25 + p.x * 0.10) * 0.025)
	# The same world-space vertex belongs to adjacent segments whose station
	# parameters differ by one. Shading with the segment's start station made
	# identical vertices get different colours, creating visible gravel seams.
	# For the village detour derive the actual station from p, once per colour
	# calculation, regardless of which adjacent triangle references it.
	var station = road_s(p) if urban else s
	var base = Color("708a9c") if winter else ((Color("857763") if station >= 381.0 and station <= 489.0 else Color("525757")) if urban else Color("9d896b"))
	var shade = sin(p.x * 0.17 + p.z * 0.11) * 0.025 + sin(p.z * 0.29 - p.x * 0.07) * 0.015
	if village_forest_detour(station):
		var lateral = (p - at(station)).dot(side(station))
		base = base.darkened(exp(-pow((absf(lateral) - 0.80) / 0.28, 2.0)) * 0.18)
	return base.lightened(shade)

func _build_road() -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(int(LENGTH)):
		var s = float(i)
		if draw_base_road_surface(s):
			# Bound physical segment length as well as station length: the side
			# lanes cover many metres per station through the village bypass.
			var divisions = maxi(4, ceili(at(s).distance_to(at(s + 1.0)) / 0.75))
			for segment in range(divisions):
				var begin = s + float(segment) / divisions
				var end = s + float(segment + 1) / divisions
				var strips = 8 if desert or village_forest_detour(s) else 4
				for strip in range(strips):
					var width = road_width(s)
					var left = -width * 0.5 + width * float(strip) / strips
					var right = -width * 0.5 + width * float(strip + 1) / strips
					var a = road_surface_vertex(begin, right)
					var b = road_surface_vertex(begin, left)
					var c = road_surface_vertex(end, right)
					var d = road_surface_vertex(end, left)
					for v in [a, b, c, b, d, c]:
						st.set_color(road_surface_color(v, s))
						st.add_vertex(v)
				if urban:
					# A visible earth shoulder closes the road-to-terrain seam.
					# Keep the analytical tyre-contact surface unchanged.
					for edge_side in [-1.0, 1.0]:
						var a = road_surface_vertex(begin, edge_side * road_width(s) * 0.5)
						var b = road_surface_vertex(end, edge_side * road_width(s) * 0.5)
						var c = a
						var d = b
						c.y = terrain_surface_height(c)
						d.y = terrain_surface_height(d)
						for v in ([a, c, b, b, c, d] if edge_side > 0 else [a, b, c, b, d, c]):
							st.set_color(road_surface_color(v, s).darkened(0.12))
							st.add_vertex(v)
		# Broken muddy wheel tracks, shallow puddles.
		if not urban and not desert and i % 12 == 0:
			for offset in [-1.0, 1.0]:
				var p = at(s) + side(s) * offset
				p.y = ground(p)
				var rut = RallyProps.box(self, p + Vector3(0, 0.07, 0), Vector3(0.5, 0.025, 2.7), Color("586974") if winter else Color("77654c"))
				rut.rotation.y = atan2(-direction(s).x, -direction(s).z)
		if not urban and not desert and i % 52 == 28:
			var p = at(s) + side(s) * 1.5
			p.y = ground(p)
			var puddle = RallyProps.cylinder(self, p + Vector3(0, 0.10, 0), 1.1, 1.1, 0.025, Color("56645d"), 9)
			puddle.scale.z = 1.7
	# Shared positions and colours allow smooth normals across strip joins.
	st.index()
	st.generate_normals()
	var n = MeshInstance3D.new()
	n.mesh = st.commit()
	var mat = RallyProps.material(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	n.material_override = mat
	n.name = "StageRoadSurface"
	add_child(n)
	if winter:
		Snowbanks.build(self)
	if urban:
		for station in [407.0, 412.0, 463.0, 469.0]:
			var offset = (-0.55 if station < 440.0 else 0.55) if station in [412.0, 463.0] else (0.5 if station < 440.0 else -0.5)
			var p = at(station) + side(station) * offset
			p.y = ground(p) + 0.07
			_build_gravel_puddle(p, station)

func _build_gravel_puddle(center: Vector3, station: float) -> void:
	var basis = Basis(Vector3.UP, atan2(-direction(station).x, -direction(station).z))
	var shoreline: Array[Vector3] = []
	for i in range(48):
		var angle = i * TAU / 48.0
		var ray = basis * Vector3(cos(angle) * 0.68, 0, sin(angle) * 1.36)
		var low = 0.0
		var high = 1.0
		# Stop at the first bank; water stays horizontal, below surrounding road.
		for sample in range(1, 13):
			var radius = float(sample) / 12.0
			if ground(center + ray * radius) + 0.04 >= center.y:
				high = radius
				break
			low = radius
		for iteration in range(8):
			var radius = (low + high) * 0.5
			if ground(center + ray * radius) + 0.04 >= center.y:
				high = radius
			else:
				low = radius
		shoreline.append(center + ray * low)
	var builder = SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(48):
		for point in [center, shoreline[i], shoreline[(i + 1) % 48]]:
			builder.add_vertex(point)
	builder.generate_normals()
	var puddle = MeshInstance3D.new()
	puddle.name = "GravelPuddle_%d" % int(station)
	puddle.mesh = builder.commit()
	puddle.material_override = RallyProps.material(Color("56645d"))
	add_child(puddle)


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
				mm.set_instance_color(local, shared_tree_color(layer, float(tree_data.shade), winter))
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
		var h: float = tree_data.height
		for layer in range(forest_layers.size()):
			var radius = 0.2 if layer == 0 else h * (0.28 - (layer - 1) * 0.055)
			var height = h * (0.64 if layer == 0 else 0.49)
			var y = h * (0.32 if layer == 0 else 0.47 + (layer - 1) * 0.18)
			var slot: Vector2i = forest_chunk_slots[index]
			forest_layers[layer][slot.x].set_instance_transform(slot.y, Transform3D(basis * Basis.from_scale(Vector3(radius, height, radius)), trees[index] - forest_chunk_centers[slot.x] + Vector3(0, 0.2, 0) + basis * Vector3(0, y, 0)))

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
	ditch *= smoothstep(2.2, 4.0, trail_distance(pos, 4.0))
	return hills - ditch

func woodland_spot(pos: Vector3, padding: float = 0.0) -> bool:
	if road_distance(pos) < 9.0 + padding or trail_distance(pos) < 3.2 + padding:
		return false
	for clearing in clearings:
		if flat(pos).distance_to(flat(clearing)) < 8.5 + padding:
			return false
	return true

func _detail_batch(name: String, mesh: Mesh, poses: Array, colors: Array, indices: Array = []) -> void:
	if (urban and name in ["MushroomCaps", "FlyAgaricCaps", "ToadstoolCaps", "MushroomStems"]) or name in ["LavenderFoliage", "LavenderStems", "LavenderFlowers", "VillageThujaLower", "VillageThujaMiddle", "VillageThujaCrown", "ForestGrass", "ForestPebbles", "CropGroundGrass", "CropGroundStones", "ForestBushes", "ForestBerryBushes", "ForestBerries", "ForestBushStems", "VineyardGrapes", "VineyardLeaves", "VineyardRoadsideGrass", "VineyardRoadsideStones", "VineyardRoadsideBushes", "VillageForestTreeLayer0", "VillageForestTreeLayer1", "VillageForestTreeLayer2", "VillageForestTreeLayer3", "VillageHorizonTreeLayer0", "VillageHorizonTreeLayer1", "VillageHorizonTreeLayer2", "VillageHorizonTreeLayer3", "VillageGravelGrass", "VillageGravelStones", "VillageGravelBoulders", "VillageForestGrass", "VillageForestStones", "VillageForestBoulders", "VillageForestBushes", "VillageForestBerryBushes", "VillageForestBerries", "VillageGrass", "VillageStones"]:
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
	if name.begins_with("FlyAgaricCaps") or name.begins_with("ToadstoolCaps"):
		mat.albedo_texture = RallyProps.MUSHROOM_TEXTURES["fly_agaric" if name.begins_with("FlyAgaricCaps") else "toadstool"]
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
		node.visibility_range_end = 70 if name.begins_with("VineyardGrapes") else (110 if name.begins_with("LavenderFlowers") or name.begins_with("LavenderStems") else 160)
		# The sparse silhouette must survive even the near preset (420 * 0.7).
		if name.begins_with("VillageHorizonTreeLayer"):
			node.visibility_range_end = 420
		node.visibility_range_end_margin = 15
		if urban and name.begins_with("Mushroom") or urban and name.begins_with("FlyAgaric") or urban and name.begins_with("Toadstool"):
			node.visibility_range_end = 70
	node.multimesh = mm
	if capture_bake_buffers:
		BakedVillage.capture_instances(node, poses, colors, center)
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	woodland_details[name] = poses.size()

func _grass_mesh() -> Mesh:
	return NATURE_GRASS

func _build_woodland_details(cooperative: bool = false) -> void:
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
	_detail_batch("ForestBushes", leaves, bush_poses, bush_colors)
	_detail_batch("ForestBerryBushes", leaves, berry_bush_poses, berry_bush_colors)
	var berry_mesh = NATURE_BERRY
	_detail_batch("ForestBerries", berry_mesh, berry_poses, berry_colors)
	var bush_stem_mesh = NATURE_BUSH_STEM
	_detail_batch("ForestBushStems", bush_stem_mesh, bush_stem_poses, bush_stem_colors)
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
	_detail_batch("ForestPebbles", shared_stone_mesh(), stone_poses, stone_colors)
	_detail_batch("ForestGrass", _grass_mesh(), grass_poses, grass_colors)
	var stem = NATURE_MUSHROOM_STEM
	_detail_batch("MushroomStems", stem, stem_poses, stem_colors)
	var cap = NATURE_MUSHROOM_CAP
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

# The first village side street branches through the woods past the cemetery
# and joins the second side street. All stations remain ordered start-to-finish.
func village_forest_detour(s: float) -> bool:
	return urban and s > 382.0 and s < 488.0

func village_forest_offset(s: float) -> float:
	return (urban_at(s) - village_main_at(s)).dot(village_main_side(s))

# Village buildings and the original cobblestone main road must not follow
# the rally-only forest bypass. Keep their historical straight village axis.
func village_main_at(s: float) -> Vector3:
	var village_blend = smoothstep(190.0, 300.0, s) * (1.0 - smoothstep(570.0, 710.0, s))
	var country_x = sin(s / 85.0) * 34.0 + sin(s / 43.0) * 10.0
	var village_x = sin((s - 300.0) / 100.0) * 14.0
	var height = 2.0 + (1.0 - village_blend) * (7.0 + sin(s / 95.0) * 3.0 + s * 0.004 + sin(s / 14.0) * 0.32 + gravel_profile(s, 178.0, 14.0) * 1.1 + gravel_profile(s, 686.0, 16.0) * 1.25 + village_country_relief(s))
	return Vector3(lerpf(country_x, village_x, village_blend), height, -s)

func village_main_direction(s: float) -> Vector3:
	return (village_main_at(minf(s + 2.0, LENGTH - 0.01)) - village_main_at(maxf(s - 2.0, 0.0))).normalized()

func village_main_side(s: float) -> Vector3:
	return village_main_direction(s).cross(Vector3.UP).normalized()

# Follow each cobbled side lane to its outer end before entering the woods.
# The church and cemetery remain together inside the loop.
func urban_at(s: float) -> Vector3:
	if s <= 370.0 or s >= 500.0:
		return village_main_at(s)
	var first = village_main_at(370.0)
	var last = village_main_at(500.0)
	var first_side = village_main_side(370.0)
	var last_side = village_main_side(500.0)
	var stations = [370.0, 382.0, 402.0, 418.0, 435.0, 454.0, 474.0, 488.0, 500.0]
	var route = [
		first, first + first_side * 47.0, first + first_side * 96.0 + village_main_direction(370.0) * 28.0,
		village_main_at(420.0) + village_main_side(420.0) * 117.0,
		village_main_at(435.0) + village_main_side(435.0) * 115.0,
		village_main_at(460.0) + village_main_side(460.0) * 118.0,
		last + last_side * 96.0 - village_main_direction(500.0) * 28.0, last + last_side * 47.0, last
	]
	for i in range(stations.size() - 1):
		if s <= stations[i + 1]:
			var t = smoothstep(stations[i], stations[i + 1], s)
			var p: Vector3 = route[i].lerp(route[i + 1], t)
			if i >= 1 and i <= 6:
				# Smooth forest bends instead of stopped straight-line corners.
				t = (s - stations[i]) / (stations[i + 1] - stations[i])
				var a: Vector3 = route[i]
				var b: Vector3 = route[i + 1]
				var start_tangent: Vector3 = (route[i + 1] - route[i - 1]) * 0.5
				var end_tangent: Vector3 = (route[i + 2] - route[i]) * 0.5
				if i == 1:
					start_tangent = first_side * a.distance_to(b)
				if i == 6:
					end_tangent = -last_side * a.distance_to(b)
				p = a * (2*t*t*t - 3*t*t + 1) + start_tangent * (t*t*t - 2*t*t + t) + b * (-2*t*t*t + 3*t*t) + end_tangent * (t*t*t - t*t)
			p.y += (sin(s * 0.12) * 0.55 + sin(s * 0.037) * 0.75) * smoothstep(402.0, 418.0, s) * (1.0 - smoothstep(454.0, 474.0, s))
			return p
	return last

# Historic main-road station is independent of the rally-only bypass.
func village_main_nearest(pos: Vector3) -> Dictionary:
	var best = INF
	var station = 300.0
	var p = flat(pos)
	var start = clampf(-pos.z - 8.0, 290.0, 578.0)
	for i in range(9):
		var s = start + i * 2.0
		var a = flat(village_main_at(s))
		var segment = flat(village_main_at(s + 2.0)) - a
		var ratio = clampf((p - a).dot(segment) / maxf(segment.length_squared(), 0.000001), 0.0, 1.0)
		var distance = p.distance_squared_to(a + segment * ratio)
		if distance < best:
			best = distance
			station = s + ratio * 2.0
	return {"s": station, "distance": sqrt(best)}

# Contact heights are the tops of the explicitly authored paving meshes.
func village_paved_height(pos: Vector3) -> float:
	var nearest = village_main_nearest(pos)
	var on_main = nearest.s >= 300.0 and nearest.s <= 570.0
	if on_main and nearest.distance <= 3.75:
		return 2.0875
	for station in [370.0, 500.0]:
		var offset = pos - village_main_at(station)
		if absf(offset.dot(village_main_side(station))) <= 46.5 and absf(offset.dot(village_main_direction(station))) <= 2.5:
			return 2.0775
	if on_main and nearest.distance > 3.75 and nearest.distance < 6.45:
		return 2.36
	return INF

func _index_urban_route() -> void:
	road_segment_starts.clear()
	road_segment_deltas.clear()
	road_segment_inverse_lengths.clear()
	road_group_low.clear()
	road_group_high.clear()
	for i in range(points.size() - 1):
		var a = flat(points[i])
		var b = flat(points[i + 1])
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

func urban_nearest(pos: Vector3) -> Dictionary:
	if road_segment_starts.size() != points.size() - 1:
		_index_urban_route()
	var best = INF
	var station = 0.0
	var p = flat(pos)
	var seed = clampi(int(-pos.z / (STEP * ROAD_GROUP_SIZE)), 0, road_group_low.size() - 1)
	# Visit the likely group first, then reject others by a conservative bound.
	# Every segment capable of winning is still tested, including distant points.
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
			var candidate = (i + ratio) * STEP
			if distance < best or (distance == best and candidate < station):
				best = distance
				station = candidate
	return {"s": station, "distance": sqrt(best)}

func rally_speed(s: float) -> float:
	if desert:
		return 17.0 if s > 240.0 and s < 420.0 else 26.0
	if not urban:
		return 27.0
	return 15.0 if village(s) else 27.0

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
