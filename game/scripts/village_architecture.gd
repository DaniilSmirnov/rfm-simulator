extends RefCounted
# Built scenery of the Provençal village: terraced stone houses with shutters,
# génoise eaves and canal-tile roofs, shops, the square with plane trees and a
# fountain, the church, mairie, café, lavoir, cemetery, pavements and lamps,
# plus the mas, wine domaine and cooperative in the countryside. Primitives are
# written as readable Props calls and collapsed by the shared batcher.
const Props = preload("res://scripts/props.gd")
const Layout = preload("res://scripts/village_layout.gd")
const Interiors = preload("res://scripts/village_interiors.gd")

const FLOOR = 3.0
const WALLS = ["e8d5b0", "e2c18f", "dcb48a", "efe2c8", "d9a982", "cfb79a", "e6cfa6", "d8c3a0", "c9a27d", "e9dcc3", "e3bf9a", "d4b58e"]
const STONE_WALLS = ["c9b393", "bfa682", "d0bc9c"]
const SHUTTERS = ["8fa7b8", "7f9d8a", "9b8bb4", "5f8e8c", "b0c2c6", "7e8b5a", "a35f4f", "6f8796", "c2b48a", "a7b7a0"]
const DOORS = ["6d4a33", "4f6b6b", "7b4d3b", "5b6e8a", "8a6b4a", "3f5a4c"]
const ROOFS = ["b8653f", "c27752", "a95a3a", "b46e4b", "9e5236", "c4825c"]
const TRIM = Color("efe4cc")
const IRON = Color("2e3330")
const SHOPS = [
	{"text": "BOULANGERIE", "awning": ["e8d9b5", "8a4a3a"], "goods": "bread"},
	{"text": "TABAC · PRESSE", "awning": ["e9e2cf", "b33a32"], "goods": "tabac"},
	{"text": "PHARMACIE", "awning": ["e6eee4", "3d8a55"], "goods": "pharmacy"},
	{"text": "ÉPICERIE", "awning": ["efe0bb", "4e7a5a"], "goods": "fruit"},
	{"text": "SAVONNERIE", "awning": ["ece4f3", "8a72b0"], "goods": "lavender"},
	{"text": "CAVE À VINS", "awning": ["ead8c0", "6e2f3c"], "goods": "wine"},
	{"text": "BOUCHERIE", "awning": ["f1e6d6", "9b3a3a"], "goods": "none"},
	{"text": "LA POSTE", "awning": ["f2df7a", "2f4f8a"], "goods": "none"},
	{"text": "ANTIQUITÉS", "awning": ["e7ddc8", "5d5a7a"], "goods": "none"},
]

var village
var stage
var solids
var batcher
var rng = RandomNumberGenerator.new()
var shop_index = 0
var house_count = 0
var shop_count = 0
var window_boxes = 0
var lamp_count = 0
# Footprints of built-up areas (houses, yards), used to keep crops and trees out.
var footprints: Array[Dictionary] = []

func _init(owner) -> void:
	village = owner
	stage = owner.stage
	solids = stage.solids
	batcher = owner.batcher
	rng.seed = 14072026

func build(cooperative: bool = false) -> void:
	_register_meshes()
	_pavements()
	await village.pause(cooperative)
	await _house_rows(cooperative)
	await village.pause(cooperative)
	await _back_rows(cooperative)
	_square()
	await village.pause(cooperative)
	_church()
	_mairie()
	_cafe()
	_lavoir()
	_cemetery()
	await village.pause(cooperative)
	_gates()
	_lamps()
	_parked_vehicles()
	_distillery()
	_borie()
	_domaine()
	_cooperative()
	await village.pause(cooperative)

# ---------------------------------------------------------------- helpers

func node(name: String, p: Vector3, yaw: float) -> Node3D:
	var root = Node3D.new()
	root.name = name
	stage.add_child(root)
	root.position = p
	root.rotation.y = yaw
	return root

func grounded(p: Vector3) -> Vector3:
	p.y = stage.ground(p)
	return p

func finish(root: Node3D) -> void:
	batcher.collect(root, root.transform)

func color(list: Array, index: int) -> Color:
	return Color(list[posmod(index, list.size())])

func reserve(center: Vector3, yaw: float, half: Vector2) -> void:
	var pose = Transform3D(Basis(Vector3.UP, yaw), Vector3(center.x, 0, center.z))
	footprints.append({"inverse": pose.affine_inverse(), "half": half})

# True when p is outside every house, yard and square of the village.
func open_ground(p: Vector3, padding: float = 0.0) -> bool:
	for area in footprints:
		var local: Vector3 = area.inverse * Vector3(p.x, 0, p.z)
		if absf(local.x) <= area.half.x + padding and absf(local.z) <= area.half.y + padding:
			return false
	return solids.clear(p, padding)

func _register_meshes() -> void:
	batcher.register_mesh("roof_canal", _canal_roof_mesh())
	batcher.register_mesh("ball", _sphere(1.0, 8, 4))
	batcher.register_mesh("crown", _sphere(1.0, 10, 6))

static func _sphere(radius: float, segments: int, rings: int) -> SphereMesh:
	var sphere = SphereMesh.new()
	sphere.radius = radius * 0.5
	sphere.height = radius
	sphere.radial_segments = segments
	sphere.rings = rings
	return sphere

# Unit gable (1 x 1 x 1, ridge along X) whose slopes are corrugated like rows
# of Provençal canal tiles running from the ridge down to the eaves.
static func _canal_roof_mesh() -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var waves = 28
	for face in [-1.0, 1.0]:
		for i in range(waves * 2):
			var x0 = -0.5 + float(i) / (waves * 2)
			var x1 = -0.5 + float(i + 1) / (waves * 2)
			var bump0 = 0.035 * (0.5 + 0.5 * cos(float(i) * PI))
			var bump1 = 0.035 * (0.5 + 0.5 * cos(float(i + 1) * PI))
			var a = Vector3(x0, 1.0 + bump0, 0.0)
			var b = Vector3(x1, 1.0 + bump1, 0.0)
			var c = Vector3(x0, bump0, face * 0.5)
			var d = Vector3(x1, bump1, face * 0.5)
			var tris = [a, c, b, b, c, d] if face > 0 else [a, b, c, b, d, c]
			for v in tris:
				st.add_vertex(v)
	# Gable ends close the volume where a terrace row ends.
	for x in [-0.5, 0.5]:
		var tris = [Vector3(x, 0, -0.5), Vector3(x, 0, 0.5), Vector3(x, 1, 0)]
		if x > 0:
			tris = [Vector3(x, 0, -0.5), Vector3(x, 1, 0), Vector3(x, 0, 0.5)]
		for v in tris:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()

# Roof centred on the body: z is the middle of the house depth.
func roof(parent: Node3D, width: float, depth: float, y: float, height: float, tile: Color, z: float = 0.0) -> void:
	var mesh = MeshInstance3D.new()
	mesh.mesh = batcher.meshes["roof_canal"] if batcher.has_mesh("roof_canal") else _canal_roof_mesh()
	mesh.set_meta("batch_key", "roof_canal")
	mesh.material_override = Props.shared_material(tile)
	parent.add_child(mesh)
	mesh.position = Vector3(0, y, z)
	mesh.scale = Vector3(width, height, depth)
	# Ridge of round tiles.
	var ridge = Props.cylinder(parent, Vector3(0, y + height + 0.04, z), 0.13, 0.13, width, tile.darkened(0.08), 6)
	ridge.rotation.z = PI / 2

# Two or three corbelled courses of tiles under the eaves (génoise).
func genoise(parent: Node3D, width: float, z: float, y: float, outward: float) -> void:
	for course in range(3):
		var depth = 0.12 + course * 0.1
		Props.box(parent, Vector3(0, y - 0.32 + course * 0.13, z + outward * depth * 0.5), Vector3(width, 0.1, depth), TRIM.darkened(0.02 + course * 0.05) if course != 1 else Color("b97a55"))

