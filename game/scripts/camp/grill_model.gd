extends RefCounted
# The camp grill: a welded sheet-steel mangal, a shallow open firebox on four
# angle-iron legs. The steel has gone dark from the fire: bronze-tinted along
# the rims, sooty inside, rust where the rain sits. Notched rims hold the
# skewers across the coals, two staggered rows of round air holes run low along
# the sides, bent-rod handles with wooden grips sit on the ends, and a rod shelf
# below carries a paper sack of charcoal, a poker and a piece of cardboard to
# fan with. Ten meat skewers are drawn as one mesh that shows the remaining
# servings; mushroom skewers keep their own textured caps.
# The firebox holds a bed of charcoal and ash, and its own glowing coals and
# flames (GrillFire): a fresh grill is cold, burns with flames while it is lit
# and then glows as coals ready for skewers.
const P = preload("res://scripts/core/props.gd")
const MeshMerge = preload("res://scripts/core/mesh_merge.gd")
const COAL_COLD = Color("2b2724")
const COAL_HOT = Color("ff7a2a")
const SKEWER_HEIGHT = 0.99

static func build(parent: Node3D) -> Node3D:
	var root = Node3D.new()
	root.name = "PicnicGrill"
	root.set_meta("servings", P.FOOD_PORTIONS)
	parent.add_child(root)
	_fire(root)
	_body(root)
	_bed(root)
	_shelf(root)
	# All meat skewers are one mesh: MeatServings shows the first `servings`
	# of them (grill_meat_mesh). Mushroom skewers keep their own textured caps.
	var meat = MeshInstance3D.new()
	meat.name = "MeatServings"
	meat.mesh = grill_meat_mesh(P.FOOD_PORTIONS)
	meat.set_meta("unbatched", true)
	root.add_child(meat)
	for i in range(P.FOOD_PORTIONS):
		var skewer_node = Node3D.new()
		skewer_node.name = "FoodSkewer_%02d" % i
		skewer_node.set_meta("unbatched", true)
		skewer_node.hide()
		root.add_child(skewer_node)
		var x = _skewer_x(i)
		var mushroom_group = Node3D.new()
		mushroom_group.name = "MushroomFood"
		skewer_node.add_child(mushroom_group)
		_skewer_stick(mushroom_group, x)
		for z in [-0.12, 0.0, 0.12]:
			P.cylinder(mushroom_group, Vector3(x, 0.912, z), 0.015, 0.012, 0.05, Color("d3c49b"), 5)
			P.faceted(mushroom_group, Vector3(x, 0.945, z), Vector3(0.055, 0.035, 0.07), Color("956337"), 12, 6).name = "MushroomCap_%s" % str(z)
		mushroom_group.hide()
	MeshMerge.bake(root, "grill")
	return load("res://scripts/player/perches.gd").mark(root, false)

# Fire-darkened steel, bronze where the heat licks over the rims, and the
# matte colours of soot, rust, ash and charcoal.
const STEEL = Color("3a3d3f")
const STEEL_EDGE = Color("4a4846")
const HEAT_TINT = Color("4d4038")
const SOOT = Color("1b1a19")
const RUST = Color("6b3f24")
const RUST_DARK = Color("4a2f21")
const ASH = Color("6f6b66")
const ASH_DARK = Color("5f5b56")
const CHARCOAL = [Color("1e1d1c"), Color("272523"), Color("2f2c2a"), Color("4d4a47")]
const ROD = Color("43413e")
const WOOD = Color("7a5232")
const RIM = 0.9
const FLOOR = 0.7
const HALF_LENGTH = 0.5
const HALF_WIDTH = 0.19
const WALL = 0.012
const SHELF_Y = 0.2

static var _metals: Dictionary = {}

