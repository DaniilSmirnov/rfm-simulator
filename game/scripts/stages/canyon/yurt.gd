extends RefCounted
# Felt-covered Kazakh yurts, with inward-facing doors and a shared open yard.
const Props = preload("res://scripts/core/props.gd")
const Records = preload("res://scripts/stages/stage_records.gd")
const Furnishings = preload("res://scripts/stages/canyon/yurt_camp_props.gd")
const FELT = Color("c6bead")
const FELT_SHADE = Color("bbb39f")
const TIMBER = Color("785031")
const DOOR = Color("8f402b")
const ROPE = Color("8e795b")
const RADIUS = 3.1
const WALL = 1.9
const SIDES = 24

static func yurt(parent: Node3D, at: Vector3, yaw: float, big: bool = false, stage = null) -> Node3D:
	var node = Node3D.new()
	node.name = "Yurt"
	parent.add_child(node)
	node.position = at
	node.rotation.y = yaw
	if big:
		node.scale = Vector3.ONE * 1.18
	_felt(node, stage)
	# Three narrow woven tension bands sit on the felt, not thick wooden disks.
	for height in [0.28, 0.95, 1.66]:
		for i in range(SIDES):
			var a = i * TAU / SIDES
			var b = (i + 1) * TAU / SIDES
			Furnishings.pole(node, Vector3(sin(a), 0, cos(a)) * 3.125 + Vector3.UP * height, Vector3(sin(b), 0, cos(b)) * 3.125 + Vector3.UP * height, 0.018, ROPE)
	_crown(node)
	_door(node, stage)
	# Stakes are beside/behind the yurt, leaving its entrance unobstructed.
	for angle in [-1.35, 1.35, PI]:
		var peg = Vector3(sin(angle), 0, cos(angle)) * 3.95
		peg.y = _ground_y(node, peg, stage)
		Furnishings.pole(node, peg, peg + Vector3(0.07, 0.28, 0), 0.035, TIMBER)
		Furnishings.pole(node, peg + Vector3.UP * 0.12, Vector3(sin(angle) * 3.14, 1.91, cos(angle) * 3.14), 0.014, ROPE)
	return node

static func _ground_y(node: Node3D, point: Vector3, stage) -> float:
	if stage == null:
		return 0.0
	var world = node.to_global(point)
	world.y = stage.terrain_surface_height(world)
	return node.to_local(world).y

static func _felt(node: Node3D, stage) -> void:
	var shell = SurfaceTool.new()
	shell.begin(Mesh.PRIMITIVE_TRIANGLES)
	# The lower skirt follows the ground; shallow curved roof panels cover the
	# rafters. Wood is visible at the door and crown, not through the roof.
	for i in range(SIDES):
		var a = i * TAU / SIDES
		var b = (i + 1) * TAU / SIDES
		var low_a = Vector3(sin(a) * RADIUS, 0, cos(a) * RADIUS)
		var low_b = Vector3(sin(b) * RADIUS, 0, cos(b) * RADIUS)
		low_a.y = _ground_y(node, low_a, stage) - 0.04
		low_b.y = _ground_y(node, low_b, stage) - 0.04
		var top_a = Vector3(low_a.x, WALL, low_a.z)
		var top_b = Vector3(low_b.x, WALL, low_b.z)
		var shade = FELT.darkened((i % 4) * 0.009)
		var skirt_a = low_a.lerp(top_a, 0.09)
		var skirt_b = low_b.lerp(top_b, 0.09)
		_quad(shell, skirt_a, top_a, top_b, skirt_b, shade)
		_quad(shell, low_a, skirt_a, skirt_b, low_b, shade.darkened(0.12))
		var rings = [Vector2(3.20, WALL), Vector2(2.91, 2.21), Vector2(2.20, 2.76), Vector2(1.40, 3.18), Vector2(0.62, 3.44)]
		for r in range(rings.size() - 1):
			var lo = rings[r]
			var hi = rings[r + 1]
			_quad(shell, Vector3(sin(a) * lo.x, lo.y, cos(a) * lo.x), Vector3(sin(a) * hi.x, hi.y, cos(a) * hi.x), Vector3(sin(b) * hi.x, hi.y, cos(b) * hi.x), Vector3(sin(b) * lo.x, lo.y, cos(b) * lo.x), FELT_SHADE.lightened((i % 3) * 0.012))
		# Narrow vertical seams, with a slight raised edge on each felt panel.
		if i % 3 == 0:
			Furnishings.pole(node, low_a + Vector3.UP * 0.05, top_a, 0.012, FELT_SHADE)
	shell.generate_normals()
	var mesh = MeshInstance3D.new()
	mesh.name = "FeltShell"
	mesh.mesh = shell.commit()
	mesh.material_override = Props.material(Color.WHITE)
	mesh.material_override.vertex_color_use_as_albedo = true
	node.add_child(mesh)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	st.set_color(color)
	for v in [a, b, c, a, c, d]:
		st.add_vertex(v)

