extends "res://scripts/stage_biome.gd"
# «Майншафт»: a red-gravel stage in the Australian bush, inspired by the famous
# Mineshaft stage near Canberra. The layout keeps its character: a run of linked
# bends after the start, a long straight climbing to a giant drop-off jump, a
# corner straight after the landing and a short section of linked bends before
# the finish. Deterministic geometry shared by driving, walking, camp placement,
# rendering and every multiplayer client.

# Lip of the giant jump: the road falls DROP metres over DROP_LENGTH beyond it.
const LIP = 500.0
const DROP = 8.0
const DROP_LENGTH = 26.0
# Corner after the landing.
const CORNER_BEGIN = LIP + 28.0
const CORNER_END = LIP + 54.0
# Linked bends after the start and before the finish.
const OPENING_BEGIN = 30.0
const OPENING_END = 222.0
const CLOSING_BEGIN = 606.0
const CLOSING_END = 790.0
# Heading of the long straight (tangent of its angle to the -z axis).
const STRAIGHT_SLOPE = -0.16

# Road elevation keys (station, metres) before the drop is cut in.
const KEYS = [
	[-20.0, 50.0], [0.0, 50.0], [40.0, 50.5], [80.0, 52.0], [120.0, 51.2], [160.0, 52.8], [200.0, 54.2],
	[240.0, 54.0], [280.0, 55.0], [330.0, 56.4], [380.0, 57.4], [430.0, 58.6], [470.0, 59.6], [500.0, 60.4],
	[520.0, 60.6], [560.0, 60.4], [620.0, 60.0], [680.0, 59.4], [740.0, 59.8], [800.0, 60.4], [840.0, 60.8], [860.0, 60.8],
]
# Station, height and half-width of the smaller crests on the straight; the
# last one is the kicker that throws cars off the lip.
const CRESTS = [[300.0, 0.6, 7.0], [372.0, 0.8, 8.0], [436.0, 0.5, 6.0], [LIP - 4.0, 0.7, 6.0]]

const TABLE_STEP = 0.5
var lateral_table := PackedFloat32Array()

const OutbackScenery = preload("res://scripts/outback_scenery.gd")
const OutbackLife = preload("res://scripts/outback_life.gd")
# Station, side and distance from the road of the spectator areas: two in the
# opening bends, both banks of the jump, the outside of the corner after it and
# the closing bends.
const CLEARINGS = [[118.0, 1.0, 17.0], [196.0, -1.0, 17.0], [468.0, 1.0, 15.0], [486.0, -1.0, 15.0], [574.0, -1.0, 17.0], [700.0, 1.0, 16.0]]
# Mine headframe beside the lip and the homestead by the opening bends.
const MINE = [LIP - 6.0, 1.0, 26.0]
const HOMESTEAD = [64.0, -1.0, 40.0]
var scenery = OutbackScenery.new()
var outback_life = OutbackLife.new()
# Buildings and landmarks; trees, boulders and termite mounds keep clear.
var reserved_spots: Array[Dictionary] = []
var mine := Vector3.ZERO
var homestead := Vector3.ZERO

# ---------------------------------------------------------------- route

# Tangent of the road heading at s; integrated into the lateral offset.
func heading_slope(s: float) -> float:
	var opening = smoothstep(OPENING_BEGIN - 4.0, OPENING_BEGIN + 10.0, s) * (1.0 - smoothstep(OPENING_END - 16.0, OPENING_END + 4.0, s))
	# Each bend of the opening complex is a little tighter than the last.
	var tighten = 0.8 + 0.45 * clampf((s - OPENING_BEGIN) / (OPENING_END - OPENING_BEGIN), 0.0, 1.0)
	var slope = tighten * sin((s - OPENING_BEGIN) * TAU / 64.0) * opening
	var straight = smoothstep(OPENING_END - 8.0, OPENING_END + 24.0, s) * (1.0 - smoothstep(CORNER_BEGIN, CORNER_END, s))
	slope += STRAIGHT_SLOPE * straight
	slope += 0.9 * smoothstep(CORNER_BEGIN, CORNER_END, s) * (1.0 - smoothstep(CLOSING_BEGIN - 10.0, CLOSING_BEGIN + 10.0, s))
	var closing = smoothstep(CLOSING_BEGIN - 10.0, CLOSING_BEGIN + 10.0, s) * (1.0 - smoothstep(CLOSING_END - 20.0, CLOSING_END + 6.0, s))
	slope += (0.8 * sin((s - CLOSING_BEGIN) * TAU / 56.0) - 0.12) * closing
	return slope

func lateral_route(s: float) -> float:
	if lateral_table.is_empty():
		var x = 0.0
		for i in range(int((stage.LENGTH + 40.0) / TABLE_STEP) + 2):
			lateral_table.append(x)
			x += heading_slope((i + 0.5) * TABLE_STEP) * TABLE_STEP
	var f = clampf(s, 0.0, stage.LENGTH + 39.0) / TABLE_STEP
	var i = int(f)
	return lerpf(lateral_table[i], lateral_table[i + 1], f - i)

