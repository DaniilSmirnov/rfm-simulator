extends RefCounted
# Furnished ground floors behind see-through street windows. Most village
# houses are one solid block with dark panes; every few street-front houses
# instead get a hollow ground floor whose street windows are real glass, so a
# passer-by looks into a Provençal living room: tiled floor, beamed ceiling,
# dining table with chairs, dresser with plates, fireplace, armchair, picture
# and clock, and a pendant lamp over the table. At night the lamp shade glows
# and the nearest few rooms get a warm light (NightLights "lamp") that falls
# out through the glass onto the pavement.
# House frame (village_architecture.gd house()): facade at z = 0, rooms toward
# +Z, ground at y = 0, storey height FLOOR. Walls are plain boxes for the
# batcher; the glass and the night glow stay their own nodes ("unbatched").
const Props = preload("res://scripts/core/props.gd")
const Glass = preload("res://scripts/core/glass.gd")
const NightLights = preload("res://scripts/core/night_lights.gd")
const WALL = 0.3
const FLOOR_Y = 0.12
const PANE = Vector2(0.82, 1.38)
const SILL_Y = 1.45 # centre of a ground-floor window
const PLASTER = Color("efe5cf")
const TILES = Color("b56a4b")
const BEAMS = Color("5a3e2c")
const WOOD = Color("7a5236")
const DARK_WOOD = Color("4d3424")
const STONE = Color("cdbd9e")

# True for the street-front houses that get a room (not shops, ~1 in 3).
static func furnished(seed_value: int, shop: Dictionary) -> bool:
	return shop.is_empty() and seed_value < 500 and seed_value % 3 == 0

# The house mass up to the eaves. A furnished house is hollow on the ground
# floor with openings at the window bays; others stay one block.
static func mass(root: Node3D, width: float, depth: float, height: float, bottom: float, floor_h: float, wall: Color, seed_value: int, shop: Dictionary) -> void:
	if not furnished(seed_value, shop):
		Props.box(root, Vector3(0, (height + bottom) * 0.5, depth * 0.5), Vector3(width, height - bottom, depth), wall)
		return
	root.set_meta("room", true)
	var bays = maxi(1, int((width - 0.6) / 2.3))
	var spacing = width / bays
	var door_bay = seed_value % bays
	var holes: Array = []
	for bay in range(bays):
		if bay != door_bay:
			holes.append(-width * 0.5 + spacing * (bay + 0.5))
	# Under the floor, above the ceiling, back and side walls.
	Props.box(root, Vector3(0, (FLOOR_Y + bottom) * 0.5, depth * 0.5), Vector3(width, FLOOR_Y - bottom, depth), wall)
	Props.box(root, Vector3(0, (height + floor_h) * 0.5, depth * 0.5), Vector3(width, height - floor_h, depth), wall)
	var room_h = floor_h - FLOOR_Y
	var mid_y = FLOOR_Y + room_h * 0.5
	Props.box(root, Vector3(0, mid_y, depth - WALL * 0.5), Vector3(width, room_h, WALL), wall)
	for side in [-1.0, 1.0]:
		Props.box(root, Vector3(side * (width - WALL) * 0.5, mid_y, depth * 0.5), Vector3(WALL, room_h, depth - WALL * 2.0), wall)
	_front(root, width, floor_h, holes, wall)
	_room(root, width, depth, floor_h, holes, seed_value)

# Facade wall split round the window openings.
static func _front(root: Node3D, width: float, floor_h: float, holes: Array, wall: Color) -> void:
	var low = SILL_Y - PANE.y * 0.5
	var high = SILL_Y + PANE.y * 0.5
	var x = -width * 0.5
	for hole in holes + [width * 0.5 + PANE.x * 0.5]:
		var left = hole - PANE.x * 0.5
		if left - x > 0.01:
			Props.box(root, Vector3((x + left) * 0.5, (FLOOR_Y + floor_h) * 0.5, WALL * 0.5), Vector3(left - x, floor_h - FLOOR_Y, WALL), wall)
		if hole < width * 0.5:
			Props.box(root, Vector3(hole, (FLOOR_Y + low) * 0.5, WALL * 0.5), Vector3(PANE.x, low - FLOOR_Y, WALL), wall)
			Props.box(root, Vector3(hole, (high + floor_h) * 0.5, WALL * 0.5), Vector3(PANE.x, floor_h - high, WALL), wall)
			# Inner window board.
			Props.box(root, Vector3(hole, low - 0.02, WALL + 0.06), Vector3(PANE.x + 0.12, 0.04, 0.14), Color("e9e1cd"))
		x = hole + PANE.x * 0.5

