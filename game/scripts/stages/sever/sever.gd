extends "res://scripts/stages/stage_biome.gd"
# «Поречье»: a flat winter СУ in the spirit of the Russian North (Vologda and
# Arkhangelsk oblasts) — open snow-covered farmland with small relief, crossed
# by a packed-snow country road, running through a log-built village between
# a birch-and-spruce field edge and a frozen stream. The geometry, the village
# and its name are original and do not reproduce a real place; only the
# character — izbas, a wooden church, a crane well, a log bridge — is taken
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

# The street between the village sign and the barn at its far end.
const VILLAGE_BEGIN = 330.0
const VILLAGE_END = 560.0
const SIGN_S = 320.0
const CHURCH = {"s": 468.0, "side": -1.0, "offset": 23.0}
const WELL = {"s": 480.0, "side": 1.0, "offset": 7.5}
const BARN = {"s": 566.0, "side": -1.0, "offset": 25.0}
const BRIDGE_S = 612.0
const BRIDGE_HALF_LENGTH = 9.0

# Izbas lining the street: station, side, lateral offset, width, depth, floors.
const HOUSES = [
	[338.0, 1.0, 15.0, 7.2, 6.0, 1], [344.0, -1.0, 15.5, 6.8, 5.8, 1],
	[366.0, 1.0, 14.5, 7.6, 6.2, 1], [372.0, -1.0, 14.8, 6.6, 5.8, 1],
	[392.0, 1.0, 15.5, 8.0, 6.6, 2], [398.0, -1.0, 14.5, 6.8, 6.0, 1],
	[420.0, 1.0, 14.8, 7.2, 6.0, 1], [424.0, -1.0, 15.2, 7.0, 6.0, 1],
	[442.0, 1.0, 15.0, 7.4, 6.2, 1],
	[460.0, 1.0, 14.5, 7.0, 6.0, 1],
	[496.0, 1.0, 15.5, 7.2, 6.0, 1], [496.0, -1.0, 14.5, 6.8, 5.8, 1],
	[518.0, 1.0, 14.8, 7.8, 6.4, 2], [518.0, -1.0, 15.2, 7.0, 6.0, 1],
	[542.0, 1.0, 14.5, 7.4, 6.2, 1], [542.0, -1.0, 14.8, 6.6, 5.8, 1],
]

const CLEARINGS_LIST = [[95.0, 1.0, 30.0], [478.0, -1.0, 34.0], [616.0, 1.0, 20.0], [772.0, -1.0, 28.0]]
# Haystacks dotted across the open fields: station, side, offset.
const HAYSTACKS = [
	[60.0, -1.0, 26.0], [110.0, 1.0, 34.0], [190.0, -1.0, 40.0], [262.0, 1.0, 46.0],
	[650.0, -1.0, 34.0], [706.0, 1.0, 40.0], [758.0, -1.0, 30.0], [812.0, 1.0, 36.0],
]

const BLEND = 9.0
const SECTIONS = [
	{"from": 0.0, "to": 160.0, "width": 6.6, "speed": 27.0},
	{"from": 160.0, "to": 232.0, "width": 6.2, "speed": 21.0},
	{"from": 232.0, "to": 328.0, "width": 6.6, "speed": 26.0},
	{"from": 328.0, "to": 562.0, "width": 5.6, "speed": 16.0},
	{"from": 562.0, "to": 600.0, "width": 6.0, "speed": 20.0},
	{"from": 600.0, "to": 624.0, "width": 4.6, "speed": 13.0},
	{"from": 624.0, "to": 700.0, "width": 6.6, "speed": 24.0},
	{"from": 700.0, "to": 760.0, "width": 6.2, "speed": 21.0},
	{"from": 760.0, "to": 841.0, "width": 6.8, "speed": 27.0},
]

const GRIP = {"snow": 0.42, "ice": 0.16, "dirt": 0.64}
const COLORS = {"snow": Color("d8e0e1"), "ice": Color("4e5c62"), "dirt": Color("473c30")}

var lateral_table = PackedFloat64Array()
var reserved_spots: Array[Dictionary] = []
var scenery
var chimneys: Array[Vector3] = []

func _init() -> void:
	_integrate_route()

# ---------------------------------------------------------------- route

# The road wanders gently (open fields, no hairpins) and swings around the
# church square; the integration is corrected at the end so the finish lies
# back near the start's lateral axis, same idea as the Turini lacets.
func _heading(s: float) -> float:
	var wander = 0.16 * sin(s / 145.0 + 0.4) + 0.09 * sin(s / 58.0 - 1.1) + 0.05 * sin(s / 21.0 + 2.3)
	var dogleg = -0.17 * sin(PI * clampf((s - 446.0) / 70.0, 0.0, 1.0))
	var bridge_line = 0.07 * sin(PI * clampf((s - 560.0) / 80.0, 0.0, 1.0))
	return wander + dogleg + bridge_line

