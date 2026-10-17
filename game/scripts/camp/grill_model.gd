extends RefCounted
# The camp grill: a folding steel mangal on four angle-iron legs, open at the
# top, with notched rims the skewers rest on, air holes along the sides, side
# handles and a shelf below with a sack of charcoal. Ten meat skewers are drawn
# as one mesh that shows the remaining servings; mushroom skewers keep their own
# textured caps.
# The firebox holds its own coals and flames (GrillFire): a fresh grill is cold,
# burns with flames while it is lit and then glows as coals ready for skewers.
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
		for z in [-0.2, 0.0, 0.2]:
			P.cylinder(mushroom_group, Vector3(x, 0.96, z), 0.015, 0.012, 0.05, Color("d3c49b"), 5)
			P.faceted(mushroom_group, Vector3(x, 1.0, z), Vector3(0.055, 0.035, 0.07), Color("956337"), 12, 6).name = "MushroomCap_%s" % str(z)
		mushroom_group.hide()
	MeshMerge.bake(root, "grill")
	return load("res://scripts/player/perches.gd").mark(root, false)

const STEEL = Color("34383a")
const STEEL_EDGE = Color("4c5154")
const SOOT = Color("1b1a19")
const ASH = Color("2a2725")
const RIM = 0.9
const HALF_LENGTH = 0.5
const HALF_WIDTH = 0.25

static func _body(root: Node3D) -> void:
	# Firebox: thin walls and a floor; the bed of ash the coals lie on is dark
	# until the grill is lit (GrillFire draws the glowing coals over it).
	var shapes: Array[AABB] = []
	var floor_y = 0.6
	var wall = RIM - floor_y
	for z in [-HALF_WIDTH, HALF_WIDTH]:
		var side = P.box(root, Vector3(0, floor_y + wall * 0.5, z), Vector3(HALF_LENGTH * 2, wall, 0.014), STEEL)
		shapes.append(side.transform * side.mesh.get_aabb())
		# A rolled edge along the rim stiffens the long sides.
		P.box(root, Vector3(0, RIM + 0.004, z), Vector3(HALF_LENGTH * 2 + 0.01, 0.012, 0.024), STEEL_EDGE)
		# Notches: the skewers drop between these teeth.
		for i in range(P.FOOD_PORTIONS + 1):
			var x = clampf(_skewer_x(0) + (i - 0.5) * (0.84 / (P.FOOD_PORTIONS - 1)), -HALF_LENGTH + 0.01, HALF_LENGTH - 0.01)
			P.box(root, Vector3(x, RIM + 0.022, z), Vector3(0.03, 0.026, 0.016), STEEL_EDGE)
		# Air holes in a row low on each side, scorched around.
		for i in range(9):
			var hole_x = -0.4 + i * 0.1
			var outward = signf(z) * 0.0085
			P.box(root, Vector3(hole_x, floor_y + 0.07, z + outward), Vector3(0.05, 0.04, 0.004), SOOT)
	for x in [-HALF_LENGTH, HALF_LENGTH]:
		var side = P.box(root, Vector3(x, floor_y + wall * 0.5, 0), Vector3(0.014, wall, HALF_WIDTH * 2), STEEL)
		shapes.append(side.transform * side.mesh.get_aabb())
		P.box(root, Vector3(x, RIM + 0.004, 0), Vector3(0.024, 0.012, HALF_WIDTH * 2 + 0.01), STEEL_EDGE)
		# Bent rod handle on each end.
		var out = signf(x)
		for z in [-0.1, 0.1]:
			P.box(root, Vector3(x + out * 0.04, 0.82, z), Vector3(0.08, 0.014, 0.014), STEEL_EDGE)
		P.box(root, Vector3(x + out * 0.08, 0.82, 0), Vector3(0.014, 0.014, 0.214), STEEL_EDGE)
	var bottom = P.box(root, Vector3(0, floor_y, 0), Vector3(HALF_LENGTH * 2, 0.014, HALF_WIDTH * 2), STEEL)
	shapes.append(bottom.transform * bottom.mesh.get_aabb())
	P.box(root, Vector3(0, 0.83, 0), Vector3(HALF_LENGTH * 2 - 0.03, 0.02, HALF_WIDTH * 2 - 0.03), ASH)
	# Angle-iron legs with small feet, and a shelf between them.
	for x in [-HALF_LENGTH + 0.03, HALF_LENGTH - 0.03]:
		for z in [-HALF_WIDTH + 0.03, HALF_WIDTH - 0.03]:
			shapes.append(AABB(Vector3(x - 0.03, 0, z - 0.03), Vector3(0.06, floor_y, 0.06)))
			P.box(root, Vector3(x, floor_y * 0.5, z - signf(z) * 0.012), Vector3(0.04, floor_y, 0.006), STEEL)
			P.box(root, Vector3(x - signf(x) * 0.012, floor_y * 0.5, z), Vector3(0.006, floor_y, 0.04), STEEL)
			P.box(root, Vector3(x, 0.006, z), Vector3(0.06, 0.012, 0.06), SOOT)
	var shelf_y = 0.2
	var shelf = P.box(root, Vector3(0, shelf_y, 0), Vector3(HALF_LENGTH * 2 - 0.08, 0.012, HALF_WIDTH * 2 - 0.06), STEEL)
	shapes.append(shelf.transform * shelf.mesh.get_aabb())
	root.set_meta("prop_shapes", shapes)
	# A paper sack of charcoal, folded over at the top, and a poker beside it.
	P.box(root, Vector3(-0.2, shelf_y + 0.13, 0.02), Vector3(0.34, 0.25, 0.2), Color("8a6740"))
	P.box(root, Vector3(-0.2, shelf_y + 0.27, 0.02), Vector3(0.345, 0.04, 0.205), Color("745532"))
	P.box(root, Vector3(-0.2, shelf_y + 0.14, 0.1205), Vector3(0.2, 0.09, 0.002), Color("23262a"))
	P.box(root, Vector3(-0.2, shelf_y + 0.14, 0.1215), Vector3(0.12, 0.022, 0.002), Color("d8572d"))
	for i in range(4):
		P.faceted(root, Vector3(0.12 + i * 0.07, shelf_y + 0.03, -0.08 + (i % 2) * 0.1), Vector3(0.06, 0.04, 0.05), SOOT, 6, 3)
	var poker = P.box(root, Vector3(0.22, shelf_y + 0.012, 0.1), Vector3(0.5, 0.012, 0.012), Color("5d5f5c"))
	poker.rotation.y = 0.15

