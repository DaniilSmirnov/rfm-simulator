extends RefCounted
# Deterministic geometry of the winter stage "Зимний Турини": a narrow alpine
# tarmac road in the spirit of the Rallye Monte-Carlo night stages over a col.
# The layout is original and only inspired by the character of the event:
# a fast corniche start above a valley, a ladder of tight lacets climbing to a
# snowy, icy col with a hamlet, a second ladder down and a fast finish.
# Tarmac carries mixed conditions: dry, wet, snow with dark wheel tracks and
# black ice. Deep snow, snowbanks, digging and compaction stay in deep_snow.gd
# and snowbanks.gd; this file only shapes the mountain they lie on.
const LENGTH = 840.0
const SAMPLE = 0.25
const SPAN = 880.0
const LACET_PERIOD = 96.0
const LACET_ANGLE = 0.733 # 42 degrees of heading on the lacet ladders
const COL_BEGIN = 412.0
const COL_END = 486.0
const COL_STATION = 448.0
const START_HEIGHT = 18.0
const COL_HEIGHT = 51.0
const FINISH_HEIGHT = 30.0

# Surface conditions: grip and colour of each kind of winter tarmac.
const GRIP = {"dry": 0.72, "wet": 0.55, "snow": 0.38, "ice": 0.17}
const COLORS = {"dry": Color("3a3f43"), "wet": Color("262c30"), "snow": Color("b6c0c6"), "ice": Color("4e5d66")}

var lateral_table = PackedFloat64Array()
var speed_table = PackedFloat32Array()
var bends: Array[Dictionary] = []
var ice_patches: Array[Dictionary] = []
var reserved_spots: Array[Dictionary] = []
# Filled by alpine_scenery.gd, animated by alpine_life.gd.
var hamlet: Array[Dictionary] = []
var chimneys: Array[Vector3] = []
var flag_spots: Array[Dictionary] = []
var flare_spots: Array[Vector3] = []

func _init() -> void:
	_integrate_route()
	_find_bends()
	_place_ice()
	_tabulate_speed()

# ---------------------------------------------------------------- route

static func ramp(a: float, b: float, x: float) -> float:
	return smoothstep(a, b, x)

# 1 on the two ladders of tight lacets, 0 on the open corniche and the col.
func lacets(s: float) -> float:
	var climb = ramp(112.0, 158.0, s) * (1.0 - ramp(372.0, 404.0, s))
	var descent = ramp(492.0, 526.0, s) * (1.0 - ramp(688.0, 722.0, s))
	return maxf(climb, descent)

func col(s: float) -> float:
	return ramp(COL_BEGIN - 8.0, COL_BEGIN + 14.0, s) * (1.0 - ramp(COL_END - 16.0, COL_END + 6.0, s))

# Open road cut into a mountainside: rock wall on one side, a drop on the other.
func corniche(s: float) -> float:
	return (1.0 - ramp(96.0, 134.0, s)) + ramp(706.0, 740.0, s)

# +1 when the mountain rises on the right of the direction of travel.
func uphill_sign(s: float) -> float:
	return -1.0 if s < COL_STATION else 1.0

# The heading is integrated so the lacets are diagonal straights joined by
# tight bends, and the corniche sections are long sweepers.
func _heading(s: float, phase: float) -> float:
	var w = lacets(s)
	var lacet = LACET_ANGLE * tanh(0.8 * sin(phase)) / tanh(0.8)
	var sweep = (0.52 * sin(s / 118.0 + 0.9) + 0.21 * sin(s / 47.0 + 2.0)) * (1.0 - 0.85 * col(s)) * ramp(0.0, 40.0, s)
	return w * lacet + (1.0 - w) * sweep

func _integrate_route() -> void:
	var count = int(SPAN / SAMPLE) + 2
	lateral_table.resize(count)
	var x = 0.0
	var phase = 0.0
	for i in range(count):
		var s = i * SAMPLE
		lateral_table[i] = x
		phase += TAU / LACET_PERIOD * SAMPLE * lacets(s)
		x += tan(_heading(s, phase)) * SAMPLE
	# Remove the slow drift, so the finish lies back in the middle of the map.
	var drift = lateral_table[int(LENGTH / SAMPLE)] + 12.0
	for i in range(count):
		lateral_table[i] -= drift * minf(i * SAMPLE, LENGTH) / LENGTH

