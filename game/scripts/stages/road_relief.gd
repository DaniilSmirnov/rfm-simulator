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
# Its place is the flattest spot within a few metres of the regular spacing, so
# the basin does not sit on a crest.
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
	for step in range(-4, 5):
		var s = nominal + step * 2.0
		var score = absf(_plain(s + 2.0, lat) - _plain(s - 2.0, lat)) + absf(_plain(s, lat + 1.2) - _plain(s, lat - 1.2)) + absf(step) * 0.004
		if score < best:
			best = score
			chosen = s
	return {"s": chosen, "lat": lat, "level": _plain(chosen, lat)}

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

# One thin disc of water in each basin, at the level the ground was flattened to.
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
		var mesh = CylinderMesh.new()
		mesh.top_radius = 1.0
		mesh.bottom_radius = 1.0
		mesh.height = 0.004
		mesh.radial_segments = 24
		mesh.rings = 1
		disc.mesh = mesh
		disc.material_override = _water_material
		disc.name = "RoadPuddle_%d" % (index - 1)
		parent.add_child(disc)
		disc.scale = Vector3(PUDDLE_RX, 1.0, PUDDLE_RZ)
		disc.position = Vector3(stage.at(puddle.s).x + puddle.lat, puddle.level - WATER_DROP, -puddle.s)
