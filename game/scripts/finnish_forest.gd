extends RefCounted
# Deterministic geometry for the fifth stage, "Финский лес": a fast, flowing gravel
# stage through a Finnish forest, with big crests, a chicane and lake shores.
# The layout is original and is only inspired by the character of classic Finnish
# rally stages (high speed, jumps, sweeping bends, lakes). It is shared by driving,
# walking, camp placement, rendering and every multiplayer client.
const LENGTH = 840.0

# Road elevation (station, metres). Catmull-Rom between keys keeps the road
# flowing; crests are added below as Gaussian bumps.
const KEYS = [
	[-20.0, 60.0], [0.0, 60.0], [60.0, 61.4], [120.0, 64.6], [160.0, 67.6], [200.0, 64.2], [245.0, 60.6],
	[285.0, 57.4], [310.0, 55.9], [350.0, 55.3], [390.0, 56.1], [425.0, 55.8], [460.0, 57.8], [490.0, 61.0],
	[520.0, 63.6], [548.0, 64.5], [575.0, 64.6], [600.0, 64.5], [625.0, 64.7], [652.0, 65.2], [675.0, 64.2],
	[705.0, 60.3], [740.0, 59.7], [780.0, 59.9], [820.0, 60.2], [840.0, 60.0], [860.0, 60.0],
]

# Station, height and half-width of each crest. The first one is the long
# "yellow house" jump; the last series is a run of rhythm crests.
const CRESTS = [
	[176.0, 1.9, 6.0], [233.0, 1.1, 6.5], [268.0, 1.3, 6.0], [514.0, 0.9, 7.0],
	[662.0, 1.6, 6.0], [684.0, 1.3, 6.0], [790.0, 0.8, 7.0],
]
const YELLOW_HOUSE_STATION = 176.0
const YELLOW_HOUSE_SIDE = 1.0
const YELLOW_HOUSE_OFFSET = 21.0

# Shallow ford where the road dips across the strait between the two lakes.
const FORD_STATION = 600.0
const FORD_DEPTH = 2.9
const FORD_HALF_WIDTH = 10.0

const CHICANE_BEGIN = 438.0
const CHICANE_END = 518.0

# `side` is the sign of the lateral offset (x - route x). `shore` is the mean
# distance from the road centre to the near shore, `width` the lake width.
# Every lake is carved into the terrain; water exists wherever the ground is
# below the lake's level, so roads, banks and islands all share one truth.
const LAKES = [
	{"name": "first", "side": -1.0, "s0": 296.0, "s1": 432.0, "level": 53.1, "depth": 4.6, "shore": 14.5, "width": 76.0, "bank": 13.0, "seed": 1.3,
		"islands": [{"s": 366.0, "u": 52.0, "radius": 10.0}, {"s": 396.0, "u": 70.0, "radius": 6.5}]},
	{"name": "isthmus_west", "side": -1.0, "s0": 548.0, "s1": 652.0, "level": 62.0, "depth": 3.4, "shore": 12.5, "width": 70.0, "bank": 12.0, "seed": 2.1, "islands": []},
	{"name": "isthmus_east", "side": 1.0, "s0": 548.0, "s1": 652.0, "level": 62.0, "depth": 3.4, "shore": 12.5, "width": 70.0, "bank": 12.0, "seed": 4.7, "islands": []},
	{"name": "third", "side": 1.0, "s0": 705.0, "s1": 822.0, "level": 57.4, "depth": 4.2, "shore": 14.5, "width": 80.0, "bank": 13.0, "seed": 3.9,
		"islands": [{"s": 760.0, "u": 50.0, "radius": 8.0}]},
]

# Rectangles (station, lateral) in which ground below `level` is water. The
# middle one spans both isthmus lakes and the ford between them.
const BODIES = [
	{"name": "first", "level": 53.1, "s0": 284.0, "s1": 444.0, "lat0": -118.0, "lat1": -4.0},
	{"name": "isthmus", "level": 62.0, "s0": 536.0, "s1": 664.0, "lat0": -100.0, "lat1": 100.0},
	{"name": "third", "level": 57.4, "s0": 693.0, "s1": 834.0, "lat0": 4.0, "lat1": 118.0},
]

# ---------------------------------------------------------------- route

func lateral_route(s: float) -> float:
	var start = smoothstep(0.0, 70.0, s) * (1.0 - 0.75 * smoothstep(796.0, 836.0, s))
	var chicane = smoothstep(CHICANE_BEGIN, CHICANE_BEGIN + 14.0, s) * (1.0 - smoothstep(CHICANE_END - 14.0, CHICANE_END, s))
	var calm = 1.0 - 0.8 * chicane
	var sweepers = 23.0 * sin(s / 92.0 + 0.4) + 12.0 * sin(s / 47.0 + 1.9) + 4.0 * sin(s / 21.0 + 0.7)
	return sweepers * start * calm + 7.5 * sin((s - CHICANE_BEGIN) * TAU / 52.0) * chicane

