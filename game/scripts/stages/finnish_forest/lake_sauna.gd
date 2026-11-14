extends RefCounted
# The log sauna on the first lake of "Финский лес". People walk in through the
# open door on the lake side (a few steps lead up to the floor), sit on the
# upper bench (полок), throw water on the stove stones and watch the rally
# through the wide window in the wall that faces the road.
#
# The hut stands in its own frame: +z points at the lake, -z at the road and
# x runs along the shore. Everything here is deterministic geometry, the same
# on every client; who is steaming comes from the room state (seated inside),
# so the steam and the chimney smoke show for every member (sauna_steam.gd).
const Props = preload("res://scripts/core/props.gd")
const Furniture = preload("res://scripts/stages/finnish_forest/sauna_furniture.gd")
const HALF = Vector2(2.0, 1.7)
const WALL = 0.22
const FLOOR = 0.6
const LOG = 0.32
const ROWS = 9
const TOP = 0.3 + ROWS * LOG
const DOOR_HALF = 0.5
const DOOR_ROWS = [1, 6]
# The window takes rows 4..7: from about knee height of a seated person to
# above the eyes of one standing, 2 m wide, in front of the bench end.
const WINDOW_ROWS = [4, 7]
const WINDOW_X = [-1.5, 0.5]
const BENCH_TOP = FLOOR + 0.8
const STEP_TOP = FLOOR + 0.4
# Two benches face each other along the side walls (sauna_furniture.gd).
const BENCH_DEPTH = 0.6
const BENCH_Z = [-1.48, 0.5]
const STOVE = Vector3(-1.2, FLOOR, 1.05)
const LOGS = Color("7a5634")
const BOARDS = Color("b48a5a")
const DARK_WOOD = Color("4a3524")
const IRON = Color("2b2826")

var root: Node3D
var interior: Node3D
var steam: CPUParticles3D
var cloud: CPUParticles3D
var smoke: CPUParticles3D
var lamp: OmniLight3D
var glow: MeshInstance3D
var hiss: AudioStreamPlayer3D

func pose() -> Transform3D:
	return root.transform

# World point in the hut frame.
func at(local: Vector3) -> Vector3:
	return root.transform * local

func local(world: Vector3) -> Vector3:
	return root.transform.affine_inverse() * world

# Inside the walls, from the floor up to the ceiling.
func contains(world: Vector3) -> bool:
	if root == null:
		return false
	var p = local(world)
	return absf(p.x) < HALF.x - WALL and absf(p.z) < HALF.y - WALL and p.y > FLOOR - 0.6 and p.y < TOP

# Seats on the upper benches: [side, z]. The first on each bench is nearest
# the window. A seated steamer's feet (game.walker) go there.
const SEATS = [[-1.0, -0.9], [-1.0, -0.1], [1.0, -0.9], [1.0, -0.1]]

func bench_x(side: float) -> float:
	return side * (HALF.x - WALL - BENCH_DEPTH * 0.5)

func seat(index: int = 0) -> Vector3:
	return at(Vector3(bench_x(SEATS[index][0]), BENCH_TOP - Props.CHAIR_SEAT, SEATS[index][1]))

# Looking from the seat at the middle of the window.
func seat_yaw(index: int = 0) -> float:
	var to = window_center() - seat(index)
	return atan2(-to.x, -to.z)

func bench_point(side: float = -1.0) -> Vector3:
	return at(Vector3(bench_x(side), BENCH_TOP + 0.1, -0.2))

func stones() -> Vector3:
	return at(STOVE + Vector3(0, 0.82, 0))

func window_center() -> Vector3:
	return at(Vector3((WINDOW_X[0] + WINDOW_X[1]) * 0.5, _row_bottom(WINDOW_ROWS[0]) + _opening(WINDOW_ROWS) * 0.5, -HALF.y))

static func _row_bottom(row: int) -> float:
	return 0.3 + row * LOG

static func _opening(rows: Array) -> float:
	return (rows[1] - rows[0] + 1) * LOG

# ---------------------------------------------------------------- build

# `hut` is already placed, turned to the lake and levelled (plinth top at FLOOR).
func build(stage: Node3D, hut: Node3D) -> void:
	root = hut
	_walls(stage)
	_roof()
	_inside()
	_porch(stage)
	_floor(stage)
	_interior(stage)