# Steel parts share a slightly metallic material per colour (one extra surface
# in the baked mesh); everything else keeps the matte prop material.
static func _metal(node: MeshInstance3D) -> MeshInstance3D:
	var color: Color = node.material_override.albedo_color
	if not _metals.has(color):
		var mat = P.material(color)
		mat.metallic = 0.5
		mat.roughness = 0.7
		_metals[color] = mat
	node.material_override = _metals[color]
	return node

static func _steel(parent: Node3D, pos: Vector3, size: Vector3, color: Color = STEEL) -> MeshInstance3D:
	return _metal(P.box(parent, pos, size, color))

static var _tubes: Dictionary = {}

# A cylinder or cone without the side rings CylinderMesh adds by default: the
# grill has dozens of small round parts, and each ring costs triangles.
static func _tube(parent: Node3D, pos: Vector3, bottom: float, top: float, height: float, color: Color, sides: int) -> MeshInstance3D:
	var key = Vector4(bottom, top, height, sides)
	if not _tubes.has(key):
		var mesh = CylinderMesh.new()
		mesh.bottom_radius = bottom
		mesh.top_radius = top
		mesh.height = height
		mesh.radial_segments = sides
		mesh.rings = 0
		mesh.cap_top = top > 0.0
		_tubes[key] = mesh
	var node = MeshInstance3D.new()
	node.mesh = _tubes[key]
	node.material_override = P.shared_material(color)
	parent.add_child(node)
	node.position = pos
	return node

# A round steel rod from `a` to `b`.
static func _rod(parent: Node3D, a: Vector3, b: Vector3, radius: float, color: Color = ROD) -> MeshInstance3D:
	var rod = _tube(parent, (a + b) * 0.5, radius, radius, a.distance_to(b), color, 6)
	var axis = (b - a).normalized()
	var side = Vector3.UP.cross(axis)
	if side.length() > 0.001:
		rod.basis = Basis(side.normalized(), Vector3.UP.angle_to(axis))
	return _metal(rod)

