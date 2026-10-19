extends "res://scripts/stages/stage_biome.gd"
# «Чарынский каньон»: a stage along and then inside the Charyn gorge, in the
# Kazakh steppe above the Ili. The land is modelled in world coordinates by
# canyon_form.gd and the road is routed through it by canyon_route.gd; this
# file joins the two and answers the stage's questions about them.
#
# About two kilometres long, the longest stage in the game. The road runs
# upstream along the rim with the gorge open below on the left, turns back on
# itself at the head of the gorge, drops over the lip and follows a bench cut
# into the near wall, under the rim road, all the way down to the floor, then
# weaves downstream between the castles of the Valley of Castles into the
# relict ash grove above the Ili, where the service park stands.
const Form = preload("res://scripts/stages/canyon/canyon_form.gd")
const Route = preload("res://scripts/stages/canyon/canyon_route.gd")
const Scenery = preload("res://scripts/stages/canyon/canyon_scenery.gd")
const CanyonLife = preload("res://scripts/stages/canyon/canyon_life.gd")

const LENGTH = 2040.0
# Stations of the parts of the stage: rim, hairpin, bench, floor, grove.
const TURN_BEGIN = 720.0
const TURN_END = 800.0
const FLOOR_BEGIN = 1380.0
const GROVE_BEGIN = 1860.0
# How far the land is graded to the road: the bench itself, then the cut and
# fill that carry it into the hillside.
const BENCH = 5.6
const BLEND = 17.0
# Steepest land a car can drive up (rise per metre), judged this far ahead.
const CLIMB = 0.85
const CLIMB_REACH = 1.6
# Radius of the level pad of a spectator area and of its blend into the land.
const CLEARING_FLAT = 6.5
const CLEARING_BLEND = 12.0
# Station, side and distance of the spectator areas. On the way up: one on
# the steppe by the start, three out on the lip of the gorge looking down on
# the floor road and the bench, one on the steppe above the hairpin. Then one
# on the floor under the bench, where the crews come down the wall towards
# them, two in the Valley of Castles and two in the grove. Each is levelled
# into the land by blend_clearings(); the bench itself has no room for one.
const CAMPS = [[80.0, -1.0, 20.0], [140.0, 1.0, 18.0], [410.0, 1.0, 18.0], [590.0, 1.0, 18.0], [660.0, -1.0, 20.0], [1160.0, -1.0, 19.0], [1610.0, -1.0, 18.0], [1820.0, 1.0, 18.0], [1940.0, 1.0, 20.0], [2000.0, -1.0, 20.0]]

var plan: PackedVector2Array = PackedVector2Array()
var surface: PackedFloat32Array = PackedFloat32Array()
var scenery = Scenery.new()
var canyon_life = CanyonLife.new()

# ---------------------------------------------------------------- route

func route_length() -> float:
	return LENGTH

# The gorge runs on past the finish to the Ili: the land is half again as deep
# as on the other stages.
func world_bounds() -> Rect2:
	return Rect2(-204.0, -1420.0, 408.0, 1500.0)

func winding_route() -> bool:
	return true

func route(s: float) -> Vector3:
	if plan.is_empty():
		var built = Route.build(stage.length)
		plan = built.plan
		surface = built.height
	var t = clampf(s, 0.0, stage.length + 2.0) / Route.TABLE_STEP
	var i = mini(int(t), plan.size() - 2)
	var f = t - i
	var xz: Vector2 = plan[i].lerp(plan[i + 1], f)
	return Vector3(xz.x, lerpf(surface[i], surface[i + 1], f), xz.y)

func configure() -> void:
	for camp in CAMPS:
		var s = float(camp[0])
		var p = stage.at(s) + stage.side(s) * float(camp[1]) * float(camp[2])
		p.y = base_ground(p)
		stage.clearings.append(p)

# ---------------------------------------------------------------- ground