# Tall window with stone surround, louvered shutters folded back, sill and
# optionally a flower box of geraniums or a wrought-iron balcony.
func window(parent: Node3D, p: Vector3, yaw: float, shutters: Color, extra: String = "") -> void:
	var w = Node3D.new()
	parent.add_child(w)
	w.position = p
	w.rotation.y = yaw
	Props.box(w, Vector3(0, 0, 0.02), Vector3(0.82, 1.38, 0.06), Color("3e4a4c"))
	Props.box(w, Vector3(0, 0, -0.005), Vector3(0.05, 1.32, 0.04), Color("d8d2c2"))
	Props.box(w, Vector3(0, 0.22, -0.005), Vector3(0.76, 0.04, 0.04), Color("d8d2c2"))
	for x in [-0.47, 0.47]:
		Props.box(w, Vector3(x, 0, -0.03), Vector3(0.12, 1.56, 0.09), TRIM)
	Props.box(w, Vector3(0, 0.74, -0.03), Vector3(1.06, 0.12, 0.09), TRIM)
	Props.box(w, Vector3(0, -0.76, -0.07), Vector3(1.08, 0.08, 0.18), TRIM.darkened(0.06))
	for x in [-1.0, 1.0]:
		Props.box(w, Vector3(x * 0.79, 0, -0.04), Vector3(0.40, 1.36, 0.05), shutters)
		for y in [-0.45, -0.15, 0.15, 0.45]:
			Props.box(w, Vector3(x * 0.79, y, -0.07), Vector3(0.34, 0.035, 0.03), shutters.darkened(0.22))
	if extra == "flowers":
		window_boxes += 1
		Props.box(w, Vector3(0, -0.88, -0.2), Vector3(0.92, 0.18, 0.24), Color("9a5a3c"))
		for i in range(6):
			var x = -0.36 + i * 0.145
			Props.box(w, Vector3(x, -0.72, -0.21), Vector3(0.14, 0.14, 0.16), Color("4f7a3a"))
			Props.box(w, Vector3(x, -0.64, -0.24), Vector3(0.09, 0.08, 0.09), Color("d23b3b") if i % 3 else Color("e47aa0"))
	elif extra == "balcony":
		Props.box(w, Vector3(0, -0.8, -0.32), Vector3(1.3, 0.08, 0.6), TRIM.darkened(0.08))
		Props.box(w, Vector3(0, -0.12, -0.6), Vector3(1.3, 0.04, 0.04), IRON)
		for i in range(9):
			Props.box(w, Vector3(-0.6 + i * 0.15, -0.45, -0.6), Vector3(0.025, 0.66, 0.025), IRON)
		for x in [-0.64, 0.64]:
			Props.box(w, Vector3(x, -0.45, -0.45), Vector3(0.025, 0.66, 0.3), IRON)
		Props.cylinder(w, Vector3(0.42, -0.62, -0.44), 0.13, 0.1, 0.26, Color("b0603e"), 7)
		Props.box(w, Vector3(0.42, -0.42, -0.44), Vector3(0.26, 0.2, 0.26), Color("5b7f3c"))

func door(parent: Node3D, x: float, colour: Color, arched: bool) -> void:
	Props.box(parent, Vector3(x, 1.1, 0.03), Vector3(1.08, 2.2, 0.08), colour)
	for dx in [-0.27, 0.27]:
		Props.box(parent, Vector3(x + dx, 1.1, -0.015), Vector3(0.38, 1.9, 0.02), colour.darkened(0.12))
	Props.box(parent, Vector3(x + 0.38, 1.05, -0.04), Vector3(0.05, 0.12, 0.05), Color("c9a95b"))
	for dx in [-0.62, 0.62]:
		Props.box(parent, Vector3(x + dx, 1.15, -0.03), Vector3(0.18, 2.4, 0.09), TRIM)
	if arched:
		var arch = Props.cylinder(parent, Vector3(x, 2.35, -0.03), 0.72, 0.72, 0.09, TRIM, 10)
		arch.rotation.x = PI / 2
		var fill = Props.cylinder(parent, Vector3(x, 2.35, 0.0), 0.54, 0.54, 0.08, colour.darkened(0.1), 10)
		fill.rotation.x = PI / 2
	else:
		Props.box(parent, Vector3(x, 2.38, -0.03), Vector3(1.42, 0.16, 0.09), TRIM)
	Props.box(parent, Vector3(x, 0.05, -0.25), Vector3(1.3, 0.1, 0.5), Color("bdb29a"))

# Bougainvillea or Virginia creeper climbing the facade.
func climber(parent: Node3D, x: float, height: float, bloom: Color) -> void:
	Props.cylinder(parent, Vector3(x, height * 0.5, -0.06), 0.05, 0.04, height, Color("5b4a35"), 5)
	for i in range(7):
		var y = height * (0.35 + i * 0.1)
		var spread = 0.4 + sin(i * 1.7) * 0.25
		Props.box(parent, Vector3(x + spread * (1.0 if i % 2 else -1.0), y, -0.1), Vector3(0.9, 0.55, 0.16), Color("4e7436") if i % 2 else bloom)

# ---------------------------------------------------------------- houses

# A terraced house: origin at the foot of the facade, local -Z toward the street.
func house(p: Vector3, yaw: float, width: float, depth: float, floors: int, seed_value: int, shop: Dictionary = {}, gable_ends: bool = true, annex: bool = false) -> Node3D:
	var root = node("VillageHouse_%d" % house_count, p, yaw)
	house_count += 1
	var height = floors * FLOOR + 0.5
	var stone = seed_value % 5 == 2
	var wall = color(STONE_WALLS, seed_value) if stone else color(WALLS, seed_value)
	var shutter = color(SHUTTERS, seed_value * 7 + 3)
	# Plinth down to the lowest corner of sloping ground.
	var lowest = 0.0
	for corner in [Vector3(-width * 0.5, 0, 0), Vector3(width * 0.5, 0, 0), Vector3(-width * 0.5, 0, depth), Vector3(width * 0.5, 0, depth)]:
		lowest = minf(lowest, stage.ground(root.transform * corner) - p.y)
	var bottom = lowest - 0.3
	Props.box(root, Vector3(0, (height + bottom) * 0.5, depth * 0.5), Vector3(width, height - bottom, depth), wall)
	Props.box(root, Vector3(0, (0.45 + bottom) * 0.5, -0.03), Vector3(width + 0.02, 0.45 - bottom, 0.06), wall.darkened(0.18))
	if stone:
		# Dressed corner quoins on exposed stone houses.
		for x in [-width * 0.5, width * 0.5]:
			for i in range(int(height / 0.55)):
				Props.box(root, Vector3(x, 0.3 + i * 0.55, -0.02), Vector3(0.5 if i % 2 else 0.32, 0.26, 0.06), Color("e2d6bd"))
	solids.solid(root, Vector3(0, height * 0.5, depth * 0.5), Vector3(width, height, depth), "building")
	reserve(root.transform * Vector3(0, 0, depth * 0.5), yaw, Vector2(width * 0.5, depth * 0.5))
	# Openings: ground floor door or shop, regular bays above.
	var bays = maxi(1, int((width - 0.6) / 2.3))
	var spacing = width / bays
	for floor in range(1, floors):
		for bay in range(bays):
			var x = -width * 0.5 + spacing * (bay + 0.5)
			var roll = (seed_value * 13 + bay * 5 + floor * 3) % 7
			var extra = "flowers" if roll in [0, 3] else ("balcony" if roll == 5 and floor == 1 else "")
			window(root, Vector3(x, floor * FLOOR + 1.3, 0), 0.0, shutter, extra)
	var door_bay = (seed_value % bays) if shop.is_empty() else -1
	for bay in range(bays):
		var x = -width * 0.5 + spacing * (bay + 0.5)
		if bay == door_bay:
			door(root, x, color(DOORS, seed_value), seed_value % 3 == 0)
		elif shop.is_empty():
			window(root, Vector3(x, 1.45, 0), 0.0, shutter, "flowers" if (seed_value + bay) % 4 == 0 else "")
	if not shop.is_empty():
		_shopfront(root, width, shop)
	# Eaves, roof and chimney.
	genoise(root, width + 0.1, 0.0, height, -1.0)
	genoise(root, width + 0.1, depth, height, 1.0)
	roof(root, width + 0.12, depth + 0.7, height, depth * 0.2, color(ROOFS, seed_value * 3 + 1), depth * 0.5)
	if annex:
		# Lower annex at the back with its own pent roof: closes the block.
		var annex_depth = 4.5
		Props.box(root, Vector3(0, (FLOOR + 0.3 + bottom) * 0.5, depth + annex_depth * 0.5), Vector3(width - 0.4, FLOOR + 0.3 - bottom, annex_depth), wall.darkened(0.04))
		solids.solid(root, Vector3(0, FLOOR * 0.5, depth + annex_depth * 0.5), Vector3(width - 0.4, FLOOR, annex_depth), "building")
		roof(root, width - 0.3, annex_depth + 0.6, FLOOR + 0.3, 0.9, color(ROOFS, seed_value + 2).darkened(0.05), depth + annex_depth * 0.5)
		reserve(root.transform * Vector3(0, 0, depth + annex_depth * 0.5), yaw, Vector2(width * 0.5, annex_depth * 0.5))
	if seed_value % 3 != 1:
		var chimney = Vector3(width * (0.25 if seed_value % 2 else -0.25), height + depth * 0.2, depth * 0.62)
		Props.box(root, chimney + Vector3(0, 0.55, 0), Vector3(0.6, 1.3, 0.6), wall.darkened(0.05))
		Props.box(root, chimney + Vector3(0, 1.25, 0), Vector3(0.74, 0.1, 0.74), TRIM.darkened(0.1))
		village.add_anchor("chimneys", root.transform * (chimney + Vector3(0, 1.35, 0)))
	if seed_value % 4 == 1 and shop.is_empty():
		climber(root, width * 0.5 - 0.6, minf(height, 5.5), Color("c2307a") if seed_value % 8 == 1 else Color("7f9a3e"))
	# Plain back facade for the views from the vineyards and the square.
	for floor in range(floors):
		for bay in range(maxi(1, bays - 1)):
			var x = -width * 0.5 + width / maxi(1, bays - 1) * (bay + 0.5)
			window(root, Vector3(x, floor * FLOOR + 1.4, depth), PI, shutter)
	if gable_ends:
		for side_sign in [-1.0, 1.0]:
			window(root, Vector3(side_sign * width * 0.5, floors * FLOOR - 1.6, depth * 0.5), -side_sign * PI * 0.5, shutter)
	finish(root)
	return root