func lateral_route(s: float) -> float:
	var t = clampf(s, 0.0, SPAN) / SAMPLE
	var i = mini(int(t), lateral_table.size() - 2)
	return lerpf(lateral_table[i], lateral_table[i + 1], t - i)

func elevation(s: float) -> float:
	var climb = (COL_HEIGHT - START_HEIGHT) * ramp(4.0, COL_BEGIN + 12.0, s)
	var descent = (COL_HEIGHT - FINISH_HEIGHT) * ramp(COL_END - 10.0, 836.0, s)
	return START_HEIGHT + climb - descent + sin(s / 31.0) * 0.9 * (1.0 - col(s))

func route(s: float) -> Vector3:
	return Vector3(lateral_route(s), elevation(s), -s)

# Plan curvature in 1/m from the integrated table (positive turns left).
func curvature(s: float) -> float:
	var h = 2.0
	var a = Vector2(lateral_route(s - h), -(s - h))
	var b = Vector2(lateral_route(s), -s)
	var c = Vector2(lateral_route(s + h), -(s + h))
	var ab = b - a
	var bc = c - b
	return 2.0 * ab.cross(bc) / maxf(ab.length() * bc.length() * (c - a).length(), 0.0001)

# Apex of each tight bend: chevrons, guard rails and fans gather there.
func _find_bends() -> void:
	for i in range(20, int(LENGTH) - 20):
		var s = float(i)
		var here = absf(curvature(s))
		if here < 1.0 / 40.0 or here < absf(curvature(s - 1.0)) or here < absf(curvature(s + 1.0)):
			continue
		if not bends.is_empty() and s - float(bends[-1].s) < 14.0:
			continue
		bends.append({"s": s, "radius": 1.0 / here, "left": curvature(s) > 0.0})

func rally_speed(s: float) -> float:
	return speed_table[clampi(int(s), 0, speed_table.size() - 1)]

# Crews brake for the tightest bend of the next 30 m. Lateral grip follows the
# surface on the racing line, so icy and snowy bends are taken more slowly.
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
		speed_table[i] = clampf(sqrt(lateral / maxf(tightest, 0.0001)), 10.0, 27.0)

# ---------------------------------------------------------------- terrain

func roughness(s: float) -> float:
	# Old alpine tarmac: frost heave and patched repairs, no gravel ruts.
	return sin(s * 0.5) * 0.02 + sin(s * 1.37) * 0.012 + sin(s * 0.13) * 0.015

# Height of the landscape before glades, clearings and camps are levelled.
func land(stage, pos: Vector3, s: float, distance: float) -> float:
	var p: Vector3 = stage.at(s)
	var lateral = (pos - p).dot(stage.side(s))
	var e = maxf(0.0, distance - 10.0)
	var height = p.y + roughness(s) * (1.0 - smoothstep(3.7, 8.0, distance))
	height += sin(pos.x * 0.07 + s * 0.013) * e * 0.06 + (sin(pos.x * 0.031 + pos.z * 0.023) * 1.4 + sin(pos.z * 0.051 - pos.x * 0.043) * 0.7) * smoothstep(12.0, 34.0, distance)
	var uphill = smoothstep(-2.0, 2.0, lateral * uphill_sign(s))
	var rise = 55.0 * (1.0 - exp(-e / 45.0)) + e * 0.12
	var drop = 30.0 * (1.0 - exp(-e / 24.0)) - maxf(0.0, e - 95.0) * 0.55
	var wall = lerpf(-drop, rise, uphill)
	# Valley flanks rise beyond the lacets, broken into spurs and gullies.
	var far = maxf(0.0, distance - 46.0)
	var ladder = e * 0.16 + far * (0.3 + 0.12 * sin(pos.z * 0.021 + lateral * 0.013)) + sin(pos.z * 0.034 + pos.x * 0.012) * smoothstep(40.0, 90.0, distance) * 6.0
	var saddle = maxf(0.0, distance - 26.0) * 0.42
	var c = clampf(corniche(s), 0.0, 1.0)
	var k = col(s) * (1.0 - c)
	return height + wall * c + saddle * k + ladder * (1.0 - c - k)

