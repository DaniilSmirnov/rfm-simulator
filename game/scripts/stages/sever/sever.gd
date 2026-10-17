extends "res://scripts/stages/stage_biome.gd"
# «Поречье»: a winter СУ on the plains of the Russian North (Vologda and
# Arkhangelsk oblasts) — open snow-covered farmland with small relief, crossed
# by a packed-snow country road with real corners and crests (подбросы),
# running through a village of log izbas past a wooden tent-roofed church and
# over a stream gully on a log bridge. The geometry, the village and its name
# are original and do not reproduce a real place; only the character is taken
# from the region. Deterministic geometry shared by driving, walking, camp
# placement, rendering and every multiplayer client; see
# docs/NORTHERN_VILLAGE_STAGE.md.
const LENGTH = 840.0
const SAMPLE = 0.5
const SPAN = 880.0

const DeepSnow = preload("res://scripts/stages/winter/deep_snow.gd")
const Snowbanks = preload("res://scripts/stages/winter/snowbanks.gd")
const Scenery = preload("res://scripts/stages/sever/sever_scenery.gd")
const Life = preload("res://scripts/stages/sever/sever_life.gd")
const WorldSync = preload("res://scripts/net/world_sync.gd")
var life: RefCounted

# ---------------------------------------------------------------- layout

# The street between the village sign and the granary at its far end.
const VILLAGE_BEGIN = 330.0
const VILLAGE_END = 560.0
const SIGN_S = 318.0
# The church stands back from the street with its bell tower towards the road.
const CHURCH = {"s": 470.0, "side": -1.0, "offset": 33.0}
const WELL = {"s": 480.0, "side": 1.0, "offset": 8.0}
const BARN = {"s": 566.0, "side": -1.0, "offset": 17.0}
const BRIDGE_S = 612.0
const BRIDGE_HALF_LENGTH = 9.0
# Depth of the stream gully below the road, and the half widths of its bed and banks.
const GULLY_DEPTH = 2.4
const GULLY_BED = 1.8
const GULLY_BANK = 8.0

# Izbas lining the street, gable end to the road: station, side, lateral
# offset of the living part's centre, facade width, living depth, storeys.
# The covered farmyard (двор) continues behind under the same roof.
const HOUSES = [
	[340.0, 1.0, 14.0, 7.0, 7.5, 1], [346.0, -1.0, 14.0, 6.6, 7.0, 1],
	[364.0, 1.0, 14.0, 7.4, 7.5, 1], [372.0, -1.0, 14.0, 6.8, 7.0, 1],
	[390.0, 1.0, 14.5, 7.8, 8.0, 2], [398.0, -1.0, 14.0, 7.0, 7.5, 1],
	[416.0, 1.0, 14.0, 7.0, 7.5, 1], [424.0, -1.0, 14.5, 7.2, 7.5, 2],
	[440.0, 1.0, 14.0, 7.2, 7.5, 1],
	[460.0, 1.0, 14.0, 6.8, 7.0, 1],
	[500.0, 1.0, 14.0, 7.2, 7.5, 1], [500.0, -1.0, 14.0, 6.8, 7.0, 1],
	[522.0, 1.0, 14.5, 7.8, 8.0, 2], [522.0, -1.0, 14.0, 7.0, 7.5, 1],
	[544.0, 1.0, 14.0, 7.2, 7.5, 1], [544.0, -1.0, 14.0, 6.6, 7.0, 1],
]
const YARD_DEPTH = 8.5

const CLEARINGS_LIST = [[96.0, -1.0, 30.0], [478.0, 1.0, 38.0], [588.0, 1.0, 22.0], [772.0, -1.0, 28.0]]
# Haystacks on poles (стога) in the open fields: station, side, offset.
const HAYSTACKS = [
	[60.0, -1.0, 26.0], [112.0, 1.0, 34.0], [192.0, -1.0, 40.0], [250.0, 1.0, 44.0],
	[662.0, -1.0, 34.0], [706.0, 1.0, 40.0], [752.0, -1.0, 32.0], [812.0, 1.0, 36.0],
]