func _shopfront(root: Node3D, width: float, shop: Dictionary) -> void:
	shop_count += 1
	var frame = Color("4a5b55") if shop.text != "BOULANGERIE" else Color("6b3e2e")
	Props.box(root, Vector3(0, 1.45, -0.04), Vector3(width - 0.8, 2.7, 0.08), frame)
	Props.box(root, Vector3(-0.6, 1.25, -0.07), Vector3(width * 0.5 - 0.4, 1.9, 0.04), Color("6f8e94"))
	Props.box(root, Vector3(width * 0.25 + 0.15, 1.15, -0.07), Vector3(1.0, 2.1, 0.04), Color("324441"))
	var sign = Props.label_3d(root, Vector3(0, 2.62, -0.11), shop.text, 64, 0.0042, Color("f1e7cf"), PI)
	sign.name = "ShopSign"
	sign.double_sided = false
	# Striped awning on a slight slope.
	var awning = Node3D.new()
	root.add_child(awning)
	awning.position = Vector3(0, 2.32, -0.48)
	awning.rotation.x = 0.32
	var stripes = int((width - 1.0) / 0.42)
	for i in range(stripes):
		Props.box(awning, Vector3(-(width - 1.0) * 0.5 + 0.21 + i * 0.42, 0, 0), Vector3(0.42, 0.04, 1.0), Color(shop.awning[i % 2]))
	for i in range(stripes):
		Props.box(awning, Vector3(-(width - 1.0) * 0.5 + 0.21 + i * 0.42, -0.12, -0.49), Vector3(0.42, 0.2, 0.03), Color(shop.awning[(i + 1) % 2]))
	match shop.goods:
		"tabac":
			# The red "carotte" of French tobacconists.
			var carrot = Props.box(root, Vector3(width * 0.5 - 0.1, 3.5, -0.55), Vector3(0.18, 0.9, 0.5), Color("c0342e"))
			carrot.rotation.z = 0.0
			Props.box(root, Vector3(width * 0.5 - 0.1, 3.5, -0.2), Vector3(0.05, 0.05, 0.4), IRON)
		"pharmacy":
			var cross = Node3D.new()
			root.add_child(cross)
			cross.position = Vector3(width * 0.5 - 0.1, 3.6, -0.7)
			Props.box(cross, Vector3.ZERO, Vector3(0.12, 0.8, 0.26), Color("37b34a"))
			Props.box(cross, Vector3.ZERO, Vector3(0.12, 0.26, 0.8), Color("37b34a"))
			Props.box(root, Vector3(width * 0.5 - 0.1, 3.6, -0.25), Vector3(0.05, 0.05, 0.5), IRON)
		"bread", "fruit", "lavender", "wine":
			# Crates or baskets of goods displayed under the awning.
			var goods = {"bread": Color("d6a35a"), "fruit": Color("d9482f"), "lavender": Color("8c6cc0"), "wine": Color("5a2433")}[shop.goods]
			for i in range(3):
				var x = -width * 0.5 + 0.9 + i * 0.8
				Props.box(root, Vector3(x, 0.35, -0.75), Vector3(0.7, 0.7, 0.45), Color("a37b50"))
				for k in range(3):
					Props.box(root, Vector3(x - 0.2 + k * 0.2, 0.76, -0.75), Vector3(0.17, 0.12 if shop.goods != "wine" else 0.32, 0.17), goods.lightened(k * 0.08))
			solids.solid(root, Vector3(-width * 0.5 + 1.7, 0.4, -0.75), Vector3(2.5, 0.8, 0.5), "street_furniture")

# Continuous terraced rows along the village streets; alleys break the rows.
func _house_rows(cooperative: bool) -> void:
	var seed_value = 0
	for row in Layout.HOUSE_ROWS:
		var s: float = row[0]
		var side_sign: float = row[2]
		while s < row[1] - 3.0:
			var width = rng.randf_range(5.6, 8.6)
			var center = s + width * 0.5
			var blocked = false
			for alley in Layout.ALLEYS:
				blocked = blocked or absf(center - alley) < width * 0.5 + 1.6
			for gap in Layout.ROW_GAPS:
				blocked = blocked or (side_sign == gap[2] and center + width * 0.5 > gap[0] and center - width * 0.5 < gap[1])
			if blocked:
				s += 2.0
				continue
			if absf(center - Layout.ROOF_TERRACE_HOUSE.s) < 4.5 and side_sign == Layout.ROOF_TERRACE_HOUSE.side:
				_roof_terrace_house(center, side_sign)
				s = center + 4.6
				continue
			var front = _front_offset(center)
			var p = grounded(village.anchor(center, side_sign * front))
			var facing = -village.side(center) * side_sign
			var floors = 2 + int(rng.randf() < 0.45)
			var shop = {}
			if village.in_village(center) and center < 381.0 and seed_value % 2 == 0 and shop_index < SHOPS.size():
				shop = SHOPS[shop_index]
				shop_index += 1
			house(p, atan2(-facing.x, -facing.z), width + 0.05, rng.randf_range(8.5, 10.5), floors, seed_value, shop, false, rng.randf() < 0.7)
			seed_value += 1
			s += width
			if cooperative and seed_value % 6 == 0:
				await stage.get_tree().process_frame

func _front_offset(s: float) -> float:
	return village.road_width(s) * 0.5 + (Layout.PAVEMENT if village.pavement(s) else 2.0) + 0.05

# The second row of village houses behind the street fronts, with courtyards,
# gaps and walled gardens: the village reads as a cluster, not a single street.
func _back_rows(cooperative: bool) -> void:
	var seed_value = 500
	for row in Layout.HOUSE_ROWS:
		var s: float = row[0]
		var side_sign: float = row[2]
		while s < row[1] - 3.0:
			var width = rng.randf_range(6.0, 9.5)
			var center = s + width * 0.5
			s += width
			if rng.randf() < 0.22:
				s += rng.randf_range(2.0, 5.0) # courtyard
				continue
			var depth = rng.randf_range(8.0, 9.5)
			var lateral = _front_offset(center) + 10.6 + 4.5 + Layout.BACK_LANE
			var facing = -village.side(center) * side_sign
			var yaw = atan2(-facing.x, -facing.z)
			var p = village.anchor(center, side_sign * lateral)
			var free = true
			for corner in [Vector3(-width * 0.5, 0, 0), Vector3(width * 0.5, 0, 0), Vector3(-width * 0.5, 0, depth), Vector3(width * 0.5, 0, depth), Vector3(0, 0, depth * 0.5)]:
				var q = p + Basis(Vector3.UP, yaw) * corner
				free = free and open_ground(q, 0.8) and stage.road_distance(q) > village.road_width(center) * 0.5 + 6.0
			if not free:
				continue
			house(grounded(p), yaw, width, depth, 2 + int(rng.randf() < 0.3), seed_value)
			seed_value += 1
			if seed_value % 3 == 0:
				_garden(p - facing * (depth + 4.5), yaw, width)
			if cooperative and seed_value % 6 == 0:
				await stage.get_tree().process_frame

