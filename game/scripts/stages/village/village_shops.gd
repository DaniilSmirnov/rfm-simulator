extends RefCounted
# Village shops you can look into: the ground floor of every shop house (and
# of the café) is hollow behind a real glass shop window and a glazed door,
# and the shop is built in geometry, stocked by trade: the baker's loaves and
# baguettes, the tabac's newspapers and magazines, the pharmacy's boxes, the
# grocer's fruit crates, the soap maker's bars and lavender, the wine cellar's
# racks of bottles, the butcher's chilled counter and hams, the post office's
# parcels, the antique dealer's furniture, the café's bar and tables. Shelves
# line the back and one side wall, a counter with a till stands on the other
# side, a display table sits behind the window; two pendant lamps light it at
# night (village_rooms.gd lamp, NightLights "lamp").
# House frame as in village_rooms.gd: facade at z = 0, rooms toward +Z.
const Props = preload("res://scripts/core/props.gd")
const Glass = preload("res://scripts/core/glass.gd")
const NightLights = preload("res://scripts/core/night_lights.gd")
const WALL = 0.3
const FLOOR_Y = 0.12
const PLASTER = Color("f1ead8")
const WOOD = Color("7a5236")
const DARK_WOOD = Color("4d3424")
const IRON = Color("2e3330")
# Trade by sign; the default sells groceries.
const TRADES = {"BOULANGERIE": "bread", "TABAC · PRESSE": "tabac", "PHARMACIE": "pharmacy", "ÉPICERIE": "fruit", "SAVONNERIE": "soap",
	"CAVE À VINS": "wine", "BOUCHERIE": "meat", "LA POSTE": "post", "ANTIQUITÉS": "antiques", "CAFÉ DE LA PLACE": "cafe"}
const FLOORS = {"bread": [Color("d9cdb4"), Color("8a5a3a")], "pharmacy": [Color("eef0ec"), Color("9fb5a8")], "meat": [Color("f0eee8"), Color("b5463a")],
	"wine": [Color("9a6a4a"), Color("5c3a28")], "cafe": [Color("e8e2d2"), Color("2f3134")], "post": [Color("dedad0"), Color("6c7a8c")]}

static func trade(shop: Dictionary) -> String:
	return TRADES.get(str(shop.get("text", "")), "fruit")

# Openings of the shopfront as [x0, x1, y0, y1]: the shop window and the glass
# in the upper part of the door.
static func openings(width: float) -> Array:
	var half = (width * 0.5 - 0.4) * 0.5
	var door = width * 0.25 + 0.15
	return [[-0.6 - half, -0.6 + half, 0.3, 2.2], [door - 0.33, door + 0.33, 1.0, 2.0]]

# How far a hollow house at `pose` must rise so the ground behind its facade
# stays under its floor (base height `base`).
static func lift(stage, pose: Transform3D, width: float, depth: float, base: float) -> float:
	var highest = 0.0
	for x in [-width * 0.4, 0.0, width * 0.4]:
		for z in [1.0, depth * 0.5, depth - 0.8]:
			highest = maxf(highest, stage.ground(pose * Vector3(x, 0, z)) - base)
	return maxf(highest - 0.06, 0.0)

# The hollow ground floor of a shop house, with its shopfront and its shop.
static func mass(root: Node3D, width: float, depth: float, height: float, bottom: float, floor_h: float, wall: Color, shop: Dictionary) -> void:
	root.set_meta("shop_room", trade(shop))
	Props.box(root, Vector3(0, (FLOOR_Y + bottom) * 0.5, depth * 0.5), Vector3(width, FLOOR_Y - bottom, depth), wall)
	Props.box(root, Vector3(0, (height + floor_h) * 0.5, depth * 0.5), Vector3(width, height - floor_h, depth), wall)
	var room_h = floor_h - FLOOR_Y
	var mid_y = FLOOR_Y + room_h * 0.5
	Props.box(root, Vector3(0, mid_y, depth - WALL * 0.5), Vector3(width, room_h, WALL), wall)
	for side in [-1.0, 1.0]:
		Props.box(root, Vector3(side * (width - WALL) * 0.5, mid_y, depth * 0.5), Vector3(WALL, room_h, depth - WALL * 2.0), wall)
	var holes = openings(width)
	_holed(root, -width * 0.5, width * 0.5, FLOOR_Y, floor_h, WALL * 0.5, WALL, holes, wall)
	_front(root, width, holes, Color("6b3e2e") if str(shop.text) == "BOULANGERIE" else Color("4a5b55"))
	_room(root, width, depth, floor_h, trade(shop))

