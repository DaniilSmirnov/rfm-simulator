extends "res://scripts/stages/stage_biome.gd"
# «Асбестовский карьер»: a stage over the spoil dumps and down into an open
# pit, after the rally stages run at Asbest in the Middle Urals on the dumps
# of «Ураласбест», beside the largest working chrysotile pit in the world.
# The land is modelled in world coordinates by quarry_form.gd and the road is
# routed over it by quarry_route.gd; this file joins the two and answers the
# stage's questions about them.
#
# Everything here is white with dust: the crushed serpentinite of the dumps,
# the graded berms and the haul road. Cars, trucks and the wind raise it
# (quarry_life.gd), and it hangs over the pit as a pale haze.
const Form = preload("res://scripts/stages/quarry/quarry_form.gd")
const Route = preload("res://scripts/stages/quarry/quarry_route.gd")
const Scenery = preload("res://scripts/stages/quarry/quarry_scenery.gd")
const QuarryLife = preload("res://scripts/stages/quarry/quarry_life.gd")

# How far the land is graded to the road: the road bed itself, then the cut
# and fill that carry it into the wall.
const BENCH = 5.6
const BLEND = 17.0
# Steepest land a car can drive up (rise per metre), judged this far ahead.
const CLIMB = 0.85
const CLIMB_REACH = 1.6
# Radius of the level pad of a spectator area and of its blend into the land.
const CLEARING_FLAT = 6.5
const CLEARING_BLEND = 12.0
# Width of the haul road and the floor road: built for 130-tonne trucks.
const HAUL_WIDTH = 9.0

var plan: PackedVector2Array = PackedVector2Array()
var surface: PackedFloat32Array = PackedFloat32Array()
var length := 0.0
# Stations where the haul road leaves the rim and where it reaches the floor.
var ramp_begin := 0.0
var ramp_end := 0.0
var scenery = Scenery.new()
var quarry_life = QuarryLife.new()
# Machines and buildings; scenery keeps clear of them.
var reserved_spots: Array[Dictionary] = []
# Exact mesh samples for wheel and foot queries after the build (see canyon.gd).
const CONTACT_CACHE_LIMIT = 2048
var contact_steps: Dictionary = {}
var contact_heights: Dictionary = {}

# ---------------------------------------------------------------- route

func _plan() -> void:
	if not plan.is_empty():
		return
	var built = Route.build()
	plan = built.plan
	surface = built.height
	length = built.length
	ramp_begin = built.ramp.x
	ramp_end = built.ramp.y

func route_length() -> float:
	_plan()
	return length

func winding_route() -> bool:
	return true

func route(s: float) -> Vector3:
	_plan()
	var t = clampf(s, 0.0, float(plan.size() - 2)) / Route.TABLE_STEP
	var i = mini(int(t), plan.size() - 2)
	var f = t - i
	var xz: Vector2 = plan[i].lerp(plan[i + 1], f)
	return Vector3(xz.x, lerpf(surface[i], surface[i + 1], f), xz.y)

# Where along the haul road a station is, 0 at the rim and 1 on the floor;
# -1 on the dumps before it, 2 on the floor road after it.
func ramp_share(s: float) -> float:
	if s < ramp_begin:
		return -1.0
	if s > ramp_end:
		return 2.0
	return (s - ramp_begin) / (ramp_end - ramp_begin)

func place(spot: Array) -> Vector3:
	var s = float(spot[0])
	var p = stage.at(s) + stage.side(s) * float(spot[1]) * float(spot[2])
	p.y = base_ground(p)
	return p

func configure() -> void:
	for camp in camps():
		stage.clearings.append(place(camp))
	scenery.configure(stage, self)

# Station, side and distance of the spectator areas: by the start and on the
# crests over the dumps, on the rim above the haul road dropping in, on the floor
# under the walls where the crews come down, and by the finish.
func camps() -> Array:
	return [
		[60.0, -1.0, 19.0], [210.0, 1.0, 19.0], [ramp_begin + 12.0, 1.0, 19.0],
		[ramp_end + 40.0, 1.0, 18.0], [ramp_end + 150.0, -1.0, 17.0], [length - 70.0, 1.0, 17.0],
	]

func reserved(pos: Vector3, padding: float = 0.0) -> bool:
	for spot in reserved_spots:
		if Vector2(pos.x - spot.pos.x, pos.z - spot.pos.z).length() < float(spot.radius) + padding:
			return true
	return false

# ---------------------------------------------------------------- ground

# Crossfall, crown and wheel ruts of the road surface itself.
func relief(s: float, lateral: float) -> float:
	var crown = -0.03 * lateral * lateral
	var rut = -exp(-pow((absf(lateral) - 0.9) / 0.32, 2.0)) * 0.1
	var waves = sin(s * 0.41 + lateral * 0.3) * 0.05
	return crown + rut + waves