func _garden(center: Vector3, yaw: float, width: float) -> void:
	center = grounded(center)
	var root = node("VillageGarden_%d" % footprints.size(), center, yaw)
	for x in [-width * 0.5, width * 0.5]:
		Props.box(root, Vector3(x, 0.55, 0), Vector3(0.4, 1.1, 8.0), Color("bfa883"))
		solids.solid(root, Vector3(x, 0.55, 0), Vector3(0.4, 1.1, 8.0), "wall")
	Props.box(root, Vector3(0, 0.55, 4.0), Vector3(width, 1.1, 0.4), Color("bfa883"))
	solids.solid(root, Vector3(0, 0.55, 4.0), Vector3(width, 1.1, 0.4), "wall")
	for i in range(3):
		Props.box(root, Vector3(-width * 0.25, 0.08, -2.4 + i * 1.4), Vector3(width * 0.4, 0.16, 0.8), Color("6b5236"))
		for k in range(4):
			Props.box(root, Vector3(-width * 0.25 - width * 0.15 + k * width * 0.1, 0.32, -2.4 + i * 1.4), Vector3(0.3, 0.3, 0.3), Color("5e8a3a").lightened(k * 0.04))
	reserve(center, yaw, Vector2(width * 0.5, 4.2))
	village.landscape_hint("fig", root.transform * Vector3(width * 0.25, 0, 1.0))
	finish(root)

# The accessible house with a roof terrace over the Grand-Rue.
func _roof_terrace_house(s: float, side_sign: float) -> void:
	var p = grounded(village.anchor(s, side_sign * (_front_offset(s) + 4.2)))
	var facing = -village.side(s) * side_sign
	var root = node("VillageRoofTerraceHouse", p, atan2(-facing.x, -facing.z))
	house_count += 1
	Interiors.house(self, root)
	reserve(p, root.rotation.y, Vector2(4.4, 4.4))
	finish(root)

# ---------------------------------------------------------------- streets

# Raised limestone pavements and kerbs on both sides of the village streets.
func _pavements() -> void:
	var root = node("VillagePavements", Vector3.ZERO, 0.0)
	var s = Layout.VILLAGE.x
	while s < Layout.VILLAGE.y:
		if village.pavement(s):
			var half = village.road_width(s) * 0.5
			var yaw = village.yaw_at(s)
			for side_sign in [-1.0, 1.0]:
				var mid = village.anchor(s, side_sign * (half + Layout.PAVEMENT * 0.5))
				mid.y = village.route(s).y + Layout.KERB
				var slab = Props.box(root, mid - Vector3.UP * 0.1, Vector3(Layout.PAVEMENT, 0.22, 1.02), Color("d8ccb2").lightened(sin(s * 1.3 + side_sign) * 0.03))
				slab.rotation.y = yaw
				var kerb_point = village.anchor(s, side_sign * (half + 0.08))
				kerb_point.y = village.route(s).y + Layout.KERB - 0.1
				var kerb = Props.box(root, kerb_point, Vector3(0.16, 0.24, 1.02), Color("e6dcc6"))
				kerb.rotation.y = yaw
		s += 1.0
	finish(root)

func _gates() -> void:
	for item in Layout.GATES:
		var s: float = item[0]
		var side_sign: float = item[1]
		# The panel's inner edge stays clear of the verge crews may use.
		var p = grounded(village.anchor(s, side_sign * (village.road_width(s) * 0.5 + 3.2)))
		var outward = -village.direction(s) if s < 400.0 else village.direction(s)
		var root = node("VillageNameSign_%d" % (0 if s < 400.0 else 1), p, atan2(-outward.x, -outward.z))
		# French entry sign: white panel with a red border on two grey posts.
		for x in [-1.2, 1.2]:
			Props.cylinder(root, Vector3(x, 1.1, 0), 0.05, 0.05, 2.2, Color("8d918c"), 6)
		Props.box(root, Vector3(0, 2.0, 0), Vector3(2.9, 0.92, 0.06), Color("c8352f"))
		Props.box(root, Vector3(0, 2.0, -0.01), Vector3(2.7, 0.74, 0.06), Color("f4f1ea"))
		for face in [-1.0, 1.0]:
			var label = Props.label_3d(root, Vector3(0, 2.0, face * 0.05), "Ля Газ в Польен", 44, 0.0045, Color("1f2326"), 0.0 if face > 0 else PI)
			label.double_sided = false
		solids.solid(root, Vector3(0, 1.6, 0), Vector3(2.9, 1.0, 0.12), "sign")
		finish(root)

func _lamps() -> void:
	for s in Layout.LAMPS:
		var side_sign = 1.0 if int(s) % 2 == 0 else -1.0
		# Lanterns stand against the house fronts, clear of the kerb line.
		var lateral = village.road_width(s) * 0.5 + (Layout.PAVEMENT - 0.15 if village.pavement(s) else 1.8)
		var p = grounded(village.anchor(s, side_sign * lateral))
		if not solids.clear(p, 0.3):
			p = grounded(village.anchor(s, -side_sign * lateral))
		solids.lamp(p, village.yaw_at(s))
		lamp_count += 1

# Old Citroën-style saloons, a van and mopeds parked off the racing line.
func _parked_vehicles() -> void:
	var spots = [[300.0, -1.0, "deux"], [342.0, 1.0, "van"], [470.0, 1.0, "moped"], [508.0, -1.0, "deux"]]
	for spot in spots:
		var s: float = spot[0]
		var lateral = village.road_width(s) * 0.5 + Layout.PAVEMENT * 0.5
		var p = village.anchor(s, spot[1] * lateral)
		p.y = village.route(s).y + Layout.KERB
		var root = node("VillageParked_%d" % int(s), p, village.yaw_at(s) + (PI if int(s) % 2 else 0.0))
		match spot[2]:
			"moped":
				_moped(root, Vector3.ZERO)
				_moped(root, Vector3(0, 0, 1.1))
				solids.solid(root, Vector3(0, 0.5, 0.55), Vector3(0.6, 1.0, 2.6), "street_furniture")
			_:
				_small_car(root, spot[2] == "van", Color("8fb3c4") if int(s) % 3 else Color("d9c46a"))
		finish(root)

func _small_car(root: Node3D, van: bool, paint: Color) -> void:
	# Parked half on the pavement, as is customary in narrow French streets.
	var body = Node3D.new()
	root.add_child(body)
	body.position = Vector3(0.0, 0.0, 0.0)
	var length = 4.0 if van else 3.8
	Props.box(body, Vector3(0, 0.62, 0), Vector3(1.48, 0.55, length), paint)
	if van:
		Props.box(body, Vector3(0, 1.32, 0.35), Vector3(1.44, 0.95, length - 1.3), paint.lightened(0.05))
		for z in [0.6, -0.4]:
			for i in range(5):
				Props.box(body, Vector3(0, 1.0 + i * 0.16, z), Vector3(1.46, 0.03, 0.4), paint.darkened(0.12))
	else:
		# Rounded cabin with a rolled-back canvas roof.
		Props.box(body, Vector3(0, 1.12, 0.15), Vector3(1.3, 0.5, 2.0), paint.lightened(0.04))
		Props.box(body, Vector3(0, 1.39, 0.3), Vector3(1.0, 0.05, 1.3), Color("3d3a35"))
		Props.box(body, Vector3(0, 1.18, -0.86), Vector3(1.18, 0.38, 0.06), Color("4b5e66"))
		var bonnet = Props.box(body, Vector3(0, 0.95, -1.35), Vector3(1.2, 0.2, 1.0), paint)
		bonnet.rotation.x = 0.22
		for x in [-0.66, 0.66]:
			var light = Props.cylinder(body, Vector3(x, 0.98, -1.86), 0.12, 0.12, 0.08, Color("e8e2c8"), 8)
			light.rotation.x = PI / 2
	for x in [-0.72, 0.72]:
		for z in [-length * 0.32, length * 0.32]:
			var wheel = Props.cylinder(body, Vector3(x, 0.3, z), 0.3, 0.3, 0.2, Color("222524"), 10)
			wheel.rotation.z = PI / 2
	solids.solid(root, Vector3(0, 0.85, 0), Vector3(1.5, 1.7, length), "parked_car")

