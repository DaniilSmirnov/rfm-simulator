extends "res://scripts/stages/stage_biome.gd"
# «Чарынский каньон»: a stage along and then inside the Charyn gorge, in the
# Kazakh steppe above the Ili. The land is modelled in world coordinates by
# canyon_form.gd and the road is routed through it by canyon_route.gd; this
# file joins the two and answers the stage's questions about them.
#
# The road runs the rim with the gorge open below on the left, turns back on
# itself at the head of the gorge, drops over the lip and follows a bench cut
# into the near wall all the way down to the gravel floor, then runs the floor
# downstream into the relict ash grove above the Ili, where the service park
# stands.
const Form = preload("res://scripts/stages/canyon/canyon_form.gd")
const Route = preload("res://scripts/stages/canyon/canyon_route.gd")
const Scenery = preload("res://scripts/stages/canyon/canyon_scenery.gd")
const CanyonLife = preload("res://scripts/stages/canyon/canyon_life.gd")

# Stations of the three parts of the stage.
const TURN_BEGIN = 176.0
const TURN_END = 254.0
const FLOOR_BEGIN = 560.0
# How far the land is graded to the road: the bench itself, then the cut and
# fill that carry it into the hillside.
const BENCH = 5.6
const BLEND = 17.0
# Station, side and distance of the spectator areas: two viewpoints on the
# steppe, two on the rim and a bench above the descent, and two on the gravel
# floor by the grove. Each is levelled into the land by blend_clearings();
# the shelf road itself has no room for one.
const CAMPS = [[48.0, -1.0, 18.0], [150.0, -1.0, 20.0], [560.0, 1.0, 26.0], [450.0, 1.0, 24.0], [700.0, 1.0, 28.0], [790.0, -1.0, 26.0]]

var plan: PackedVector2Array = PackedVector2Array()
var surface: PackedFloat32Array = PackedFloat32Array()
var scenery = Scenery.new()
var canyon_life = CanyonLife.new()

# ---------------------------------------------------------------- route

func winding_route() -> bool:
	return true

func route(s: float) -> Vector3:
	if plan.is_empty():
		var built = Route.build(stage.LENGTH)
		plan = built.plan
		surface = built.height
	var t = clampf(s, 0.0, stage.LENGTH + 2.0) / Route.TABLE_STEP
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
	var wash = smoothstep(700.0, 740.0, s) * (1.0 - smoothstep(800.0, 836.0, s))
	var bank = sin(s / 34.0) * 0.055 * lateral
	var crown = -0.035 * lateral * lateral
	var rut = -exp(-pow((absf(lateral) - 0.85) / 0.30, 2.0)) * 0.13
	var waves = sin(s * 0.36 + lateral * 0.4) * (0.07 + wash * 0.18)
	var crest = pow(maxf(0.0, cos((s - 35.0) * TAU / 83.0)), 6.0) * 0.5
	return bank + crown + rut + waves + crest

# The land, with the road graded into it: a bench on the wall, a cut above it
# and a fill below, easing back into the gorge within BLEND metres.
func base_ground(pos: Vector3) -> float:
	var land = stage.blend_clearings(pos, Form.surface(pos), 5.5, 11.5)
	var distance: float = stage.road_distance(pos)
	if distance > BLEND:
		return land
	var s: float = stage.road_s(pos)
	var p: Vector3 = stage.at(s)
	var lateral = (pos - p).dot(stage.side(s))
	var bench = p.y + relief(s, lateral) * (1.0 - smoothstep(3.7, 9.0, distance))
	return lerpf(bench, land, smoothstep(BENCH, BLEND, distance))

# ---------------------------------------------------------------- terrain

func cache_terrain() -> bool:
	return true

# Fine triangles where the detail is: the road, and the faces of both walls.
func terrain_tile_step(p: Vector3) -> float:
	if stage.road_distance(p) < 13.0:
		return 2.0
	var across = Form.offset(p)
	var side = signf(across) if across != 0.0 else 1.0
	var distance = absf(across)
	var foot = Form.wall_foot(p.z, side)
	if distance < foot - 6.0 or distance > Form.rim_edge(p.z, side) + 6.0:
		return 4.0
	# The cliff bands are a few metres wide: they need the finest triangles.
	return 1.0 if Form.depth(p.z) > 26.0 else 2.0

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
	var turf = smoothstep(-7.0, -1.5, v.y - rim) * (1.0 - smoothstep(1.5, 5.0, v.y - rim))
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
	var base = Color("a9805b").lerp(Color("b79470"), smoothstep(FLOOR_BEGIN, 800.0, s) * 0.5)
	# Compacted wheel tracks, paler loose gravel at the crown and the edges.
	var track = exp(-pow((absf(lateral) - 1.05) / 0.36, 2.0))
	var loose = exp(-pow(lateral / 0.6, 2.0)) * 0.05 + smoothstep(2.2, 3.3, absf(lateral)) * 0.07
	return base.darkened(track * 0.12).lightened(loose + sin(p.z * 0.25 + p.x * 0.10) * 0.025)

func road_strips() -> int:
	return 8

# Loose sand off the road, and river gravel where the road crosses the bed.
func grip(pos: Vector3) -> float:
	var s = stage.road_s(pos)
	return 0.48 if stage.road_distance(pos) > road_width(s) * 0.5 or s > 740.0 else 0.74

func rally_speed(s: float) -> float:
	if s > TURN_BEGIN and s < TURN_END + 20.0:
		return 11.0
	if s < TURN_BEGIN:
		return 25.0
	return 17.0 if s < FLOOR_BEGIN else 23.0

func clearing_signs() -> bool:
	return false

# ---------------------------------------------------------------- people

func walk_blocked(next: Vector3, feet_height: float) -> bool:
	# Grounded walkers cannot teleport up cliffs; airborne feet must clear a lip.
	return base_ground(next) > feet_height + 0.18

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
	return [140.0, 232.0, 470.0, 716.0]

# ---------------------------------------------------------------- scenery

func build_details(cooperative: bool) -> void:
	await scenery.build(stage, self, cooperative)
	canyon_life.build(stage, self)

func build_horizon() -> void:
	scenery.horizon()

func update_life(delta: float, focus: Vector3) -> void:
	canyon_life.update(delta, focus)