# A wall in the plane z (thickness `thick`) from x0..x1, y0..y1 with
# rectangular holes, as horizontal bands of boxes.
static func _holed(root: Node3D, x0: float, x1: float, y0: float, y1: float, z: float, thick: float, holes: Array, color: Color) -> void:
	var cuts = [y0, y1]
	for hole in holes:
		cuts.append_array([clampf(hole[2], y0, y1), clampf(hole[3], y0, y1)])
	cuts.sort()
	for i in range(cuts.size() - 1):
		var lo: float = cuts[i]
		var hi: float = cuts[i + 1]
		if hi - lo < 0.005:
			continue
		var spans = []
		for hole in holes:
			if hole[2] < hi - 0.001 and hole[3] > lo + 0.001:
				spans.append([hole[0], hole[1]])
		spans.sort_custom(func(a, b): return a[0] < b[0])
		var x = x0
		for span in spans + [[x1, x1]]:
			if span[0] - x > 0.005:
				Props.box(root, Vector3((x + span[0]) * 0.5, (lo + hi) * 0.5, z), Vector3(span[0] - x, hi - lo, thick), color)
			x = maxf(x, span[1])

# Painted shopfront frame around the openings, the glass, glazing bars and
# the door leaf with its handle and kick plate.
static func _front(root: Node3D, width: float, holes: Array, frame: Color) -> void:
	_holed(root, -(width - 0.8) * 0.5, (width - 0.8) * 0.5, 0.1, 2.8, -0.04, 0.08, holes, frame)
	var window: Array = holes[0]
	var door: Array = holes[1]
	for hole in holes:
		var pane = Props.box(root, Vector3((hole[0] + hole[1]) * 0.5, (hole[2] + hole[3]) * 0.5, -0.02), Vector3(hole[1] - hole[0], hole[3] - hole[2], 0.02), Color("6f8e94"))
		Glass.glaze(pane)
		pane.set_meta("unbatched", true)
		pane.name = "ShopGlass"
	# Transom bar and a stall riser below the window.
	Props.box(root, Vector3((window[0] + window[1]) * 0.5, 1.88, -0.06), Vector3(window[1] - window[0], 0.05, 0.05), frame.darkened(0.2))
	for t in [0.33, 0.66]:
		Props.box(root, Vector3(lerpf(window[0], window[1], t), 2.04, -0.06), Vector3(0.04, 0.32, 0.05), frame.darkened(0.2))
	# The door leaf: solid below its glass, frame round it.
	var x = (door[0] + door[1]) * 0.5
	_holed(root, x - 0.5, x + 0.5, 0.1, 2.2, -0.07, 0.04, [door], Color("324441"))
	Props.box(root, Vector3(x, 0.3, -0.095), Vector3(0.9, 0.3, 0.01), Color("b39a5a"))
	Props.box(root, Vector3(x + 0.38, 1.05, -0.11), Vector3(0.04, 0.22, 0.04), Color("c9a95b"))