func _moped(root: Node3D, p: Vector3) -> void:
	for z in [-0.55, 0.55]:
		var wheel = Props.cylinder(root, p + Vector3(0, 0.25, z), 0.25, 0.25, 0.06, Color("222524"), 10)
		wheel.rotation.z = PI / 2
	Props.box(root, p + Vector3(0, 0.45, 0), Vector3(0.14, 0.12, 1.1), Color("3b6b8c"))
	Props.box(root, p + Vector3(0, 0.62, 0.2), Vector3(0.3, 0.1, 0.5), Color("2e2a26"))
	Props.box(root, p + Vector3(0, 0.85, -0.5), Vector3(0.6, 0.04, 0.04), IRON)

# ---------------------------------------------------------------- square

func square_point(x: float, z: float) -> Vector3:
	var sq: Dictionary = village.square
	var p: Vector3 = sq.center + Basis(Vector3.UP, float(sq.yaw)) * Vector3(x, 0, z)
	p.y = float(sq.height)
	return p

# Place du village: plane trees, fountain, pétanque, benches, market stalls
# and a war memorial on one even paving, open to the road on two sides.
func _square() -> void:
	var sq: Dictionary = village.square
	var root = node("VillageSquare", square_point(0, 0), float(sq.yaw))
	_paving(root, sq.half, Color("d6c6a6"))
	reserve(root.position, root.rotation.y, sq.half)
	for key in ["fountain", "petanque"]:
		village.anchors[key] = square_point(-3.5, 1.0) if key == "fountain" else square_point(-8.5, 0.0)
	# Plane trees with pale mottled bark and large crowns.
	for z in [-7.5, 7.5]:
		for x in [-9.0, -3.0, 3.0]:
			plane_tree(root, Vector3(x, 0, z), 1.0)
	_fountain(root, Vector3(-3.5, 0, 1.0))
	# Pétanque court: raked gravel inside a timber border.
	Props.box(root, Vector3(-8.5, 0.035, 0), Vector3(4.2, 0.05, 10.0), Color("c9b48c"))
	for x in [-10.6, -6.4]:
		Props.box(root, Vector3(x, 0.08, 0), Vector3(0.12, 0.14, 10.0), Color("8a6a48"))
	for z in [-5.0, 5.0]:
		Props.box(root, Vector3(-8.5, 0.08, z), Vector3(4.3, 0.14, 0.12), Color("8a6a48"))
	for item in [[-6.0, 4.6, PI], [-1.0, 4.6, PI], [-1.0, -4.6, 0.0]]:
		bench(root, Vector3(item[0], 0, item[1]), item[2])
		village.add_anchor("benches", {"pos": square_point(item[0], item[1]), "yaw": float(village.square.yaw) + item[2]})
	# Market stalls under the northern row of plane trees.
	var goods = [[Color("d9482f"), Color("e9c43b")], [Color("8c6cc0"), Color("b39ad6")], [Color("efe2b8"), Color("e0b45c")]]
	for i in range(3):
		_stall(root, Vector3(-6.0 + i * 6.0, 0, -10.6), goods[i], i)
	_memorial(root, Vector3(9.0, 0, -9.0))
	finish(root)

# Textured cobbled paving following the authored flat height.
func _paving(root: Node3D, half: Vector2, tint: Color) -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners = [Vector3(-half.x, 0.03, -half.y), Vector3(half.x, 0.03, -half.y), Vector3(-half.x, 0.03, half.y), Vector3(half.x, 0.03, half.y)]
	for v in [corners[0], corners[1], corners[2], corners[1], corners[3], corners[2]]:
		st.set_color(tint)
		st.set_uv(Vector2(v.x, v.z) * 0.45)
		st.add_vertex(v)
	st.generate_normals()
	var mesh = MeshInstance3D.new()
	mesh.name = "Paving"
	mesh.mesh = st.commit()
	mesh.material_override = village.road_material("cobble")
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.set_meta("unbatched", true)
	root.add_child(mesh)

func plane_tree(parent: Node3D, p: Vector3, scale: float) -> void:
	var tree = Node3D.new()
	parent.add_child(tree)
	tree.position = p
	var height = 5.2 * scale
	Props.cylinder(tree, Vector3(0, height * 0.5, 0), 0.26 * scale, 0.2 * scale, height, Color("b5b197"), 8)
	# Mottled plane bark: olive-grey and cream patches.
	for i in range(6):
		var angle = i * 1.3
		Props.box(tree, Vector3(cos(angle) * 0.2 * scale, 0.9 + i * 0.7, sin(angle) * 0.2 * scale), Vector3(0.2, 0.45, 0.2) * scale, Color("7d7f63") if i % 2 else Color("d9d3b8"))
	for i in range(3):
		var limb = Props.cylinder(tree, Vector3((i - 1) * 0.6 * scale, height + 0.6, (i % 2) * 0.3), 0.14 * scale, 0.09 * scale, 2.0 * scale, Color("b7af94"), 6)
		limb.rotation.z = (i - 1) * 0.5
	for i in range(7):
		var angle = i * TAU / 7.0
		var offset = Vector3(cos(angle) * 2.0, (i % 3) * 0.6, sin(angle) * 2.0) * scale
		var crown = MeshInstance3D.new()
		crown.mesh = batcher.meshes["crown"]
		crown.set_meta("batch_key", "crown")
		crown.material_override = Props.shared_material(Color("5f7f3e").lightened((i % 3) * 0.05))
		tree.add_child(crown)
		crown.position = Vector3(0, height + 1.8, 0) + offset
		crown.scale = Vector3(3.6, 2.6, 3.6) * scale
	var top = MeshInstance3D.new()
	top.mesh = batcher.meshes["crown"]
	top.set_meta("batch_key", "crown")
	top.material_override = Props.shared_material(Color("6a8a45"))
	tree.add_child(top)
	top.position = Vector3(0, height + 3.2 * scale, 0)
	top.scale = Vector3(4.4, 3.0, 4.4) * scale
	solids.solid(tree, Vector3(0, 1.6, 0), Vector3(0.6, 3.2, 0.6) * scale, "tree")

func bench(parent: Node3D, p: Vector3, yaw: float) -> void:
	var root = Node3D.new()
	parent.add_child(root)
	root.position = p
	root.rotation.y = yaw
	for slat in range(3):
		Props.box(root, Vector3(0, 0.46, -0.16 + slat * 0.15), Vector3(1.8, 0.05, 0.12), Color("4f6b55"))
	for y in [0.68, 0.84]:
		Props.box(root, Vector3(0, y, 0.24), Vector3(1.8, 0.1, 0.05), Color("4f6b55"))
	for x in [-0.75, 0.75]:
		Props.box(root, Vector3(x, 0.24, 0.02), Vector3(0.06, 0.48, 0.5), IRON)
	solids.solid(root, Vector3(0, 0.45, 0.05), Vector3(1.8, 0.9, 0.6), "street_furniture")

func _fountain(parent: Node3D, p: Vector3) -> void:
	var root = Node3D.new()
	root.name = "Fountain"
	parent.add_child(root)
	root.position = p
	var stone = Color("d9ccb0")
	Props.cylinder(root, Vector3(0, 0.35, 0), 2.1, 2.1, 0.7, stone, 8)
	Props.cylinder(root, Vector3(0, 0.62, 0), 1.85, 1.85, 0.12, Color("6f9aa3"), 8)
	Props.cylinder(root, Vector3(0, 1.2, 0), 0.32, 0.26, 1.7, stone, 8)
	Props.cylinder(root, Vector3(0, 2.1, 0), 0.8, 0.5, 0.25, stone, 8)
	Props.cylinder(root, Vector3(0, 2.45, 0), 0.2, 0.12, 0.5, Color("8a9a6a"), 8)
	for i in range(4):
		var angle = i * PI * 0.5
		var spout = Props.box(root, Vector3(cos(angle) * 0.42, 1.5, sin(angle) * 0.42), Vector3(0.36, 0.06, 0.06), Color("8a7a50"))
		spout.rotation.y = -angle
	solids.solid(root, Vector3(0, 0.6, 0), Vector3(3.6, 1.2, 3.6), "fountain")