# Coals on the grate and the flames above them, kept out of the baked mesh so
# they can glow and move on their own. Both start hidden: the grill is cold.
static func _fire(root: Node3D) -> void:
	var fire = Node3D.new()
	fire.name = "GrillFire"
	fire.set_meta("unbatched", true)
	root.add_child(fire)
	var coals = Node3D.new()
	coals.name = "Coals"
	fire.add_child(coals)
	for i in range(16):
		var row = -0.09 if i % 2 == 0 else 0.09
		var coal = P.faceted(coals, Vector3(-0.39 + (i / 2) * 0.11 + (i % 2) * 0.05, 0.853, row + sin(i * 2.1) * 0.03), Vector3(0.105, 0.038, 0.12), COAL_COLD, 6, 3)
		P.unique_material(coal)
		coal.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var flames = Node3D.new()
	flames.name = "Flames"
	fire.add_child(flames)
	for i in range(8):
		var flame = P.faceted(flames, Vector3(-0.37 + i * 0.105, 0.95, sin(i * 2.4) * 0.08), Vector3(0.1, 0.3, 0.1), Color("ff751e") if i % 2 else Color("ffc53f"), 6, 3)
		P.unique_material(flame)
		flame.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
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

# The first `count` meat skewers of a grill as one mesh (shared, built once).
static func grill_meat_mesh(count: int) -> Mesh:
	if _grill_meat.is_empty():
		for servings in range(P.FOOD_PORTIONS + 1):
			var holder = Node3D.new()
			for i in range(servings):
				_skewer_stick(holder, _skewer_x(i))
				# Browned chunks with onion between, charred along the top.
				for k in range(5):
					var z = -0.2 + k * 0.1
					var piece = P.box(holder, Vector3(_skewer_x(i), 0.985, z), Vector3(0.05, 0.05, 0.07), Color("8c4527").lightened(float((i + k) % 3) * 0.05))
					piece.rotation = Vector3(float(k % 2) * 0.2, float(i % 2) * 0.25, float((i + k) % 3 - 1) * 0.15)
					P.box(holder, Vector3(_skewer_x(i), 1.011, z), Vector3(0.044, 0.006, 0.06), Color("3a2116"))
					if k < 4:
						P.box(holder, Vector3(_skewer_x(i), 0.98, z + 0.05), Vector3(0.042, 0.042, 0.016), Color("e4dcc4"))
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

# A flat steel skewer lying across both rims, with a twisted shank and a ring.
static func _skewer_stick(parent: Node3D, x: float) -> void:
	P.box(parent, Vector3(x, 0.935, 0.02), Vector3(0.01, 0.016, 0.66), Color("c4c2bb"))
	var shank = P.box(parent, Vector3(x, 0.94, -0.36), Vector3(0.012, 0.012, 0.1), Color("a9a7a0"))
	shank.rotation.z = 0.7
	var ring = P.cylinder(parent, Vector3(x, 0.945, -0.43), 0.026, 0.026, 0.006, Color("a9a7a0"), 8)
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
