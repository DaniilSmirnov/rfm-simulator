extends RefCounted
# The camp grill: a static body, ten meat skewers drawn as one mesh that shows
# the remaining servings, and mushroom skewers with their own textured caps.
const P = preload("res://scripts/props.gd")
const MeshMerge = preload("res://scripts/mesh_merge.gd")

static func build(parent: Node3D) -> Node3D:
	var root = Node3D.new()
	root.name = "PicnicGrill"
	root.set_meta("servings", P.FOOD_PORTIONS)
	parent.add_child(root)
	P.box(root, Vector3(0, 0.65, 0), Vector3(1.05, 0.32, 0.55), Color("393d37"))
	for x in [-0.43, 0.43]:
		for z in [-0.2, 0.2]:
			P.box(root, Vector3(x, 0.3, z), Vector3(0.05, 0.6, 0.05), Color("555c52"))
	P.box(root, Vector3(0, 0.83, 0), Vector3(0.9, 0.03, 0.4), Color("d9612e"))
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