func _stall(parent: Node3D, p: Vector3, goods: Array, index: int) -> void:
	var root = Node3D.new()
	parent.add_child(root)
	root.position = p
	Props.box(root, Vector3(0, 0.82, 0), Vector3(2.4, 0.08, 1.1), Color("a07a52"))
	for x in [-1.1, 1.1]:
		for z in [-0.5, 0.5]:
			Props.box(root, Vector3(x, 1.1, z), Vector3(0.06, 2.2, 0.06), Color("6e5a44"))
	for i in range(6):
		Props.box(root, Vector3(-1.0 + i * 0.4, 2.25, 0), Vector3(0.4, 0.05, 1.5), Color("efe6d2") if i % 2 else Color(["b33a32", "3d6b8a", "4e7a5a"][index]))
	for i in range(8):
		Props.box(root, Vector3(-0.95 + (i % 4) * 0.63, 0.92 + (i / 4) * 0.02, -0.25 + (i / 4) * 0.5), Vector3(0.5, 0.12, 0.38), goods[i % 2])
	solids.solid(root, Vector3(0, 0.6, 0), Vector3(2.4, 1.2, 1.1), "street_furniture")

# Monument aux morts: a stone obelisk on a stepped base inside a little railing.
func _memorial(parent: Node3D, p: Vector3) -> void:
	var root = Node3D.new()
	parent.add_child(root)
	root.position = p
	Props.box(root, Vector3(0, 0.15, 0), Vector3(2.6, 0.3, 2.6), Color("cfc4ab"))
	Props.box(root, Vector3(0, 0.55, 0), Vector3(1.6, 0.5, 1.6), Color("ddd3bb"))
	for part in [Props.cylinder(root, Vector3(0, 2.4, 0), 0.62, 0.32, 3.2, Color("e2d9c3"), 4), Props.cylinder(root, Vector3(0, 4.2, 0), 0.3, 0.0, 0.5, Color("e2d9c3"), 4)]:
		part.rotation.y = PI / 4
	Props.box(root, Vector3(0, 1.4, -0.62), Vector3(0.7, 0.5, 0.04), Color("9c8c5c"))
	for i in range(12):
		var angle = i * TAU / 12.0
		Props.cylinder(root, Vector3(cos(angle) * 1.6, 0.4, sin(angle) * 1.6), 0.03, 0.03, 0.8, IRON, 5)
	solids.solid(root, Vector3(0, 1.0, 0), Vector3(3.3, 2.0, 3.3), "monument")

# ---------------------------------------------------------------- landmarks

func _church() -> void:
	var p = grounded(village.anchor(Layout.CHURCH.s, Layout.CHURCH.lateral))
	var facing = -village.side(Layout.CHURCH.s)
	# Settle the nave to the street level in front of the tower door, so the
	# forecourt meets the pavement without a step; the floor stays above ground.
	p.y = minf(p.y, stage.ground(p + facing * 16.0))
	var root = node("VillageChurch", p, atan2(-facing.x, -facing.z))
	Interiors.church(self, root)
	# Forecourt between the tower door and the street.
	var forecourt = Node3D.new()
	forecourt.name = "VillageChurchSquare"
	root.add_child(forecourt)
	forecourt.position = Vector3(0, 0.0, -17.0)
	_paving(forecourt, Vector2(4.5, 3.0), Color("cbbb9b"))
	reserve(root.transform * Vector3(0, 0, -2.0), root.rotation.y, Vector2(6.0, 13.0))
	finish(root)

func _mairie() -> void:
	var p = square_point(-12.0 - 0.05, 0.0)
	var yaw = float(village.square.yaw) - PI * 0.5
	var root = node("VillageMairie", p, yaw)
	var width = 14.0
	var depth = 10.0
	var height = 8.8
	Props.box(root, Vector3(0, height * 0.5 - 0.2, depth * 0.5), Vector3(width, height + 0.4, depth), Color("efe4cc"))
	solids.solid(root, Vector3(0, height * 0.5, depth * 0.5), Vector3(width, height, depth), "building")
	reserve(root.transform * Vector3(0, 0, depth * 0.5), yaw, Vector2(width * 0.5, depth * 0.5))
	for floor in range(2):
		for i in range(5):
			window(root, Vector3(-5.2 + i * 2.6, 1.6 + floor * 3.6, 0), 0.0, Color("6f8796"), "balcony" if floor == 1 and i == 2 else "")
	Props.box(root, Vector3(0, 7.9, -0.1), Vector3(9.0, 0.7, 0.1), Color("d9cdb3"))
	var title = Props.label_3d(root, Vector3(0, 7.9, -0.17), "MAIRIE", 72, 0.006, Color("3b3a36"), PI)
	title.double_sided = false
	var motto = Props.label_3d(root, Vector3(0, 7.3, -0.17), "LIBERTÉ · ÉGALITÉ · FRATERNITÉ", 40, 0.0042, Color("5a554c"), PI)
	motto.double_sided = false
	# Two tricolour flags on brackets over the balcony.
	for x in [-1.1, 1.1]:
		var staff = Props.cylinder(root, Vector3(x, 6.3, -0.7), 0.03, 0.03, 1.8, IRON, 5)
		staff.rotation.x = -0.6
		var flag = Node3D.new()
		flag.name = "MairieFlag"
		root.add_child(flag)
		flag.position = Vector3(x, 6.95, -1.3)
		flag.set_meta("unbatched", true)
		for i in range(3):
			var stripe = Props.box(flag, Vector3(0.12 - 0.05, -0.35, -0.12 - i * 0.24), Vector3(0.02, 0.6, 0.24), [Color("2f4f9a"), Color("f2f2ee"), Color("d23a32")][i])
	roof(root, width + 0.3, depth + 1.0, height, 2.1, Color("a95a3a"), depth * 0.5)
	# Clock pediment.
	var clock = Props.cylinder(root, Vector3(0, height + 1.05, -0.05), 0.55, 0.55, 0.08, Color("f3eddc"), 16)
	clock.rotation.x = PI / 2
	Props.box(root, Vector3(0, height + 0.9, 0.2), Vector3(2.2, 1.9, 0.4), Color("efe4cc"))
	door(root, 0.0, Color("4f6b6b"), true)
	finish(root)

func _cafe() -> void:
	var p = square_point(4.0, 12.0 + 0.05)
	var yaw = float(village.square.yaw)
	var root = node("VillageCafe", p, yaw)
	house_count += 1
	var width = 14.0
	var depth = 9.0
	var height = 6.6
	var wall = Color("e2c18f")
	Props.box(root, Vector3(0, height * 0.5 - 0.3, depth * 0.5), Vector3(width, height + 0.6, depth), wall)
	solids.solid(root, Vector3(0, height * 0.5, depth * 0.5), Vector3(width, height, depth), "building")
	reserve(root.transform * Vector3(0, 0, depth * 0.5), yaw, Vector2(width * 0.5, depth * 0.5))
	_shopfront(root, width, {"text": "CAFÉ DE LA PLACE", "awning": ["f0e6cf", "9a2f2f"], "goods": "none"})
	for i in range(4):
		window(root, Vector3(-5.0 + i * 3.3, 4.4, 0), 0.0, Color("5f8e8c"), "flowers")
	genoise(root, width, 0.0, height, -1.0)
	roof(root, width + 0.1, depth + 0.9, height, 2.0, Color("b8653f"), depth * 0.5)
	finish(root)
	# Terrace tables on the square in front of the café.
	var terrace = node("VillageCafeTerrace", square_point(0, 0), float(village.square.yaw))
	for i in range(4):
		var x = 1.5 + (i % 2) * 3.6
		var z = 5.2 + (i / 2) * 2.8
		_cafe_table(terrace, Vector3(x, 0, z), i)
		for side_sign in [-1.0, 1.0]:
			var seat = terrace.transform * Transform3D(Basis(Vector3.UP, side_sign * PI * 0.5), Vector3(x + side_sign * 0.72, 0, z))
			village.add_anchor("cafe_seats", {"pos": seat.origin, "yaw": seat.basis.get_euler().y, "table": terrace.transform * Vector3(x, 0.78, z)})
	# Parasols.
	for x in [3.3]:
		Props.cylinder(terrace, Vector3(x, 1.25, 6.6), 0.03, 0.03, 2.5, Color("d8d2c2"), 5)
		Props.cylinder(terrace, Vector3(x, 2.45, 6.6), 2.2, 0.05, 0.6, Color("f0e6cf"), 8)
	finish(terrace)

