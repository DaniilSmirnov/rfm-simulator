extends RefCounted
# Living details of «Асбестовский карьер» (quarry.gd): the white dust. Every
# car on the move — rally crews, the course cars, the players' cars — drags a
# pale cloud that hangs behind it for seconds, as on the real stages at
# Asbest. In the pit the shovel digs and swings to the waiting BelAZ, its
# dipper dumping in a puff of dust, and an empty BelAZ shuttles along a berm
# of the west wall. Local scenery only: every client animates its own copy,
# gameplay state stays in stage.gd.
const Props = preload("res://scripts/core/props.gd")
const MeshMerge = preload("res://scripts/core/mesh_merge.gd")
const Form = preload("res://scripts/stages/quarry/quarry_form.gd")
const Machines = preload("res://scripts/stages/quarry/quarry_machines.gd")

# Dust trails: this many clouds at once, for the nearest cars faster than
# DUST_SPEED (m/s) within DUST_RANGE metres.
const DUST_TRAILS = 6
const DUST_SPEED = 4.0
const DUST_RANGE = 260.0
const DUST_COLOR = Color(0.92, 0.92, 0.88, 0.38)
# The shuttle truck on the berm of the second bench up, west wall.
const SHUTTLE_BENCH = 1
const SHUTTLE_NORTH = -390.0
const SHUTTLE_SOUTH = -600.0
const SHUTTLE_SPEED = 5.5
# One working cycle of the shovel (s): dig, swing, dump, swing back.
const SHOVEL_CYCLE = 26.0
const SHOVEL_SWING = PI * 0.5

var stage
var biome
var root: Node3D
var clock = 0.0
var trails: Array[CPUParticles3D] = []
# Last positions of the cars, to tell their speed: instance id -> Vector3.
var last_seen: Dictionary = {}
var shuttle: Node3D
var shuttle_dust: CPUParticles3D
var shuttle_at := 0.0
var shuttle_way := -1.0
var shuttle_turn := 0.0
var shovel_house: Node3D
var shovel_stick: Node3D
var shovel_puff: CPUParticles3D
var dumped := false

func build(owner_stage, owner_biome) -> void:
	stage = owner_stage
	biome = owner_biome
	root = Node3D.new()
	root.name = "QuarryLife"
	stage.add_child(root)
	for i in range(DUST_TRAILS):
		trails.append(_dust_cloud("DustTrail%d" % i, 48, 4.2))
	shuttle_dust = _dust_cloud("ShuttleDust", 30, 4.0)
	shovel_puff = _dust_cloud("ShovelPuff", 24, 2.6)
	shovel_puff.one_shot = true
	shovel_puff.explosiveness = 0.8
	shovel_puff.emission_sphere_radius = 1.6
	_build_shuttle()
	var shovel: Node3D = biome.scenery.shovel
	if shovel != null:
		shovel_house = shovel.get_node_or_null("ShovelHouse")
		if shovel_house != null:
			shovel_stick = shovel_house.get_node_or_null("ShovelStick")

func _dust_cloud(node_name: String, amount: int, lifetime: float) -> CPUParticles3D:
	var dust = CPUParticles3D.new()
	dust.name = node_name
	# Low-poly puffs, like the rest of the world; overlapping, they read
	# as a cloud.
	var puff = SphereMesh.new()
	puff.radius = 1.0
	puff.height = 1.6
	puff.radial_segments = 8
	puff.rings = 4
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	puff.material = mat
	dust.mesh = puff
	dust.amount = amount
	dust.lifetime = lifetime
	dust.local_coords = false
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	dust.emission_sphere_radius = 0.9
	dust.direction = Vector3(0, 1, 0)
	dust.spread = 70.0
	dust.gravity = Vector3(0.35, 0.12, 0.2)
	dust.initial_velocity_min = 0.6
	dust.initial_velocity_max = 1.8
	dust.damping_min = 0.6
	dust.damping_max = 1.2
	dust.scale_amount_min = 1.0
	dust.scale_amount_max = 1.8
	var grow = Curve.new()
	grow.max_value = 4.0
	grow.add_point(Vector2(0.0, 0.6))
	grow.add_point(Vector2(1.0, 3.2))
	dust.scale_amount_curve = grow
	var fade = Gradient.new()
	fade.set_color(0, DUST_COLOR)
	fade.set_color(1, Color(DUST_COLOR, 0.0))
	dust.color_ramp = fade
	dust.emitting = false
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(dust)
	return dust

func update(delta: float, focus: Vector3) -> void:
	if root == null:
		return
	clock += delta
	_update_trails(delta, focus)
	_update_shuttle(delta)
	_update_shovel()

# ---------------------------------------------------------------- dust

