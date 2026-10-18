extends RefCounted
# The fans' folding camp chair: a low hiking chair on an aluminium frame. Side
# legs cross in an X and are pinned in the middle, rubber feet keep them out of
# the mud and a spreader tube ties each pair together. A canvas sling hangs
# between the side rails, the back is canvas stretched between two leaning
# posts with a stash pocket for the stage map behind it. Padded armrests carry
# a cup holder on the right and a hanging gear pocket on the left.
#   ChairModel.build(parent)            # a chair standing at the parent's origin
#   ChairModel.build(parent, offset)    # the same, shifted by `offset`
# The seat top stays at Props.CHAIR_SEAT (the character's seat pose and the
# perches rely on it); the back is on +Z, so a sitter looks along -Z.
# Everything is baked into one mesh shared by every chair.
const P = preload("res://scripts/core/props.gd")
const MeshMerge = preload("res://scripts/core/mesh_merge.gd")
const Perches = preload("res://scripts/player/perches.gd")
const SEAT = P.CHAIR_SEAT
const HALF_W = 0.31
const HALF_D = 0.28
const RAIL = SEAT - 0.03
const BACK_BOTTOM = 0.36
const BACK_TOP = 0.9
const POST_Z = 0.27
const LEAN = 0.11
const ARM = 0.54
const LEG_X = 0.22
const FRAME = Color("9aa1a6")
const FRAME_DARK = Color("4a4f55")
const RUBBER = Color("26292b")
const CANVAS = Color("cf703e")
const BINDING = Color("9c4f27")
const OLIVE = Color("4f5a3c")

static func build(parent: Node3D, offset: Vector3 = Vector3.ZERO) -> void:
	Perches.mark(parent, false)
	var holders: Array = []
	_seat(parent)
	_legs(parent)
	_back(parent, holders)
	_arms(parent)
	parent.set_meta("prop_shapes", _shapes(offset))
	var baked = MeshMerge.bake(parent, "chair")
	if baked != null:
		baked.position = offset
	# The baked mesh replaced their contents; the empty holders go too.
	for holder in holders:
		holder.free()

# What a knocked-over chair collides with: a thick seat slab, a tall back and
# four leg posts. The posts stand closer together than the visible feet, so a
# chair that is struck tips and stays down instead of sliding away upright. The
# tubes and the armrests are left out so it slides cleanly.
static func _shapes(offset: Vector3) -> Array[AABB]:
	var shapes: Array[AABB] = [
		AABB(Vector3(-0.325, SEAT - 0.09, -0.325), Vector3(0.65, 0.09, 0.65)),
		AABB(Vector3(-0.325, SEAT, 0.26), Vector3(0.65, 0.65, 0.08))]
	for x in [-LEG_X, LEG_X]:
		for z in [-0.27, 0.27]:
			shapes.append(AABB(Vector3(x - 0.03, 0.0, z - 0.03), Vector3(0.06, SEAT - 0.09, 0.06)))
	for i in range(shapes.size()):
		shapes[i].position += offset
	return shapes