# Crossfall, crown, wheel ruts and the crests of the road surface itself.
func relief(s: float, lateral: float) -> float:
	var wash = smoothstep(GROVE_BEGIN + 40.0, GROVE_BEGIN + 80.0, s) * (1.0 - smoothstep(LENGTH - 40.0, LENGTH - 4.0, s))
	var bank = sin(s / 34.0) * 0.055 * lateral
	var crown = -0.035 * lateral * lateral
	var rut = -exp(-pow((absf(lateral) - 0.85) / 0.30, 2.0)) * 0.13
	var waves = sin(s * 0.36 + lateral * 0.4) * (0.07 + wash * 0.18)
	var crest = pow(maxf(0.0, cos((s - 35.0) * TAU / 83.0)), 6.0) * 0.5
	return bank + crown + rut + waves + crest

# The land, with the road graded into it: a bench on the wall, a cut above it
# and a fill below, easing back into the gorge within BLEND metres. The
# spectator areas are levelled last, so a camp near the road is flat too.
func base_ground(pos: Vector3) -> float:
	var land = Form.surface(pos)
	var near: Dictionary = stage.route_nearest(pos, BLEND)
	var distance: float = near.distance
	if distance < BLEND:
		var s: float = near.s
		var p: Vector3 = stage.at(s)
		var lateral = (pos - p).dot(stage.side(s))
		var bench = p.y + relief(s, lateral) * (1.0 - smoothstep(3.7, 9.0, distance))
		land = lerpf(bench, land, smoothstep(BENCH, BLEND, distance))
	return stage.blend_clearings(pos, land, CLEARING_FLAT, CLEARING_BLEND)

# ---------------------------------------------------------------- terrain

func cache_terrain() -> bool:
	return true

# Fine triangles where the detail is: the road, and the faces of both walls.
func terrain_tile_step(p: Vector3) -> float:
	var road = stage.road_distance(p, 34.0)
	if road < 13.0:
		return 2.0
	var across = Form.offset(p)
	var side = signf(across) if across != 0.0 else 1.0
	var distance = absf(across)
	var foot = Form.wall_foot(p.z, side)
	if distance < foot - 6.0 or distance > Form.rim_edge(p.z, side) + 6.0:
		return 4.0
	# The cliff bands are a few metres wide: they need the finest triangles
	# where the road passes close under or over them.
	return 1.0 if Form.depth(p.z) > 26.0 and road < 34.0 else 2.0

# Horizontal strata: red sandstone, grey gravels and pale marl in bands that
# waver slightly, so a wall and the castles cut from it share one palette.
func rock_color(v: Vector3) -> Color:
	var waver = sin(v.x * 0.023 + v.z * 0.019) * 2.0 + sin(v.x * 0.061 - v.z * 0.043) * 0.9
	var layer = fposmod((v.y + waver) * 0.14, 1.0)
	var rock = Color("7b3a24").lerp(Color("c06c36"), smoothstep(0.02, 0.22, layer))
	rock = rock.lerp(Color("ecd3ab"), smoothstep(0.3, 0.44, layer))
	rock = rock.lerp(Color("8a7261"), smoothstep(0.52, 0.66, layer))
	return rock.lerp(Color("a04f28"), smoothstep(0.78, 0.98, layer))

# Bare strata on the walls, pale gravel on the bed, dry turf on the table and
# grass under the ash grove.
func terrain_color(v: Vector3) -> Color:
	var bed = Form.bed_level(v.z)
	var rim = Form.rim_level(v)
	var wash = 1.0 - smoothstep(1.5, 9.0, v.y - bed)
	var turf = smoothstep(-7.0, -1.5, v.y - rim) * (1.0 - smoothstep(0.6, 1.8, v.y - rim))
	var gravel = Color("c2ab8c").lerp(Color("a79274"), (sin(v.x * 0.14) * sin(v.z * 0.09) + 1.0) * 0.5)
	var meadow = Color("8d8a4e").lerp(Color("79813f"), Form.grove(v.z))
	var steppe = meadow.lerp(Color("a79c62"), (sin(v.x * 0.03) * sin(v.z * 0.026) + 1.0) * 0.5)
	var ground = rock_color(v).lerp(gravel, wash * 0.85)
	return ground.lerp(steppe, maxf(turf, wash * Form.grove(v.z) * 0.7)).lightened(sin(v.x * 0.09 + v.z * 0.06) * 0.03)

# ---------------------------------------------------------------- road