# Bare rock in the cut above the corniche and on the far valley walls.
func rock(stage, pos: Vector3, s: float, distance: float, height: float) -> float:
	var lateral = (pos - stage.at(s)).dot(stage.side(s))
	var c = clampf(corniche(s), 0.0, 1.0) * smoothstep(-1.0, 1.0, lateral * uphill_sign(s))
	var cut = c * smoothstep(12.5, 15.5, distance)
	var crags = sin(pos.x * 0.021 + pos.z * 0.017) * 0.6 + sin(pos.z * 0.043 - pos.x * 0.011) * 0.4
	var walls = (1.0 - c) * smoothstep(60.0, 80.0, distance) * smoothstep(0.1, 0.5, crags)
	# Snow lies on ledges; rock shows on the steep bands between them.
	var ledges = smoothstep(-0.2, 0.6, sin(height * 0.45 + pos.x * 0.03 + s * 0.02) + crags * 0.5)
	return clampf(maxf(cut, walls) * ledges, 0.0, 1.0)

func terrain_color(stage, v: Vector3) -> Color:
	var s: float = stage.road_s(v)
	var distance: float = stage.road_distance(v)
	var snow = Color("e7eef2").lerp(Color("f4f7f9"), (sin(v.x * 0.043 + v.z * 0.031) + 1.0) * 0.25)
	# Plough spray and exhaust grime close to the tarmac.
	snow = snow.lerp(Color("d8dfe3"), (1.0 - smoothstep(5.2, 9.5, distance)) * 0.6)
	var stone = Color("6d6863").lerp(Color("8c8781"), (sin(v.y * 1.7 + v.x * 0.2) + 1.0) * 0.5)
	return snow.lerp(stone, rock(stage, v, s, distance, v.y) * 0.8)

func reserved(pos: Vector3, padding: float = 0.0) -> bool:
	for spot in reserved_spots:
		if Vector2(pos.x - spot.pos.x, pos.z - spot.pos.z).length() < float(spot.radius) + padding:
			return true
	return false

# Glades must not swallow the col hamlet or the frozen waterfall.
func glade_blocked(s: float) -> bool:
	return s > COL_BEGIN - 14.0 and s < COL_END + 10.0

# ---------------------------------------------------------------- surface

# How much of the tarmac is under compacted snow at this station.
func snow_cover(s: float) -> float:
	var climb = ramp(102.0, 138.0, s) * (1.0 - ramp(386.0, 404.0, s))
	var col_snow = ramp(396.0, 414.0, s) * (1.0 - ramp(488.0, 502.0, s))
	var patchy = ramp(492.0, 510.0, s) * (1.0 - ramp(690.0, 726.0, s)) * clampf(0.5 + 0.55 * sin(s / 23.0 + 1.1) + 0.25 * sin(s / 9.0), 0.0, 1.0)
	return maxf(maxf(climb * 0.95, col_snow), patchy)

func wetness(s: float) -> float:
	return clampf(0.35 + 0.45 * sin(s / 37.0 + 0.4) + 0.2 * sin(s / 13.0), 0.0, 1.0)

func _place_ice() -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 30012026
	# The col never sees the sun: a long glazed stretch, then patches below it.
	ice_patches.append({"s": 446.0, "half": 15.0, "lat": 0.4, "width": 3.3})
	ice_patches.append({"s": 474.0, "half": 7.0, "lat": -1.2, "width": 2.2})
	for i in range(30):
		var s = rng.randf_range(24.0, LENGTH - 24.0)
		if absf(s - COL_STATION) < 40.0:
			continue
		ice_patches.append({"s": s, "half": rng.randf_range(2.5, 8.0), "lat": rng.randf_range(-1.8, 1.8), "width": rng.randf_range(1.1, 2.6)})
	ice_patches.sort_custom(func(a, b): return float(a.s) < float(b.s))