static func _room(root: Node3D, width: float, depth: float, floor_h: float, kind: String) -> void:
	var inner = Vector2(width * 0.5 - WALL, depth - WALL)
	var top = floor_h - 0.02
	var colors: Array = FLOORS.get(kind, [Color("d8ccb0"), Color("a86b4a")])
	# Tiled floor in a checker of two colours, plaster walls, a light ceiling.
	Props.box(root, Vector3(0, FLOOR_Y + 0.005, (WALL + inner.y) * 0.5), Vector3(inner.x * 2.0, 0.01, inner.y - WALL), colors[0])
	var tile = 0.5
	var rows = int((inner.y - WALL) / tile)
	for row in range(rows):
		for col in range(int(inner.x * 2.0 / tile)):
			if (row + col) % 2 == 0:
				continue
			Props.box(root, Vector3(-inner.x + (col + 0.5) * tile, FLOOR_Y + 0.011, WALL + (row + 0.5) * tile), Vector3(tile, 0.004, tile), colors[1])
	Props.box(root, Vector3(0, (FLOOR_Y + top) * 0.5, inner.y - 0.005), Vector3(inner.x * 2.0, top - FLOOR_Y, 0.01), PLASTER)
	for side in [-1.0, 1.0]:
		Props.box(root, Vector3(side * (inner.x - 0.005), (FLOOR_Y + top) * 0.5, (WALL + inner.y) * 0.5), Vector3(0.01, top - FLOOR_Y, inner.y - WALL), PLASTER.darkened(0.04))
	Props.box(root, Vector3(0, top - 0.005, (WALL + inner.y) * 0.5), Vector3(inner.x * 2.0, 0.01, inner.y - WALL), PLASTER.lightened(0.1))
	# Two pendant lamps; the front one lights the street at night.
	_lamp(root, Vector3(-0.6, top, WALL + 1.6), true)
	_lamp(root, Vector3(0.4, top, inner.y - 2.2), false)
	var floor = Vector3(0, FLOOR_Y, 0)
	if kind == "cafe":
		_cafe(root, inner, floor)
		return
	# Shelving along the back wall and the left wall, a counter on the right.
	var back = floor + Vector3(0, 0, inner.y - 0.25)
	_shelves(root, back, Vector3(inner.x * 2.0 - 0.3, 0, 0), kind)
	_shelves(root, floor + Vector3(-inner.x + 0.25, 0, (WALL + 1.5 + inner.y - 0.7) * 0.5), Vector3(0, 0, inner.y - WALL - 2.2), kind)
	var counter = floor + Vector3(inner.x - 0.75, 0, inner.y * 0.55)
	_counter(root, counter, kind)
	# The display behind the window.
	_display(root, floor + Vector3(-0.6, 0, WALL + 1.0), kind)
	_wall_piece(root, Vector3(0, 2.3, inner.y - 0.02), kind)

static func _lamp(root: Node3D, ceiling: Vector3, night: bool) -> void:
	var drop = 0.6
	Props.box(root, ceiling - Vector3(0, drop * 0.5, 0), Vector3(0.012, drop, 0.012), Color("2b2b2b"))
	Props.cylinder(root, ceiling - Vector3(0, drop + 0.08, 0), 0.22, 0.06, 0.16, Color("e9e4d6"), 12)
	var light = Node3D.new()
	light.name = "ShopLamp"
	light.set_meta("unbatched", true)
	root.add_child(light)
	light.position = ceiling - Vector3(0, drop + 0.1, 0)
	if night:
		NightLights.mark(light, "lamp")
	var glow = Props.box(light, Vector3(0, -0.02, 0), Vector3(0.3, 0.05, 0.3), Color("ffd98a"))
	glow.name = "LampGlow"
	glow.material_override = NightLights.glow_material()
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	NightLights.glow(glow)

# A shelving unit standing at `at` (feet, centre) running along `run`.
static func _shelves(root: Node3D, at: Vector3, run: Vector3, kind: String) -> void:
	var length = run.length()
	if length < 0.6:
		return
	var along = run / length
	var across = Vector3(along.z, 0, -along.x) # toward the room
	var deep = 0.36
	var wood = Color("e8e3d6") if kind == "pharmacy" else (DARK_WOOD if kind in ["wine", "antiques"] else WOOD)
	var size_along = func(a: float, h: float, d: float) -> Vector3: return Vector3(absf(along.x) * a + absf(along.z) * d, h, absf(along.z) * a + absf(along.x) * d)
	for i in range(int(length / 1.1) + 1):
		var t = -length * 0.5 + length * float(i) / int(length / 1.1)
		Props.box(root, at + along * t + Vector3(0, 1.2, 0), size_along.call(0.04, 2.4, deep), wood.darkened(0.15))
	Props.box(root, at + Vector3(0, 1.2, 0) - across * (deep * 0.5 - 0.01), size_along.call(length, 2.4, 0.02), wood.darkened(0.25))
	var levels = [0.15, 0.6, 1.05, 1.5, 1.95]
	for level in range(levels.size()):
		var y: float = levels[level]
		Props.box(root, at + Vector3(0, y, 0), size_along.call(length, 0.03, deep), wood)
		var count = int(length / 0.2)
		for k in range(count):
			var t = -length * 0.5 + (k + 0.5) * length / count
			_item(root, at + along * t + Vector3(0, y + 0.015, 0), along, kind, k * 7 + level * 13)