func elevation(s: float) -> float:
	var y = _keyed_elevation(s)
	for crest in CRESTS:
		var t = (s - crest[0]) / crest[2]
		y += crest[1] * exp(-t * t)
	# The drop-off: a short steep fall well beyond the reach of a flying car.
	y -= DROP * smoothstep(LIP, LIP + DROP_LENGTH, s)
	return y + sin(s * 0.23) * 0.03

func _keyed_elevation(s: float) -> float:
	var last = KEYS.size() - 3
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
	if s < OPENING_END + 6.0:
		return 16.0
	if s < LIP - 30.0:
		return 29.0
	if s < CORNER_BEGIN - 2.0:
		return 26.0
	if s < CORNER_END + 10.0:
		return 13.0
	return 17.0 if s < CLOSING_END + 4.0 else 24.0

func roughness(s: float) -> float:
	# Corrugations of a dry outback road.
	return sin(s * 0.9) * 0.025 + sin(s * 2.3) * 0.012

# ---------------------------------------------------------------- places

func place(spot: Array) -> Vector3:
	var s: float = spot[0]
	var p: Vector3 = stage.at(s) + stage.side(s) * float(spot[1]) * float(spot[2])
	p.y = stage.base_ground(p)
	return p

func configure() -> void:
	for spot in CLEARINGS:
		stage.clearings.append(place(spot))
	mine = place(MINE)
	homestead = place(HOMESTEAD)
	reserved_spots.append({"pos": mine, "radius": 13.0})
	reserved_spots.append({"pos": homestead, "radius": 16.0})

func reserved(pos: Vector3, padding: float = 0.0) -> bool:
	for spot in reserved_spots:
		if Vector2(pos.x - spot.pos.x, pos.z - spot.pos.z).length() < float(spot.radius) + padding:
			return true
	return false

func roadside_rock_blocked(p: Vector3) -> bool:
	return reserved(p, 1.0)

func woodland_blocked(pos: Vector3, padding: float) -> bool:
	return reserved(pos, padding)

func build_details(_cooperative: bool) -> void:
	scenery.build(stage, self)
	outback_life.build(stage, self)

func update_life(delta: float, focus: Vector3) -> void:
	outback_life.update(delta, focus)

# ---------------------------------------------------------------- ground

# Rolling grazing country: low granite hills, a gully below the jump.
func land_relief(pos: Vector3, distance: float) -> float:
	var swell = sin(pos.x * 0.031 + pos.z * 0.017) * 2.2 + sin(pos.z * 0.047 - pos.x * 0.023) * 1.3 + sin(pos.x * 0.09) * sin(pos.z * 0.08) * 0.6
	var ditch = (1.0 - smoothstep(0.45, 1.6, absf(distance - 6.0))) * 0.45
	ditch *= smoothstep(2.2, 4.0, stage.trail_distance(pos, 4.0))
	return swell * smoothstep(12.0, 32.0, distance) - ditch

func terrain_tile_step(p: Vector3) -> float:
	return 2.0 if stage.road_distance(p) < 12.0 else 4.0

func terrain_color(v: Vector3) -> Color:
	var patch = (sin(v.x * 0.061) * sin(v.z * 0.043) + 1.0) * 0.5
	var dirt = Color("7c3c22").lerp(Color("8f4c2c"), patch)
	var grass = Color("958a57").lerp(Color("7a7a4a"), patch)
	# Dry paddock grass over red earth; bare red ground near the road and on
	# scattered scalds where the grass has worn away.
	var bare = smoothstep(0.62, 0.85, sin(v.x * 0.027 - v.z * 0.035) * 0.5 + 0.5 + sin(v.z * 0.11) * 0.12)
	var cover = smoothstep(6.0, 14.0, stage.road_distance(v)) * (1.0 - bare * 0.85)
	var color = dirt.lerp(grass, cover)
	if stage.road_distance(v) > 4.5 and stage.road_distance(v) < 8.0:
		color = color.darkened(0.08)
	return color

# ---------------------------------------------------------------- road

func road_color(p: Vector3, s: float) -> Color:
	var lateral = (p - stage.at(s)).dot(stage.side(s))
	var base = Color("a65a36")
	var shade = sin(p.x * 0.17 + p.z * 0.11) * 0.025 + sin(p.z * 0.29 - p.x * 0.07) * 0.015
	# Dark compacted wheel tracks and a pale loose crown between them.
	var track = exp(-pow((absf(lateral) - 1.0) / 0.34, 2.0))
	var centre = exp(-pow(lateral / 0.55, 2.0))
	return base.darkened(track * 0.14).lightened(centre * 0.06 + shade)

func road_strips() -> int:
	return 6

func grip(pos: Vector3) -> float:
	var s: float = stage.road_s(pos)
	if stage.road_distance(pos) > stage.WIDTH * 0.55:
		return 0.46
	# Marbles of loose red gravel on the outside of the bends.
	return 0.42 if int(s / stage.STEP) % 11 == 6 else 0.75

func build_horizon() -> void:
	# Blue-grey ranges of the Great Dividing Range on the skyline.
	for i in range(16):
		var p = Vector3((-1 if i % 2 == 0 else 1) * stage.rng.randf_range(240, 340), 40, -i * 62.0 + 20.0)
		RallyProps.cylinder(stage, p, stage.rng.randf_range(130, 190), 0, stage.rng.randf_range(90, 150), Color("6f7f8f"), 6)