static func _body(root: Node3D) -> void:
	var shapes: Array[AABB] = []
	var wall = RIM - FLOOR
	# Each wall is three bands (rusty foot, plain steel, heat-tinted top) with
	# a sooty face inside; the long ones carry the notches and the air holes.
	for z in [-HALF_WIDTH, HALF_WIDTH]:
		var out = signf(z)
		_wall_bands(root, Vector3(0, 0, z), Vector3(HALF_LENGTH * 2, 0, WALL))
		shapes.append(AABB(Vector3(-HALF_LENGTH, FLOOR, z - WALL * 0.5), Vector3(HALF_LENGTH * 2, wall, WALL)))
		P.box(root, Vector3(0, FLOOR + wall * 0.5, z - out * (WALL * 0.5 + 0.0015)), Vector3(HALF_LENGTH * 2 - 0.02, wall - 0.01, 0.002), SOOT)
		# A folded lip along the rim stiffens the long sides.
		_steel(root, Vector3(0, RIM + 0.003, z + out * 0.006), Vector3(HALF_LENGTH * 2 + 0.012, 0.01, 0.022), STEEL_EDGE)
		# The top edge is cut into narrow slots the skewers drop into.
		_steel(root, Vector3(0, RIM + 0.0155, z), Vector3(HALF_LENGTH * 2, 0.031, WALL), HEAT_TINT)
		var step = 0.84 / (P.FOOD_PORTIONS - 1)
		for i in range(P.FOOD_PORTIONS + 1):
			var left = maxf(_skewer_x(0) + (i - 1) * step + 0.008, -HALF_LENGTH)
			var right = minf(_skewer_x(0) + i * step - 0.008, HALF_LENGTH)
			_steel(root, Vector3((left + right) * 0.5, RIM + 0.04, z), Vector3(right - left, 0.018, WALL), HEAT_TINT)
		# Two staggered rows of round air holes, soot smudged above them.
		for row in range(2):
			for i in range(9 - row):
				var hole = _tube(root, Vector3(-0.4 + i * 0.1 + row * 0.05, FLOOR + 0.035 + row * 0.04, z + out * (WALL * 0.5 + 0.001)), 0.013, 0.013, 0.004, SOOT, 6)
				hole.rotation.x = PI / 2
		P.box(root, Vector3(0, FLOOR + 0.1, z + out * (WALL * 0.5 + 0.0012)), Vector3(0.84, 0.03, 0.002), Color("2a2827"))
		# Rust runs from the lower holes and patches near the legs.
		for x in [-0.36, -0.07, 0.22, 0.41]:
			P.box(root, Vector3(x, FLOOR + 0.012, z + out * (WALL * 0.5 + 0.0016)), Vector3(0.012, 0.024, 0.002), RUST)
		P.box(root, Vector3(-0.3 * out, FLOOR + 0.03, z + out * (WALL * 0.5 + 0.0018)), Vector3(0.11, 0.035, 0.002), RUST_DARK)
	for x in [-HALF_LENGTH, HALF_LENGTH]:
		var out = signf(x)
		_wall_bands(root, Vector3(x, 0, 0), Vector3(WALL, 0, HALF_WIDTH * 2))
		shapes.append(AABB(Vector3(x - WALL * 0.5, FLOOR, -HALF_WIDTH), Vector3(WALL, wall, HALF_WIDTH * 2)))
		P.box(root, Vector3(x - out * (WALL * 0.5 + 0.0015), FLOOR + wall * 0.5, 0), Vector3(0.002, wall - 0.01, HALF_WIDTH * 2 - 0.02), SOOT)
		_steel(root, Vector3(x + out * 0.006, RIM + 0.003, 0), Vector3(0.022, 0.01, HALF_WIDTH * 2 + 0.012), STEEL_EDGE)
		# Bent-rod handle with a wooden grip.
		for z in [-0.09, 0.09]:
			_rod(root, Vector3(x, 0.84, z), Vector3(x + out * 0.085, 0.84, z), 0.006)
		_rod(root, Vector3(x + out * 0.085, 0.84, -0.095), Vector3(x + out * 0.085, 0.84, 0.095), 0.006)
		var grip = _tube(root, Vector3(x + out * 0.085, 0.84, 0), 0.014, 0.014, 0.13, WOOD, 7)
		grip.rotation.x = PI / 2
	# Folded corner seams, and the bolts that fix the legs to them.
	for x in [-HALF_LENGTH, HALF_LENGTH]:
		for z in [-HALF_WIDTH, HALF_WIDTH]:
			_steel(root, Vector3(x, FLOOR + wall * 0.5, z), Vector3(0.022, wall, 0.022), STEEL_EDGE)
	var bottom = _steel(root, Vector3(0, FLOOR, 0), Vector3(HALF_LENGTH * 2, 0.012, HALF_WIDTH * 2), RUST_DARK)
	shapes.append(bottom.transform * bottom.mesh.get_aabb())
	_legs(root, shapes)
	root.set_meta("prop_shapes", shapes)

# Angle-iron legs bolted to the outside of the corners, splayed a little, on
# flat feet; their collision boxes go into `shapes`.
static func _legs(root: Node3D, shapes: Array[AABB]) -> void:
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var corner = Vector3(sx * (HALF_LENGTH + WALL * 0.5), FLOOR + 0.1, sz * (HALF_WIDTH + WALL * 0.5))
			shapes.append(AABB(Vector3(corner.x - 0.035, 0, corner.z - 0.035), Vector3(0.07, FLOOR, 0.07)))
			var leg = Node3D.new()
			root.add_child(leg)
			leg.position = corner
			leg.rotation = Vector3(-sz * 0.035, 0, sx * 0.035)
			var length = corner.y
			_steel(leg, Vector3(-sx * 0.0175, -length * 0.5, sz * 0.002), Vector3(0.035, length, 0.004))
			_steel(leg, Vector3(sx * 0.002, -length * 0.5, -sz * 0.0175), Vector3(0.004, length, 0.035))
			_steel(leg, Vector3(-sx * 0.014, -length + 0.004, -sz * 0.014), Vector3(0.055, 0.008, 0.055), SOOT)
			for y in [0.02, 0.07]:
				var bolt = _tube(root, Vector3(corner.x - sx * 0.018, FLOOR + y, corner.z + sz * 0.006), 0.007, 0.007, 0.006, STEEL_EDGE, 6)
				bolt.rotation.x = PI / 2