# One article of stock standing on a shelf at `at` (its foot).
static func _item(root: Node3D, at: Vector3, along: Vector3, kind: String, n: int) -> void:
	var pick = posmod(n * 2654435761, 97)
	var ox = along * (0.0 if pick % 3 else 0.03)
	match kind:
		"bread":
			if pick % 4 == 0:
				return
			var loaf = Props.box(root, at + ox + Vector3(0, 0.06, 0), Vector3(0.17, 0.11, 0.17), Color("c98a43").lightened((pick % 5) * 0.04))
			loaf.rotation.y = pick * 0.3
			Props.box(root, at + ox + Vector3(0, 0.12, 0), Vector3(0.12, 0.02, 0.12), Color("e0b066"))
		"tabac":
			# Magazines and papers leaning in racks; boxes of sweets lower down.
			var colors = [Color("d23a32"), Color("2f5e9a"), Color("e8c040"), Color("f0ece0"), Color("3a8a4e"), Color("8a3a8a")]
			var mag = Props.box(root, at + ox + Vector3(0, 0.16, 0), Vector3(0.16, 0.3, 0.16) if absf(along.x) < 0.5 else Vector3(0.16, 0.3, 0.02), colors[pick % colors.size()])
			mag.rotation.x = 0.0
		"pharmacy":
			if pick % 5 == 0:
				return
			var colors = [Color("ffffff"), Color("cfe6f2"), Color("e3f0d8"), Color("f3e2e2")]
			Props.box(root, at + Vector3(0, 0.07 + (pick % 3) * 0.02, 0), Vector3(0.12, 0.14 + (pick % 3) * 0.04, 0.1), colors[pick % colors.size()])
			Props.box(root, at + Vector3(0, 0.1, 0) - Vector3(along.z, 0, -along.x) * 0.0, Vector3(0.05, 0.02, 0.105), Color("3d9a5c"))
		"fruit":
			if pick % 3 == 0:
				# Tins and jars.
				Props.cylinder(root, at + Vector3(0, 0.07, 0), 0.05, 0.05, 0.14, [Color("c94a3a"), Color("e3c050"), Color("4e7a5a")][pick % 3], 8)
			else:
				Props.box(root, at + Vector3(0, 0.06, 0), Vector3(0.16, 0.12, 0.28), Color("a37b50"))
				for f in range(3):
					Props.box(root, at + Vector3(0, 0.14, -0.08 + f * 0.08), Vector3(0.07, 0.06, 0.07), [Color("d9482f"), Color("e8a12a"), Color("8bb043"), Color("e8d040")][(pick + f) % 4])
		"soap":
			var colors = [Color("c9b3e0"), Color("f2e6c8"), Color("b6d6b0"), Color("f0c4c4"), Color("e8d890")]
			for s in range(2):
				Props.box(root, at + Vector3(0, 0.03 + s * 0.05, 0), Vector3(0.12, 0.05, 0.08), colors[(pick + s) % colors.size()])
		"wine":
			# Bottles lying in a wine rack, necks to the room; some standing.
			var glass = [Color("1e3a2a"), Color("3a1820"), Color("2a3a1e")][pick % 3]
			if pick % 4 == 0:
				Props.cylinder(root, at + Vector3(0, 0.12, 0), 0.04, 0.04, 0.24, glass, 8)
				Props.cylinder(root, at + Vector3(0, 0.29, 0), 0.014, 0.014, 0.1, glass, 6)
				Props.box(root, at + Vector3(0, 0.12, 0) + Vector3(along.z, 0, -along.x) * 0.041, Vector3(0.06, 0.08, 0.06) * Vector3(absf(along.x) + 0.1, 1, absf(along.z) + 0.1), Color("efe6cf"))
			else:
				for b in range(2):
					var bottle = Props.cylinder(root, at + Vector3(0, 0.05 + b * 0.09, 0), 0.04, 0.04, 0.3, glass, 8)
					bottle.rotation = Vector3(PI * 0.5, 0, 0) if absf(along.x) > 0.5 else Vector3(0, 0, PI * 0.5)
		"meat":
			# Jars of pâté and tins on the shelves.
			Props.cylinder(root, at + Vector3(0, 0.06, 0), 0.05, 0.05, 0.12, Color("e9e2d0"), 8)
			Props.cylinder(root, at + Vector3(0, 0.125, 0), 0.052, 0.052, 0.02, Color("b8382e"), 8)
		"post":
			if pick % 3 == 0:
				return
			Props.box(root, at + Vector3(0, 0.1, 0), Vector3(0.18, 0.2, 0.26), [Color("b58a52"), Color("c9a46a"), Color("f2c94c")][pick % 3])
		"antiques":
			if pick % 2 == 0:
				Props.cylinder(root, at + Vector3(0, 0.12, 0), 0.06, 0.08, 0.24, [Color("3f6e8c"), Color("e9e2d2"), Color("8a5a2a")][pick % 3], 8)
			elif pick % 3 == 0:
				Props.box(root, at + Vector3(0, 0.15, 0), Vector3(0.16, 0.3, 0.16), Color("a37b3e"))
		_:
			pass