# Window pane of village_architecture.gd window(): glass on the ground floor of
# a furnished house's street facade, the usual dark pane everywhere else.
static func pane(w: Node3D, parent: Node3D, p: Vector3) -> void:
	var pane_node = Props.box(w, Vector3(0, 0, 0.02), Vector3(0.82, 1.38, 0.06), Color("3e4a4c"))
	if parent.get_meta("room", false) and p.y < 3.0 and absf(p.z) < 0.01 and absf(w.rotation.y) < 0.01:
		Glass.glaze(pane_node)
		pane_node.set_meta("unbatched", true)
		pane_node.name = "WindowGlass"

static func _room(root: Node3D, width: float, depth: float, floor_h: float, holes: Array, seed_value: int) -> void:
	var inner = Vector2(width * 0.5 - WALL, depth - WALL)
	var top = floor_h - 0.02
	# Plaster on the inner faces, terracotta floor with joints, beamed ceiling.
	Props.box(root, Vector3(0, FLOOR_Y + 0.005, (WALL + inner.y) * 0.5), Vector3(inner.x * 2.0, 0.01, inner.y - WALL), TILES)
	for i in range(1, int(inner.x * 2.0 / 0.5)):
		Props.box(root, Vector3(-inner.x + i * 0.5, FLOOR_Y + 0.012, (WALL + inner.y) * 0.5), Vector3(0.015, 0.004, inner.y - WALL), TILES.darkened(0.25))
	Props.box(root, Vector3(0, (FLOOR_Y + top) * 0.5, inner.y - 0.005), Vector3(inner.x * 2.0, top - FLOOR_Y, 0.01), PLASTER)
	for side in [-1.0, 1.0]:
		Props.box(root, Vector3(side * (inner.x - 0.005), (FLOOR_Y + top) * 0.5, (WALL + inner.y) * 0.5), Vector3(0.01, top - FLOOR_Y, inner.y - WALL), PLASTER.darkened(0.04))
	Props.box(root, Vector3(0, top - 0.005, (WALL + inner.y) * 0.5), Vector3(inner.x * 2.0, 0.01, inner.y - WALL), PLASTER.lightened(0.1))
	var beam_z = WALL + 0.45
	while beam_z < inner.y - 0.2:
		Props.box(root, Vector3(0, top - 0.09, beam_z), Vector3(inner.x * 2.0, 0.16, 0.14), BEAMS)
		beam_z += 0.9
	# Curtains tied back beside each street window.
	for hole in holes:
		_curtains(root, hole, seed_value)
	# The table is where the windows look: centred on the window bays.
	var table_x = 0.0
	for hole in holes:
		table_x += hole / holes.size()
	table_x = clampf(table_x, -inner.x + 1.4, inner.x - 1.4)
	var table = Vector3(table_x, FLOOR_Y, WALL + minf(2.4, inner.y * 0.35))
	_table(root, table, seed_value)
	_lamp(root, table + Vector3(0, top - FLOOR_Y, 0))
	_dresser(root, Vector3(table_x, FLOOR_Y, inner.y - 0.28), seed_value)
	var fire_side = -1.0 if seed_value % 2 == 0 else 1.0
	_fireplace(root, Vector3(fire_side * (inner.x - 0.25), FLOOR_Y, WALL + inner.y * 0.55), fire_side)
	_armchair(root, Vector3(-fire_side * (inner.x - 0.6), FLOOR_Y, WALL + inner.y * 0.55), fire_side)
	# A framed landscape over the armchair and a clock on the back wall.
	var picture = Vector3(-fire_side * (inner.x - 0.02), 1.75, WALL + inner.y * 0.55)
	Props.box(root, picture, Vector3(0.04, 0.62, 0.86), Color("a37b3e"))
	Props.box(root, picture + Vector3(fire_side * 0.022, 0.05, 0), Vector3(0.01, 0.3, 0.74), Color("8fb3c9"))
	Props.box(root, picture + Vector3(fire_side * 0.022, -0.16, 0), Vector3(0.01, 0.2, 0.74), Color("9a8a46"))
	var clock = Props.cylinder(root, Vector3(table_x + 1.3, 2.25, inner.y - 0.03), 0.17, 0.17, 0.04, Color("efe9da"), 12)
	clock.rotation.x = PI / 2
	Props.box(root, Vector3(table_x + 1.3, 2.29, inner.y - 0.06), Vector3(0.015, 0.11, 0.01), Color("2b2b2b"))
	Props.box(root, Vector3(table_x + 1.33, 2.25, inner.y - 0.06), Vector3(0.07, 0.015, 0.01), Color("2b2b2b"))
	# Rug under the table.
	Props.box(root, table + Vector3(0, 0.012, 0), Vector3(2.4, 0.012, 1.7), Color("8c3b33") if seed_value % 2 else Color("3f5d6e"))
	Props.box(root, table + Vector3(0, 0.016, 0), Vector3(2.0, 0.012, 1.3), Color("c9a86a"))