static func _wall_bands(root: Node3D, at: Vector3, size: Vector3) -> void:
	var wall = RIM - FLOOR
	var bands = [[0.0, 0.1, RUST_DARK], [0.1, 0.55, STEEL], [0.55, 1.0, HEAT_TINT]]
	for band in bands:
		var low = FLOOR + wall * float(band[0])
		var high = FLOOR + wall * float(band[1])
		_steel(root, Vector3(at.x, (low + high) * 0.5, at.z), Vector3(size.x, high - low, size.z), band[2])

# Charcoal and grey ash on the firebox floor: what a cold grill shows, and
# what the glowing coals (GrillFire) burn on.
static func _bed(root: Node3D) -> void:
	P.box(root, Vector3(0, FLOOR + 0.012, 0), Vector3(HALF_LENGTH * 2 - 0.03, 0.014, HALF_WIDTH * 2 - 0.03), ASH_DARK)
	for i in range(4):
		var drift = P.faceted(root, Vector3(-0.36 + i * 0.24, FLOOR + 0.02, sin(i * 1.9) * 0.08), Vector3(0.1, 0.012, 0.07), ASH, 7, 3)
		drift.rotation.y = i * 0.9
	# A heaped layer of charcoal over the whole floor, a few lumps grey with ash.
	for i in range(84):
		var col = i % 21
		var row = i / 21
		var jitter = Vector3(sin(i * 2.3) * 0.012, absf(sin(i * 1.1)) * 0.012 + float((col + row) % 2) * 0.008, cos(i * 1.7) * 0.012)
		var lump = P.faceted(root, Vector3(-0.455 + col * 0.0455, FLOOR + 0.034, -0.135 + row * 0.09) + jitter, Vector3(0.06, 0.038, 0.05), CHARCOAL[(i * 7) % CHARCOAL.size()], 4, 3)
		lump.rotation = Vector3(i * 0.7, i * 1.3, i * 0.4)
		lump.scale = Vector3.ONE * (0.8 + fmod(i * 0.29, 0.45))