static func _counter(root: Node3D, at: Vector3, kind: String) -> void:
	var wood = Color("e8e3d6") if kind == "pharmacy" else WOOD
	if kind == "meat":
		# Chilled glass counter: steel base, glass hood over cuts of meat.
		Props.box(root, at + Vector3(0, 0.4, 0), Vector3(0.75, 0.8, 2.6), Color("c9cdcf"))
		Props.box(root, at + Vector3(0, 0.81, 0), Vector3(0.7, 0.02, 2.5), Color("f2f2ee"))
		for i in range(8):
			Props.box(root, at + Vector3(-0.15 + (i % 2) * 0.28, 0.86, -1.05 + (i / 2) * 0.6), Vector3(0.24, 0.08, 0.4), [Color("b5383a"), Color("d76a6a"), Color("c9504a"), Color("e8b0a0")][i % 4])
		var hood = Props.box(root, at + Vector3(-0.05, 1.05, 0), Vector3(0.65, 0.4, 2.5), Color("cfe6ea"))
		Glass.glaze(hood)
		hood.set_meta("unbatched", true)
		hood.name = "ShopGlass"
		# Hams hanging from a rail behind.
		Props.box(root, at + Vector3(0.55, 2.3, 0), Vector3(0.03, 0.03, 2.6), IRON)
		for i in range(5):
			Props.cylinder(root, at + Vector3(0.55, 1.95, -1.0 + i * 0.5), 0.07, 0.12, 0.42, Color("8a4a32"), 8)
		return
	Props.box(root, at + Vector3(0, 0.45, 0), Vector3(0.65, 0.9, 2.4), wood)
	Props.box(root, at + Vector3(0, 0.92, 0), Vector3(0.75, 0.04, 2.5), wood.darkened(0.25))
	for z in [-0.6, 0.0, 0.6]:
		Props.box(root, at + Vector3(-0.33, 0.45, z), Vector3(0.01, 0.6, 0.5), wood.darkened(0.12))
	# Till, a little scale and something of the trade on the counter.
	Props.box(root, at + Vector3(0, 1.02, 0.7), Vector3(0.36, 0.16, 0.32), Color("2e3134"))
	Props.box(root, at + Vector3(-0.06, 1.14, 0.7), Vector3(0.22, 0.1, 0.02), Color("6fa08a"))
	Props.box(root, at + Vector3(0, 0.98, -0.6), Vector3(0.3, 0.08, 0.3), Color("d8d2c2"))
	Props.cylinder(root, at + Vector3(0, 1.1, -0.6), 0.14, 0.14, 0.02, Color("c9cdcf"), 12)
	match kind:
		"bread":
			for i in range(4):
				Props.box(root, at + Vector3(0, 0.98, -0.1 + i * 0.12), Vector3(0.16, 0.08, 0.1), Color("d9a05a"))
		"tabac":
			# Stack of newspapers and a jar of sweets.
			for i in range(5):
				Props.box(root, at + Vector3(0.05, 0.95 + i * 0.012, 0.1), Vector3(0.36, 0.01, 0.5), Color("efeadc").darkened(i * 0.02))
			Props.cylinder(root, at + Vector3(0, 1.05, -0.2), 0.09, 0.09, 0.22, Color("e3a0b8"), 10)
		"post":
			Props.box(root, at + Vector3(0, 1.0, 0.0), Vector3(0.4, 0.12, 0.3), Color("b58a52"))
		"wine":
			for i in range(3):
				Props.cylinder(root, at + Vector3(0, 1.08, -0.15 + i * 0.12), 0.04, 0.04, 0.3, Color("3a1820"), 8)

