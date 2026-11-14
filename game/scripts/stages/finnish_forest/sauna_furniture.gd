extends RefCounted
# Furnishing of the lake sauna (lake_sauna.gd), in the hut frame: two upper
# benches (полки) facing each other along the side walls, each with a lower
# step, backrest, headrest and a towel; slatted duckboards on the floor; birch
# whisks (веники) and felt hats on pegs by the door; a thermometer and a wooden
# lamp shade. All of it is static and merges with the logs into one mesh.
const Props = preload("res://scripts/core/props.gd")
const BIRCH = Color("5f7d3a")
const FELT = Color("d9cdb3")
const TOWEL = Color("eeeae0")

static func build(sauna, root: Node3D) -> void:
	for side in [-1.0, 1.0]:
		_bench(sauna, root, side)
	_duckboards(sauna, root)
	_pegs(sauna, root)
	_details(sauna, root)

# One полок along the wall on `side` (-1 left, +1 right) with its step.
static func _bench(sauna, root: Node3D, side: float) -> void:
	var z0: float = sauna.BENCH_Z[0]
	var z1: float = sauna.BENCH_Z[1]
	var length = z1 - z0
	var middle_z = (z0 + z1) * 0.5
	var wall_x = side * (sauna.HALF.x - sauna.WALL)
	var depth = sauna.BENCH_DEPTH
	var edge = wall_x - side * depth
	for i in range(4):
		var x = wall_x - side * depth * (i + 0.5) / 4.0
		Props.box(root, Vector3(x, sauna.BENCH_TOP - 0.03, middle_z), Vector3(depth / 4.0 - 0.02, 0.05, length), sauna.BOARDS.lightened((i % 2) * 0.06))
	for i in range(2):
		var x = edge - side * 0.2 * (i + 0.5)
		Props.box(root, Vector3(x, sauna.STEP_TOP - 0.03, middle_z), Vector3(0.18, 0.05, length), sauna.BOARDS.lightened((i % 2) * 0.06))
	for z in [z0 + 0.1, middle_z, z1 - 0.1]:
		Props.box(root, Vector3(edge + side * 0.05, (sauna.FLOOR + sauna.BENCH_TOP) * 0.5, z), Vector3(0.07, sauna.BENCH_TOP - sauna.FLOOR, 0.07), sauna.BOARDS.darkened(0.2))
		Props.box(root, Vector3(edge - side * 0.35, (sauna.FLOOR + sauna.STEP_TOP) * 0.5, z), Vector3(0.07, sauna.STEP_TOP - sauna.FLOOR, 0.07), sauna.BOARDS.darkened(0.2))
	# Backrest: two slats on brackets off the logs.
	for y in [0.25, 0.5]:
		Props.box(root, Vector3(wall_x - side * 0.05, sauna.BENCH_TOP + y, middle_z), Vector3(0.04, 0.12, length - 0.1), sauna.BOARDS.lightened(0.04))
	# Curved headrest at the door end, a folded towel near the window end.
	var rest = Props.box(root, Vector3(wall_x - side * depth * 0.5, sauna.BENCH_TOP + 0.06, z1 - 0.2), Vector3(depth - 0.1, 0.08, 0.3), sauna.BOARDS.lightened(0.1))
	rest.rotation.x = -0.35
	Props.box(root, Vector3(wall_x - side * depth * 0.45, sauna.BENCH_TOP + 0.015, -0.5), Vector3(depth * 0.7, 0.03, 0.42), TOWEL.darkened(0.04 if side < 0 else 0.0))