func elevation(s: float) -> float:
	var y = _keyed_elevation(s)
	for crest in CRESTS:
		var t = (s - crest[0]) / crest[2]
		y += crest[1] * exp(-t * t)
	var ford = pow(absf(s - FORD_STATION) / FORD_HALF_WIDTH, 4.0)
	y -= FORD_DEPTH * exp(-ford)
	return y + sin(s * 0.21) * 0.02

func _keyed_elevation(s: float) -> float:
	var last = KEYS.size() - 2
	var i = 1
	while i < last and s >= KEYS[i + 1][0]:
		i += 1
	var a: Array = KEYS[i]
	var b: Array = KEYS[i + 1]
	var t = clampf((s - a[0]) / (b[0] - a[0]), 0.0, 1.0)
	return cubic_interpolate(float(a[1]), float(b[1]), float(KEYS[i - 1][1]), float(KEYS[i + 2][1]), t)

func route(s: float) -> Vector3:
	return Vector3(lateral_route(s), elevation(s), -s)

func rally_speed(s: float) -> float:
	if s > CHICANE_BEGIN - 22.0 and s < CHICANE_END + 8.0:
		return 17.0
	if absf(s - FORD_STATION) < 28.0:
		return 19.0
	return 28.0

func road_width(s: float) -> float:
	# Wider on the open fast sections, a little narrower through the forest chicane.
	var chicane = smoothstep(CHICANE_BEGIN - 8.0, CHICANE_BEGIN + 8.0, s) * (1.0 - smoothstep(CHICANE_END - 8.0, CHICANE_END + 8.0, s))
	return 7.4 + 0.5 * smoothstep(60.0, 140.0, s) * (1.0 - smoothstep(660.0, 760.0, s)) - 1.0 * chicane

func roughness(s: float) -> float:
	return sin(s * 0.5) * 0.03 + sin(s * 1.31) * 0.015

# ---------------------------------------------------------------- terrain

func configure(stage) -> void:
	# Roadside spectator areas: flat, dry, and well away from every lake.
	for spot in [[128.0, 1.0, 15.0], [244.0, -1.0, 16.0], [486.0, 1.0, 15.0], [676.0, -1.0, 15.0]]:
		var p = stage.at(spot[0]) + stage.side(spot[0]) * spot[1] * spot[2]
		p.y = raw_ground(stage, p)
		stage.clearings.append(p)

func hills(pos: Vector3, distance: float) -> float:
	var swell = sin(pos.x * 0.036 + pos.z * 0.019) * 1.3 + sin(pos.z * 0.057 - pos.x * 0.027) * 0.8 + sin(pos.x * 0.11) * sin(pos.z * 0.09) * 0.5
	return swell * smoothstep(12.0, 30.0, distance)

func land(stage, pos: Vector3, s: float, distance: float) -> float:
	var p: Vector3 = stage.at(s)
	var slope = maxf(0.0, distance - 10.0)
	return p.y + roughness(s) * (1.0 - smoothstep(3.7, 8.0, distance)) + sin(pos.x * 0.07 + s * 0.013) * slope * 0.08 + slope * 0.2 + hills(pos, distance)

static func smooth_min(a: float, b: float, k: float) -> float:
	var h = clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, h) - k * h * (1.0 - h)

func shore_distance(lake: Dictionary, s: float) -> float:
	return lake.shore + 2.6 * sin(s * 0.047 + lake.seed) + 1.6 * sin(s * 0.121 + 2.0 * lake.seed)

# Signed distance (metres, positive inside the water polygon) of a point in
# route coordinates; the near shore, far shore and both ends close the lake.
func lake_margin(lake: Dictionary, s: float, lat: float) -> float:
	var u = lat * lake.side
	var near_shore = shore_distance(lake, s)
	var far_shore = near_shore + lake.width + 5.0 * sin(s * 0.031 + lake.seed)
	return minf(minf(u - near_shore, far_shore - u), 0.85 * minf(s - lake.s0, lake.s1 - s))