func road_width(s: float) -> float:
	var bench = smoothstep(TURN_END - 20.0, TURN_END + 30.0, s) * (1.0 - smoothstep(FLOOR_BEGIN - 40.0, FLOOR_BEGIN, s))
	var turn = smoothstep(TURN_BEGIN - 10.0, TURN_BEGIN + 14.0, s) * (1.0 - smoothstep(TURN_END - 14.0, TURN_END + 10.0, s))
	return stage.WIDTH - bench * 1.5 + turn * 1.2

func road_color(p: Vector3, s: float) -> Color:
	var lateral = (p - stage.at(s)).dot(stage.side(s))
	var base = Color("a9805b").lerp(Color("b79470"), smoothstep(FLOOR_BEGIN, GROVE_BEGIN, s) * 0.5)
	# Compacted wheel tracks, paler loose gravel at the crown and the edges.
	var track = exp(-pow((absf(lateral) - 1.05) / 0.36, 2.0))
	var loose = exp(-pow(lateral / 0.6, 2.0)) * 0.05 + smoothstep(2.2, 3.3, absf(lateral)) * 0.07
	return base.darkened(track * 0.12).lightened(loose + sin(p.z * 0.25 + p.x * 0.10) * 0.025)

func road_strips() -> int:
	return 8

# Loose sand off the road, and river gravel where the road crosses the bed.
func grip(pos: Vector3) -> float:
	var s = stage.road_s(pos)
	return 0.48 if stage.road_distance(pos) > road_width(s) * 0.5 or s > GROVE_BEGIN + 40.0 else 0.74

func rally_speed(s: float) -> float:
	if s > TURN_BEGIN and s < TURN_END + 20.0:
		return 11.0
	if s < TURN_BEGIN:
		return 25.0
	if s < FLOOR_BEGIN:
		return 17.0
	return 20.0 if s < GROVE_BEGIN else 23.0

func clearing_signs() -> bool:
	return false

# The bench and the slot between the castles have no verge to stand on: the
# spectators keep to their areas on the rim and the floor.
func roadside_spectators() -> bool:
	return false

# ---------------------------------------------------------------- people

func walk_blocked(next: Vector3, feet_height: float) -> bool:
	# Grounded walkers cannot teleport up cliffs; airborne feet must clear a lip.
	return base_ground(next) > feet_height + 0.18

# Tyres climb the graded road and the steppe, not the faces of the walls: a
# car is stopped by land rising steeper than CLIMB just ahead of it.
func drive_blocked(from: Vector3, to: Vector3) -> bool:
	var travel = Vector3(to.x - from.x, 0.0, to.z - from.z)
	if travel.length_squared() < 0.000001:
		return false
	var ahead = from + travel.normalized() * CLIMB_REACH
	return stage.vehicle_ground(ahead) - stage.vehicle_ground(from) > CLIMB * CLIMB_REACH

# The whole camp stands on the level pad of its area, not on the slope round it.
func spectator_camp(_index: int, clearing: Vector3, _s: float, _outward: Vector3) -> Vector3:
	return clearing

func camp_allowed(spot: Vector3, _kind: String) -> bool:
	return camp_supported(spot)

# Camp furniture needs level ground: not a cliff bench, not a talus slope.
func camp_supported(pos: Vector3) -> bool:
	var height = base_ground(pos)
	for offset in [Vector3(1.4, 0, 0), Vector3(-1.4, 0, 0), Vector3(0, 0, 1.4), Vector3(0, 0, -1.4), Vector3(1.4, 0, 1.4), Vector3(-1.4, 0, 1.4), Vector3(1.4, 0, -1.4), Vector3(-1.4, 0, -1.4)]:
		if absf(base_ground(pos + offset) - height) > 0.22:
			return false
	return true

func marshal_stations() -> Array:
	return [140.0, 690.0, 1520.0, 1790.0]

# ---------------------------------------------------------------- scenery

func build_details(cooperative: bool) -> void:
	await scenery.build(stage, self, cooperative)
	canyon_life.build(stage, self)

func build_horizon() -> void:
	scenery.horizon()

func update_life(delta: float, focus: Vector3) -> void:
	canyon_life.update(delta, focus)