func _cafe_table(parent: Node3D, p: Vector3, index: int) -> void:
	var table = Node3D.new()
	table.name = "CafeTable_%d" % index
	parent.add_child(table)
	table.position = p
	Props.cylinder(table, Vector3(0, 0.74, 0), 0.38, 0.38, 0.04, Color("e9e6dc"), 12)
	Props.cylinder(table, Vector3(0, 0.37, 0), 0.04, 0.04, 0.72, IRON, 6)
	Props.cylinder(table, Vector3(0.12, 0.81, 0.05), 0.04, 0.035, 0.09, Color("f4efe2"), 8)
	Props.cylinder(table, Vector3(-0.15, 0.85, -0.08), 0.03, 0.03, 0.18, Color("5b8a5a"), 8)
	for side_sign in [-1.0, 1.0]:
		var chair = Node3D.new()
		table.add_child(chair)
		chair.position = Vector3(side_sign * 0.72, 0, 0)
		chair.rotation.y = side_sign * PI * 0.5
		Props.box(chair, Vector3(0, 0.45, 0), Vector3(0.42, 0.04, 0.42), Color("b8743d"))
		Props.box(chair, Vector3(0, 0.7, 0.2), Vector3(0.42, 0.45, 0.04), Color("b8743d"))
		for x in [-0.18, 0.18]:
			for z in [-0.18, 0.18]:
				Props.cylinder(chair, Vector3(x, 0.22, z), 0.015, 0.015, 0.45, IRON, 4)
	solids.solid(table, Vector3(0, 0.45, 0), Vector3(2.0, 0.9, 0.8), "street_furniture")

# Lavoir: the open washhouse with a long stone basin under a tiled roof.
func _lavoir() -> void:
	var s: float = Layout.LAVOIR.s
	var p = grounded(village.anchor(s, Layout.LAVOIR.lateral - 3.0))
	var facing = village.side(s)
	var root = node("VillageLavoir", p, atan2(-facing.x, -facing.z))
	Props.box(root, Vector3(0, 0.05, 0), Vector3(8.0, 0.1, 6.0), Color("cdbf9f"))
	Props.box(root, Vector3(0, 0.38, 0.6), Vector3(6.4, 0.7, 2.6), Color("c9b896"))
	Props.box(root, Vector3(0, 0.6, 0.6), Vector3(5.8, 0.12, 2.0), Color("6f9aa3"))
	for x in [-3.0, 3.0]:
		Props.box(root, Vector3(x, 0.72, -0.8), Vector3(0.5, 0.06, 0.9), Color("d7cab0"))
	for x in [-3.7, 3.7]:
		for z in [-2.6, 2.6]:
			Props.box(root, Vector3(x, 1.5, z), Vector3(0.4, 3.0, 0.4), Color("d2c3a2"))
	Props.box(root, Vector3(0, 1.5, 2.9), Vector3(7.8, 3.0, 0.3), Color("d2c3a2"))
	roof(root, 8.6, 6.8, 3.0, 1.0, Color("a95a3a"))
	var spout = Props.box(root, Vector3(0, 1.2, 2.6), Vector3(0.1, 0.1, 0.5), Color("8a7a50"))
	solids.solid(root, Vector3(0, 0.4, 0.6), Vector3(6.4, 0.8, 2.6), "fountain")
	solids.solid(root, Vector3(0, 1.5, 2.9), Vector3(7.8, 3.0, 0.3), "building")
	for x in [-3.7, 3.7]:
		for z in [-2.6, 2.6]:
			solids.solid(root, Vector3(x, 1.5, z), Vector3(0.4, 3.0, 0.4), "building")
	reserve(p, root.rotation.y, Vector2(4.2, 3.2))
	finish(root)

func _cemetery() -> void:
	var c = Layout.CEMETERY
	var p = grounded(village.anchor(c.s, c.lateral))
	var root = node("VillageCemetery", p, village.yaw_at(c.s))
	var half: Vector2 = c.size * 0.5
	Props.box(root, Vector3(0, 0.02, 0), Vector3(c.size.x, 0.04, c.size.y), Color("bba886"))
	# Rendered-stone enclosure wall with a wrought-iron gate facing the lane.
	for side_sign in [-1.0, 1.0]:
		Props.box(root, Vector3(side_sign * half.x, 1.0, 0), Vector3(0.45, 2.0, c.size.y), Color("e3d6bb"))
		solids.solid(root, Vector3(side_sign * half.x, 1.0, 0), Vector3(0.45, 2.0, c.size.y), "wall")
	Props.box(root, Vector3(0, 1.0, half.y), Vector3(c.size.x, 2.0, 0.45), Color("e3d6bb"))
	solids.solid(root, Vector3(0, 1.0, half.y), Vector3(c.size.x, 2.0, 0.45), "wall")
	Props.box(root, Vector3(0, 1.0, -half.y), Vector3(c.size.x, 2.0, 0.45), Color("e3d6bb"))
	solids.solid(root, Vector3(0, 1.0, -half.y), Vector3(c.size.x, 2.0, 0.45), "wall")
	var graves = 0
	for row in range(4):
		for column in range(5):
			var g = Vector3(-6.0 + column * 3.0, 0, -7.0 + row * 4.4)
			Props.box(root, g + Vector3(0, 0.2, 0.6), Vector3(1.0, 0.4, 2.0), Color("d6d0c4").darkened((row + column) % 3 * 0.05))
			if (row + column) % 2 == 0:
				Props.box(root, g + Vector3(0, 0.75, -0.4), Vector3(0.12, 1.1, 0.12), Color("bdb7aa"))
				Props.box(root, g + Vector3(0, 1.0, -0.4), Vector3(0.6, 0.12, 0.12), Color("bdb7aa"))
			else:
				Props.box(root, g + Vector3(0, 0.6, -0.42), Vector3(0.9, 0.9, 0.14), Color("9d9a92"))
			graves += 1
	root.set_meta("graves", graves)
	reserve(p, root.rotation.y, half + Vector2(1.0, 1.0))
	for z in [-8.0, -2.0, 4.0]:
		for x in [-half.x - 1.4, half.x + 1.4]:
			village.landscape_hint("cypress", root.transform * Vector3(x, 0, z))
	finish(root)

# The mas with its lavender distillery: low stone farmhouse, still and stacks.
func _distillery() -> void:
	var s: float = Layout.DISTILLERY.s
	var p = grounded(village.anchor(s, Layout.DISTILLERY.lateral))
	var facing = -village.side(s)
	var yaw = atan2(-facing.x, -facing.z)
	house(p, yaw, 14.0, 8.0, 2, 2)
	var shed = node("LavenderDistillery", grounded(p + village.direction(s) * 13.0), yaw)
	for x in [-3.0, 3.0]:
		for z in [0.0, 5.0]:
			Props.box(shed, Vector3(x, 1.7, z), Vector3(0.3, 3.4, 0.3), Color("6b5236"))
			solids.solid(shed, Vector3(x, 1.7, z), Vector3(0.3, 3.4, 0.3), "landmark")
	roof(shed, 7.0, 6.2, 3.4, 1.1, Color("9e5236"), 2.5)
	# Copper still and a pile of dried lavender bales.
	Props.cylinder(shed, Vector3(-1.2, 1.0, 2.5), 0.9, 0.7, 2.0, Color("b06a3a"), 12)
	Props.cylinder(shed, Vector3(-1.2, 2.25, 2.5), 0.5, 0.15, 0.5, Color("b06a3a"), 12)
	var pipe = Props.cylinder(shed, Vector3(0.0, 2.3, 2.5), 0.08, 0.08, 2.4, Color("b06a3a"), 6)
	pipe.rotation.z = PI / 2
	Props.cylinder(shed, Vector3(1.4, 1.2, 2.5), 0.7, 0.7, 1.8, Color("8a8f8a"), 10)
	solids.solid(shed, Vector3(0, 1.0, 2.5), Vector3(4.6, 2.0, 2.0), "landmark")
	for i in range(6):
		Props.box(shed, Vector3(-4.6 + (i % 3) * 1.15, 0.35 + (i / 3) * 0.7, -2.0), Vector3(1.1, 0.68, 0.8), Color("9077b0"))
	solids.solid(shed, Vector3(-3.45, 0.7, -2.0), Vector3(3.5, 1.4, 0.8), "landmark")
	var chimney = Props.box(shed, Vector3(2.5, 4.6, 5.0), Vector3(0.6, 3.0, 0.6), Color("b9a582"))
	village.add_anchor("smoke", shed.transform * Vector3(2.5, 6.2, 5.0))
	reserve(shed.position, yaw, Vector2(4.0, 4.0))
	finish(shed)

