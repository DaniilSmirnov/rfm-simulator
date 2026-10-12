extends RefCounted
# The camp grill: a static body, ten meat skewers drawn as one mesh that shows
# the remaining servings, and mushroom skewers with their own textured caps.
# The firebox holds its own coals and flames (GrillFire): a fresh grill is cold,
# burns with flames while it is lit and then glows as coals ready for skewers.
const P = preload("res://scripts/props.gd")
const MeshMerge = preload("res://scripts/mesh_merge.gd")
const COAL_COLD = Color("2b2724")
const COAL_HOT = Color("ff7a2a")
const SKEWER_HEIGHT = 0.99

static func build(parent: Node3D) -> Node3D:
	var root = Node3D.new()
	root.name = "PicnicGrill"
	root.set_meta("servings", P.FOOD_PORTIONS)
	parent.add_child(root)
	_fire(root)
	P.box(root, Vector3(0, 0.65, 0), Vector3(1.05, 0.32, 0.55), Color("393d37"))
	for x in [-0.43, 0.43]:
		for z in [-0.2, 0.2]:
			P.box(root, Vector3(x, 0.3, z), Vector3(0.05, 0.6, 0.05), Color("555c52"))
	# The bed the coals lie in: dark until the grill is lit (GrillFire).
	P.box(root, Vector3(0, 0.83, 0), Vector3(0.9, 0.03, 0.4), Color("21201e"))
	for i in range(5):
		P.box(root, Vector3(-0.36 + i * 0.18, 0.87, 0), Vector3(0.02, 0.02, 0.8), Color("d9cdb4"))
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
	return root

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
				for z in [-0.22, 0, 0.22]:
					var piece = P.box(holder, Vector3(_skewer_x(i), 0.99, z), Vector3(0.048, 0.055, 0.075), Color("99502e").lightened(float(i % 3) * 0.035))
					piece.rotation.y = float(i % 2) * 0.25
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

static func _skewer_stick(parent: Node3D, x: float) -> void:
	P.box(parent, Vector3(x, 0.93, 0), Vector3(0.012, 0.018, 0.72), Color("b9b3a3"))
	P.box(parent, Vector3(x, 0.95, -0.39), Vector3(0.018, 0.022, 0.16), Color("a57949"))

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