# A rod shelf between the legs: the sack of charcoal, a few spilled lumps, a
# hooked poker and the cardboard everyone fans the coals with.
static func _shelf(root: Node3D) -> void:
	var half_x = HALF_LENGTH + 0.02
	var half_z = HALF_WIDTH + 0.02
	var shapes: Array = root.get_meta("prop_shapes")
	shapes.append(AABB(Vector3(-half_x, SHELF_Y - 0.006, -half_z), Vector3(half_x * 2, 0.012, half_z * 2)))
	root.set_meta("prop_shapes", shapes)
	for z in [-half_z, half_z]:
		_rod(root, Vector3(-half_x, SHELF_Y, z), Vector3(half_x, SHELF_Y, z), 0.007)
	for i in range(9):
		var x = -half_x + 0.03 + i * (half_x * 2 - 0.06) / 8.0
		_rod(root, Vector3(x, SHELF_Y + 0.006, -half_z), Vector3(x, SHELF_Y + 0.006, half_z), 0.004)
	# The kraft-paper sack slumps, its top rolled over, with a printed label.
	P.box(root, Vector3(-0.2, SHELF_Y + 0.1, 0.0), Vector3(0.28, 0.18, 0.17), Color("8a6740"))
	P.faceted(root, Vector3(-0.2, SHELF_Y + 0.19, 0.0), Vector3(0.28, 0.06, 0.17), Color("8a6740"), 8, 4)
	var fold = _tube(root, Vector3(-0.2, SHELF_Y + 0.22, 0.0), 0.025, 0.025, 0.25, Color("745532"), 7)
	fold.rotation.z = PI / 2
	P.box(root, Vector3(-0.2, SHELF_Y + 0.12, 0.0855), Vector3(0.18, 0.09, 0.002), Color("23262a"))
	P.box(root, Vector3(-0.2, SHELF_Y + 0.12, 0.0865), Vector3(0.12, 0.022, 0.002), Color("d8572d"))
	for i in range(3):
		var lump = P.faceted(root, Vector3(-0.02 + i * 0.03, SHELF_Y + 0.025, -0.1 + (i % 2) * 0.05), Vector3(0.05, 0.032, 0.042), CHARCOAL[i % 3], 5, 3)
		lump.rotation = Vector3(i * 0.8, i * 1.1, 0.3)
	_rod(root, Vector3(0.0, SHELF_Y + 0.02, 0.1), Vector3(0.44, SHELF_Y + 0.02, 0.05), 0.005, Color("5d5f5c"))
	_rod(root, Vector3(0.44, SHELF_Y + 0.02, 0.05), Vector3(0.46, SHELF_Y + 0.02, 0.09), 0.005, Color("5d5f5c"))
	var ring = _tube(root, Vector3(-0.015, SHELF_Y + 0.02, 0.102), 0.022, 0.022, 0.006, Color("5d5f5c"), 8)
	ring.rotation.x = PI / 2
	var card = P.box(root, Vector3(0.28, SHELF_Y + 0.016, -0.03), Vector3(0.24, 0.004, 0.2), Color("a9865a"))
	card.rotation = Vector3(0.02, 0.2, 0)
	P.box(card, Vector3(0.0, 0.0025, 0.06), Vector3(0.2, 0.001, 0.02), Color("6e5536"))

static var _coal_clusters: Array = []
static var _flame_tongues: Array = []
static var _fire_materials: Dictionary = {}

# A glowing coal is a clump of lumps in one mesh, shaded by vertex colour so
# the lumps glow unevenly under one animated colour.
static func _coal_mesh(variant: int) -> Mesh:
	if _coal_clusters.is_empty():
		for v in range(4):
			var holder = Node3D.new()
			for k in range(12):
				var lump = P.faceted(holder, Vector3(sin(v * 2.0 + k * 1.7) * 0.055, float(k % 3) * 0.012, cos(v * 1.3 + k * 2.3) * 0.06), Vector3(0.05, 0.034, 0.044), Color.WHITE.darkened(float((k + v) % 3) * 0.22), 5, 3)
				lump.rotation = Vector3(k * 0.9 + v, k * 1.4, v * 0.5)
				lump.scale = Vector3.ONE * (0.8 + float((k * 3 + v) % 4) * 0.12)
			var baked = MeshMerge.bake(holder)
			_coal_clusters.append(baked.mesh if baked != null else null)
			holder.free()
	return _coal_clusters[variant % _coal_clusters.size()]

# A flame tongue: an outer orange cone around a hotter yellow core, built from
# its base so it grows up out of the coals.
static func _flame_mesh(variant: int) -> Mesh:
	if _flame_tongues.is_empty():
		for v in range(3):
			var holder = Node3D.new()
			var outer = _tube(holder, Vector3(0, 0.13, 0), 0.055, 0.0, 0.26, Color("ff751e"), 6)
			outer.rotation.z = (v - 1) * 0.12
			for k in range(2):
				var core = _tube(holder, Vector3((k - 0.5) * 0.04, 0.09 + v * 0.01, (k - 0.5) * 0.03), 0.04, 0.0, 0.2 + k * 0.04, Color("ffc53f"), 6)
				core.rotation = Vector3(0.1 * k, 0, (k - 0.5) * 0.25)
			var baked = MeshMerge.bake(holder)
			_flame_tongues.append(baked.mesh if baked != null else null)
			holder.free()
	return _flame_tongues[variant % _flame_tongues.size()]