# Corners: apex station, heading after the corner (degrees), radius (m).
# Open sweepers in the fields, a dogleg round the church square, a tight
# corner straight after the icy bridge.
const CORNERS = [
	[92.0, 36.0, 42.0], [160.0, -30.0, 26.0], [222.0, 18.0, 40.0], [298.0, 0.0, 46.0],
	[452.0, -22.0, 30.0], [492.0, 4.0, 32.0], [576.0, -6.0, 60.0],
	[642.0, 40.0, 24.0], [716.0, -24.0, 32.0], [782.0, 8.0, 46.0],
]
# Crests (подбросы) over field humps: station, height (m). Rally speed takes
# a car off the ground over each of them.
const CRESTS = [[132.0, 1.5], [262.0, 1.9], [678.0, 1.7], [800.0, 1.6]]

const BLEND = 9.0
const SECTIONS = [
	{"from": 0.0, "to": 160.0, "width": 6.6},
	{"from": 160.0, "to": 232.0, "width": 6.2},
	{"from": 232.0, "to": 328.0, "width": 6.6},
	{"from": 328.0, "to": 562.0, "width": 5.8},
	{"from": 562.0, "to": 594.0, "width": 6.0},
	{"from": 594.0, "to": 630.0, "width": 4.6},
	{"from": 630.0, "to": 700.0, "width": 6.4},
	{"from": 700.0, "to": 760.0, "width": 6.2},
	{"from": 760.0, "to": 841.0, "width": 6.8},
]

const GRIP = {"snow": 0.42, "ice": 0.16, "dirt": 0.64}
const COLORS = {"snow": Color("d8e0e1"), "ice": Color("9aaeb6"), "dirt": Color("473c30")}
const ICE_PATCHES = [118.0, 300.0, 404.0, 760.0, 822.0]

var lateral_table = PackedFloat64Array()
var speed_table = PackedFloat32Array()
var bends: Array[Dictionary] = []
var reserved_spots: Array[Dictionary] = []
var scenery
var chimneys: Array[Vector3] = []
# Frame of the stream crossing, set in configure().
var stream_origin = Vector3.ZERO
var stream_across = Vector3.RIGHT
var stream_along = Vector3.FORWARD

func _init() -> void:
	_integrate_route()
	_find_bends()
	_tabulate_speed()

# ---------------------------------------------------------------- route

# Heading (rad) at s: straights joined by circular arcs of the given radii.
func _heading(s: float) -> float:
	var heading = 0.0
	for corner in CORNERS:
		var target = deg_to_rad(float(corner[1]))
		var arc = absf(target - heading) * float(corner[2])
		var start = float(corner[0]) - arc * 0.5
		if s < start:
			break
		heading = lerpf(heading, target, clampf((s - start) / maxf(arc, 0.01), 0.0, 1.0))
		if s < start + arc:
			break
	return heading + 0.02 * sin(s / 37.0)

func _integrate_route() -> void:
	var count = int(SPAN / SAMPLE) + 2
	lateral_table.resize(count)
	var x = 0.0
	for i in range(count):
		lateral_table[i] = x
		x += tan(_heading(i * SAMPLE)) * SAMPLE
	# Remove the slow drift, so the finish lies back near the middle of the map.
	var drift = lateral_table[int(LENGTH / SAMPLE)]
	for i in range(count):
		lateral_table[i] -= drift * minf(i * SAMPLE, LENGTH) / LENGTH

func lateral_route(s: float) -> float:
	var t = clampf(s, 0.0, SPAN) / SAMPLE
	var i = mini(int(t), lateral_table.size() - 2)
	return lerpf(lateral_table[i], lateral_table[i + 1], t - i)

# Height of the crest humps at s: a long run-up and a shorter, steeper back.
func crest(s: float) -> float:
	var total = 0.0
	for item in CRESTS:
		var x = s - float(item[0])
		var width = 13.0 if x < 0.0 else 8.0
		total += float(item[1]) * exp(-pow(x / width, 2.0))
	return total

# Gentle farmland roll and the crests; the bridge deck is level.
func elevation(s: float) -> float:
	var roll = 2.0 + sin(s * 0.013) * 0.45 + sin(s * 0.041 + 1.1) * 0.25
	var deck = smoothstep(BRIDGE_S - BRIDGE_HALF_LENGTH - 14.0, BRIDGE_S - BRIDGE_HALF_LENGTH, s) * (1.0 - smoothstep(BRIDGE_S + BRIDGE_HALF_LENGTH, BRIDGE_S + BRIDGE_HALF_LENGTH + 14.0, s))
	var level = 2.0 + sin(BRIDGE_S * 0.013) * 0.45 + sin(BRIDGE_S * 0.041 + 1.1) * 0.25 + 0.3
	return lerpf(roll, level, deck) + crest(s)