# Every car in the world: the players' and those of the course. The stage
# sits under the game node, which keeps them; a bare stage (tests, tools)
# has none.
func _cars() -> Array:
	var game = stage.get_parent()
	var cars: Array = []
	if game == null or not "racers" in game:
		return cars
	cars.append(game.car)
	for peer in game.room.peers.values():
		if peer.has("car"):
			cars.append(peer.car)
	for racer in game.racers:
		cars.append(racer.node)
	return cars

func _update_trails(delta: float, focus: Vector3) -> void:
	var moving: Array = []
	var seen: Dictionary = {}
	for car in _cars():
		if not is_instance_valid(car) or not car.is_visible_in_tree():
			continue
		var id = car.get_instance_id()
		var p: Vector3 = car.global_position
		seen[id] = p
		if not last_seen.has(id) or delta <= 0.0:
			continue
		var travel: Vector3 = p - last_seen[id]
		var speed = Vector2(travel.x, travel.z).length() / delta
		var distance = p.distance_to(focus)
		if speed > DUST_SPEED and distance < DUST_RANGE and absf(p.y - stage.ground(p)) < 1.2:
			moving.append({"pos": p, "back": -travel.normalized(), "distance": distance, "speed": speed})
	last_seen = seen
	moving.sort_custom(func(a, b): return a.distance < b.distance)
	for i in range(trails.size()):
		var trail = trails[i]
		if i >= moving.size():
			trail.emitting = false
			continue
		var car: Dictionary = moving[i]
		trail.position = car.pos + car.back * 2.2 + Vector3.UP * 0.5
		# Faster cars raise more: a lazy plume when rolling, a wall of it flat out.
		trail.speed_scale = clampf(car.speed / 18.0, 0.6, 1.4)
		trail.emitting = true

# ---------------------------------------------------------------- shuttle

func _shuttle_point(z: float) -> Vector3:
	var reach = Form.FLOOR + SHUTTLE_BENCH * Form.BENCH_RUN + (Form.FACE_RUN + Form.BENCH_RUN) * 0.5
	var p = Vector3(Form.AXIS_X - reach, 0.0, z)
	p.y = stage.terrain_surface_height(p)
	return p

func _build_shuttle() -> void:
	shuttle = Machines.belaz()
	shuttle.name = "QuarryBelazShuttle"
	MeshMerge.bake(shuttle, "belaz")
	root.add_child(shuttle)
	shuttle_at = lerpf(SHUTTLE_NORTH, SHUTTLE_SOUTH, 0.3)
	shuttle.position = _shuttle_point(shuttle_at)

func _update_shuttle(delta: float) -> void:
	if shuttle == null:
		return
	if shuttle_turn > 0.0:
		# Three-point turn at the end of the berm: stop, swing round.
		shuttle_turn -= delta
		shuttle.rotation.y = (0.0 if shuttle_way < 0.0 else PI) + PI * clampf(shuttle_turn / 4.0, 0.0, 1.0)
		shuttle_dust.emitting = false
		return
	shuttle_at += shuttle_way * SHUTTLE_SPEED * delta
	if shuttle_at < SHUTTLE_SOUTH or shuttle_at > SHUTTLE_NORTH:
		shuttle_at = clampf(shuttle_at, SHUTTLE_SOUTH, SHUTTLE_NORTH)
		shuttle_way = -shuttle_way
		shuttle_turn = 4.0
	shuttle.position = _shuttle_point(shuttle_at)
	shuttle.rotation.y = 0.0 if shuttle_way < 0.0 else PI
	shuttle_dust.position = shuttle.position + Vector3(0, 0.8, 7.0 * -shuttle_way)
	shuttle_dust.emitting = true

# ---------------------------------------------------------------- shovel

# 0..1 phases of the cycle: dig 0–0.35, swing to the truck 0.35–0.6, dump
# 0.6–0.7, swing back 0.7–0.95, settle.
func _update_shovel() -> void:
	if shovel_house == null:
		return
	var t = fposmod(clock, SHOVEL_CYCLE) / SHOVEL_CYCLE
	var swing = smoothstep(0.35, 0.6, t) * (1.0 - smoothstep(0.7, 0.95, t))
	shovel_house.rotation.y = swing * SHOVEL_SWING
	if shovel_stick != null:
		var crowd = sin(clamp(t / 0.35, 0.0, 1.0) * PI) * 0.35
		shovel_stick.rotation.x = crowd - smoothstep(0.6, 0.66, t) * (1.0 - smoothstep(0.7, 0.8, t)) * 0.3
	var dumping = t > 0.6 and t < 0.7
	if dumping and not dumped:
		var dipper = shovel_stick.global_transform * Vector3(0, -3.8, -5.6) if shovel_stick != null else shovel_house.global_position
		shovel_puff.position = dipper
		shovel_puff.restart()
		shovel_puff.emitting = true
	dumped = dumping