static func _display(root: Node3D, at: Vector3, kind: String) -> void:
	match kind:
		"antiques":
			# A chair, a dresser and a long-case clock.
			Props.box(root, at + Vector3(-0.6, 0.45, 0), Vector3(0.45, 0.05, 0.45), Color("8a5a3a"))
			Props.box(root, at + Vector3(-0.6, 0.8, 0.2), Vector3(0.45, 0.7, 0.05), Color("6a4228"))
			for dx in [-0.2, 0.2]:
				for dz in [-0.2, 0.2]:
					Props.box(root, at + Vector3(-0.6 + dx, 0.22, dz), Vector3(0.04, 0.44, 0.04), Color("6a4228"))
			Props.box(root, at + Vector3(0.5, 0.45, 0.2), Vector3(1.0, 0.9, 0.45), Color("7c5a3a"))
			Props.box(root, at + Vector3(0.5, 1.15, 0.2), Vector3(0.36, 0.5, 0.2), Color("c9a95b"))
			Props.box(root, at + Vector3(1.4, 1.0, 0.4), Vector3(0.42, 2.0, 0.3), DARK_WOOD)
			var dial = Props.cylinder(root, at + Vector3(1.4, 1.65, 0.24), 0.15, 0.15, 0.02, Color("efe9da"), 12)
			dial.rotation.x = PI / 2
			return
		"post":
			# Yellow letter box and stacked parcels.
			Props.box(root, at + Vector3(-0.3, 0.6, 0.1), Vector3(0.5, 1.2, 0.4), Color("f2c94c"))
			Props.box(root, at + Vector3(-0.3, 1.0, -0.11), Vector3(0.3, 0.04, 0.02), Color("2b2b2b"))
			for i in range(5):
				Props.box(root, at + Vector3(0.5 + (i % 2) * 0.4, 0.2 + (i / 2) * 0.32, 0), Vector3(0.38, 0.3, 0.4), Color("b58a52").lightened(i * 0.04))
			return
	# A table with a cloth, stocked by trade.
	Props.box(root, at + Vector3(0, 0.72, 0), Vector3(1.6, 0.05, 0.8), WOOD)
	for x in [-0.72, 0.72]:
		for z in [-0.32, 0.32]:
			Props.box(root, at + Vector3(x, 0.36, z), Vector3(0.06, 0.72, 0.06), DARK_WOOD)
	Props.box(root, at + Vector3(0, 0.75, 0), Vector3(1.64, 0.01, 0.84), Color("f0e8d6") if kind != "soap" else Color("cdbfe0"))
	_table_goods(root, at + Vector3(0, 0.76, 0), kind)