# Soft-edged ice mask; the visible glaze uses the same function.
func ice(s: float, lateral: float) -> float:
	var result = 0.0
	for patch in ice_patches:
		var along = (s - float(patch.s)) / float(patch.half)
		if absf(along) > 1.3:
			continue
		var across = (lateral - float(patch.lat)) / float(patch.width)
		var edge = 0.16 * sin(s * 2.3 + lateral * 3.1 + float(patch.s)) + 0.08 * sin(s * 5.1 - lateral * 1.7)
		result = maxf(result, 1.0 - smoothstep(0.78, 1.0, sqrt(along * along + across * across) + edge))
	return result

# Weights of dry, wet, snow and ice for a point on the carriageway.
func conditions(s: float, lateral: float, half_width: float) -> Dictionary:
	var cover = snow_cover(s)
	# Cars sweep two dark tracks through the snow; the crown and edges stay white.
	var track = exp(-pow((absf(lateral) - 0.95) / 0.42, 2.0))
	var edge = smoothstep(half_width - 1.15, half_width - 0.1, absf(lateral))
	# Glaze lies on top of everything else, even on snowy stretches.
	var ice_weight = ice(s, lateral)
	var snow = clampf(cover * (1.0 - 0.8 * track) + edge * 0.85 * maxf(cover, 0.45), 0.0, 1.0) * (1.0 - ice_weight)
	var rest = maxf(0.0, 1.0 - snow - ice_weight)
	var wet = rest * wetness(s) * (0.6 + 0.4 * cover)
	return {"dry": maxf(0.0, rest - wet), "wet": wet, "snow": snow, "ice": ice_weight}

func surface_grip(s: float, lateral: float, half_width: float = 3.7) -> float:
	var mix = conditions(s, lateral, half_width)
	return mix.dry * GRIP.dry + mix.wet * GRIP.wet + mix.snow * GRIP.snow + mix.ice * GRIP.ice

func road_color(p: Vector3, s: float, lateral: float, half_width: float) -> Color:
	var mix = conditions(s, lateral, half_width)
	var color = COLORS.dry * mix.dry + COLORS.wet * mix.wet + COLORS.snow * mix.snow + COLORS.ice * mix.ice
	color.a = 1.0
	var grain = sin(p.x * 0.9 + p.z * 1.3) * 0.015 + sin(p.z * 0.37 - p.x * 0.21) * 0.02
	return color.lightened(grain)

# Thin glossy glaze over every ice patch, conforming to the road surface. The
# vertex alpha follows the same soft mask as grip, so the edges fade out.
func build_ice(stage) -> void:
	var surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count = 0
	var half = stage.WIDTH * 0.5
	var steps_l = 20
	for patch in ice_patches:
		var s0 = maxf(1.0, float(patch.s) - float(patch.half) * 1.35)
		var s1 = minf(LENGTH - 1.0, float(patch.s) + float(patch.half) * 1.35)
		var steps_s = maxi(2, int((s1 - s0) / 0.35))
		for i in range(steps_s):
			for j in range(steps_l):
				var corners = []
				var visible = false
				for corner in [[i, j], [i + 1, j], [i, j + 1], [i + 1, j + 1]]:
					var s = lerpf(s0, s1, float(corner[0]) / steps_s)
					var lateral = lerpf(-half, half, float(corner[1]) / steps_l)
					var mask = ice(s, lateral) * (1.0 - smoothstep(half - 0.9, half - 0.2, absf(lateral)))
					visible = visible or mask > 0.03
					corners.append([stage.road_surface_vertex(s, lateral) + Vector3.UP * 0.012, mask])
				if not visible:
					continue
				for k in [0, 1, 2, 2, 1, 3]:
					surface.set_color(Color(0.33, 0.4, 0.45, clampf(float(corners[k][1]) * 0.75, 0.0, 0.75)))
					surface.add_vertex(corners[k][0])
				count += 1
	if count == 0:
		return
	surface.generate_normals()
	var node = MeshInstance3D.new()
	node.name = "BlackIce"
	node.mesh = surface.commit()
	var material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.04
	material.metallic = 0.2
	material.metallic_specular = 0.7
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(node)
