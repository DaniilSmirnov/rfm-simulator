extends RefCounted
# Wheel ruts and puddles dug into the road itself. A stage whose biome says
# road_ruts(s) gets them as real relief: the surface height every tyre, foot and
# camp reads (Stage.ground) is lowered in two wheel tracks and in shallow basins,
# and the road mesh is cut finely enough to show it, so the cars rock in the ruts
# and sink into the puddles instead of skating over decals.
#
#   ruts     Two tracks at ±RUT_OFFSET, broken into stretches that come and go
#            and vary in depth, each with a low berm of pushed-up mud beside it.
#   puddles  A basin every PUDDLE_SPACING m, on alternating sides. The ground
#            around its centre is levelled first so the water sits flat in it;
#            the water is a separate thin disc at that level, visible only where
#            the basin is deeper than WATER_DROP.
#
# The relief is a pure function of the position, like the rest of the ground, so
# every member of a room sees the same road. Everything is measured from the
# route: s along it, `lat` across it (x offset, as the land of these stages does).
const RUT_OFFSET = 1.0
const RUT_WIDTH = 0.3
const RUT_DEPTH = 0.09
const BERM_HEIGHT = 0.2
const PUDDLE_FIRST = 28.0
const PUDDLE_SPACING = 52.0
const PUDDLE_SIDE = 1.45
const PUDDLE_RX = 1.25
const PUDDLE_RZ = 2.1
const PUDDLE_DEPTH = 0.11
const WATER_DROP = 0.04
# How far from the regular spacing a puddle may move to find a dip, and how
# many directions its footprint and surroundings are sampled in.
const SITE_REACH = 12.0
const SITE_RAYS = 12
const SHEET_SEGMENTS = 24
const MAX_DEPTH = 0.2
const REACH = 3.2
const FINE_STRIP = 0.2
const FINE_HALF = 2.6
const MUD = Color("5a4a38")
const WATER = Color("465a5e")

var stage
var _state = -1
var _sites: Dictionary = {}
static var _water_material: StandardMaterial3D

func _init(owner = null) -> void:
	stage = owner

# True when this stage digs ruts anywhere along its length.
func enabled() -> bool:
	if _state < 0:
		_state = 0
		for s in range(0, int(stage.length) + 1, 8):
			if stage.biome.road_ruts(float(s)):
				_state = 1
				break
	return _state == 1

# ---------------------------------------------------------------- mesh layout

# Lateral breakpoints of the road mesh across `width`: the usual even strips, or
# a fine grid over the tracks and puddles with coarse strips at the edges.
func edges(width: float, strips: int) -> Array:
	var half = width * 0.5
	var result: Array = []
	if not enabled():
		for i in range(strips + 1):
			result.append(-half + width * float(i) / strips)
		return result
	var fine = minf(FINE_HALF, half - 0.3)
	result.append(-half)
	var count = roundi(fine * 2.0 / FINE_STRIP)
	for i in range(count + 1):
		result.append(-fine + fine * 2.0 * float(i) / count)
	result.append(half)
	return result

# Segments per metre of route: finer than the plain road when it is dug.
func divisions(length: float) -> int:
	if enabled():
		return maxi(2, ceili(length / 0.6))
	return maxi(4, ceili(length / 0.75))

# ---------------------------------------------------------------- relief

func _track(s: float, lat: float) -> float:
	var across = absf(absf(lat) - RUT_OFFSET)
	if across > 0.95:
		return 0.0
	var trough = exp(-pow(across / RUT_WIDTH, 2.0))
	var berm = exp(-pow((across - 0.5) / 0.14, 2.0)) * BERM_HEIGHT
	var phase = s * 0.173 + sin(s * 0.041) * 2.0 + (1.7 if lat > 0.0 else 0.0)
	var broken = smoothstep(0.55, 0.9, 0.5 + 0.5 * sin(phase))
	var depth = RUT_DEPTH * (0.65 + 0.35 * sin(s * 0.31 + 1.1))
	return (trough - berm) * depth * broken * stage.biome.rut_strength(s)

# The puddle nearest to station s: {"s", "lat", "level"} or an empty dictionary.
# Its place is the lowest, most level spot within SITE_REACH m of the regular
# spacing: a dip in the road, never a crest or a hump, where water would not
# gather and the flat disc would stand proud of the falling ground around it.
func site(s: float) -> Dictionary:
	var index = roundi((s - PUDDLE_FIRST) / PUDDLE_SPACING)
	if index < 0:
		return {}
	if not _sites.has(index):
		_sites[index] = _find_site(index)
	return _sites[index]