# The land, with the road graded into it: a bed cut into the wall and the
# dumps, easing back into them within BLEND metres. The spectator areas are
# levelled last, so a camp near the road is flat too.
func base_ground(pos: Vector3) -> float:
	var land = Form.surface(pos)
	var nearest: Dictionary = stage.route_nearest(pos, BLEND)
	var distance: float = nearest.distance
	if distance < BLEND:
		var s: float = nearest.s
		var p: Vector3 = stage.at(s)
		var lateral = (pos - p).dot(stage.side(s))
		var bed = p.y + relief(s, lateral) * (1.0 - smoothstep(4.0, 9.0, distance))
		land = lerpf(bed, land, smoothstep(BENCH, BLEND, distance))
	return stage.blend_clearings(pos, land, CLEARING_FLAT, CLEARING_BLEND)

# ---------------------------------------------------------------- terrain

func cache_terrain() -> bool:
	contact_steps.clear()
	contact_heights.clear()
	return true

func terrain_tiled() -> bool:
	return true

func terrain_vertex_height(x: float, z: float) -> float:
	if stage.terrain_cache_enabled:
		return stage.snapped_vertex_height(x, z)
	var key = Vector2(x, z)
	if not contact_heights.has(key):
		if contact_heights.size() >= CONTACT_CACHE_LIMIT:
			contact_heights.clear()
		contact_heights[key] = stage.snapped_vertex_height(x, z)
	return contact_heights[key]

func terrain_tile_step(p: Vector3) -> float:
	if stage.terrain_cache_enabled:
		return _terrain_tile_step(p)
	var key = Vector2(p.x, p.z)
	if not contact_steps.has(key):
		if contact_steps.size() >= CONTACT_CACHE_LIMIT:
			contact_steps.clear()
		contact_steps[key] = _terrain_tile_step(p)
	return contact_steps[key]

# Fine triangles by the road and on the faces of the benches.
func _terrain_tile_step(p: Vector3) -> float:
	var road = stage.road_distance(p, 30.0)
	if road < 13.0:
		return 2.0
	var k = Form.axis_distance(p) - Form.FLOOR
	if k < -4.0 or k > Form.RUN + 4.0:
		return 4.0
	var within = fposmod(k, Form.BENCH_RUN)
	return 1.0 if road < 30.0 and (within < Form.FACE_RUN + 1.0 or within > Form.BENCH_RUN - 1.0) else 2.0

# Dark green-grey serpentinite in the faces, streaked with pale fibre veins;
# everything that lies flat is white with dust.
func rock_color(v: Vector3) -> Color:
	var vein = pow(maxf(0.0, sin(v.x * 0.37 + v.y * 1.3 - v.z * 0.21)), 10.0)
	var band = sin(v.y * 0.9 + sin(v.x * 0.05 + v.z * 0.04) * 2.0) * 0.5 + 0.5
	var rock = Color("4f5a50").lerp(Color("6c766a"), band)
	return rock.lerp(Color("c9cbbf"), vein * 0.7)

func terrain_color(v: Vector3) -> Color:
	var dust = Color("b4b6ac").lerp(Color("a5a89e"), (sin(v.x * 0.13) * sin(v.z * 0.11) + 1.0) * 0.5)
	var k = Form.axis_distance(v) - Form.FLOOR
	var color: Color
	if k >= Form.RUN:
		# Old dumps are greening over with birch scrub and grass; the land
		# away from them is Ural meadow.
		var meadow = Color("7a8259").lerp(Color("8a8d62"), (sin(v.x * 0.031) * sin(v.z * 0.027) + 1.0) * 0.5)
		var spoil = smoothstep(0.5, 3.0, Form.dump_height(v))
		var worn = 1.0 - smoothstep(10.0, 26.0, stage.road_distance(v, 26.0))
		var rim = 1.0 - smoothstep(Form.RIM, Form.RIM + 22.0, Form.axis_distance(v))
		color = meadow.lerp(dust.darkened(0.06), maxf(maxf(spoil, worn), rim))
	elif k <= 0.0:
		var sump = Vector2(v.x - Form.SUMP[0], v.z - Form.SUMP[1]).length()
		color = dust.lerp(Color("858d84"), 1.0 - smoothstep(Form.SUMP[2] * 0.6, Form.SUMP[2] * 1.4, sump))
	else:
		var within = fposmod(k, Form.BENCH_RUN)
		var face = smoothstep(-1.2, 0.3, within) * (1.0 - smoothstep(Form.FACE_RUN - 0.2, Form.FACE_RUN + 1.2, within))
		face = maxf(face, smoothstep(Form.BENCH_RUN - 1.4, Form.BENCH_RUN - 0.2, within))
		color = dust.lerp(rock_color(v), face)
	# Where the road is cut into a face the rock shows; below it the fill is
	# loose grey spoil.
	var cut = v.y - Form.surface(v)
	if absf(cut) > 1.0 and stage.road_distance(v, BLEND) < BLEND:
		var share = smoothstep(1.0, 4.0, absf(cut)) * smoothstep(BENCH - 1.0, BENCH + 2.0, stage.road_distance(v, BLEND))
		color = color.lerp(rock_color(v) if cut < 0.0 else Color("8f948b"), share * 0.85)
	return color