static func _crown(node: Node3D) -> void:
	Props.cylinder(node, Vector3(0, 3.42, 0), 0.58, 0.58, 0.02, Color("302b25"), SIDES)
	var ring = MeshInstance3D.new()
	ring.name = "Shanyrak"
	ring.mesh = TorusMesh.new()
	ring.mesh.inner_radius = 0.49
	ring.mesh.outer_radius = 0.64
	ring.mesh.rings = SIDES
	ring.mesh.ring_segments = 6
	ring.material_override = Props.material(TIMBER)
	node.add_child(ring)
	ring.position.y = 3.46
	for x in [-0.20, 0.20]:
		Props.box(node, Vector3(x, 3.47, 0), Vector3(0.045, 0.045, 1.03), TIMBER)
		Props.box(node, Vector3(0, 3.49, x), Vector3(1.03, 0.045, 0.045), TIMBER)
	# Folded-back felt cover leaves the crown visible.
	var cover = Props.box(node, Vector3(0, 3.42, -0.63), Vector3(1.20, 0.06, 0.50), FELT)
	cover.rotation.x = -0.20

static func _door(node: Node3D, stage) -> void:
	var front = RADIUS + 0.04
	var floor_y = _ground_y(node, Vector3(0, 0, front), stage)
	var height = maxf(1.35, 1.80 - floor_y)
	var middle = floor_y + height * 0.5
	Props.box(node, Vector3(0, middle, front), Vector3(1.34, height + 0.10, 0.17), TIMBER.darkened(0.15))
	for i in range(6):
		Props.box(node, Vector3(-0.48 + i * 0.192, middle, front + 0.10), Vector3(0.18, height - 0.10, 0.05), DOOR.lightened((i % 2) * 0.035))
	for y in [floor_y + 0.25, floor_y + height - 0.25]:
		Props.box(node, Vector3(0, y, front + 0.14), Vector3(1.10, 0.065, 0.035), TIMBER.lightened(0.12))
	for side in [-0.52, 0.52]:
		for y in [floor_y + 0.35, floor_y + height - 0.35]:
			Props.box(node, Vector3(side, y, front + 0.17), Vector3(0.14, 0.055, 0.025), Color("393631"))
	Props.box(node, Vector3(0.16, middle, front + 0.18), Vector3(0.07, 0.12, 0.04), Color("393631"))
	Props.box(node, Vector3(0, floor_y + 0.04, front + 0.22), Vector3(1.35, 0.08, 0.45), TIMBER)

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
		var big = i == 0
		yurt(node, spot, angle, big, stage)
		stage.rocks.append(Records.rock(node.to_global(spot), RADIUS * (1.18 if big else 1.0), 3.5 * (1.18 if big else 1.0), Records.BUILDING))
	var food = load("res://scripts/camp/stage_meals.gd").build(node)
	food.position.y = stage.terrain_surface_height(at) - at.y
	Furnishings.build(stage, node)
	return node