func _walls(stage: Node3D) -> void:
	for row in range(ROWS):
		var y = 0.45 + row * LOG
		var tint = LOGS.lightened((row % 2) * 0.05)
		# Log ends cross at the corners: every other course reaches past them.
		var reach = 0.05 if row % 2 == 0 else 0.0
		var along = HALF.x * 2.0 + reach * 2.0
		var across = HALF.y * 2.0 - WALL * 2.0 + reach * 2.0
		for side in [-1.0, 1.0]:
			Props.box(root, Vector3(side * (HALF.x - WALL * 0.5), y, 0), Vector3(WALL, LOG + 0.01, across), tint)
		_course(Vector3(0, y, HALF.y - WALL * 0.5), along, [-DOOR_HALF, DOOR_HALF] if _within(row, DOOR_ROWS) else [], tint)
		_course(Vector3(0, y, -HALF.y + WALL * 0.5), along, WINDOW_X if _within(row, WINDOW_ROWS) else [], tint)
	# Walls stop cars and walkers; the doorway and the room stay free.
	var height = TOP + 0.4
	var middle = (TOP - 0.4) * 0.5
	for side in [-1.0, 1.0]:
		stage.solids.solid(root, Vector3(side * (HALF.x - WALL * 0.5), middle, 0), Vector3(WALL, height, HALF.y * 2.0), "building")
		var width = HALF.x - DOOR_HALF
		stage.solids.solid(root, Vector3(side * (DOOR_HALF + width * 0.5), middle, HALF.y - WALL * 0.5), Vector3(width, height, WALL), "building")
	# The road wall leaves the window open, so nothing stops a look out of it.
	var back = -HALF.y + WALL * 0.5
	var sill = _row_bottom(WINDOW_ROWS[0])
	var head = sill + _opening(WINDOW_ROWS)
	stage.solids.solid(root, Vector3(0, (sill - 0.8) * 0.5, back), Vector3(HALF.x * 2.0, sill + 0.8, WALL), "building")
	stage.solids.solid(root, Vector3(0, (head + TOP) * 0.5, back), Vector3(HALF.x * 2.0, TOP - head, WALL), "building")
	for edge in [[-HALF.x, WINDOW_X[0]], [WINDOW_X[1], HALF.x]]:
		stage.solids.solid(root, Vector3((edge[0] + edge[1]) * 0.5, (sill + head) * 0.5, back), Vector3(edge[1] - edge[0], head - sill, WALL), "building")
	var lintel = _row_bottom(DOOR_ROWS[1] + 1)
	stage.solids.solid(root, Vector3(0, (lintel + TOP) * 0.5, HALF.y - WALL * 0.5), Vector3(DOOR_HALF * 2.0, TOP - lintel, WALL), "building")
	stage.solids.solid(root, STOVE + Vector3(0, 0.4, 0), Vector3(0.6, 0.8, 0.6), "building")
	stage.solids.interior_footprints.append({"inverse": root.transform.affine_inverse(), "half": HALF})

static func _within(row: int, rows: Array) -> bool:
	return row >= rows[0] and row <= rows[1]

# One course of a long wall, split around an opening [x0, x1] if there is one.
func _course(center: Vector3, length: float, gap: Array, tint: Color) -> void:
	if gap.is_empty():
		Props.box(root, center, Vector3(length, LOG + 0.01, WALL), tint)
		return
	var left = -length * 0.5
	var right = length * 0.5
	Props.box(root, center + Vector3((left + gap[0]) * 0.5, 0, 0), Vector3(gap[0] - left, LOG + 0.01, WALL), tint)
	Props.box(root, center + Vector3((gap[1] + right) * 0.5, 0, 0), Vector3(right - gap[1], LOG + 0.01, WALL), tint)

func _roof() -> void:
	for sign in [-1.0, 1.0]:
		var slab = Props.box(root, Vector3(sign * 1.1, TOP + 0.43, 0), Vector3(2.5, 0.14, 4.0), Color("3f3a36"))
		slab.rotation.z = -sign * 0.42
	# Gable ends: boards fill the triangles under the roof.
	for z in [-HALF.y + 0.06, HALF.y - 0.06]:
		for i in range(4):
			var width = 3.9 - i * 1.0
			Props.box(root, Vector3(0, TOP + 0.1 + i * 0.22, z), Vector3(width, 0.22, 0.08), BOARDS.darkened(0.25))
	Props.box(root, Vector3(0, TOP + 0.03, 0), Vector3(HALF.x * 2.0 - 0.1, 0.06, HALF.y * 2.0 - 0.1), BOARDS.darkened(0.1))
	Props.cylinder(root, Vector3(STOVE.x, TOP + 0.5, STOVE.z), 0.12, 0.12, 1.6, Color("2f2f2f"), 6)