func carve(s: float, lat: float, base: float) -> float:
	var edge = smoothstep(4.5, 9.0, absf(lat))
	if edge <= 0.0:
		return base
	var result = base
	for lake in LAKES:
		if s < lake.s0 - 32.0 or s > lake.s1 + 32.0:
			continue
		var m = lake_margin(lake, s, lat)
		var reach = 1.0 - smoothstep(10.0, 24.0, -m)
		if reach <= 0.0:
			continue
		var bank = smooth_min(result, lake.level + maxf(0.0, -m) * 0.27, 1.2)
		var bed = bank - lake.depth * smoothstep(0.0, lake.bank, maxf(m, 0.0))
		var u = lat * lake.side
		for island in lake.islands:
			var ds = s - island.s
			var du = u - island.u
			var r = island.radius
			bed += (lake.depth + 2.3) * exp(-(ds * ds + du * du) / (r * r)) * smoothstep(2.0, 7.0, m)
		result = lerpf(result, bed, edge * reach)
	return result

func raw_ground(stage, pos: Vector3) -> float:
	var s: float = stage.road_s(pos)
	var p: Vector3 = stage.at(s)
	var lat = pos.x - p.x
	var distance = absf(lat)
	return carve(s, lat, land(stage, pos, s, distance))

func ground(stage, pos: Vector3) -> float:
	var height = raw_ground(stage, pos)
	for clearing in stage.clearings:
		var d = Vector2(pos.x - clearing.x, pos.z - clearing.z).length()
		height = lerpf(clearing.y, height, smoothstep(5.5, 11.5, d))
	return height

func grip(stage, pos: Vector3) -> float:
	var s: float = stage.road_s(pos)
	if stage.road_distance(pos) > road_width(s) * 0.55:
		return 0.46
	# Fast, well-packed gravel with a loose centre line and softer chicane exits.
	return 0.40 if int(s / stage.STEP) % 17 == 9 else 0.76

# ---------------------------------------------------------------- water

func water_body(stage, pos: Vector3) -> Dictionary:
	var s: float = stage.road_s(pos)
	for body in BODIES:
		if s < body.s0 or s > body.s1:
			continue
		var lat = pos.x - stage.at(s).x
		if lat >= body.lat0 and lat <= body.lat1:
			return body
	return {}

# Depth of water above the ground at pos; negative above the surface, and a very
# large negative number outside every lake's footprint.
func water_depth(stage, pos: Vector3) -> float:
	var body = water_body(stage, pos)
	if body.is_empty():
		return -1000.0
	return body.level - stage.ground(pos)

func nearest_water_level(stage, pos: Vector3) -> float:
	var body = water_body(stage, pos)
	return body.level if not body.is_empty() else -1000.0

# True where a 2 m terrain tile must be used to keep shorelines smooth.
func shoreline_near(s: float, lat: float) -> bool:
	for lake in LAKES:
		if s < lake.s0 - 20.0 or s > lake.s1 + 20.0:
			continue
		var m = lake_margin(lake, s, lat)
		if m > -9.0 and m < lake.bank + 4.0:
			return true
	return false

func terrain_color(stage, v: Vector3, variation: float) -> Color:
	var level = nearest_water_level(stage, v)
	var s: float = stage.road_s(v)
	var patch = (sin(v.x * 0.065) * sin(v.z * 0.041) + 1.0) * 0.5
	var moss = Color("4b5b34").lerp(Color("5e6a3a"), patch)
	var heath = Color("6a5a45").lerp(Color("72664a"), patch)
	var color = moss.lerp(heath, smoothstep(0.55, 0.9, sin(v.x * 0.021 - v.z * 0.033) * 0.5 + 0.5) * 0.7)
	if level > -999.0:
		var above = v.y - level
		var beach = 1.0 - smoothstep(0.0, 0.8, above)
		var sand = Color("b9a87c").lerp(Color("a4946b"), patch)
		color = color.lerp(sand, beach * smoothstep(-0.2, 0.05, above + 0.15))
		if above < 0.0:
			var bed_depth = smoothstep(0.0, 3.0, -above)
			color = sand.darkened(0.12).lerp(Color("3d4a42"), bed_depth)
	if stage.road_distance(v) > 4.5 and stage.road_distance(v) < 8.0:
		color = color.darkened(0.12)
	return color.lightened(variation)

func road_color(p: Vector3, s: float, lateral: float) -> Color:
	var base = Color("b3a283")
	var shade = sin(p.x * 0.17 + p.z * 0.11) * 0.025 + sin(p.z * 0.29 - p.x * 0.07) * 0.015
	# Dark wheel tracks and a loose pale crown between them.
	var track = exp(-pow((absf(lateral) - 1.0) / 0.34, 2.0))
	var centre = exp(-pow(lateral / 0.55, 2.0))
	return base.darkened(track * 0.16).lightened(centre * 0.05 + shade)