static func _fire_material(kind: String) -> StandardMaterial3D:
	if not _fire_materials.has(kind):
		var mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		_fire_materials[kind] = mat
	return _fire_materials[kind]

# Coals on the charcoal bed and the flames above them, kept out of the baked
# mesh so they can glow and move on their own. Both start hidden: the grill is
# cold.
static func _fire(root: Node3D) -> void:
	var fire = Node3D.new()
	fire.name = "GrillFire"
	fire.set_meta("unbatched", true)
	root.add_child(fire)
	# Lit at night while the coals glow (a cold grill hides GrillFire).
	preload("res://scripts/core/night_lights.gd").mark(fire, "grill")
	var coals = Node3D.new()
	coals.name = "Coals"
	fire.add_child(coals)
	for i in range(16):
		var coal = MeshInstance3D.new()
		coal.mesh = _coal_mesh(i)
		# Each coal glows on its own: a material of its own, tinted per frame.
		coal.material_override = _fire_material("coal").duplicate()
		coal.material_override.albedo_color = COAL_COLD
		coals.add_child(coal)
		coal.position = Vector3(-0.39 + (i / 2) * 0.11 + (i % 2) * 0.05, FLOOR + 0.045, (-0.07 if i % 2 == 0 else 0.07) + sin(i * 2.1) * 0.03)
		coal.rotation.y = i * 1.1
	var flames = Node3D.new()
	flames.name = "Flames"
	fire.add_child(flames)
	for i in range(8):
		var tongue = MeshInstance3D.new()
		tongue.mesh = _flame_mesh(i)
		tongue.material_override = _fire_material("flame")
		flames.add_child(tongue)
		tongue.position = Vector3(-0.37 + i * 0.105, FLOOR + 0.04, sin(i * 2.4) * 0.07)
		tongue.rotation.y = i * 0.8
	fire.hide()

# How hot the firebox looks: `heat` 0 cold, 1 glowing coals; `flame` 0..1 is the
# height of the flames above them, and 0 hides them for a bed of bare coals.
static func set_fire(grill_node: Node3D, heat: float, flame: float, time: float = 0.0) -> void:
	if grill_node == null:
		return
	var fire = grill_node.get_node_or_null("GrillFire")
	if fire == null:
		return
	fire.visible = heat > 0.0 or flame > 0.0
	if not fire.visible:
		return
	var coals: Node3D = fire.get_node("Coals")
	for i in range(coals.get_child_count()):
		var coal: MeshInstance3D = coals.get_child(i)
		var glow = clampf(heat * (0.72 + 0.28 * sin(time * 2.4 + i * 1.7)), 0.0, 1.0)
		coal.material_override.albedo_color = COAL_COLD.lerp(COAL_HOT, glow)
	var flames: Node3D = fire.get_node("Flames")
	flames.visible = flame > 0.001
	for i in range(flames.get_child_count()):
		var tongue: Node3D = flames.get_child(i)
		var height = flame * (0.75 + 0.45 * absf(sin(time * 7.0 + i * 1.3)))
		tongue.scale = Vector3(0.7 + flame * 0.4, maxf(0.05, height), 0.7 + flame * 0.4)

static var _grill_meat: Array = []
const MEAT = [Color("7a3a1f"), Color("8c4527"), Color("6e3219"), Color("94502e")]