func _inside() -> void:
	Props.box(root, Vector3(0, FLOOR + 0.01, 0), Vector3(HALF.x * 2.0 - WALL * 2.0, 0.02, HALF.y * 2.0 - WALL * 2.0), BOARDS.darkened(0.2))
	Furniture.build(self, root)
	# Stove (каменка): an iron box with a cage of stones on top.
	Props.box(root, STOVE + Vector3(0, 0.33, 0), Vector3(0.6, 0.66, 0.6), IRON)
	Props.box(root, STOVE + Vector3(0, 0.7, 0), Vector3(0.66, 0.06, 0.66), IRON.lightened(0.1))
	for i in range(9):
		var spot = Vector3((i % 3 - 1) * 0.17, 0.79 + (i % 2) * 0.04, (i / 3 - 1) * 0.17)
		Props.cylinder(root, STOVE + spot, 0.09, 0.07, 0.12, Color("7d7a74").darkened((i % 4) * 0.08), 6)
	# Bucket of water with a ladle, by the stove.
	var bucket = STOVE + Vector3(0.65, 0, -0.1)
	Props.cylinder(root, bucket + Vector3(0, 0.15, 0), 0.15, 0.17, 0.3, Color("9b7448"), 10)
	Props.cylinder(root, bucket + Vector3(0, 0.29, 0), 0.135, 0.135, 0.02, Color("6f8fa6"), 10)
	var ladle = Props.box(root, bucket + Vector3(0.1, 0.36, 0), Vector3(0.36, 0.03, 0.04), DARK_WOOD)
	ladle.rotation.z = 0.5
	# Window frame (the opening itself is cut in the courses).
	var bottom = _row_bottom(WINDOW_ROWS[0])
	var height = _opening(WINDOW_ROWS)
	var width = WINDOW_X[1] - WINDOW_X[0]
	var cx = (WINDOW_X[0] + WINDOW_X[1]) * 0.5
	var z = -HALF.y + WALL * 0.5
	for y in [bottom, bottom + height]:
		Props.box(root, Vector3(cx, y, z), Vector3(width + 0.12, 0.06, WALL + 0.04), Color("efe9dc"))
	for x in [WINDOW_X[0], WINDOW_X[1], cx]:
		Props.box(root, Vector3(x, bottom + height * 0.5, z), Vector3(0.05 if x == cx else 0.06, height, WALL + 0.04), Color("efe9dc"))
	# The door stands open against the wall outside.
	var leaf = Props.box(root, Vector3(DOOR_HALF + 0.38, FLOOR + 0.92, HALF.y + 0.08), Vector3(0.76, 1.84, 0.05), DARK_WOOD)
	leaf.rotation.y = -0.25

# Steps up from the lake path to the threshold.
func _porch(stage: Node3D) -> void:
	# The lowest step meets the ground at the outer end, where the slope to the
	# lake is lowest; twice, as the flight's length depends on the rise.
	var length = 0.9
	var ground = 0.0
	var rise = 0.0
	var count = 0
	for i in range(2):
		ground = stage.ground(at(Vector3(0, 0, HALF.y + length))) - root.position.y
		rise = FLOOR - ground
		count = ceili(rise / 0.2)
		length = 0.3 * count
	if rise < 0.12:
		return
	for i in range(count):
		var top = ground + rise * float(i + 1) / count
		var z = HALF.y + length - 0.3 * (i + 0.5)
		Props.box(root, Vector3(0, (top + ground - 0.3) * 0.5, z), Vector3(1.2, top - ground + 0.3, 0.3), BOARDS.darkened(0.15))
	var steps = Transform3D(Basis(Vector3.UP, PI), Vector3(0, ground, HALF.y + length * 0.5))
	_surface(stage, steps, Vector2(0.6, length * 0.5), rise, count)

func _floor(stage: Node3D) -> void:
	_surface(stage, Transform3D(Basis.IDENTITY, Vector3(0, FLOOR, 0.02)), Vector2(HALF.x - 0.1, HALF.y + 0.02), 0.0, 0)