# Borie: a corbelled dry-stone hut of the Provençal hills.
func _borie() -> void:
	var p = grounded(village.anchor(Layout.BORIE.s, Layout.BORIE.lateral))
	var root = node("VillageBorie", p, village.yaw_at(Layout.BORIE.s))
	for ring in range(6):
		var radius = 2.6 - ring * 0.4
		Props.cylinder(root, Vector3(0, 0.35 + ring * 0.55, 0), radius, radius - 0.32, 0.6, Color("a9a08c").darkened(ring % 2 * 0.06), 10)
	Props.cylinder(root, Vector3(0, 3.7, 0), 0.5, 0.15, 0.4, Color("a9a08c"), 8)
	Props.box(root, Vector3(0, 0.75, -2.45), Vector3(0.8, 1.5, 0.4), Color("3a332a"))
	Props.box(root, Vector3(0, 1.6, -2.45), Vector3(1.1, 0.2, 0.5), Color("b9b09a"))
	solids.solid(root, Vector3(0, 1.2, 0), Vector3(4.4, 2.4, 4.4), "building")
	reserve(p, root.rotation.y, Vector2(3.0, 3.0))
	for k in range(3):
		village.landscape_hint("cypress", root.transform * Vector3(-4.5 + k * 4.5, 0, 4.5))
	finish(root)

func _domaine() -> void:
	var s: float = Layout.DOMAINE.s
	var p = grounded(village.anchor(s, Layout.DOMAINE.lateral))
	var facing = village.side(s)
	var yaw = atan2(-facing.x, -facing.z)
	house(p, yaw, 16.0, 9.0, 2, 4)
	var root = node("VillageDomaine", grounded(p - facing * 2.5 + village.direction(s) * 3.0), yaw)
	var sign = Props.label_3d(root, Vector3(0, 2.4, -5.6), "DOMAINE DES CIGALES", 48, 0.006, Color("4a2a2f"), PI)
	sign.double_sided = false
	Props.box(root, Vector3(0, 2.4, -5.55), Vector3(4.6, 0.6, 0.06), Color("efe4cc"))
	for x in [-2.0, 2.0]:
		Props.box(root, Vector3(x, 1.2, -5.55), Vector3(0.12, 2.4, 0.12), Color("6b5236"))
	# Barrels and grape crates in the yard.
	for i in range(6):
		var barrel = Props.cylinder(root, Vector3(-5.0 + i * 1.0, 0.45, -8.0), 0.42, 0.42, 0.9, Color("7a4c30"), 12)
		barrel.rotation.z = PI / 2
		var hoop = Props.cylinder(root, Vector3(-5.0 + i * 1.0, 0.45, -8.0), 0.44, 0.44, 0.05, IRON, 12)
		hoop.rotation.z = PI / 2
	solids.solid(root, Vector3(-2.5, 0.45, -8.0), Vector3(6.0, 0.9, 1.0), "landmark")
	for i in range(8):
		var crate = Vector3(2.0 + (i % 4) * 0.62, 0.2 + (i / 4) * 0.4, -8.2)
		Props.box(root, crate, Vector3(0.58, 0.38, 0.42), Color("a37b50"))
		Props.box(root, crate + Vector3(0, 0.17, 0), Vector3(0.5, 0.08, 0.36), Color("4b2a46"))
	solids.solid(root, Vector3(2.95, 0.4, -8.2), Vector3(2.6, 0.8, 0.5), "landmark")
	finish(root)

func _cooperative() -> void:
	var s: float = Layout.COOPERATIVE.s
	var p = grounded(village.anchor(s, Layout.COOPERATIVE.lateral))
	var facing = -village.side(s)
	var root = node("VillageCooperative", p, atan2(-facing.x, -facing.z))
	var width = 22.0
	var depth = 12.0
	Props.box(root, Vector3(0, 3.0, depth * 0.5), Vector3(width, 6.6, depth), Color("e6d4ae"))
	solids.solid(root, Vector3(0, 3.3, depth * 0.5), Vector3(width, 6.6, depth), "building")
	reserve(root.transform * Vector3(0, 0, depth * 0.5), root.rotation.y, Vector2(width * 0.5, depth * 0.5))
	Props.box(root, Vector3(0, 5.2, -0.06), Vector3(15.0, 0.9, 0.1), Color("6e2f3c"))
	var title = Props.label_3d(root, Vector3(0, 5.2, -0.13), "CAVE COOPÉRATIVE", 80, 0.008, Color("f2e6cf"), PI)
	title.double_sided = false
	for i in range(3):
		Props.box(root, Vector3(-6.0 + i * 6.0, 1.8, 0.0), Vector3(3.2, 3.6, 0.12), Color("5a4a3a"))
	roof(root, width + 0.4, depth + 1.0, 6.6, 1.6, Color("b46e4b"), depth * 0.5)
	# Pale stone dressings: a plinth, arched upper windows and painted lettering.
	Props.box(root, Vector3(0, 0.3, -0.04), Vector3(width + 0.04, 0.6, 0.08), Color("c9b393"))
	for i in range(4):
		var x = -8.25 + i * 5.5
		Props.box(root, Vector3(x, 4.1, -0.05), Vector3(1.1, 1.0, 0.08), Color("3e4a46"))
		Props.cylinder(root, Vector3(x, 4.6, -0.05), 0.55, 0.55, 0.08, Color("3e4a46"), 10).rotation.x = PI / 2
		Props.box(root, Vector3(x, 3.55, -0.1), Vector3(1.3, 0.1, 0.16), TRIM)
	for i in range(3):
		Props.box(root, Vector3(-6.0 + i * 6.0, 3.7, -0.08), Vector3(3.5, 0.18, 0.14), TRIM)
	# Old oak barrels, stacked grape bins and a bench for the growers.
	var yard = Node3D.new()
	root.add_child(yard)
	yard.position = Vector3(0, 0, -3.5)
	for i in range(5):
		var barrel = Props.cylinder(yard, Vector3(7.0 + (i % 3) * 0.95, 0.45 + (i / 3) * 0.8, 0.0), 0.42, 0.42, 0.9, Color("7a4c30"), 12)
		barrel.rotation.x = PI / 2
		for z in [-0.3, 0.3]:
			var hoop = Props.cylinder(yard, Vector3(7.0 + (i % 3) * 0.95, 0.45 + (i / 3) * 0.8, z), 0.44, 0.44, 0.05, IRON, 12)
			hoop.rotation.x = PI / 2
	solids.solid(yard, Vector3(7.95, 0.8, 0.0), Vector3(3.0, 1.6, 1.0), "landmark")
	for i in range(9):
		var crate = Vector3(-9.0 + (i % 3) * 0.7, 0.2 + (i / 3) * 0.4, 0.4)
		Props.box(yard, crate, Vector3(0.62, 0.38, 0.5), Color("3f6e8c") if i % 4 else Color("c9483a"))
		Props.box(yard, crate + Vector3(0, 0.17, 0), Vector3(0.54, 0.06, 0.42), Color("4b2a46"))
	solids.solid(yard, Vector3(-8.3, 0.6, 0.4), Vector3(2.2, 1.2, 0.6), "landmark")
	bench(yard, Vector3(-2.0, 0, 1.2), 0.0)
	plane_tree(root, Vector3(-12.5, 0, -5.0), 1.0)
	# Concrete vats and the grape reception hopper.
	for i in range(3):
		Props.cylinder(root, Vector3(-7.0 + i * 3.2, 3.2, depth + 2.5), 1.3, 1.3, 6.4, Color("d8d2c2"), 12)
	solids.solid(root, Vector3(-3.8, 3.2, depth + 2.5), Vector3(10.0, 6.4, 2.8), "building")
	finish(root)
