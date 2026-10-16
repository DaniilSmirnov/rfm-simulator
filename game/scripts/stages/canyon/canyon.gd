extends "res://scripts/stages/stage_biome.gd"
# «Чарынский каньон»: the Kazakh steppe split open by the Charyn gorge. The
# road crosses a flat feather-grass plateau, slips through a gate of rock
# towers, drops down a ledge cut into the wall of the Valley of Castles, runs
# along the dry bed between stratified walls and climbs back out to the
# steppe. The walls are the stage: banded cliffs broken by benches of fallen
# rock, buttresses and recesses, ravine heads notching the skyline and towers
# left standing on the rim. Deterministic geometry shared by driving,
# walking, camp placement, rendering and every multiplayer client.
const Scenery = preload("res://scripts/stages/canyon/canyon_scenery.gd")
const CanyonLife = preload("res://scripts/stages/canyon/canyon_life.gd")

# The steppe table and how deep the river has cut into it.
const PLATEAU = 64.0
const DEPTH = 58.0
# Station, extra half-width and length of the places where the gorge opens
# out: two amphitheatres under the walls and two side gullies.
const BAYS = [[462.0, 54.0, 36.0], [616.0, 48.0, 32.0], [318.0, 26.0, 16.0], [672.0, 22.0, 18.0]]
# Station, side and distance of the spectator areas: the yurt camp and the
# viewpoint on the steppe, then the amphitheatre, the narrows, the ash grove
# in the dry bed and the last one back up on the steppe after the climb out.
const CAMPS = [[138.0, 1.0, 17.0], [168.0, -1.0, 20.0], [462.0, 1.0, 24.0], [556.0, -1.0, 15.0], [658.0, 1.0, 18.0], [806.0, 1.0, 20.0]]

var scenery = Scenery.new()
var canyon_life = CanyonLife.new()

# ---------------------------------------------------------------- route

# Fraction of the full descent reached at station s.
func depth_fraction(s: float) -> float:
	return clampf(smoothstep(206.0, 402.0, s) - smoothstep(700.0, 806.0, s), 0.0, 1.0)

func route(s: float) -> Vector3:
	var switchbacks = smoothstep(200.0, 240.0, s) * (1.0 - smoothstep(368.0, 404.0, s))
	var meander = smoothstep(404.0, 440.0, s) * (1.0 - smoothstep(676.0, 706.0, s))
	var x = sin(s / 96.0) * 23.0 + sin(s / 41.0) * 8.0
	x += sin((s - 200.0) / 29.0) * 26.0 * switchbacks
	x += sin((s - 404.0) / 54.0) * 11.0 * meander
	var y = PLATEAU - DEPTH * depth_fraction(s) + sin(s / 57.0) * 1.8
	y += sin(s / 15.0) * 0.55 + sin(s / 6.5) * 0.16
	return Vector3(x, y, -s)

# Bed of the Charyn under the road. It falls away from the rim long before the
# road does, so the descent runs along a ledge with the gorge open beside it.
func bed_level(s: float) -> float:
	var cut = clampf(smoothstep(196.0, 276.0, s) - smoothstep(700.0, 806.0, s), 0.0, 1.0)
	var bed = PLATEAU - DEPTH * cut - 1.1 + sin(s / 57.0) * 1.8
	# The bed never climbs above the road that runs along it.
	return minf(stage.at(s).y - 0.9, bed)

# How much of the gorge is open at s: 0 on the steppe, 1 between the walls.
func gorge(s: float) -> float:
	return smoothstep(176.0, 220.0, s) * (1.0 - smoothstep(742.0, 802.0, s))

# Where the road itself is a ledge cut into the wall.
func ledge(s: float) -> float:
	return smoothstep(188.0, 240.0, s) * (1.0 - smoothstep(376.0, 416.0, s))

# Half-width of the gorge floor: a narrow corridor with amphitheatres and
# side gullies opening off it.
func floor_half(s: float) -> float:
	var half = 23.0 + sin(s * 0.021) * 5.0
	for bay in BAYS:
		half += float(bay[1]) * exp(-pow((s - float(bay[0])) / float(bay[2]), 2.0))
	return half

# Horizontal run the wall takes to reach the rim: the gorge is not a smooth
# funnel, so the figure changes with the station and with the height of the
# sample, which leans the faces of the buttresses.
func wall_run(s: float, lateral: float) -> float:
	return 18.0 + sin(s * 0.082 + lateral * 0.01) * 5.0 + sin(s * 0.31) * 3.5 + sin(s * 0.73) * 1.4

# Buttresses that stand out of the wall and the recesses between them, added
# to wherever the foot of that wall would otherwise be.
func wall_foot(s: float, base: float) -> float:
	return maxf(3.4, base + sin(s * 0.52) * 2.0 + sin(s * 0.19) * 3.2)