# The goods laid out on a display table top.
static func _table_goods(root: Node3D, top: Vector3, kind: String) -> void:
	match kind:
		"bread":
			# Baguettes upright in two baskets, round loaves between them.
			for bx in [-0.5, 0.5]:
				Props.cylinder(root, top + Vector3(bx, 0.12, 0), 0.18, 0.14, 0.24, Color("a37b50"), 10)
				for i in range(6):
					var stick = Props.cylinder(root, top + Vector3(bx + (i % 3 - 1) * 0.08, 0.38, (i / 3 - 0.5) * 0.1), 0.03, 0.03, 0.62, Color("d6a35a"), 6)
					stick.rotation.z = (i % 3 - 1) * 0.12
			for i in range(3):
				Props.cylinder(root, top + Vector3(-0.12 + i * 0.12, 0.05, 0.15), 0.1, 0.11, 0.1, Color("b8783a"), 10)
		"tabac":
			# A wire rack of postcards and the day's papers in a row.
			for i in range(6):
				Props.box(root, top + Vector3(-0.65 + i * 0.26, 0.012, -0.05), Vector3(0.24, 0.02, 0.34), [Color("efeadc"), Color("d23a32"), Color("2f5e9a")][i % 3])
			Props.box(root, top + Vector3(0.5, 0.4, 0.2), Vector3(0.03, 0.8, 0.03), IRON)
			for i in range(4):
				Props.box(root, top + Vector3(0.5, 0.2 + i * 0.16, 0.18), Vector3(0.36, 0.12, 0.01), [Color("6fa0c8"), Color("e8c040"), Color("8bb043"), Color("e07a5a")][i])
		"pharmacy":
			for i in range(8):
				Props.box(root, top + Vector3(-0.6 + (i % 4) * 0.4, 0.07, -0.15 + (i / 4) * 0.3), Vector3(0.18, 0.14, 0.12), [Color("ffffff"), Color("cfe6f2"), Color("e3f0d8")][i % 3])
		"fruit":
			# Crates of apples, oranges, lemons and greens.
			for i in range(4):
				var c = top + Vector3(-0.6 + i * 0.4, 0.07, 0)
				Props.box(root, c, Vector3(0.36, 0.14, 0.6), Color("a37b50"))
				for f in range(6):
					Props.box(root, c + Vector3(-0.09 + (f % 2) * 0.18, 0.09, -0.2 + (f / 2) * 0.2), Vector3(0.11, 0.08, 0.11), [Color("d9482f"), Color("e8a12a"), Color("e8d040"), Color("6f9a3a")][i])
		"soap":
			for i in range(12):
				Props.box(root, top + Vector3(-0.66 + (i % 6) * 0.26, 0.03, -0.15 + (i / 6) * 0.3), Vector3(0.14, 0.06, 0.09), [Color("c9b3e0"), Color("f2e6c8"), Color("b6d6b0"), Color("f0c4c4")][i % 4])
			for x in [-0.5, 0.5]:
				Props.cylinder(root, top + Vector3(x, 0.1, 0.25), 0.07, 0.06, 0.2, Color("e9e2d2"), 8)
				for k in range(5):
					var stem = Props.cylinder(root, top + Vector3(x + (k - 2) * 0.025, 0.36, 0.25), 0.012, 0.012, 0.36, Color("8c6cc0"), 5)
					stem.rotation.z = (k - 2) * 0.12
		"wine":
			# Open wooden cases of bottles.
			for i in range(3):
				var c = top + Vector3(-0.5 + i * 0.5, 0.1, 0)
				Props.box(root, c, Vector3(0.42, 0.2, 0.3), Color("a37b50"))
				for b in range(6):
					Props.cylinder(root, c + Vector3(-0.13 + (b % 3) * 0.13, 0.2, -0.07 + (b / 3) * 0.14), 0.035, 0.035, 0.3, [Color("1e3a2a"), Color("3a1820")][b % 2], 8)
		"meat":
			Props.box(root, top + Vector3(0, 0.06, 0), Vector3(1.0, 0.12, 0.5), Color("e9e2d0"))
			for i in range(4):
				Props.cylinder(root, top + Vector3(-0.36 + i * 0.24, 0.17, 0), 0.06, 0.06, 0.12, Color("c9504a"), 8)