# The first `count` meat skewers of a grill as one mesh (shared, built once).
static func grill_meat_mesh(count: int) -> Mesh:
	if _grill_meat.is_empty():
		for servings in range(P.FOOD_PORTIONS + 1):
			var holder = Node3D.new()
			for i in range(servings):
				var x = _skewer_x(i)
				_skewer_stick(holder, x)
				# Uneven browned chunks with onion rings between, charred on top.
				for k in range(5):
					var z = -0.13 + k * 0.065
					var piece = P.faceted(holder, Vector3(x, 0.937, z), Vector3(0.056, 0.05, 0.058), MEAT[(i + k) % MEAT.size()], 6, 3)
					piece.rotation = Vector3(float(k % 2) * 0.4, float(i + k) * 0.9, float((i + k) % 3 - 1) * 0.25)
					piece.scale = Vector3(1.0 + float((i * 2 + k) % 3) * 0.1, 0.9 + float((i + k * 2) % 3) * 0.1, 1.0)
					# The char sits half buried in the top of its chunk.
					P.box(piece, Vector3(0.004, 0.02, 0), Vector3(0.034, 0.012, 0.038), Color("3a2116"))
					if k < 4:
						var onion = _tube(holder, Vector3(x, 0.935, z + 0.0325), 0.022, 0.022, 0.01, Color("e4dcc4"), 6)
						onion.rotation = Vector3(PI / 2, 0, float(k) * 0.3)
			var baked = MeshMerge.bake(holder)
			_grill_meat.append(baked.mesh if baked != null else null)
			holder.free()
	return _grill_meat[clampi(count, 0, P.FOOD_PORTIONS)]

# Where a run of skewer slots sits in the world, with a gaze radius that covers
# it: food and free slots are offered separately, so the fan picks by looking.
static func slot_zone(grill_node: Node3D, from_index: int, count: int) -> Dictionary:
	var first = _skewer_x(clampi(from_index, 0, P.FOOD_PORTIONS - 1))
	var last = _skewer_x(clampi(from_index + maxi(1, count) - 1, 0, P.FOOD_PORTIONS - 1))
	var local = Vector3((first + last) * 0.5, SKEWER_HEIGHT, 0)
	return {"point": grill_node.global_transform * local, "radius": 0.26 + absf(last - first) * 0.5}

static func _skewer_x(index: int) -> float:
	return -0.42 + index * (0.84 / (P.FOOD_PORTIONS - 1))

# A flat steel skewer lying across both rims, its tip just past the far one,
# with a twisted shank and a ring hanging out over the near side.
static func _skewer_stick(parent: Node3D, x: float) -> void:
	P.box(parent, Vector3(x, 0.935, -0.01), Vector3(0.01, 0.004, 0.56), Color("b5b3ad"))
	var shank = P.box(parent, Vector3(x, 0.935, -0.32), Vector3(0.006, 0.006, 0.07), Color("a9a7a0"))
	shank.rotation.z = 0.7
	var ring = _tube(parent, Vector3(x, 0.935, -0.38), 0.026, 0.026, 0.005, Color("a9a7a0"), 8)
	ring.rotation.z = PI / 2

static func set_servings(grill_node: Node3D, servings: int) -> void:
	if grill_node == null:
		return
	var count = clampi(servings, 0, P.FOOD_PORTIONS)
	var mushrooms = clampi(int(grill_node.get_meta("mushrooms", 0)), 0, P.FOOD_PORTIONS - count)
	var state = Vector2i(count, mushrooms)
	if grill_node.get_meta("serving_visual_state", Vector2i(-1, -1)) == state:
		return
	grill_node.set_meta("serving_visual_state", state)
	grill_node.set_meta("servings", count)
	var meat = grill_node.get_node_or_null("MeatServings")
	if meat != null:
		meat.mesh = grill_meat_mesh(count)
	for i in range(P.FOOD_PORTIONS):
		var skewer_node = grill_node.get_node_or_null("FoodSkewer_%02d" % i)
		if skewer_node != null:
			skewer_node.visible = i >= count and i < count + mushrooms
			skewer_node.get_node("MushroomFood").visible = skewer_node.visible
