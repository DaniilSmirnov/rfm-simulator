extends RefCounted
# Yurts of the Charyn stage: a felt dome on a lattice wall, a painted wooden
# door and the wheel of the shanyrak at the crown. One builder used by the
# camp on the steppe and by the smaller camp down in the gorge, plus the camp
# furniture that stands around them.
const Props = preload("res://scripts/core/props.gd")
const Records = preload("res://scripts/stages/stage_records.gd")

const FELT = Color("e4ded0")
const FELT_SHADE = Color("d6cfbe")
const TIMBER = Color("8a5a30")
const DOOR = Color("a8481f")
const TRIM = Color("d08f2c")
const ROPE = Color("b7a888")
const STONE = Color("9c8e7c")
const RADIUS = 3.1
const WALL = 1.9

# One yurt standing at `at` in `parent` space, its door turned to `yaw`.
static func yurt(parent: Node3D, at: Vector3, yaw: float, big: bool = false) -> Node3D:
	var node = Node3D.new()
	node.name = "Yurt"
	parent.add_child(node)
	node.position = at
	node.rotation.y = yaw
	if big:
		node.scale = Vector3.ONE * 1.18
	Props.cylinder(node, Vector3(0, WALL * 0.5, 0), RADIUS, RADIUS * 1.02, WALL, FELT, 16)
	# Belt ropes that hold the lattice wall together.
	for height in [0.75, 1.35]:
		Props.cylinder(node, Vector3(0, height, 0), RADIUS * 1.03, RADIUS * 1.03, 0.07, ROPE, 16)
	Props.cylinder(node, Vector3(0, WALL + 0.78, 0), RADIUS * 1.03, 0.62, 1.56, FELT_SHADE, 16)
	# Shanyrak: the wooden wheel of the crown with its spokes.
	Props.cylinder(node, Vector3(0, WALL + 1.57, 0), 0.66, 0.66, 0.12, TIMBER, 12)
	Props.cylinder(node, Vector3(0, WALL + 1.62, 0), 0.5, 0.5, 0.06, TIMBER.darkened(0.2), 12)
	for i in range(10):
		var angle = i * TAU / 10.0
		var pole = Props.box(node, Vector3(sin(angle), 0, cos(angle)) * RADIUS * 0.55 + Vector3(0, WALL + 0.86, 0), Vector3(0.07, 0.07, RADIUS * 1.1), TIMBER)
		pole.rotation = Vector3(0.52, angle, 0)
	_door(node)
	return node

static func _door(node: Node3D) -> void:
	var front = RADIUS * 0.99
	Props.box(node, Vector3(0, 0.95, front), Vector3(1.24, 1.9, 0.12), TIMBER)
	Props.box(node, Vector3(0, 0.92, front + 0.07), Vector3(1.0, 1.66, 0.06), DOOR)
	Props.box(node, Vector3(0, 1.72, front + 0.09), Vector3(1.02, 0.12, 0.05), TRIM)
	Props.box(node, Vector3(0, 0.92, front + 0.09), Vector3(0.1, 1.5, 0.04), TRIM)
	for side in [-0.34, 0.34]:
		Props.box(node, Vector3(side, 1.2, front + 0.09), Vector3(0.26, 0.26, 0.04), TRIM)

# A camp of yurts facing an open yard, with a fire ring, a hitching rail and
# rolls of felt. Returns the node so the stage can bake it.
static func camp(stage, at: Vector3, facing: Vector3, count: int, name: String) -> Node3D:
	var node = Node3D.new()
	node.name = name
	stage.add_child(node)
	node.position = at
	node.rotation.y = atan2(facing.x, facing.z)
	for i in range(count):
		var angle = (float(i) / maxf(1.0, float(count) - 1.0) - 0.5) * 1.5
		var spot = Vector3(sin(angle + PI), 0, cos(angle + PI)) * 11.0
		spot.y = stage.terrain_surface_height(node.to_global(spot)) - at.y
		yurt(node, spot, angle + PI, i == 0)
		stage.rocks.append(Records.rock(node.to_global(spot), RADIUS * 1.05, 3.4, Records.BUILDING))
	_fire_ring(node)
	_hitching_rail(node, Vector3(9.0, 0, 3.0))
	for i in range(3):
		var roll = Props.cylinder(node, Vector3(-8.5 + i * 0.9, 0.35, 4.2), 0.34, 0.34, 1.7, FELT_SHADE.darkened(0.06), 8)
		roll.rotation.z = PI * 0.5
	flag(node, Vector3(-6.0, 0, -4.5))
	return node

static func _fire_ring(node: Node3D) -> void:
	load("res://scripts/camp/stage_meals.gd").build(node)

static func _hitching_rail(node: Node3D, at: Vector3) -> void:
	for side in [-2.4, 2.4]:
		Props.cylinder(node, at + Vector3(side, 0.8, 0), 0.09, 0.08, 1.6, TIMBER, 6)
	var rail = Props.cylinder(node, at + Vector3(0, 1.45, 0), 0.07, 0.07, 4.8, TIMBER.lightened(0.08), 6)
	rail.rotation.z = PI * 0.5
	for i in range(3):
		Props.cylinder(node, at + Vector3(-1.6 + i * 1.6, 1.1, 0.1), 0.02, 0.02, 0.7, ROPE, 4)

# Exact vector artwork on vertical cloth; both sides share the same texture.
# The former cylinder/box symbols were not in the cloth plane and omitted the eagle.
static func flag(parent: Node3D, at: Vector3) -> void:
	Props.cylinder(parent, at + Vector3(0, 3.2, 0), 0.05, 0.04, 6.4, Color("d8d8d2"), 6)
	var cloth = MeshInstance3D.new()
	cloth.name = "KazakhstanFlag"
	cloth.mesh = QuadMesh.new()
	cloth.mesh.size = Vector2(1.8, 0.9)
	var material = StandardMaterial3D.new()
	material.albedo_texture = preload("res://textures/flags/kazakhstan.svg")
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 1.0
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	cloth.material_override = material
	# A zero-thickness sheet must not shadow itself in the sun cascades.
	cloth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(cloth)
	cloth.position = at + Vector3(0.95, 5.6, 0)