# A tube between two points; always built from the lower end upwards.
static func _tube(parent: Node3D, from: Vector3, to: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var tube = P.cylinder(parent, (from + to) * 0.5, radius, radius, from.distance_to(to), color, 6)
	tube.quaternion = Quaternion(Vector3.UP, (to - from).normalized())
	return tube

static func _post_z(y: float) -> float:
	return POST_Z + LEAN * (y - RAIL) / (BACK_TOP - RAIL)

static func _seat(parent: Node3D) -> void:
	# Canvas sling between the side rails, hemmed with a darker binding at the
	# front and the back.
	P.box(parent, Vector3(0, SEAT - 0.01, 0), Vector3(HALF_W * 2 - 0.05, 0.02, HALF_D * 2 - 0.06), CANVAS)
	for z in [-1, 1]:
		P.box(parent, Vector3(0, SEAT - 0.012, z * (HALF_D - 0.015)), Vector3(HALF_W * 2 - 0.05, 0.024, 0.03), BINDING)
	for x in [-1, 1]:
		_tube(parent, Vector3(x * HALF_W, RAIL, -HALF_D), Vector3(x * HALF_W, RAIL, HALF_D), 0.014, FRAME)
	for z in [-1, 1]:
		_tube(parent, Vector3(-HALF_W, RAIL, z * HALF_D), Vector3(HALF_W, RAIL, z * HALF_D), 0.012, FRAME)

static func _legs(parent: Node3D) -> void:
	# Two crossing tubes on each side: one runs from the front foot up to the
	# rear of the seat rail, the other from the rear foot up to the front.
	var inner = HALF_W + 0.014
	var outer = HALF_W + 0.04
	var foot = 0.03
	for side in [-1, 1]:
		_tube(parent, Vector3(side * inner, foot, -0.2), Vector3(side * inner, RAIL, 0.26), 0.014, FRAME)
		_tube(parent, Vector3(side * outer, foot, 0.2), Vector3(side * outer, RAIL, -0.26), 0.014, FRAME)
		# The pivot bolt where they cross.
		var bolt = P.cylinder(parent, Vector3(side * (inner + outer) * 0.5, (foot + RAIL) * 0.5, 0), 0.02, 0.02, 0.07, FRAME_DARK, 8)
		bolt.rotation.z = PI / 2
		P.cylinder(parent, Vector3(side * inner, foot * 0.5, -0.2), 0.022, 0.022, foot, RUBBER, 8)
		P.cylinder(parent, Vector3(side * outer, foot * 0.5, 0.2), 0.022, 0.022, foot, RUBBER, 8)
	# Spreaders keep each pair of feet apart.
	_tube(parent, Vector3(-inner, 0.045, -0.2), Vector3(inner, 0.045, -0.2), 0.011, FRAME)
	_tube(parent, Vector3(-outer, 0.045, 0.2), Vector3(outer, 0.045, 0.2), 0.011, FRAME)

static func _back(parent: Node3D, holders: Array) -> void:
	var lean = atan2(LEAN, BACK_TOP - RAIL)
	for side in [-1, 1]:
		_tube(parent, Vector3(side * HALF_W, RAIL, POST_Z), Vector3(side * HALF_W, BACK_TOP, POST_Z + LEAN), 0.014, FRAME)
	_tube(parent, Vector3(-HALF_W, BACK_TOP, POST_Z + LEAN), Vector3(HALF_W, BACK_TOP, POST_Z + LEAN), 0.014, FRAME)
	# The canvas sits between the posts and leans with them.
	var low = BACK_BOTTOM
	var high = BACK_TOP - 0.05
	var mid = (low + high) * 0.5
	var length = (high - low) / cos(lean)
	var panel = Node3D.new()
	parent.add_child(panel)
	panel.position = Vector3(0, mid, _post_z(mid))
	panel.rotation.x = lean
	holders.append(panel)
	var width = HALF_W * 2 - 0.05
	P.box(panel, Vector3.ZERO, Vector3(width, length, 0.014), CANVAS)
	for edge in [-1, 1]:
		P.box(panel, Vector3(0, edge * (length * 0.5 - 0.015), 0), Vector3(width + 0.01, 0.03, 0.02), BINDING)
	# A seam across the back and the stash pocket behind it.
	P.box(panel, Vector3(0, 0.03, 0), Vector3(width - 0.03, 0.008, 0.017), BINDING)
	P.box(panel, Vector3(0, -0.07, 0.013), Vector3(0.4, 0.17, 0.012), OLIVE)
	P.box(panel, Vector3(0, 0.005, 0.014), Vector3(0.4, 0.02, 0.016), BINDING)

static func _arms(parent: Node3D) -> void:
	var x = HALF_W + 0.04
	var rear_z = _post_z(ARM)
	for side in [-1, 1]:
		# Armrest tube, its front support and a padded cover on top.
		_tube(parent, Vector3(side * x, ARM, -0.22), Vector3(side * x, ARM, rear_z), 0.014, FRAME)
		_tube(parent, Vector3(side * x, RAIL, -0.26), Vector3(side * x, ARM, -0.22), 0.014, FRAME)
		P.box(parent, Vector3(side * x, ARM + 0.027, 0.0), Vector3(0.07, 0.04, 0.4), OLIVE)
	# Cup holder at the front of the right armrest: a bracket and a deep fabric cup.
	_tube(parent, Vector3(x, ARM - 0.012, -0.2), Vector3(x, ARM - 0.012, -0.3), 0.01, FRAME)
	P.cylinder(parent, Vector3(x, ARM - 0.04, -0.31), 0.034, 0.042, 0.1, OLIVE, 10)
	P.cylinder(parent, Vector3(x, ARM + 0.0105, -0.31), 0.034, 0.034, 0.004, RUBBER, 10)
	# Gear pocket hanging off the left armrest with a flap on top.
	P.box(parent, Vector3(-x - 0.025, ARM - 0.14, 0.02), Vector3(0.022, 0.2, 0.26), OLIVE)
	P.box(parent, Vector3(-x - 0.025, ARM - 0.055, 0.02), Vector3(0.03, 0.05, 0.27), BINDING)