# Fraction of the wall's rise reached `t` of the way across its run: three
# cliff bands, each ending in a narrow bench of fallen rock, with the bands
# thickening and thinning along the gorge.
func wall_profile(t: float, s: float) -> float:
	var shift = sin(s * 0.057) * 0.05
	var step = clampf(t, 0.0, 1.0)
	var first = smoothstep(0.0, 0.27 + shift, step) * (0.37 + shift)
	var second = smoothstep(0.36 + shift, 0.57, step) * 0.29
	var third = smoothstep(0.65, 0.94 + shift, step) * (0.34 - shift)
	return clampf(first + second + third, 0.0, 1.0)

# Long, low swell of the feather-grass plateau.
func steppe(pos: Vector3) -> float:
	return sin(pos.x * 0.016 + pos.z * 0.009) * 1.6 + sin(pos.z * 0.021 - pos.x * 0.013) * 1.1

# Towers of the Valley of Castles left standing on the rim, cut from the wall.
func rim_towers(s: float, lateral: float) -> float:
	var phase = s * 0.17 + (2.3 if lateral > 0.0 else 0.0)
	return pow(maxf(0.0, sin(phase)), 6.0) * 11.0 + pow(maxf(0.0, sin(s * 0.41)), 8.0) * 4.0

# Height the wall reaches: the rim of the plateau, notched where the head of
# a ravine bites into it and crowned where a tower survived. `over` is how
# far past the top of the wall the sample lies.
func crest(s: float, lateral: float, over: float, rim: float) -> float:
	var ravine = pow(maxf(0.0, sin(s * 0.043 + (1.7 if lateral > 0.0 else 0.0))), 12.0) * 15.0
	return rim - ravine * (1.0 - smoothstep(0.0, 26.0, over)) + rim_towers(s, lateral) * (1.0 - smoothstep(0.0, 18.0, over))

func configure() -> void:
	for camp in CAMPS:
		var s = float(camp[0])
		var p = stage.at(s) + stage.side(s) * float(camp[1]) * float(camp[2])
		p.y = base_ground(p)
		stage.clearings.append(p)

# ---------------------------------------------------------------- ground

func relief(s: float, lateral: float) -> float:
	var wash = smoothstep(560.0, 596.0, s) * (1.0 - smoothstep(648.0, 684.0, s))
	var bank = sin(s / 34.0) * 0.055 * lateral
	var crown = -0.035 * lateral * lateral
	var rut = -exp(-pow((absf(lateral) - 0.85) / 0.30, 2.0)) * 0.13
	var waves = sin(s * 0.36 + lateral * 0.4) * (0.07 + wash * 0.18)
	var crest_bump = pow(maxf(0.0, cos((s - 35.0) * TAU / 83.0)), 6.0) * 0.5
	return bank + crown + rut + waves + crest_bump

func base_ground(pos: Vector3) -> float:
	var s: float = stage.road_s(pos)
	var p: Vector3 = stage.at(s)
	var lateral = (pos - p).dot(stage.side(s))
	var distance: float = stage.road_distance(pos)
	var near = p.y + relief(s, lateral) * (1.0 - smoothstep(3.7, 9.0, distance))
	var open = near + steppe(pos) * smoothstep(7.0, 30.0, distance)
	var inside = gorge(s)
	if inside < 0.001:
		return open
	var shelf = ledge(s)
	var rim = PLATEAU + steppe(pos)
	var run = wall_run(s, lateral)
	# Wall side: the cliff rises in bands straight off the road bench.
	var foot = wall_foot(s, lerpf(9.0, 4.6, shelf))
	var wall = lerpf(near, crest(s, lateral, distance - foot - run, rim), wall_profile((distance - foot) / run, s))
	# Open side: the ground falls to the bed, runs flat and climbs the far wall.
	var brink = lerpf(9.0, 7.6, shelf)
	var half = wall_foot(s, floor_half(s))
	var bed = lerpf(near, bed_level(s), smoothstep(brink, brink + 16.0, distance))
	var below = lerpf(bed, crest(s, lateral, distance - half - run, rim), wall_profile((distance - half) / run, s))
	var cliff = shelf * smoothstep(-3.0, 3.0, lateral)
	return lerpf(open, lerpf(below, wall, cliff), inside)

# ---------------------------------------------------------------- stage hooks

func cache_terrain() -> bool:
	return true