# ---------------------------------------------------------------- road

func road_width(s: float) -> float:
	return lerpf(stage.WIDTH, HAUL_WIDTH, smoothstep(ramp_begin - 30.0, ramp_begin, s))

# Packed white dust with grey wheel tracks.
func road_color(p: Vector3, s: float) -> Color:
	var lateral = (p - stage.at(s)).dot(stage.side(s))
	var base = Color("b7b9b1")
	var track = exp(-pow((absf(lateral) - 1.0) / 0.38, 2.0)) + exp(-pow((absf(lateral) - 3.0) / 0.5, 2.0)) * 0.6 * float(s > ramp_begin)
	var shade = sin(p.z * 0.23 + p.x * 0.11) * 0.02
	return base.darkened(track * 0.13).lightened(shade)

func road_strips() -> int:
	return 8

func grip(pos: Vector3) -> float:
	var nearest: Dictionary = stage.route_nearest(pos)
	var s: float = nearest.s
	if float(nearest.distance) > road_width(s) * 0.5:
		return 0.5
	# Fine dust over a hard bed: marbles of loose rock where trucks spill.
	return 0.5 if int(s / stage.STEP) % 17 == 9 else 0.72

func rally_speed(s: float) -> float:
	var share = ramp_share(s)
	if share < 0.0:
		return 27.0 if s < ramp_begin - 40.0 else 15.0
	if share > 1.0:
		return 23.0
	# The turn round the south end of the pit is the slowest part of the ramp.
	var turn = _ramp_turn(s)
	return lerpf(18.0, 12.0, turn)

# How much of the turn round the south end of the pit a station is in, 0..1.
func _ramp_turn(s: float) -> float:
	var p = stage.at(s)
	return smoothstep(Form.SOUTH_Z + 10.0, Form.SOUTH_Z - 20.0, p.z)

func shoulder(s: float) -> float:
	return 0.8 if ramp_share(s) >= 0.0 and ramp_share(s) <= 1.0 else 1.4

func surface_sound(_pos: Vector3) -> String:
	return "gravel"

# The haul road has a rock windrow along its open edge, not a verge to stand
# on: spectators keep to their areas.
func roadside_spectators() -> bool:
	return false

func marshal_stations() -> Array:
	return [120.0, ramp_begin - 20.0, ramp_end + 70.0, length - 110.0]

# ---------------------------------------------------------------- people

func walk_blocked(next: Vector3, feet_height: float) -> bool:
	# Grounded walkers cannot climb a face; airborne feet must clear the crest.
	return base_ground(next) > feet_height + 0.18

# Tyres climb the graded road, the berms and the dumps' gentle tops, not the
# faces of the benches.
func drive_blocked(from: Vector3, to: Vector3) -> bool:
	var travel = Vector3(to.x - from.x, 0.0, to.z - from.z)
	if travel.length_squared() < 0.000001:
		return false
	var ahead = from + travel.normalized() * CLIMB_REACH
	return stage.vehicle_ground(ahead) - stage.vehicle_ground(from) > CLIMB * CLIMB_REACH

func spectator_camp(_index: int, clearing: Vector3, _s: float, _outward: Vector3) -> Vector3:
	return clearing

func camp_allowed(spot: Vector3, _kind: String) -> bool:
	var height = base_ground(spot)
	for offset in [Vector3(1.4, 0, 0), Vector3(-1.4, 0, 0), Vector3(0, 0, 1.4), Vector3(0, 0, -1.4), Vector3(1.4, 0, 1.4), Vector3(-1.4, 0, 1.4), Vector3(1.4, 0, -1.4), Vector3(-1.4, 0, -1.4)]:
		if absf(base_ground(spot + offset) - height) > 0.22:
			return false
	return true

# ---------------------------------------------------------------- scenery

# Birch and pine stand on the land around the pit, away from the dumps.
func forest_tree_count() -> int:
	return 1500

func forest_tree_max_height() -> float:
	return 18.0

func tree_blocked(p: Vector3) -> bool:
	return Form.in_pit(p, 40.0) or Form.dump_height(p) > 0.0 or stage.road_distance(p, 26.0) < 26.0 or reserved(p, 4.0) or stage.trail_distance(p) < 3.2

func roadside_rock_blocked(p: Vector3) -> bool:
	return reserved(p, 1.0)

func woodland_blocked(pos: Vector3, padding: float) -> bool:
	return Form.in_pit(pos, 6.0) or reserved(pos, padding)

func build_details(cooperative: bool) -> void:
	await scenery.build(cooperative)
	quarry_life.build(stage, self)

func build_horizon() -> void:
	scenery.horizon()

func update_life(delta: float, focus: Vector3) -> void:
	quarry_life.update(delta, focus)
