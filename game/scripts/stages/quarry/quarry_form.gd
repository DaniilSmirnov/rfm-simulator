extends RefCounted
# The shape of the open pit and the spoil dumps around it, in world
# coordinates and without any reference to the road: quarry.gd routes the
# stage through this land. Modelled on the chrysotile pit of «Ураласбест» at
# Asbest in the Middle Urals (about 11 km long, 2 km wide and over 300 m
# deep), brought down to the size of a stage: an elongated pit with a flat
# floor, walls stepped in benches, and the grey dumps of crushed serpentinite
# around it, where the Asbest rally runs its special stages.
#
# The pit is a stadium: every bench follows the same outline at a constant
# distance from the axis segment, so a bench keeps its width round the ends.

# Axis segment of the floor (world x, and z from north to south).
const AXIS_X = -40.0
const NORTH_Z = -330.0
const SOUTH_Z = -690.0
# Half-width of the floor, and its height and that of the land around the pit.
const FLOOR = 34.0
const FLOOR_LEVEL = 12.0
const RIM_LEVEL = 62.0
# Each bench: a steep face FACE_RUN wide rising BENCH_RISE, then a level
# berm out to BENCH_RUN.
const BENCHES = 5
const BENCH_RISE = 10.0
const FACE_RUN = 5.5
const BENCH_RUN = 16.0
const RUN = BENCHES * BENCH_RUN
const RIM = FLOOR + RUN
const DEPTH = RIM_LEVEL - FLOOR_LEVEL
# The sump in the floor where the pit water gathers (world x, z, radius).
const SUMP = [-22.0, -640.0, 12.0]
# Spoil dumps on the land around the pit: world x, z, radius of the flat top,
# height. Their flanks stand at the angle of repose of loose rock.
const DUMPS = [
	[-110.0, -90.0, 34.0, 16.0], [-150.0, -170.0, 26.0, 12.0], [140.0, -60.0, 28.0, 14.0],
	[168.0, -230.0, 18.0, 13.0], [166.0, -420.0, 22.0, 18.0], [170.0, -620.0, 20.0, 15.0],
	[-60.0, 30.0, 22.0, 10.0], [100.0, -860.0, 40.0, 14.0], [-150.0, -860.0, 30.0, 12.0],
]
const REPOSE = 0.72

# Distance from the axis segment in plan.
static func axis_distance(pos: Vector3) -> float:
	var z = clampf(pos.z, SOUTH_Z, NORTH_Z)
	return Vector2(pos.x - AXIS_X, pos.z - z).length()

# Height of the stepped wall `k` metres out from the toe of the lowest face.
static func wall(k: float) -> float:
	if k <= 0.0:
		return FLOOR_LEVEL
	if k >= RUN:
		return RIM_LEVEL
	var bench = floorf(k / BENCH_RUN)
	var within = k - bench * BENCH_RUN
	var face = smoothstep(0.0, 1.0, clampf(within / FACE_RUN, 0.0, 1.0))
	return FLOOR_LEVEL + (bench + face) * BENCH_RISE

# Distance out from the toe at which the stepped wall, read as an even slope
# through the middle of its berms, reaches `height`; the haul road keeps to it.
static func slope_reach(height: float) -> float:
	var berm_middle = (FACE_RUN + BENCH_RUN) * 0.5
	return (height - FLOOR_LEVEL - BENCH_RISE) * BENCH_RUN / BENCH_RISE + berm_middle

# Inside the outline of the rim.
static func in_pit(pos: Vector3, padding: float = 0.0) -> bool:
	return axis_distance(pos) < RIM + padding

static func on_floor(pos: Vector3, padding: float = 0.0) -> bool:
	return axis_distance(pos) < FLOOR - padding

# Which bench (0 the lowest) a point stands on, and how far across its berm
# (0 at the crest of the face below, 1 at the toe of the next face); -1 off
# the berms.
static func berm(pos: Vector3) -> Vector2:
	var k = axis_distance(pos) - FLOOR
	if k < FACE_RUN or k > RUN:
		return Vector2(-1.0, 0.0)
	var bench = floorf(k / BENCH_RUN)
	var within = k - bench * BENCH_RUN
	if within < FACE_RUN:
		return Vector2(-1.0, 0.0)
	return Vector2(bench, (within - FACE_RUN) / (BENCH_RUN - FACE_RUN))

# The land around the pit: a low swell, and the dumps standing on it.
static func plateau(pos: Vector3) -> float:
	var swell = sin(pos.x * 0.021 + pos.z * 0.013) * 1.6 + sin(pos.z * 0.034 - pos.x * 0.017) * 0.9
	# The ground falls away gently to the pit, so the rim is a clean edge.
	var height = RIM_LEVEL + swell * smoothstep(RIM, RIM + 30.0, axis_distance(pos))
	return height + dump_height(pos)

static func dump_height(pos: Vector3) -> float:
	var height = 0.0
	for dump in DUMPS:
		var d = Vector2(pos.x - dump[0], pos.z - dump[1]).length()
		var flank = float(dump[3]) / REPOSE
		var rise = clampf((float(dump[2]) + flank - d) / flank, 0.0, 1.0)
		# Tipped from the top in lobes: the flank is ribbed, not a cone.
		var ribs = 1.0 + sin(atan2(pos.z - dump[1], pos.x - dump[0]) * 7.0 + dump[0]) * 0.05
		height = maxf(height, float(dump[3]) * smoothstep(0.0, 1.0, minf(rise * ribs, 1.0)))
	return height

# The land itself: dumps, rim, stepped walls, the floor and its sump.
static func surface(pos: Vector3) -> float:
	var k = axis_distance(pos) - FLOOR
	if k >= RUN:
		return plateau(pos)
	if k <= 0.0:
		var sump = Vector2(pos.x - SUMP[0], pos.z - SUMP[1]).length()
		var dip = (1.0 - smoothstep(SUMP[2] * 0.4, SUMP[2], sump)) * 1.4
		return FLOOR_LEVEL + sin(pos.x * 0.11 + pos.z * 0.07) * 0.18 - dip
	# Blasted faces are rough; the berms are graded.
	var rough = sin(pos.x * 0.53 + pos.z * 0.37) * 0.35 + sin(pos.z * 0.91 - pos.x * 0.29) * 0.2
	var within = fposmod(k, BENCH_RUN)
	var on_face = 1.0 - smoothstep(FACE_RUN, FACE_RUN + 1.0, within)
	return wall(k) + rough * on_face * smoothstep(0.0, 1.0, within)