func route(s: float) -> Vector3:
	return Vector3(lateral_route(s), elevation(s), -s)

# Plan curvature in 1/m (positive turns left).
func curvature(s: float) -> float:
	var h = 2.0
	var a = Vector2(lateral_route(s - h), -(s - h))
	var b = Vector2(lateral_route(s), -s)
	var c = Vector2(lateral_route(s + h), -(s + h))
	var ab = b - a
	var bc = c - b
	return 2.0 * ab.cross(bc) / maxf(ab.length() * bc.length() * (c - a).length(), 0.0001)

func _find_bends() -> void:
	for i in range(20, int(LENGTH) - 20):
		var s = float(i)
		var here = absf(curvature(s))
		if here < 1.0 / 70.0 or here < absf(curvature(s - 1.0)) or here < absf(curvature(s + 1.0)):
			continue
		if not bends.is_empty() and s - float(bends[-1].s) < 14.0:
			continue
		bends.append({"s": s, "radius": 1.0 / here, "left": curvature(s) > 0.0})

# ---------------------------------------------------------------- sections

func _blended(s: float, key: String) -> float:
	var total = 0.0
	var weight = 0.0
	for item in SECTIONS:
		var w = smoothstep(item.from - BLEND, item.from + BLEND, s) * (1.0 - smoothstep(item.to - BLEND, item.to + BLEND, s))
		if item.from <= 0.0 and s < BLEND:
			w = 1.0 - smoothstep(item.to - BLEND, item.to + BLEND, s)
		total += float(item[key]) * w
		weight += w
	return total / maxf(weight, 0.0001)

func road_width(s: float) -> float:
	return _blended(s, "width")

func rally_speed(s: float) -> float:
	return speed_table[clampi(int(s), 0, speed_table.size() - 1)]

# Crews brake for the tightest bend of the next 30 m and for the surface on
# the racing line; they lift through the village and over the narrow bridge.
func _tabulate_speed() -> void:
	speed_table.resize(int(LENGTH) + 1)
	for i in range(int(LENGTH) + 1):
		var tightest = 0.0
		var grip = 1.0
		for ahead in range(-4, 31, 2):
			var s = float(i + ahead)
			tightest = maxf(tightest, absf(curvature(s)))
			grip = minf(grip, surface_grip(s, 0.0))
		var lateral = clampf(17.0 * grip * 0.55, 3.0, 7.5)
		var limit = 27.0
		if in_village(float(i)):
			limit = 21.0
		if absf(float(i) - BRIDGE_S) < BRIDGE_HALF_LENGTH + 20.0:
			limit = 15.0
		speed_table[i] = clampf(sqrt(lateral / maxf(tightest, 0.0001)), 10.0, limit)

func in_village(s: float) -> bool:
	return s >= VILLAGE_BEGIN and s <= VILLAGE_END

func on_bridge(s: float) -> bool:
	return absf(s - BRIDGE_S) <= BRIDGE_HALF_LENGTH

func shoulder(s: float) -> float:
	if in_village(s) or absf(s - BRIDGE_S) < BRIDGE_HALF_LENGTH + 5.0:
		return 0.2
	return 1.4

func roughness(s: float) -> float:
	# Packed snow over a graded dirt road: faint corrugations, no gravel ruts.
	return sin(s * 0.6) * 0.022 + sin(s * 1.9) * 0.01

# ---------------------------------------------------------------- places

func place(s: float, side: float, offset: float) -> Vector3:
	var p: Vector3 = stage.at(s) + stage.side(s) * side * offset
	p.y = stage.base_ground(p)
	return p

# The whole footprint of an izba and its farmyard: centre and radius.
func house_footprint(item: Array) -> Dictionary:
	var depth = float(item[4]) + YARD_DEPTH
	var center = place(item[0], item[1], float(item[2]) + (depth - float(item[4])) * 0.5)
	return {"pos": center, "radius": Vector2(float(item[3]) * 0.5 + 1.2, depth * 0.5).length() + 1.5}

