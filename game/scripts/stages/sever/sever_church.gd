extends RefCounted
# Wooden tent-roofed church of the Russian North («восьмерик на четверике»),
# all on one axis: the apse (алтарь) at the back, the log quadrangle
# (четверик) carrying an octagon (восьмерик) and a tall shingled tent (шатёр)
# with a small onion dome of silvery aspen shingle, the lower refectory
# (трапезная) and, nearest the road, the bell tower: a log base with an open
# octagonal belfry under its own tent. Weathered, unpainted wood.
# Local frame: +Z faces the road; the quadrangle is centred on the origin.
const Props = preload("res://scripts/core/props.gd")
const Carpentry = preload("res://scripts/stages/sever/sever_carpentry.gd")
const SNOW = Color("eef2f2")
const LOGS = Color("756c60")
const SHINGLE = Color("8f9391")
const PLANK = Color("5e5c57")
const IRON = Color("3b3a36")

static func build(stage, biome, root: Node3D) -> Node3D:
	var c = biome.CHURCH
	var pos = biome.place(c.s, c.side, c.offset)
	var node = Node3D.new()
	node.name = "VillageChurch"
	root.add_child(node)
	node.position = pos
	var facing = stage.at(c.s) - pos
	node.rotation.y = atan2(facing.x, facing.z)
	_level(stage, node)
	_quadrangle(node)
	_apse(node)
	_refectory(node)
	_bell_tower(stage, node)
	stage.solids.solid(node, Vector3(0, 3.2, 0), Vector3(8.3, 6.4, 8.3), "building")
	stage.solids.solid(node, Vector3(0, 2.5, -5.9), Vector3(5.3, 5.0, 3.9), "building")
	stage.solids.solid(node, Vector3(0, 2.2, 7.25), Vector3(7.3, 4.4, 6.8), "building")
	stage.solids.solid(node, Vector3(0, 3.5, 12.6), Vector3(4.5, 7.0, 4.5), "building")
	return node

static func _level(stage, node: Node3D) -> void:
	var low = INF
	var high = -INF
	for corner in [Vector3(4.5, 0, 15.5), Vector3(-4.5, 0, 15.5), Vector3(4.5, 0, -8.0), Vector3(-4.5, 0, -8.0), Vector3.ZERO]:
		var height = stage.ground(node.position + node.basis * corner)
		low = minf(low, height)
		high = maxf(high, height)
	node.position.y = lerpf(low, high, 0.6)
	var depth = node.position.y - low + 0.5
	Props.box(node, Vector3(0, 0.1 - depth * 0.5, 3.6), Vector3(9.0, depth + 0.2, 23.6), Color("6a6660"))

# Onion dome on a drum with an Orthodox cross, standing at `top`.
static func dome(node: Node3D, top: float, scale: float) -> void:
	Props.cylinder(node, Vector3(0, top + 0.6 * scale, 0), 0.5 * scale, 0.5 * scale, 1.2 * scale, LOGS.darkened(0.1), 10)
	Props.faceted(node, Vector3(0, top + 1.85 * scale, 0), Vector3(1.55, 1.7, 1.55) * scale, SHINGLE.lightened(0.15), 12, 8)
	Props.cylinder(node, Vector3(0, top + 2.95 * scale, 0), 0.32 * scale, 0.0, 0.7 * scale, SHINGLE.lightened(0.15), 10)
	var cross = top + 3.2 * scale
	Props.box(node, Vector3(0, cross + 0.8 * scale, 0), Vector3(0.08, 1.6, 0.08) * scale, IRON)
	Props.box(node, Vector3(0, cross + 1.25 * scale, 0), Vector3(0.42, 0.07, 0.07) * scale, IRON)
	Props.box(node, Vector3(0, cross + 0.95 * scale, 0), Vector3(0.82, 0.08, 0.08) * scale, IRON)
	var foot = Props.box(node, Vector3(0, cross + 0.42 * scale, 0), Vector3(0.56, 0.07, 0.07) * scale, IRON)
	foot.rotation.z = 0.38

# Octagonal log tier: alternate courses step in and out like hewn logs.
static func octagon(node: Node3D, y0: float, height: float, radius: float) -> void:
	var courses = roundi(height / 0.26)
	var step = height / courses
	for i in range(courses):
		var r = radius + (0.04 if i % 2 == 0 else -0.02)
		var ring = Props.cylinder(node, Vector3(0, y0 + (i + 0.5) * step, 0), r, r, step * 0.98, LOGS.lightened(0.04) if i % 2 == 0 else LOGS, 8)
		ring.rotation.y = PI / 8.0