# Finer triangles where the detail is: the road and the faces of the walls.
func terrain_tile_step(p: Vector3) -> float:
	var distance: float = stage.road_distance(p)
	if distance < 12.0:
		return 2.0
	var s: float = stage.road_s(p)
	if gorge(s) < 0.15:
		return 4.0
	var run = wall_run(s, 0.0)
	var inner = wall_foot(s, lerpf(9.0, 4.6, ledge(s)))
	if distance > inner - 6.0 and distance < inner + run + 8.0:
		return 2.0
	var far_foot = wall_foot(s, floor_half(s))
	return 2.0 if distance > far_foot - 8.0 and distance < far_foot + run + 10.0 else 4.0

# Pale river gravel on the floor of the gorge, bare strata up the walls and a
# band of dry steppe turf around the rim, with the towers bare above it.
func terrain_color(v: Vector3) -> Color:
	var above = v.y - PLATEAU
	var turf = smoothstep(-6.0, -1.0, above) * (1.0 - smoothstep(1.5, 5.0, above))
	var grass = Color("8d8a4e").lerp(Color("a79c62"), (sin(v.x * 0.03) * sin(v.z * 0.026) + 1.0) * 0.5)
	var wash = 1.0 - smoothstep(1.0, 11.0, v.y - bed_level(stage.road_s(v)))
	var ground = rock_color(v).lerp(Color("c6ab87"), wash * 0.8)
	return ground.lerp(grass, turf).lightened(sin(v.x * 0.09 + v.z * 0.06) * 0.03)

# Horizontal strata of the gorge: ochre, red clay and pale marl in bands that
# waver slightly, so the wall and the towers cut from it share one palette.
func rock_color(v: Vector3) -> Color:
	var waver = sin(v.x * 0.021 + v.z * 0.017) * 3.5 + sin(v.x * 0.058 - v.z * 0.041) * 1.6
	var layer = fposmod((v.y + waver) * 0.048, 1.0)
	var rock = Color("96563c").lerp(Color("b87249"), smoothstep(0.0, 0.3, layer))
	rock = rock.lerp(Color("cb9a72"), smoothstep(0.4, 0.6, layer))
	return rock.lerp(Color("a7643f"), smoothstep(0.7, 1.0, layer))

func road_width(s: float) -> float:
	var narrow = smoothstep(226.0, 262.0, s) * (1.0 - smoothstep(392.0, 424.0, s))
	var wash = smoothstep(566.0, 592.0, s) * (1.0 - smoothstep(652.0, 680.0, s))
	return stage.WIDTH - narrow * 1.6 + wash * 1.6

func road_color(p: Vector3, s: float) -> Color:
	var wash = smoothstep(566.0, 592.0, s) * (1.0 - smoothstep(652.0, 680.0, s))
	var lateral = (p - stage.at(s)).dot(stage.side(s))
	var base = Color("a9805b").lerp(Color("b79470"), wash * 0.5)
	# Compacted wheel tracks, paler loose gravel swept to the crown and the edges.
	var track = exp(-pow((absf(lateral) - 1.05) / 0.36, 2.0))
	var loose = exp(-pow(lateral / 0.6, 2.0)) * 0.05 + smoothstep(2.2, 3.3, absf(lateral)) * 0.07
	return base.darkened(track * 0.12).lightened(loose + sin(p.z * 0.25 + p.x * 0.10) * 0.025)

func road_strips() -> int:
	return 8

# Loose sand off the road and in the dry riverbed.
func grip(pos: Vector3) -> float:
	var s = stage.road_s(pos)
	return 0.48 if stage.road_distance(pos) > road_width(s) * 0.5 or (s > 566.0 and s < 672.0) else 0.74

func rally_speed(s: float) -> float:
	if s > 206.0 and s < 416.0:
		return 15.0
	return 20.0 if s < 700.0 else 27.0

func clearing_signs() -> bool:
	return false

func walk_blocked(next: Vector3, feet_height: float) -> bool:
	# Grounded walkers cannot teleport up cliffs; airborne feet must clear a lip.
	return base_ground(next) > feet_height + 0.18

func camp_allowed(spot: Vector3, _kind: String) -> bool:
	return camp_supported(spot)

# Camp furniture needs level ground: not a bench of the wall, not a talus slope.
func camp_supported(pos: Vector3) -> bool:
	var height = base_ground(pos)
	for offset in [Vector3(1.4, 0, 0), Vector3(-1.4, 0, 0), Vector3(0, 0, 1.4), Vector3(0, 0, -1.4), Vector3(1.4, 0, 1.4), Vector3(-1.4, 0, 1.4), Vector3(1.4, 0, -1.4), Vector3(-1.4, 0, -1.4)]:
		if absf(base_ground(pos + offset) - height) > 0.22:
			return false
	return true

func build_details(_cooperative: bool) -> void:
	scenery.build(stage, self)
	canyon_life.build(stage, self)

func build_horizon() -> void:
	scenery.horizon()

func update_life(delta: float, focus: Vector3) -> void:
	canyon_life.update(delta, focus)