static func _curtains(root: Node3D, x: float, seed_value: int) -> void:
	var cloth = [Color("c7553f"), Color("e7dcc2"), Color("6f8c6a"), Color("d0a24c")][posmod(seed_value / 3, 4)]
	var y = SILL_Y + 0.05
	for side in [-1.0, 1.0]:
		Props.box(root, Vector3(x + side * (PANE.x * 0.5 + 0.12), y, WALL + 0.06), Vector3(0.26, PANE.y + 0.3, 0.05), cloth)
	Props.box(root, Vector3(x, SILL_Y + PANE.y * 0.5 + 0.22, WALL + 0.05), Vector3(PANE.x + 0.7, 0.03, 0.03), DARK_WOOD)

static func _table(root: Node3D, at: Vector3, seed_value: int) -> void:
	Props.box(root, at + Vector3(0, 0.76, 0), Vector3(1.6, 0.05, 0.9), WOOD)
	for x in [-0.72, 0.72]:
		for z in [-0.38, 0.38]:
			Props.box(root, at + Vector3(x, 0.37, z), Vector3(0.06, 0.74, 0.06), DARK_WOOD)
	# Checked cloth runner, a jug and a fruit bowl.
	Props.box(root, at + Vector3(0, 0.79, 0), Vector3(1.62, 0.006, 0.36), Color("d64b3c") if seed_value % 2 else Color("3f78a8"))
	Props.cylinder(root, at + Vector3(-0.3, 0.88, 0), 0.06, 0.05, 0.17, Color("e9e2d2"), 8)
	Props.cylinder(root, at + Vector3(0.25, 0.82, 0.05), 0.08, 0.13, 0.06, Color("c58a4a"), 10)
	for i in range(3):
		Props.box(root, at + Vector3(0.21 + i * 0.05, 0.87, 0.03 + (i % 2) * 0.05), Vector3(0.06, 0.06, 0.06), [Color("e0a13a"), Color("b83a32"), Color("8bb043")][i])
	# Four rush-seat chairs, two on each long side.
	for x in [-0.4, 0.4]:
		for side in [-1.0, 1.0]:
			var chair = at + Vector3(x, 0, side * 0.68)
			Props.box(root, chair + Vector3(0, 0.45, 0), Vector3(0.42, 0.05, 0.42), Color("c9a660"))
			for dx in [-0.18, 0.18]:
				for dz in [-0.18, 0.18]:
					Props.box(root, chair + Vector3(dx, 0.22, dz), Vector3(0.04, 0.44, 0.04), DARK_WOOD)
				Props.box(root, chair + Vector3(dx, 0.75, side * 0.19), Vector3(0.04, 0.6, 0.04), DARK_WOOD)
			for y in [0.7, 0.88]:
				Props.box(root, chair + Vector3(0, y, side * 0.19), Vector3(0.4, 0.05, 0.03), DARK_WOOD)

