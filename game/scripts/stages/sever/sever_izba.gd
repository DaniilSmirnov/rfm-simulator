extends RefCounted
# A northern izba of the «кошель» kind seen in Vologda and Arkhangelsk
# villages: a log living part raised on a high basement storey (подклет) with
# its gable end to the street, and the covered farmyard (двор) behind it under
# the same steep plank roof. Carved white surrounds with painted shutters,
# barge boards and a horse-head ridge log on the street gable, a brick chimney,
# a side porch with a flight of steps and the yard gate.
# Local frame: +Z faces the road; the living part is centred on the origin.
const Props = preload("res://scripts/core/props.gd")
const Carpentry = preload("res://scripts/stages/sever/sever_carpentry.gd")
const SNOW = Color("eef2f2")
const PODKLET = 1.6
const STOREY = 2.7
const PITCH = 0.74
const LOGS = [Color("6c5a47"), Color("74624d"), Color("5f5244"), Color("7a6a58")]
const PAINT = [Color("c39a4e"), Color("6d8b76"), Color("6b8798"), Color("a8705a")]
const SURROUNDS = [Color("ece8de"), Color("e9e2cf"), Color("b9cfdb")]
const SHUTTERS = [Color("3d6b8c"), Color("4c7a52"), Color("8a3d32"), Color("e9e2cf")]
const ROOFS = [Color("5b5853"), Color("55524c"), Color("4f6a57"), Color("6e4a3c")]
const BOARDS = Color("675a4a")

# Builds one izba from a biome.HOUSES record; returns its node.
static func build(stage, biome, root: Node3D, item: Array, rng: RandomNumberGenerator) -> Node3D:
	var s: float = item[0]
	var w: float = item[3]
	var d: float = item[4]
	var floors: int = item[5]
	var yard: float = biome.YARD_DEPTH
	var pos = biome.place(s, item[1], item[2])
	var node = Node3D.new()
	node.name = "Izba_%d_%d" % [int(s), int(item[1])]
	root.add_child(node)
	node.position = pos
	var facing = stage.at(s) - pos
	node.rotation.y = atan2(facing.x, facing.z)
	_level(stage, node, w * 0.5 + 0.3, d * 0.5 + 0.3, -d * 0.5 - yard - 0.2)
	var logs: Color = LOGS[rng.randi() % LOGS.size()]
	var surround: Color = SURROUNDS[rng.randi() % SURROUNDS.size()]
	var shutters: Color = SHUTTERS[rng.randi() % SHUTTERS.size()]
	var roof: Color = ROOFS[rng.randi() % ROOFS.size()]
	var walls = PODKLET + floors * STOREY
	Carpentry.log_frame(node, Vector3.ZERO, w, d, walls, logs)
	_yard(stage, node, w, d, yard, walls)
	var front = d * 0.5 + 0.8
	var ridge = Carpentry.gable_roof(node, walls, w, -d * 0.5 - yard - 0.5, front, PITCH, roof)
	# Street gable: boards with the window of the attic room (светёлка).
	var face_z = d * 0.5 + 0.14
	if rng.randf() < 0.35:
		# Some facades are boarded and painted.
		var paint: Color = PAINT[rng.randi() % PAINT.size()]
		Props.box(node, Vector3(0, walls * 0.5, d * 0.5 + 0.17), Vector3(w + 0.66, walls, 0.08), paint)
		for sx in [-1.0, 1.0]:
			Props.box(node, Vector3(sx * (w * 0.5 + 0.3), walls * 0.5, d * 0.5 + 0.23), Vector3(0.18, walls, 0.06), surround)
		face_z = d * 0.5 + 0.2
	Carpentry.gable(node, d * 0.5 + 0.16, w, walls, ridge - 0.1, 0.2, logs.lightened(0.12))
	Carpentry.gable(node, -d * 0.5 - yard + 0.1, w, walls, ridge - 0.1, 0.2, BOARDS)
	Carpentry.window(node, Vector3(0, walls + (ridge - walls) * 0.36, d * 0.5 + 0.18), Vector2(0.62, 0.78), surround, shutters, false)
	Carpentry.barge_boards(node, front, walls, w, PITCH, surround)
	Carpentry.ridge_log(node, ridge, -d * 0.5 - yard - 0.5, front, logs.darkened(0.15))
	_windows(node, w, d, floors, face_z, surround, shutters, int(s))
	# Brick chimney through the roof of the living part.
	var chimney = Vector3(w * 0.18, 0, -d * 0.18)
	var chimney_top = ridge + 0.9
	Props.box(node, Vector3(chimney.x, (walls + chimney_top) * 0.5, chimney.z), Vector3(0.62, chimney_top - walls, 0.62), Color("8a4b3a"))
	Props.box(node, Vector3(chimney.x, chimney_top + 0.06, chimney.z), Vector3(0.76, 0.12, 0.76), SNOW)
	biome.chimneys.append(node.position + node.basis * Vector3(chimney.x, chimney_top + 0.2, chimney.z))
	_porch(stage, node, w, -d * 0.5 - 1.0, roof, logs)
	stage.solids.solid(node, Vector3(0, walls * 0.5, -yard * 0.5), Vector3(w + 0.3, walls, d + yard), "building")
	return node