func _find_site(index: int) -> Dictionary:
	var nominal = PUDDLE_FIRST + index * PUDDLE_SPACING
	if nominal > stage.length - 8.0 or stage.biome.rut_strength(nominal) < 0.6:
		return {}
	var lat = PUDDLE_SIDE * (1.0 if index % 2 == 0 else -1.0)
	var best = INF
	var chosen = nominal
	var level = 0.0
	var steps = int(SITE_REACH / 2.0)
	for step in range(-steps, steps + 1):
		var s = nominal + step * 2.0
		if stage.biome.rut_strength(s) < 0.6:
			continue
		var centre = _plain(s, lat)
		# The water fills the basin up to its lowest point, so none of the disc
		# can lie above the ground at its edge.
		var lowest = centre
		var around = 0.0
		for a in range(SITE_RAYS):
			var angle = TAU * a / SITE_RAYS
			var dir = Vector2(cos(angle) * PUDDLE_RX, sin(angle) * PUDDLE_RZ)
			lowest = minf(lowest, _plain(s + dir.y * 0.55, lat + dir.x * 0.55))
			lowest = minf(lowest, _plain(s + dir.y, lat + dir.x))
			around += _plain(s + dir.y * 2.0, lat + dir.x * 2.0)
		# How far the basin would be cut below its centre, and how far the centre
		# stands above the land around it (a crest or a hump).
		var score = (centre - lowest) + maxf(0.0, centre - around / SITE_RAYS) * 2.0 + absf(step) * 0.004
		if score < best:
			best = score
			chosen = s
			level = lowest
	return {"s": chosen, "lat": lat, "level": level}

# The land height at (s, lat) before anything is dug into it.
func _plain(s: float, lat: float) -> float:
	var pos = Vector3(stage.at(s).x + lat, 0.0, -s)
	return stage.biome.base_ground(pos)

func _basin(s: float, lat: float, puddle: Dictionary) -> float:
	var q = Vector2((lat - puddle.lat) / PUDDLE_RX, (s - puddle.s) / PUDDLE_RZ).length()
	return 1.0 - smoothstep(0.3, 1.0, q)

# `height` is the plain ground at pos; returns it with the ruts and puddles dug.
func dig(pos: Vector3, height: float) -> float:
	if not enabled():
		return height
	var s = stage.road_s(pos)
	var lat = pos.x - stage.at(s).x
	if absf(lat) > REACH:
		return height
	var dug = _track(s, lat)
	var puddle = site(s)
	if not puddle.is_empty() and absf(s - puddle.s) < PUDDLE_RZ * 1.4:
		var q = Vector2((lat - puddle.lat) / PUDDLE_RX, (s - puddle.s) / PUDDLE_RZ).length()
		height = lerpf(height, puddle.level, 1.0 - smoothstep(0.75, 1.4, q))
		dug += _basin(s, lat, puddle) * PUDDLE_DEPTH
	return height - clampf(dug, -BERM_HEIGHT * RUT_DEPTH, MAX_DEPTH)

# Damp, dark mud in the tracks and the basins.
func tint(p: Vector3, color: Color) -> Color:
	if not enabled():
		return color
	var s = stage.road_s(p)
	var lat = p.x - stage.at(s).x
	if absf(lat) > REACH:
		return color
	var wet = maxf(0.0, _track(s, lat)) / RUT_DEPTH
	var puddle = site(s)
	if not puddle.is_empty() and absf(s - puddle.s) < PUDDLE_RZ * 1.4:
		wet = maxf(wet, _basin(s, lat, puddle))
	return color.lerp(MUD, clampf(wet, 0.0, 1.0) * 0.6)

# ---------------------------------------------------------------- water

# One thin sheet of water in each basin, at the level the ground was flattened to.
func build_water(parent: Node3D) -> void:
	if not enabled():
		return
	if _water_material == null:
		_water_material = StandardMaterial3D.new()
		_water_material.albedo_color = WATER
		_water_material.roughness = 0.06
		_water_material.metallic_specular = 0.9
	var index = 0
	while PUDDLE_FIRST + index * PUDDLE_SPACING <= stage.length:
		var puddle = site(PUDDLE_FIRST + index * PUDDLE_SPACING)
		index += 1
		if puddle.is_empty():
			continue
		var disc = MeshInstance3D.new()
		disc.mesh = _sheet(puddle)
		disc.material_override = _water_material
		disc.name = "RoadPuddle_%d" % (index - 1)
		parent.add_child(disc)
		disc.position = Vector3(stage.at(puddle.s).x + puddle.lat, puddle.level - WATER_DROP, -puddle.s)

# The water's outline in road coordinates, the same ellipse the basin is dug in:
# on a bend the road shifts sideways under it, and a plain world-space disc would
# slide off the basin and lie on the bank in two crescents.
func _sheet(puddle: Dictionary) -> ArrayMesh:
	var origin = Vector3(stage.at(puddle.s).x + puddle.lat, 0.0, -puddle.s)
	var rings = [0.0, 0.5, 1.0]
	var points: Array = []
	for ring in rings:
		var row: Array = []
		for a in range(SHEET_SEGMENTS):
			var angle = TAU * a / SHEET_SEGMENTS
			var s = puddle.s + sin(angle) * PUDDLE_RZ * ring
			var x = stage.at(s).x + puddle.lat + cos(angle) * PUDDLE_RX * ring
			row.append(Vector3(x, 0.0, -s) - origin)
		points.append(row)
	var surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_normal(Vector3.UP)
	for r in range(rings.size() - 1):
		for a in range(SHEET_SEGMENTS):
			var b = (a + 1) % SHEET_SEGMENTS
			for vertex in [points[r][a], points[r + 1][b], points[r + 1][a], points[r][a], points[r][b], points[r + 1][b]]:
				surface.add_vertex(vertex)
	return surface.commit()