func _integrate_route() -> void:
	var count = int(SPAN / SAMPLE) + 2
	lateral_table.resize(count)
	var x = 0.0
	for i in range(count):
		lateral_table[i] = x
		x += tan(_heading(i * SAMPLE)) * SAMPLE
	var drift = lateral_table[int(LENGTH / SAMPLE)]
	for i in range(count):
		lateral_table[i] -= drift * minf(i * SAMPLE, LENGTH) / LENGTH

func lateral_route(s: float) -> float:
	var t = clampf(s, 0.0, SPAN) / SAMPLE
	var i = mini(int(t), lateral_table.size() - 2)
	return lerpf(lateral_table[i], lateral_table[i + 1], t - i)

# Gentle farmland roll, with a shallow valley where the road crosses the
# frozen stream on the log bridge.
func elevation(s: float) -> float:
	var roll = 2.0 + sin(s * 0.013) * 0.45 + sin(s * 0.041 + 1.1) * 0.25
	var dip = -1.35 * exp(-pow((s - BRIDGE_S) / 20.0, 2.0))
	return roll + dip

func route(s: float) -> Vector3:
	return Vector3(lateral_route(s), elevation(s), -s)

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
	return _blended(s, "speed")

func in_village(s: float) -> bool:
	return s >= VILLAGE_BEGIN and s <= VILLAGE_END

func shoulder(s: float) -> float:
	if in_village(s) or (s > BRIDGE_S - 14.0 and s < BRIDGE_S + 14.0):
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

func configure() -> void:
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
		var p = place(item[0], item[1], item[2])
		reserved_spots.append({"pos": p, "radius": maxf(float(item[3]), float(item[4])) * 0.62 + 2.4})
	var church_p = place(CHURCH.s, CHURCH.side, CHURCH.offset)
	reserved_spots.append({"pos": church_p, "radius": 10.5})
	var barn_p = place(BARN.s, BARN.side, BARN.offset)
	reserved_spots.append({"pos": barn_p, "radius": 8.5})
	reserved_spots.append({"pos": place(WELL.s, WELL.side, WELL.offset), "radius": 3.0})
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
	return (s > VILLAGE_BEGIN - 16.0 and s < VILLAGE_END + 16.0) or absf(s - BRIDGE_S) < 24.0

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

# ---------------------------------------------------------------- ground

func has_snow() -> bool:
	return true

# Open farmland: close to flat, a shallow ditch beside the road and the
# gentlest of swells further out. No systematic rise away from the road, as
# this is level country, not a hillside.
func base_ground(pos: Vector3) -> float:
	var s = stage.road_s(pos)
	var p = stage.at(s)
	var distance = stage.road_distance(pos)
	var half = road_width(s) * 0.5
	var height = p.y + roughness(s) * (1.0 - smoothstep(3.7, 8.0, distance))
	var ditch = -(1.0 - smoothstep(0.6, 2.4, absf(distance - (half + 1.6)))) * 0.3
	var swell = (sin(pos.x * 0.023 + pos.z * 0.015) * 1.1 + sin(pos.z * 0.037 - pos.x * 0.019) * 0.6 + sin(pos.x * 0.05) * sin(pos.z * 0.045) * 0.4) * smoothstep(half + 2.0, half + 24.0, distance)
	height += ditch + swell
	height = stage.blend_clearings(pos, height, 5.5, 11.5)
	return stage.blend_trails(pos, height)

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

func grip(pos: Vector3) -> float:
	if stage.snow.is_dug(stage, pos): return 0.65
	if DeepSnow.depth(stage, pos) > 0.02:
		return lerpf(0.22, 0.46, stage.snow.packed(pos))
	var station = stage.road_s(pos)
	if stage.road_distance(pos) > road_width(station) * 0.55:
		return 0.3
	return surface_grip(station, (pos - stage.at(station)).dot(stage.side(station)), road_width(station) * 0.5)

func terrain_tile_step(p: Vector3) -> float:
	return 2.0 if stage.road_distance(p) < 20.0 else 4.0

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

# A bridge glazed with ice, plus a handful of shaded patches; everywhere else
# is packed snow with dark wheel tracks, and wind-scoured dirt shows through
# on crests away from the trees.
func ice(s: float, lateral: float) -> float:
	var bridge = smoothstep(BRIDGE_S - BRIDGE_HALF_LENGTH - 3.0, BRIDGE_S - BRIDGE_HALF_LENGTH + 3.0, s) * (1.0 - smoothstep(BRIDGE_S + BRIDGE_HALF_LENGTH - 3.0, BRIDGE_S + BRIDGE_HALF_LENGTH + 3.0, s))
	var patches = 0.0
	for patch_s in [118.0, 276.0, 404.0, 690.0, 804.0]:
		var along = (s - patch_s) / 6.0
		var across = lateral / 1.9
		patches = maxf(patches, 1.0 - smoothstep(0.75, 1.0, sqrt(along * along + across * across)))
	return clampf(maxf(bridge, patches), 0.0, 1.0)

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
	return stage.road_distance(p) < 55.0 or reserved(p, 2.5)

func roadside_rock_blocked(p: Vector3) -> bool:
	return reserved(p, 1.0)

func woodland_blocked(pos: Vector3, padding: float) -> bool:
	return reserved(pos, padding)

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