static func _quadrangle(node: Node3D) -> void:
	Carpentry.log_frame(node, Vector3.ZERO, 8.0, 8.0, 6.4, LOGS)
	# Low hipped roof over the quadrangle's corners, under the octagon.
	var hip = Props.cylinder(node, Vector3(0, 7.0, 0), 6.5, 3.6, 1.2, PLANK, 4)
	hip.rotation.y = PI / 4.0
	var hip_snow = Props.cylinder(node, Vector3(0, 7.1, 0), 6.4, 3.55, 1.12, SNOW, 4)
	hip_snow.rotation.y = PI / 4.0
	octagon(node, 6.4, 4.4, 3.5)
	# Flared top of the octagon (повал) and the tall shingled tent.
	var flare = Props.cylinder(node, Vector3(0, 11.05, 0), 3.55, 4.05, 0.5, LOGS, 8)
	flare.rotation.y = PI / 8.0
	var tent = Props.cylinder(node, Vector3(0, 15.85, 0), 4.2, 0.42, 9.6, SHINGLE, 8)
	tent.rotation.y = PI / 8.0
	dome(node, 20.65, 1.0)
	for side in [-1.0, 1.0]:
		for z in [-1.8, 1.8]:
			Carpentry.side_window(node, Vector3(side * 4.12, 3.6, z), Vector2(0.5, 0.8), LOGS.lightened(0.25), LOGS, false, side)
		var octa = Node3D.new()
		node.add_child(octa)
		octa.rotation.y = side * PI * 0.5
		Carpentry.window(octa, Vector3(0, 8.6, 3.28), Vector2(0.45, 0.7), LOGS.lightened(0.25), LOGS, false)

static func _apse(node: Node3D) -> void:
	Carpentry.log_frame(node, Vector3(0, 0, -5.9), 5.0, 3.6, 4.8, LOGS)
	var ridge = Carpentry.gable_roof(node, 4.8, 5.0, -8.1, -4.0, 0.78, PLANK, 0.45)
	Carpentry.gable(node, -7.6, 5.0, 4.8, ridge - 0.1, 0.25, LOGS.lightened(0.1))
	Carpentry.log_between(node, Vector3(0, ridge + 0.1, -4.0), Vector3(0, ridge + 0.1, -8.1), 0.16, LOGS.darkened(0.2))
	var crown = Node3D.new()
	node.add_child(crown)
	crown.position = Vector3(0, 0, -5.9)
	dome(crown, ridge - 0.1, 0.45)
	var back = Node3D.new()
	node.add_child(back)
	back.position = Vector3(0, 0, -7.85)
	back.rotation.y = PI
	Carpentry.window(back, Vector3(0, 2.8, 0), Vector2(0.45, 0.7), LOGS.lightened(0.25), LOGS, false)

static func _refectory(node: Node3D) -> void:
	Carpentry.log_frame(node, Vector3(0, 0, 7.25), 7.0, 6.5, 4.4, LOGS)
	Carpentry.gable_roof(node, 4.4, 7.0, 4.0, 10.6, 0.62, PLANK, 0.5)
	for side in [-1.0, 1.0]:
		for z in [5.6, 8.9]:
			Carpentry.side_window(node, Vector3(side * 3.62, 2.5, z), Vector2(0.6, 0.85), LOGS.lightened(0.25), LOGS, false, side)

static func _bell_tower(stage, node: Node3D) -> void:
	var base = Vector3(0, 0, 12.6)
	Carpentry.log_frame(node, base, 4.2, 4.2, 7.0, LOGS)
	# Open octagonal belfry: floor, posts, bells and the crowning ring.
	var floor_ring = Props.cylinder(node, base + Vector3(0, 7.15, 0), 2.45, 2.45, 0.3, PLANK, 8)
	floor_ring.rotation.y = PI / 8.0
	for i in range(8):
		var angle = TAU * i / 8.0
		Props.box(node, base + Vector3(sin(angle) * 2.15, 8.6, cos(angle) * 2.15), Vector3(0.18, 2.6, 0.18), LOGS)
	var parapet = Props.cylinder(node, base + Vector3(0, 7.65, 0), 2.25, 2.25, 0.7, LOGS.darkened(0.1), 8)
	parapet.rotation.y = PI / 8.0
	Props.box(node, base + Vector3(0, 9.55, 0), Vector3(0.14, 0.14, 3.6), LOGS)
	Props.cylinder(node, base + Vector3(0, 9.12, 0), 0.5, 0.24, 0.7, Color("6c5a34"), 10)
	for z in [-0.95, 0.95]:
		Props.cylinder(node, base + Vector3(0, 9.31, z), 0.22, 0.11, 0.32, Color("6c5a34"), 8)
	var ring = Props.cylinder(node, base + Vector3(0, 10.0, 0), 2.5, 2.5, 0.3, LOGS, 8)
	ring.rotation.y = PI / 8.0
	var tent = Props.cylinder(node, base + Vector3(0, 12.75, 0), 2.75, 0.24, 5.2, SHINGLE, 8)
	tent.rotation.y = PI / 8.0
	var holder = Node3D.new()
	node.add_child(holder)
	holder.position = base
	dome(holder, 15.3, 0.55)
	# Entrance on the road side with a small gabled porch.
	Props.box(node, base + Vector3(0, 1.15, 2.27), Vector3(1.2, 2.3, 0.08), Color("4a3b2c"))
	var porch = Node3D.new()
	node.add_child(porch)
	porch.position = base + Vector3(0, 0, 2.15)
	for x in [-0.95, 0.95]:
		Props.box(porch, Vector3(x, 1.3, 1.35), Vector3(0.16, 2.6, 0.16), LOGS)
		stage.solids.solid(porch, Vector3(x, 1.3, 1.35), Vector3(0.16, 2.6, 0.16), "building")
	var ridge = Carpentry.gable_roof(porch, 2.6, 2.1, 0.0, 1.75, 0.75, PLANK, 0.25)
	Carpentry.gable(porch, 1.6, 2.1, 2.6, ridge - 0.08, 0.12, LOGS.lightened(0.1))
	Props.box(porch, Vector3(0, 0.1, 0.9), Vector3(2.0, 0.2, 1.8), Color("7a6650"))
