extends RefCounted
# Eastern grey kangaroo of the «Майншафт» stage, facing -z, about 1.4 m tall
# when standing. Pear-shaped body over massive haunches, long flat hind feet,
# a thick tapering tail, short forearms held at the chest, a slender neck, a
# deer-like head with a long muzzle and tall ears. Two poses share one node:
# "Stand" (upright, tail on the ground) and "Bound" (body level, legs thrown
# back, tail out as a counterweight); outback_life.gd shows one at a time.
const Props = preload("res://scripts/props.gd")
const MeshMerge = preload("res://scripts/mesh_merge.gd")

const GREY = Color("8a7a69")
const BUCK = Color("6f5f51")
const BELLY = Color("d2c3a8")
const DARK = Color("2b2420")
const PAW = Color("4a3d33")

static func build(buck: bool) -> Node3D:
	var roo = Node3D.new()
	roo.name = "Kangaroo"
	var fur = BUCK if buck else GREY
	var key = "kangaroo:%s:" % ("buck" if buck else "doe")
	var stand = Node3D.new()
	stand.name = "Stand"
	roo.add_child(stand)
	_body(stand, fur, false)
	MeshMerge.bake(stand, key + "stand")
	var bound = Node3D.new()
	bound.name = "Bound"
	roo.add_child(bound)
	_body(bound, fur, true)
	MeshMerge.bake(bound, key + "bound")
	bound.visible = false
	if buck:
		roo.scale = Vector3.ONE * 1.15
	return roo

# Shows the pose for a hop height: bounding in the air, standing on the ground.
static func pose(roo: Node3D, airborne: bool) -> void:
	roo.get_node("Stand").visible = not airborne
	roo.get_node("Bound").visible = airborne

# A tapered round segment from a to b (limbs, neck, tail, muzzle).
static func _limb(parent: Node3D, a: Vector3, b: Vector3, radius_a: float, radius_b: float, color: Color) -> void:
	var direction = b - a
	var part = Props.cylinder(parent, (a + b) * 0.5, radius_a, radius_b, direction.length(), color, 7)
	part.basis = Basis(Quaternion(Vector3.UP, direction.normalized()))

static func _blob(parent: Node3D, at: Vector3, size: Vector3, color: Color, pitch: float = 0.0) -> void:
	var part = Props.faceted(parent, at, size, color, 8, 4)
	part.rotation.x = pitch

static func _body(root: Node3D, fur: Color, bounding: bool) -> void:
	# Bounding swings the whole upper body forward around the hips.
	var lean = -1.05 if bounding else -0.42
	var hip = Vector3(0, 0.62 if bounding else 0.5, 0.12)
	var up = Vector3(0, cos(lean), sin(lean))
	var chest = hip + up * 0.42
	_blob(root, hip, Vector3(0.34, 0.46, 0.5), fur, lean * 0.5)
	_blob(root, hip + up * 0.26, Vector3(0.27, 0.5, 0.3), fur, lean)
	_blob(root, hip + up * 0.24 + Vector3(0, 0, -0.1).rotated(Vector3.RIGHT, lean), Vector3(0.2, 0.44, 0.12), Color(BELLY), lean)
	# Neck and head; the head stays level whatever the body does.
	var head = chest + up * 0.12 + Vector3(0, 0.14, -0.1)
	_limb(root, chest + up * 0.02, head + Vector3(0, -0.03, 0.03), 0.075, 0.055, fur)
	_blob(root, head, Vector3(0.13, 0.13, 0.17), fur)
	_limb(root, head + Vector3(0, -0.01, -0.06), head + Vector3(0, -0.05, -0.19), 0.05, 0.028, fur)
	Props.box(root, head + Vector3(0, -0.05, -0.2), Vector3(0.045, 0.03, 0.025), DARK)
	for side in [-1.0, 1.0]:
		Props.box(root, head + Vector3(side * 0.055, 0.025, -0.07), Vector3(0.022, 0.022, 0.02), DARK)
		var ear = Props.faceted(root, head + Vector3(side * 0.045, 0.13, 0.03), Vector3(0.055, 0.17, 0.03), fur, 6, 3)
		ear.rotation = Vector3(-0.15, 0, -side * 0.28)
		var inner = Props.faceted(root, head + Vector3(side * 0.045, 0.13, 0.015), Vector3(0.032, 0.12, 0.012), BELLY.darkened(0.15), 5, 2)
		inner.rotation = Vector3(-0.15, 0, -side * 0.28)
		_arm(root, chest, up, side, fur, bounding)
		_hind_leg(root, hip, side, fur, bounding)
	_tail(root, hip, fur, bounding)

# Short forearms held in front of the chest, small dark paws.
static func _arm(root: Node3D, chest: Vector3, up: Vector3, side: float, fur: Color, bounding: bool) -> void:
	var shoulder = chest - up * 0.06 + Vector3(side * 0.09, 0, -0.07)
	var elbow = shoulder + Vector3(side * 0.02, -0.13, -0.05)
	var paw = elbow + (Vector3(0, -0.02, -0.12) if bounding else Vector3(0, -0.1, -0.06))
	_limb(root, shoulder, elbow, 0.035, 0.03, fur)
	_limb(root, elbow, paw, 0.028, 0.022, fur)
	Props.box(root, paw, Vector3(0.04, 0.035, 0.05), PAW)

# Massive haunch, a long shin running back to the heel and a long flat foot.
static func _hind_leg(root: Node3D, hip: Vector3, side: float, fur: Color, bounding: bool) -> void:
	var thigh = hip + Vector3(side * 0.13, -0.08, 0.0)
	_blob(root, thigh, Vector3(0.18, 0.38, 0.46), fur, -0.35)
	var knee = thigh + (Vector3(0, -0.12, 0.08) if bounding else Vector3(0, -0.14, -0.14))
	var heel = Vector3(side * 0.11, 0.06, 0.24) if not bounding else thigh + Vector3(0, -0.3, 0.42)
	var toe = Vector3(side * 0.1, 0.03, -0.24) if not bounding else heel + Vector3(0, -0.18, 0.36)
	_limb(root, knee, heel, 0.065, 0.04, fur)
	_limb(root, heel, toe, 0.045, 0.028, fur.darkened(0.15))

# Thick at the root, tapering to a dark tip; on the ground when standing,
# streaming out behind when bounding.
static func _tail(root: Node3D, hip: Vector3, fur: Color, bounding: bool) -> void:
	var points = [hip + Vector3(0, -0.06, 0.2)]
	var bends = [Vector3(0, 0.02, 0.38), Vector3(0, 0.06, 0.36), Vector3(0, 0.1, 0.32)] if bounding else [Vector3(0, -0.24, 0.32), Vector3(0, -0.17, 0.36), Vector3(0, -0.04, 0.36)]
	for bend in bends:
		points.append(points[-1] + bend)
	if not bounding:
		points[-1].y = maxf(points[-1].y, 0.04)
		points[-2].y = maxf(points[-2].y, 0.07)
	var radii = [0.11, 0.08, 0.055, 0.025]
	for i in range(3):
		_limb(root, points[i], points[i + 1], radii[i], radii[i + 1], fur if i < 2 else fur.darkened(0.25))