func _surface(stage: Node3D, local_pose: Transform3D, half: Vector2, rise: float, steps: int) -> void:
	var world = root.transform * local_pose
	var surface = {"pose": world, "inverse": world.affine_inverse(), "half": half, "reach": maxf(half.x, half.y) * 2.0, "rise": rise}
	if steps > 0:
		surface.steps = steps
	stage.solids.walk_surfaces.append(surface)

# What changes while people steam: not merged with the logs.
func _interior(stage: Node3D) -> void:
	interior = Node3D.new()
	interior.name = "LakeSaunaInterior"
	stage.add_child(interior)
	interior.transform = root.transform
	var glass = Props.box(interior, Vector3((WINDOW_X[0] + WINDOW_X[1]) * 0.5, _row_bottom(WINDOW_ROWS[0]) + _opening(WINDOW_ROWS) * 0.5, -HALF.y + WALL * 0.5), Vector3(WINDOW_X[1] - WINDOW_X[0], _opening(WINDOW_ROWS), 0.02), Color(0.78, 0.86, 0.9, 0.16))
	Props.unique_material(glass)
	glass.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.material_override.roughness = 0.05
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow = Props.box(interior, STOVE + Vector3(0.301, 0.3, 0), Vector3(0.01, 0.2, 0.3), Color("ff8a3a"))
	Props.unique_material(glow)
	glow.material_override.emission_enabled = true
	glow.material_override.emission = Color("ff7a2a")
	glow.material_override.emission_energy_multiplier = 1.6
	lamp = OmniLight3D.new()
	interior.add_child(lamp)
	lamp.position = Vector3(0, TOP - 0.45, 0)
	lamp.light_color = Color("ffbf80")
	lamp.light_energy = 0.9
	lamp.omni_range = 3.6
	lamp.shadow_enabled = false
	lamp.visible = false
	steam = _particles(Color(0.95, 0.95, 0.95, 0.08), 0.9, 16, 3.2)
	steam.position = STOVE + Vector3(0, 0.95, 0)
	steam.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	steam.emission_sphere_radius = 0.3
	steam.direction = Vector3(0, 1.0, -0.6)
	steam.spread = 50.0
	steam.gravity = Vector3(0, 0.25, -0.15)
	steam.initial_velocity_min = 0.3
	steam.initial_velocity_max = 0.8
	smoke = _particles(Color(0.82, 0.82, 0.8, 0.28), 1.0, 14, 4.0)
	smoke.position = Vector3(STOVE.x, TOP + 1.35, STOVE.z)
	smoke.direction = Vector3(0.15, 1.0, 0.05)
	smoke.spread = 10.0
	smoke.gravity = Vector3(0.3, 0.25, 0.1)
	smoke.initial_velocity_min = 0.5
	smoke.initial_velocity_max = 0.9
	hiss = preload("res://scripts/core/sound_bank.gd").spatial(interior, -4.0, 2.5, 18.0, "sauna-hiss")
	hiss.position = STOVE + Vector3(0, 0.8, 0)
	cloud = _particles(Color(0.97, 0.97, 0.97, 0.22), 1.2, 18, 2.6)
	cloud.position = STOVE + Vector3(0, 0.9, 0)
	cloud.one_shot = true
	cloud.explosiveness = 0.85
	cloud.direction = Vector3(0.2, 1.0, -0.6)
	cloud.spread = 70.0
	cloud.gravity = Vector3(0, 0.4, -0.25)
	cloud.initial_velocity_min = 0.6
	cloud.initial_velocity_max = 1.4

func _particles(color: Color, size: float, amount: int, lifetime: float) -> CPUParticles3D:
	var particles = CPUParticles3D.new()
	var quad = QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = mat
	particles.mesh = quad
	particles.amount = amount
	particles.lifetime = lifetime
	particles.local_coords = false
	particles.scale_amount_min = 0.8
	particles.scale_amount_max = 1.8
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.emitting = false
	interior.add_child(particles)
	return particles

# ---------------------------------------------------------------- life

# `occupied`: somebody in the room is steaming. `camera`: where this client looks from.
func update(occupied: bool, camera: Vector3) -> void:
	if interior == null:
		return
	var near = camera.distance_to(at(Vector3(0, FLOOR + 1.0, 0))) < 9.0
	lamp.visible = near
	steam.emitting = occupied and near
	smoke.emitting = occupied

# Water on the stones: a hiss and a thick cloud for a moment.
func loyly() -> void:
	if interior == null:
		return
	cloud.restart()
	cloud.emitting = true
	if hiss.stream != null:
		hiss.play()