static func _duckboards(sauna, root: Node3D) -> void:
	var width = 2.0 * (sauna.HALF.x - sauna.WALL - sauna.BENCH_DEPTH - 0.4) - 0.1
	var z0 = -sauna.HALF.y + sauna.WALL + 0.1
	var z1 = sauna.HALF.y - sauna.WALL - 0.1
	var count = int((z1 - z0) / 0.14)
	for i in range(count):
		var z = z0 + (i + 0.5) * (z1 - z0) / count
		Props.box(root, Vector3(0, sauna.FLOOR + 0.035, z), Vector3(width, 0.025, 0.1), sauna.BOARDS.darkened(0.08 + (i % 2) * 0.05))
	for x in [-width * 0.4, 0.0, width * 0.4]:
		Props.box(root, Vector3(x, sauna.FLOOR + 0.012, (z0 + z1) * 0.5), Vector3(0.05, 0.022, z1 - z0), sauna.DARK_WOOD)

# Pegs on the lake wall right of the door: two whisks and two felt hats.
static func _pegs(sauna, root: Node3D) -> void:
	var z = sauna.HALF.y - sauna.WALL - 0.03
	Props.box(root, Vector3(1.15, sauna.FLOOR + 1.75, z), Vector3(1.1, 0.08, 0.04), sauna.DARK_WOOD)
	for i in range(2):
		var x = 0.75 + i * 0.3
		Props.cylinder(root, Vector3(x, sauna.FLOOR + 1.68, z - 0.04), 0.02, 0.02, 0.12, sauna.DARK_WOOD, 5)
		whisk(root, Vector3(x, sauna.FLOOR + 1.38, z - 0.09), 0.0)
	for i in range(2):
		var x = 1.35 + i * 0.32
		var hat = Props.cylinder(root, Vector3(x, sauna.FLOOR + 1.6, z - 0.1), 0.13, 0.1, 0.16, FELT.darkened(i * 0.08), 8)
		hat.rotation.x = 0.35
		Props.cylinder(hat, Vector3(0, -0.07, 0), 0.17, 0.17, 0.02, FELT.darkened(i * 0.08 + 0.05), 8)

static func _details(sauna, root: Node3D) -> void:
	# Round thermometer in a wooden frame between the window and the right bench.
	var z = -sauna.HALF.y + sauna.WALL + 0.03
	Props.box(root, Vector3(0.95, sauna.FLOOR + 1.85, z), Vector3(0.16, 0.42, 0.03), sauna.BOARDS.lightened(0.12))
	Props.box(root, Vector3(0.95, sauna.FLOOR + 1.85, z + 0.02), Vector3(0.025, 0.3, 0.01), Color("c8382c"))
	# Slatted wooden shade around the lamp in the middle of the ceiling.
	for i in range(4):
		var shade = Props.box(root, Vector3(0, sauna.TOP - 0.28, 0) + Vector3(0.14, 0, 0).rotated(Vector3.UP, i * PI / 2.0), Vector3(0.03, 0.28, 0.26), sauna.BOARDS.lightened(0.08))
		shade.rotation.y = i * PI / 2.0
	Props.box(root, Vector3(0, sauna.TOP - 0.12, 0), Vector3(0.06, 0.24, 0.06), sauna.DARK_WOOD)

# A birch whisk: leafy fan bound at the handle. `swing` tilts it (rad).
static func whisk(parent: Node3D, pos: Vector3, swing: float) -> Node3D:
	var node = Node3D.new()
	parent.add_child(node)
	node.position = pos
	node.rotation.x = swing
	Props.cylinder(node, Vector3(0, 0.2, 0), 0.025, 0.03, 0.18, Color("8c6a46"), 5)
	Props.box(node, Vector3(0, 0.12, 0), Vector3(0.07, 0.03, 0.07), Color("b9a27a"))
	var leaves = Props.cylinder(node, Vector3(0, -0.08, 0), 0.15, 0.05, 0.38, BIRCH, 7)
	leaves.scale = Vector3(1.0, 1.0, 0.45)
	Props.cylinder(node, Vector3(0, -0.12, 0.02), 0.12, 0.04, 0.3, BIRCH.lightened(0.12), 6).scale = Vector3(1.0, 1.0, 0.4)
	return node