func configure() -> void:
	stream_origin = stage.at(BRIDGE_S)
	stream_along = stage.direction(BRIDGE_S)
	stream_across = stage.side(BRIDGE_S)
	for item in CLEARINGS_LIST:
		stage.clearings.append(place(item[0], item[1], item[2]))
	for clearing in stage.clearings:
		var station = stage.road_s(clearing)
		var outward = clearing - stage.at(station)
		outward.y = 0
		stage.snow_camps.append(clearing + outward.normalized() * 6.0)
	for i in range(3):
		var station = 140.0 + i * 230.0
		stage.snow_camps.append(stage.at(station) + stage.side(station) * (8.0 if i % 2 == 0 else -8.0))
	_register_reserved()
	_place_snow_glades()

func _register_reserved() -> void:
	for item in HOUSES:
		reserved_spots.append(house_footprint(item))
	reserved_spots.append({"pos": place(CHURCH.s, CHURCH.side, CHURCH.offset - 4.0), "radius": 14.5})
	reserved_spots.append({"pos": place(BARN.s, BARN.side, BARN.offset), "radius": 6.5})
	reserved_spots.append({"pos": place(WELL.s, WELL.side, WELL.offset + 1.5), "radius": 4.5})
	reserved_spots.append({"pos": place(SIGN_S, 1.0, 5.5), "radius": 2.5})
	reserved_spots.append({"pos": stage.at(BRIDGE_S), "radius": BRIDGE_HALF_LENGTH + 6.0})
	for item in HAYSTACKS:
		reserved_spots.append({"pos": place(item[0], item[1], item[2]), "radius": 4.5})

func reserved(pos: Vector3, padding: float = 0.0) -> bool:
	for spot in reserved_spots:
		if Vector2(pos.x - spot.pos.x, pos.z - spot.pos.z).length() < float(spot.radius) + padding:
			return true
	return false

func glade_blocked(s: float) -> bool:
	return (s > VILLAGE_BEGIN - 16.0 and s < VILLAGE_END + 16.0) or absf(s - BRIDGE_S) < 26.0

func _place_snow_glades() -> void:
	var taken: Array[float] = []
	for point in stage.clearings + stage.snow_camps: taken.append(stage.road_s(point))
	var candidates: Array = []
	for i in range(int((LENGTH - 80.0) / 4.0)):
		var station = 40.0 + i * 4.0
		var before = stage.direction(station - stage.GLADE_STRAIGHT)
		var after = stage.direction(station + stage.GLADE_STRAIGHT)
		var turn = Vector2(before.x, before.z).angle_to(Vector2(after.x, after.z))
		if absf(turn) < stage.GLADE_MAX_TURN and not glade_blocked(station): candidates.append([absf(turn), station])
	candidates.sort()
	for candidate in candidates:
		var station: float = candidate[1]
		var free = true
		for other in taken: free = free and absf(other - station) > stage.GLADE_SPACING
		if not free: continue
		taken.append(station)
		var side_sign = 1.0 if stage.snow_glades.size() % 2 == 0 else -1.0
		var center = stage.at(station) + stage.side(station) * side_sign * stage.GLADE_OFFSET
		center.y = stage.base_ground(stage.at(station) + stage.side(station) * side_sign * (stage.GLADE_OFFSET - stage.GLADE_FLAT))
		stage.snow_glades.append(center)
		if stage.snow_glades.size() >= stage.GLADE_COUNT: break

# ---------------------------------------------------------------- stream

# Meander of the stream centre line, metres along the road, at lateral t.
static func meander(t: float) -> float:
	return sin(t * 0.06) * 4.0 + sin(t * 0.023 + 0.7) * 7.0 - sin(0.7) * 7.0

# Signed distance across the stream at pos, and its lateral position t.
func stream_coordinates(pos: Vector3) -> Vector2:
	var rel = pos - stream_origin
	var t = rel.dot(stream_across)
	return Vector2(rel.dot(stream_along) - meander(t), t)

# Depth of the gully below the surrounding land at pos (0 away from it).
func gully(pos: Vector3) -> float:
	var c = stream_coordinates(pos)
	if absf(c.x) > GULLY_BANK or absf(c.y) > 160.0:
		return 0.0
	return GULLY_DEPTH * (1.0 - smoothstep(GULLY_BED, GULLY_BANK, absf(c.x))) * (1.0 - smoothstep(120.0, 160.0, absf(c.y)))

# The road crosses on the bridge deck: the gully opens beside it, not under the
# wheels. Rendered land below the deck is cut separately (terrain_vertex_height).
func road_mask(pos: Vector3) -> float:
	return smoothstep(road_width(BRIDGE_S) * 0.5 + 0.6, road_width(BRIDGE_S) * 0.5 + 1.6, absf(stream_coordinates(pos).y))