# Something on the back wall above the shelves: a sign of the trade.
static func _wall_piece(root: Node3D, at: Vector3, kind: String) -> void:
	match kind:
		"pharmacy":
			Props.box(root, at + Vector3(0, 0.15, 0), Vector3(0.12, 0.42, 0.02), Color("37b34a"))
			Props.box(root, at + Vector3(0, 0.15, 0), Vector3(0.42, 0.12, 0.02), Color("37b34a"))
		"wine":
			Props.cylinder(root, at + Vector3(-1.0, 0.1, -0.2), 0.3, 0.3, 0.4, Color("7a4c30"), 12).rotation.x = PI / 2
		_:
			Props.box(root, at + Vector3(0, 0.12, 0), Vector3(1.4, 0.3, 0.02), Color("2f3a36"))
			Props.box(root, at + Vector3(0, 0.12, -0.005), Vector3(1.2, 0.03, 0.01), Color("e9e2d0"))

# The café: a zinc bar with stools and a coffee machine, bottles on shelves
# behind it, round tables with bistro chairs, a menu board.
static func _cafe(root: Node3D, inner: Vector2, floor: Vector3) -> void:
	var bar = floor + Vector3(inner.x - 1.6, 0, inner.y - 1.6)
	Props.box(root, bar + Vector3(0, 0.55, 0), Vector3(2.6, 1.1, 0.6), Color("6a3a2a"))
	Props.box(root, bar + Vector3(0, 1.12, 0), Vector3(2.7, 0.04, 0.7), Color("b9bdbf"))
	Props.box(root, bar + Vector3(0.8, 1.32, 0.05), Vector3(0.5, 0.36, 0.4), Color("c9cdcf"))
	Props.box(root, bar + Vector3(0.8, 1.28, -0.16), Vector3(0.3, 0.06, 0.04), Color("2b2b2b"))
	for i in range(4):
		var stool = bar + Vector3(-1.0 + i * 0.6, 0, -0.65)
		Props.cylinder(root, stool + Vector3(0, 0.38, 0), 0.03, 0.03, 0.76, IRON, 6)
		Props.cylinder(root, stool + Vector3(0, 0.78, 0), 0.17, 0.17, 0.05, Color("8a2f2f"), 10)
	_shelves(root, floor + Vector3(inner.x - 1.6, 0, inner.y - 0.25), Vector3(2.6, 0, 0), "wine")
	for i in range(4):
		var t = floor + Vector3(-inner.x + 1.2 + (i % 2) * 1.8, 0, WALL + 1.2 + (i / 2) * 1.9)
		Props.cylinder(root, t + Vector3(0, 0.36, 0), 0.04, 0.04, 0.72, IRON, 6)
		Props.cylinder(root, t + Vector3(0, 0.74, 0), 0.34, 0.34, 0.03, Color("e9e4d6"), 12)
		Props.cylinder(root, t + Vector3(0.1, 0.8, 0.05), 0.04, 0.035, 0.08, Color("f2f2ee"), 8)
		for side in [-1.0, 1.0]:
			var chair = t + Vector3(side * 0.55, 0, 0)
			Props.cylinder(root, chair + Vector3(0, 0.45, 0), 0.2, 0.2, 0.04, Color("c9a660"), 10)
			Props.box(root, chair + Vector3(side * 0.18, 0.7, 0), Vector3(0.03, 0.5, 0.36), Color("3a2a1e"))
			for dz in [-0.12, 0.12]:
				Props.box(root, chair + Vector3(0, 0.22, dz), Vector3(0.03, 0.44, 0.03), Color("3a2a1e"))
	Props.box(root, floor + Vector3(-inner.x + 0.02, 1.7, inner.y - 1.5), Vector3(0.03, 0.9, 1.2), Color("2f3a36"))
	for k in range(4):
		Props.box(root, floor + Vector3(-inner.x + 0.04, 1.95 - k * 0.18, inner.y - 1.5), Vector3(0.01, 0.03, 0.9 - k * 0.12), Color("e9e2d0"))