# Sets the node on the micro-terrain and skirts the footprint (half width
# `half_x`, from z = back to z = front) with a stone plinth down into the snow.
static func _level(stage, node: Node3D, half_x: float, front: float, back: float) -> void:
	var low = INF
	var high = -INF
	for corner in [Vector3(half_x, 0, front), Vector3(-half_x, 0, front), Vector3(half_x, 0, back), Vector3(-half_x, 0, back), Vector3(0, 0, (front + back) * 0.5)]:
		var height = stage.ground(node.position + node.basis * corner)
		low = minf(low, height)
		high = maxf(high, height)
	node.position.y = lerpf(low, high, 0.6)
	var depth = node.position.y - low + 0.5
	Props.box(node, Vector3(0, 0.08 - depth * 0.5, (front + back) * 0.5), Vector3(half_x * 2.0, depth + 0.16, front - back), Color("6a6660"))

# The covered farmyard: plank walls the height of the house under the same roof.
static func _yard(stage, node: Node3D, w: float, d: float, yard: float, walls: float) -> void:
	var z = -d * 0.5 - yard * 0.5
	Props.box(node, Vector3(0, walls * 0.5, z), Vector3(w, walls, yard), BOARDS)
	for sx in [-1.0, 1.0]:
		for i in range(int(yard / 0.9) + 1):
			Props.box(node, Vector3(sx * (w * 0.5 + 0.02), walls * 0.5, z - yard * 0.5 + i * 0.9), Vector3(0.05, walls, 0.07), BOARDS.darkened(0.2))
	# Yard gate (ворота) under a small canopy.
	var gate_z = -d * 0.5 - yard * 0.62
	Props.box(node, Vector3(w * 0.5 + 0.06, 1.3, gate_z), Vector3(0.08, 2.6, 2.8), Color("4f4438"))
	Props.box(node, Vector3(w * 0.5 + 0.11, 1.3, gate_z), Vector3(0.04, 2.6, 0.07), Color("2f2a24"))
	var canopy = Props.box(node, Vector3(w * 0.5 + 0.42, 2.95, gate_z), Vector3(0.95, 0.08, 3.3), Color("5a564f"))
	canopy.rotation.z = -0.3
	Props.box(canopy, Vector3(0, 0.08, 0), Vector3(0.9, 0.08, 3.25), SNOW)
	# Firewood stacked along the other yard wall.
	Props.box(node, Vector3(-w * 0.5 - 0.42, 0.75, z), Vector3(0.7, 1.5, yard * 0.7), Color("a3845d"))
	Props.box(node, Vector3(-w * 0.5 - 0.42, 1.55, z), Vector3(0.74, 0.12, yard * 0.7 + 0.04), SNOW)
	stage.solids.solid(node, Vector3(-w * 0.5 - 0.42, 0.8, z), Vector3(0.74, 1.6, yard * 0.7 + 0.04), "wall")

static func _windows(node: Node3D, w: float, d: float, floors: int, face_z: float, surround: Color, shutters: Color, seed: int) -> void:
	var columns = 3 if w >= 6.8 else 2
	for floor in range(floors):
		var y = PODKLET + floor * STOREY + 1.35
		for c in range(columns):
			var x = (float(c) - (columns - 1) * 0.5) * w * 0.3
			Carpentry.window(node, Vector3(x, y, face_z), Vector2(0.78, 1.0), surround, shutters, (c + floor + seed) % 4 == 1)
		for sx in [-1.0, 1.0]:
			for z in [d * 0.5 - 1.5, d * 0.5 - 3.7]:
				Carpentry.side_window(node, Vector3(sx * (w * 0.5 + 0.12), y, z), Vector2(0.72, 0.94), surround, shutters, false, sx)
	# Small basement windows.
	for x in [-w * 0.25, w * 0.25]:
		Props.box(node, Vector3(x, 0.85, face_z + 0.03), Vector3(0.62, 0.48, 0.05), surround)
		Props.box(node, Vector3(x, 0.85, face_z + 0.06), Vector3(0.48, 0.34, 0.03), Color("26323a"))

# Covered porch (крыльцо) on the +X wall at z: a log-boxed landing at the
# height of the living floor, a flight of steps down towards the street and
# a lean-to roof on two posts.
static func _porch(stage, node: Node3D, w: float, z: float, roof: Color, logs: Color) -> void:
	var x = w * 0.5 + 0.03
	Props.box(node, Vector3(x + 0.8, PODKLET * 0.5, z), Vector3(1.6, PODKLET, 1.7), logs.darkened(0.1))
	Props.box(node, Vector3(x + 0.8, PODKLET + 0.04, z), Vector3(1.7, 0.08, 1.8), Color("7a6650"))
	stage.solids.solid(node, Vector3(x + 0.8, PODKLET * 0.5 + 0.04, z), Vector3(1.7, PODKLET + 0.08, 1.8), "building")
	var steps = 5
	for i in range(steps):
		var top = PODKLET * float(steps - i) / (steps + 1)
		Props.box(node, Vector3(x + 0.8, top * 0.5, z + 1.0 + i * 0.32), Vector3(1.3, top, 0.32), Color("7a6650"))
		# Each step is its own box, so the flight keeps its stepped shape.
		stage.solids.solid(node, Vector3(x + 0.8, top * 0.5, z + 1.0 + i * 0.32), Vector3(1.3, top, 0.32), "building")
	for post_z in [z - 0.75, z + 0.75]:
		Props.box(node, Vector3(x + 1.55, PODKLET + 1.15, post_z), Vector3(0.14, 2.3, 0.14), logs)
	var lean = Props.box(node, Vector3(x + 0.85, PODKLET + 2.42, z), Vector3(1.95, 0.1, 2.0), roof)
	lean.rotation.z = -0.24
	Props.box(lean, Vector3(0, 0.09, 0), Vector3(1.9, 0.08, 1.95), SNOW)
	Props.box(node, Vector3(x + 0.03, PODKLET + 1.0, z), Vector3(0.06, 1.9, 0.9), Color("4a3b2c"))