# ---------------------------------------------------------------- ground

func has_snow() -> bool:
	return true

# Open farmland: close to flat, a shallow ditch beside the road, the gentlest
# of swells further out, and the stream gully.
func base_ground(pos: Vector3) -> float:
	var s = stage.road_s(pos)
	var p = stage.at(s)
	var distance = stage.road_distance(pos)
	var half = road_width(s) * 0.5
	var height = p.y + roughness(s) * (1.0 - smoothstep(3.7, 8.0, distance))
	# Crests are humps of the road, not of the whole field.
	height -= crest(s) * smoothstep(half + 1.5, half + 14.0, distance)
	var ditch = -(1.0 - smoothstep(0.6, 2.4, absf(distance - (half + 1.6)))) * 0.3
	var swell = (sin(pos.x * 0.023 + pos.z * 0.015) * 1.1 + sin(pos.z * 0.037 - pos.x * 0.019) * 0.6 + sin(pos.x * 0.05) * sin(pos.z * 0.045) * 0.4) * smoothstep(half + 2.0, half + 24.0, distance)
	height += ditch + swell - gully(pos) * road_mask(pos)
	height = stage.blend_clearings(pos, height, 5.5, 11.5)
	return stage.blend_trails(pos, height)

# Drawn land: the gully continues below the bridge deck.
func terrain_vertex_height(x: float, z: float) -> float:
	var pos = Vector3(x, 0, z)
	return stage.snapped_vertex_height(x, z) - gully(pos) * (1.0 - road_mask(pos))

func ground(pos: Vector3) -> float:
	var height = stage.snow.floor_height(stage, pos) if stage.snow.is_dug(stage, pos) else stage.base_ground(pos)
	return maxf(height, Snowbanks.surface_height(stage, pos))

func vehicle_ground(pos: Vector3) -> float:
	return maxf(stage.snow.contact(stage, pos), Snowbanks.surface_height(stage, pos))

func walking_ground(pos: Vector3) -> float:
	var height = stage.ground(pos)
	var loose = stage.snow.loose_depth(stage, pos)
	if loose <= 0.02: return height
	var sunk = height - loose * lerpf(DeepSnow.FOOT_SINK, 0.28, stage.snow.packed(pos))
	return maxf(sunk, Snowbanks.surface_height(stage, pos))

func camp_allowed(spot: Vector3, kind: String) -> bool:
	var radius = 0.9 if kind == "table" else 0.55
	for x in [-radius, 0.0, radius]:
		for z in [-radius, 0.0, radius]:
			if stage.snow.loose_depth(stage, spot + Vector3(x, 0, z)) > 0.02: return false
	return true

# No ploughed banks on the bridge deck.
func snowbank_mask(s: float) -> float:
	var from = BRIDGE_S - BRIDGE_HALF_LENGTH
	var to = BRIDGE_S + BRIDGE_HALF_LENGTH
	return 1.0 - smoothstep(from - 6.0, from - 1.0, s) * (1.0 - smoothstep(to + 1.0, to + 6.0, s))

func grip(pos: Vector3) -> float:
	if stage.snow.is_dug(stage, pos): return 0.65
	if DeepSnow.depth(stage, pos) > 0.02:
		return lerpf(0.22, 0.46, stage.snow.packed(pos))
	var station = stage.road_s(pos)
	if stage.road_distance(pos) > road_width(station) * 0.55:
		return 0.3
	return surface_grip(station, (pos - stage.at(station)).dot(stage.side(station)), road_width(station) * 0.5)

func terrain_tile_step(p: Vector3) -> float:
	return 2.0 if stage.road_distance(p) < 20.0 or gully(p) > 0.0 else 4.0

func terrain_tiled() -> bool:
	return true

func terrain_chunk_built(tile: Vector2i, node: MeshInstance3D) -> void:
	stage.snow.register_chunk(stage, tile, node)

func terrain_color(v: Vector3) -> Color:
	var distance = stage.road_distance(v)
	var snow = Color("eef3f3").lerp(Color("f7f9f7"), (sin(v.x * 0.043 + v.z * 0.031) + 1.0) * 0.25)
	var trampled = smoothstep(18.0, 3.0, distance) * 0.5
	snow = snow.lerp(Color("d7dee0"), trampled)
	var bare = smoothstep(0.15, 0.55, sin(v.x * 0.021 + v.z * 0.027) * 0.5 + 0.5 + sin(v.z * 0.07) * 0.1)
	var stubble = Color("9a8f6e").lerp(Color("7c7256"), (sin(v.x * 0.09) + 1.0) * 0.3)
	return snow.lerp(stubble, bare * 0.3)