# Pendant lamp: cord, conical shade and a bulb that glows at night; the node
# carries the room's night light.
static func _lamp(root: Node3D, ceiling: Vector3) -> void:
	var drop = 0.75
	Props.box(root, ceiling - Vector3(0, drop * 0.5, 0), Vector3(0.012, drop, 0.012), Color("2b2b2b"))
	var shade = Props.cylinder(root, ceiling - Vector3(0, drop + 0.08, 0), 0.26, 0.07, 0.16, Color("e7d9a9"), 12)
	shade.name = "LampShade"
	var light = Node3D.new()
	light.name = "RoomLamp"
	light.set_meta("unbatched", true)
	root.add_child(light)
	light.position = ceiling - Vector3(0, drop + 0.1, 0)
	NightLights.mark(light, "lamp")
	var glow = Props.box(light, Vector3(0, -0.02, 0), Vector3(0.36, 0.05, 0.36), Color("ffd98a"))
	glow.name = "LampGlow"
	glow.material_override = NightLights.glow_material()
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	NightLights.glow(glow)

# Provençal dresser: cupboard below, open plate rack above.
static func _dresser(root: Node3D, at: Vector3, seed_value: int) -> void:
	var paint = [Color("7c9a8e"), Color("a7b7a0"), WOOD, Color("8fa7b8")][posmod(seed_value, 4)]
	Props.box(root, at + Vector3(0, 0.45, 0), Vector3(1.8, 0.9, 0.5), paint)
	for x in [-0.45, 0.45]:
		Props.box(root, at + Vector3(x, 0.48, -0.26), Vector3(0.8, 0.7, 0.02), paint.darkened(0.12))
		Props.box(root, at + Vector3(x + (0.3 if x < 0 else -0.3), 0.5, -0.28), Vector3(0.03, 0.1, 0.03), Color("c9a95b"))
	Props.box(root, at + Vector3(0, 0.92, 0), Vector3(1.86, 0.04, 0.54), WOOD)
	for x in [-0.88, 0.88]:
		Props.box(root, at + Vector3(x, 1.5, 0.1), Vector3(0.05, 1.1, 0.25), paint)
	for y in [1.3, 1.75, 2.05]:
		Props.box(root, at + Vector3(0, y, 0.1), Vector3(1.8, 0.03, 0.26), paint)
	for i in range(6):
		for row in [1.3, 1.75]:
			var plate = Props.cylinder(root, at + Vector3(-0.7 + i * 0.28, row + 0.13, 0.12), 0.11, 0.11, 0.02, Color("f1ece0") if (i + int(row * 4)) % 3 else Color("4f7fa8"), 10)
			plate.rotation.x = PI / 2 - 0.2

static func _fireplace(root: Node3D, at: Vector3, side: float) -> void:
	# Stone hearth against the side wall with a dark opening, mantel and logs.
	Props.box(root, at + Vector3(0, 0.6, 0), Vector3(0.5, 1.2, 1.5), STONE)
	Props.box(root, at + Vector3(-side * 0.255, 0.45, 0), Vector3(0.02, 0.7, 0.9), Color("1e1a17"))
	Props.box(root, at + Vector3(-side * 0.1, 1.25, 0), Vector3(0.75, 0.1, 1.7), DARK_WOOD)
	Props.box(root, at + Vector3(side * 0.05, 2.0, 0), Vector3(0.4, 1.5, 1.1), STONE.darkened(0.05))
	for i in range(2):
		var log_node = Props.cylinder(root, at + Vector3(-side * 0.3, 0.17 + i * 0.1, 0.1 - i * 0.12), 0.06, 0.06, 0.6, Color("6b4a2f"), 6)
		log_node.rotation.x = PI / 2
	Props.cylinder(root, at + Vector3(-side * 0.1, 1.38, -0.4), 0.06, 0.05, 0.16, Color("3f6e9a"), 8)
	Props.cylinder(root, at + Vector3(-side * 0.1, 1.36, 0.45), 0.05, 0.05, 0.12, Color("c9a95b"), 8)

static func _armchair(root: Node3D, at: Vector3, side: float) -> void:
	var cloth = Color("6e7f4c")
	Props.box(root, at + Vector3(0, 0.25, 0), Vector3(0.8, 0.3, 0.8), cloth)
	Props.box(root, at + Vector3(-side * 0.35, 0.65, 0), Vector3(0.18, 0.75, 0.8), cloth.darkened(0.1))
	for dz in [-0.36, 0.36]:
		Props.box(root, at + Vector3(0, 0.5, dz), Vector3(0.8, 0.22, 0.12), cloth.darkened(0.05))
	Props.box(root, at + Vector3(side * 0.05, 0.44, 0), Vector3(0.6, 0.1, 0.6), cloth.lightened(0.12))
