extends RefCounted
# The shape of the Charyn gorge, in world coordinates and without any
# reference to the road: canyon.gd routes the stage through this land, it does
# not define it. The river runs roughly along -z through a flat feather-grass
# table that tilts gently towards the Ili. Downstream the gorge deepens into
# the narrow slot of the Valley of Castles, then shallows and opens out into
# the wide gravel floor where the ash grove stands.
#
# Keys are read downstream (decreasing z) and interpolated smoothly.

# The land above the gorge and how deep the gorge is cut below it at world z.
# The table rises gently towards the Valley of Castles, where the river has
# sawn deepest, then breaks down into the open Ili valley at the mouth. The
# bed of the river is their difference, so it falls the whole way down.
const RIMS = [[80.0, 62.0], [0.0, 62.0], [-120.0, 68.0], [-250.0, 74.0], [-420.0, 75.0], [-500.0, 70.0], [-580.0, 63.0], [-680.0, 50.0], [-800.0, 34.0], [-960.0, 24.0]]
const DEPTHS = [[80.0, 3.0], [0.0, 15.0], [-60.0, 24.0], [-120.0, 32.0], [-200.0, 40.0], [-300.0, 46.0], [-420.0, 50.0], [-500.0, 46.0], [-580.0, 39.0], [-680.0, 31.0], [-800.0, 22.0], [-960.0, 16.0]]
# Half-width of its floor at world z: a slot through the castles, a wide
# gravel bed at the grove, the open Ili valley beyond.
const HALVES = [[80.0, 5.0], [0.0, 7.0], [-120.0, 11.0], [-250.0, 15.0], [-350.0, 18.0], [-450.0, 25.0], [-520.0, 38.0], [-580.0, 58.0], [-650.0, 84.0], [-800.0, 112.0], [-960.0, 124.0]]
# The Ili below the mouth of the gorge: a wide river running across the map
# from edge to edge, with its far bank rising into the ridges beyond.
const ILI_LEVEL = 6.5
const ILI_NEAR = -782.0
const ILI_FAR = -894.0
const ILI_BED = 2.6
const FAR_BANK = 26.0

# How fully a point lies in the channel of the Ili.
static func ili(z: float) -> float:
	return smoothstep(ILI_NEAR + 30.0, ILI_NEAR - 16.0, z) * (1.0 - smoothstep(ILI_FAR + 16.0, ILI_FAR - 26.0, z))

# The land of the valley floor below the gorge: the river channel cut into it
# and the far bank climbing away on the other side.
static func ili_bed(pos: Vector3, height: float) -> float:
	var channel = ILI_BED + sin(pos.x * 0.035) * 0.7 + sin(pos.x * 0.11 + pos.z * 0.07) * 0.35
	var bank = smoothstep(ILI_FAR - 2.0, ILI_FAR - 52.0, pos.z) * FAR_BANK
	return lerpf(height, channel, ili(pos.z)) + bank

# Where the ash grove stands: the reach below the castles where the floor has
# widened and the walls have dropped back.
const GROVE_BEGIN = -470.0
const GROVE_END = -760.0

# Smooth interpolation of a downstream-keyed table.
static func keyed(table: Array, z: float) -> float:
	if z >= float(table[0][0]):
		return float(table[0][1])
	for i in range(table.size() - 1):
		var a: Array = table[i]
		var b: Array = table[i + 1]
		if z >= float(b[0]):
			return lerpf(float(a[1]), float(b[1]), smoothstep(float(a[0]), float(b[0]), z))
	return float(table[-1][1])

# Centre line of the gorge: a meander across the table.
static func axis_x(z: float) -> float:
	return -26.0 + sin(z * 0.0075) * 26.0 + sin(z * 0.019) * 8.0

# Signed distance across the gorge, corrected for the slope of the meander so
# the walls keep their width where the river turns.
static func offset(pos: Vector3) -> float:
	var slope = (axis_x(pos.z + 2.0) - axis_x(pos.z - 2.0)) * 0.25
	return (pos.x - axis_x(pos.z)) / sqrt(1.0 + slope * slope)

static func depth(z: float) -> float:
	return keyed(DEPTHS, z)

static func floor_half(z: float) -> float:
	return keyed(HALVES, z) + sin(z * 0.021) * 2.5