# ---------------------------------------------------------------- road surface

# The bridge deck is glazed with ice, plus a handful of shaded patches;
# everywhere else is packed snow with dark wheel tracks.
func ice(s: float, lateral: float) -> float:
	var from = BRIDGE_S - BRIDGE_HALF_LENGTH
	var to = BRIDGE_S + BRIDGE_HALF_LENGTH
	var bridge = smoothstep(from - 3.0, from + 1.0, s) * (1.0 - smoothstep(to - 1.0, to + 3.0, s))
	var patches = 0.0
	for patch_s in ICE_PATCHES:
		var along = (s - patch_s) / 6.0
		var across = lateral / 1.9
		patches = maxf(patches, 1.0 - smoothstep(0.75, 1.0, sqrt(along * along + across * across)))
	return clampf(maxf(bridge * 0.8, patches), 0.0, 1.0)

func snow_cover(s: float) -> float:
	return clampf(0.84 + 0.1 * sin(s * 0.021) + 0.06 * sin(s * 0.07), 0.55, 1.0)

func conditions(s: float, lateral: float) -> Dictionary:
	var cover = snow_cover(s)
	var track = exp(-pow((absf(lateral) - 0.9) / 0.42, 2.0))
	var ice_weight = ice(s, lateral)
	var snow = clampf(cover * (1.0 - 0.55 * track), 0.0, 1.0) * (1.0 - ice_weight)
	var dirt = maxf(0.0, 1.0 - snow - ice_weight)
	return {"snow": snow, "dirt": dirt, "ice": ice_weight}

func surface_grip(s: float, lateral: float, _half_width: float = 2.8) -> float:
	var mix = conditions(s, lateral)
	return mix.snow * GRIP.snow + mix.dirt * GRIP.dirt + mix.ice * GRIP.ice

func road_paint(p: Vector3, s: float, lateral: float) -> Color:
	var mix = conditions(s, lateral)
	var color = COLORS.snow * mix.snow + COLORS.dirt * mix.dirt + COLORS.ice * mix.ice
	color.a = 1.0
	var grain = sin(p.x * 0.9 + p.z * 1.3) * 0.015 + sin(p.z * 0.37 - p.x * 0.21) * 0.02
	return color.lightened(grain)

func road_color(p: Vector3, _s: float) -> Color:
	var station = stage.road_s(p)
	return road_paint(p, station, (p - stage.at(station)).dot(stage.side(station)))

func road_strips() -> int:
	return 10

func after_road() -> void:
	Snowbanks.build(stage)

# ---------------------------------------------------------------- scenery

func forest_tree_count() -> int:
	return 1400

func forest_tree_max_height() -> float:
	return 15.0

func forest_clearing_radius() -> float:
	return 9.0

# Wide open snow fields close to the road; the taiga stands further out.
func tree_blocked(p: Vector3) -> bool:
	return stage.road_distance(p) < 55.0 or reserved(p, 2.5) or gully(p) > 0.0

func roadside_rock_blocked(p: Vector3) -> bool:
	return reserved(p, 1.0) or gully(p) > 0.0

func woodland_blocked(pos: Vector3, padding: float) -> bool:
	return reserved(pos, padding) or gully(pos) > 0.0

func build_details(_cooperative: bool) -> void:
	scenery = Scenery.new()
	scenery.build(stage, self)
	life = Life.new()
	life.build(stage, self)

func update_life(delta: float, focus: Vector3) -> void:
	if life != null:
		life.update(delta, focus)

func build_horizon() -> void:
	Scenery.build_treeline(stage)

func sync_providers(_game) -> Array:
	var snow = stage.snow
	var snapshot = func() -> Dictionary:
		return {"snow": snow.snapshot(), "snow_dug": snow.dug_snapshot()}
	var apply = func(f: Dictionary, _t: float) -> void:
		snow.authoritative = false
		snow.apply_snapshot(f.get("snow", []))
		snow.apply_dug_snapshot(f.get("snow_dug", []))
	return [WorldSync.provider("snow", "snow", ["snow", "snow_dug"], snapshot, apply, true)]

func marshal_stations() -> Array:
	return [150.0, 400.0, 540.0, 700.0]