# Height of the gravel bed the river runs over.
static func bed_level(z: float) -> float:
	return keyed(RIMS, z) - depth(z)

# Height of the steppe table, with its long swell.
static func rim_level(pos: Vector3) -> float:
	var swell = sin(pos.x * 0.016 + pos.z * 0.009) * 1.4 + sin(pos.z * 0.021 - pos.x * 0.013) * 0.9
	return keyed(RIMS, pos.z) + swell

# Horizontal run the wall takes from the foot of the talus to the rim. Soft
# beds stand back further than hard ones, so the run breathes along the gorge.
static func wall_run(z: float, side: float) -> float:
	var base = depth(z) * 0.34 + 6.0
	return base * (1.0 + sin(z * 0.023 + side * 1.7) * 0.18 + sin(z * 0.071) * 0.09)

# Where the foot of the wall stands: buttresses push out into the floor,
# recesses and the mouths of side gullies bite back into it.
static func wall_foot(z: float, side: float) -> float:
	var half = floor_half(z)
	var bays = sin(z * 0.047 + side * 2.4) * 4.5 + sin(z * 0.013) * 3.0
	return maxf(half * 0.55, half + bays)

# Distance from the axis at which the rim of the table begins.
static func rim_edge(z: float, side: float) -> float:
	return wall_foot(z, side) + wall_run(z, side)

# Fraction of the wall's rise reached `t` of the way across its run. The rock
# does not slope: it stands in three near-vertical cliffs, each ending in a
# narrow bench of its own debris, and the bands thicken and thin along the
# gorge as the soft beds come and go.
static func wall_profile(t: float, z: float) -> float:
	var shift = sin(z * 0.037) * 0.04
	var step = clampf(t, 0.0, 1.0)
	var first = smoothstep(0.02, 0.19 + shift, step) * (0.44 + shift)
	var second = smoothstep(0.29 + shift, 0.45, step) * 0.26
	var third = smoothstep(0.55, 0.73 + shift, step) * 0.24
	var last = smoothstep(0.88, 0.97, step) * 0.06
	return clampf(first + second + third + last, 0.0, 1.0)

# What the wall reaches at the rim: the table, notched where the head of a
# side ravine bites into it and crowned where a castle was left standing.
# `over` is how far past the top of the wall the sample lies.
static func crest(z: float, side: float, over: float, rim: float) -> float:
	var ravine = pow(maxf(0.0, sin(z * 0.029 + side * 1.9)), 12.0) * 14.0
	var towers = pow(maxf(0.0, sin(z * 0.14 + side * 2.3)), 6.0) * 9.0 + pow(maxf(0.0, sin(z * 0.37)), 8.0) * 3.5
	return rim - ravine * (1.0 - smoothstep(0.0, 24.0, over)) + towers * (1.0 - smoothstep(0.0, 16.0, over))

# The land itself: steppe table, walls, gravel floor. No road anywhere in it.
static func surface(pos: Vector3) -> float:
	var across = offset(pos)
	var side = signf(across) if across != 0.0 else 1.0
	var distance = absf(across)
	var rim = rim_level(pos)
	var foot = wall_foot(pos.z, side)
	if distance <= foot:
		return ili_bed(pos, _floor_surface(pos, distance, foot))
	var run = wall_run(pos.z, side)
	var top = crest(pos.z, side, distance - foot - run, rim)
	return ili_bed(pos, lerpf(bed_level(pos.z), top, wall_profile((distance - foot) / run, pos.z)))

# The gravel floor: braided channels in the bed, grassy flats by the grove.
static func _floor_surface(pos: Vector3, distance: float, foot: float) -> float:
	var bed = bed_level(pos.z)
	var braid = sin(pos.x * 0.12 + pos.z * 0.05) * 0.35 + sin(pos.z * 0.17) * 0.2
	var bank = smoothstep(foot * 0.45, foot, distance) * 1.6
	return bed + braid + bank

# How fully a point lies in the reach of the ash grove.
static func grove(z: float) -> float:
	return smoothstep(GROVE_BEGIN, GROVE_BEGIN - 60.0, z) * (1.0 - smoothstep(GROVE_END + 60.0, GROVE_END, z))
