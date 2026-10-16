extends RefCounted
# Bactrian camel of «Чарынский каньон», facing -z, about 2.3 m to the top of
# the humps. A deep barrel on long legs, two woolly humps, a curved neck with
# a shaggy mane, a narrow head with a split lip and tall knees. Four poses
# share one node — "Stand", "Graze" (head down in the feather grass) and the
# two halves of a walk, "StepA" and "StepB" — and canyon_life.gd shows one of
# them at a time.
const Props = preload("res://scripts/core/props.gd")
const MeshMerge = preload("res://scripts/core/mesh_merge.gd")

const WOOL = Color("b6926a")
const BULL = Color("97744f")
const MANE = Color("7d5c3c")
const BELLY = Color("d3c0a0")
const DARK = Color("36291f")
const HOOF = Color("5b4a38")

static func build(bull: bool) -> Node3D:
	var camel = Node3D.new()
	camel.name = "Camel"
	var wool = BULL if bull else WOOL
	var key = "camel:%s:" % ("bull" if bull else "cow")
	for pose_name in ["Stand", "Graze", "StepA", "StepB"]:
		var pose_node = Node3D.new()
		pose_node.name = pose_name
		camel.add_child(pose_node)
		_body(pose_node, wool, pose_name)
		MeshMerge.bake(pose_node, key + pose_name)
		pose_node.visible = pose_name == "Stand"
	if bull:
		camel.scale = Vector3.ONE * 1.12
	return camel

# Shows one of the four poses by name.
static func pose(camel: Node3D, pose_name: String) -> void:
	for child in camel.get_children():
		child.visible = child.name == pose_name

static func _limb(parent: Node3D, a: Vector3, b: Vector3, radius_a: float, radius_b: float, color: Color) -> void:
	var direction = b - a
	var part = Props.cylinder(parent, (a + b) * 0.5, radius_a, radius_b, direction.length(), color, 7)
	part.basis = Basis(Quaternion(Vector3.UP, direction.normalized()))

static func _blob(parent: Node3D, at: Vector3, size: Vector3, color: Color, pitch: float = 0.0) -> void:
	var part = Props.faceted(parent, at, size, color, 9, 5)
	part.rotation.x = pitch

static func _body(root: Node3D, wool: Color, pose_name: String) -> void:
	_blob(root, Vector3(0, 1.52, 0.0), Vector3(0.94, 1.02, 2.25), wool)
	_blob(root, Vector3(0, 1.3, -0.1), Vector3(0.8, 0.7, 1.9), BELLY.darkened(0.08))
	# Two humps, the front one a little taller and leaning forward.
	_blob(root, Vector3(0, 2.12, -0.42), Vector3(0.66, 0.72, 0.84), MANE.lerp(wool, 0.5), -0.12)
	_blob(root, Vector3(0, 2.06, 0.52), Vector3(0.62, 0.64, 0.78), MANE.lerp(wool, 0.5), 0.1)
	_neck(root, wool, pose_name == "Graze")
	for side in [-1.0, 1.0]:
		_foreleg(root, side, wool, _swing(pose_name, side > 0.0))
		_hindleg(root, side, wool, _swing(pose_name, side < 0.0))
	_tail(root, wool)

# How far this leg is thrown forward in the pose, metres along -z.
static func _swing(pose_name: String, leading: bool) -> float:
	if pose_name == "StepA":
		return -0.3 if leading else 0.26
	if pose_name == "StepB":
		return 0.26 if leading else -0.3
	return 0.0

static func _neck(root: Node3D, wool: Color, grazing: bool) -> void:
	var withers = Vector3(0, 1.95, -0.95)
	var top = Vector3(0, 2.72, -1.42) if not grazing else Vector3(0, 1.5, -1.62)
	var head = Vector3(0, 2.72, -1.78) if not grazing else Vector3(0, 0.52, -1.95)
	_limb(root, withers, top, 0.23, 0.15, wool)
	_blob(root, (withers + top) * 0.5 + Vector3(0, 0.1, 0), Vector3(0.3, 0.44, 0.34), MANE, 0.5 if grazing else 0.0)
	_blob(root, head, Vector3(0.24, 0.27, 0.46), wool)
	var muzzle = head + (Vector3(0, -0.06, -0.28) if not grazing else Vector3(0, -0.16, -0.2))
	_limb(root, head + Vector3(0, -0.02, -0.1), muzzle, 0.1, 0.085, wool.lightened(0.06))
	Props.box(root, muzzle + Vector3(0, -0.02, -0.03), Vector3(0.12, 0.07, 0.06), DARK)
	for side in [-1.0, 1.0]:
		Props.box(root, head + Vector3(side * 0.11, 0.06, -0.14), Vector3(0.04, 0.04, 0.04), DARK)
		var ear = Props.faceted(root, head + Vector3(side * 0.1, 0.17, 0.02), Vector3(0.07, 0.1, 0.05), wool, 5, 3)
		ear.rotation.z = -side * 0.3

static func _foreleg(root: Node3D, side: float, wool: Color, swing: float) -> void:
	var shoulder = Vector3(side * 0.34, 1.35, -0.78)
	var knee = Vector3(side * 0.33, 0.72, -0.82 + swing * 0.5)
	var fetlock = Vector3(side * 0.32, 0.16, -0.8 + swing)
	_blob(root, shoulder + Vector3(0, 0.05, 0), Vector3(0.3, 0.52, 0.42), wool)
	_limb(root, shoulder, knee, 0.12, 0.085, wool)
	_limb(root, knee, fetlock, 0.08, 0.06, wool.darkened(0.08))
	Props.box(root, fetlock + Vector3(0, -0.1, -0.03), Vector3(0.22, 0.12, 0.3), HOOF)

static func _hindleg(root: Node3D, side: float, wool: Color, swing: float) -> void:
	var hip = Vector3(side * 0.36, 1.38, 0.8)
	var hock = Vector3(side * 0.34, 0.68, 0.92 - swing * 0.4)
	var fetlock = Vector3(side * 0.33, 0.16, 0.82 - swing)
	_blob(root, hip, Vector3(0.34, 0.56, 0.5), wool)
	_limb(root, hip, hock, 0.13, 0.085, wool)
	_limb(root, hock, fetlock, 0.08, 0.06, wool.darkened(0.08))
	Props.box(root, fetlock + Vector3(0, -0.1, 0.02), Vector3(0.22, 0.12, 0.3), HOOF)

static func _tail(root: Node3D, wool: Color) -> void:
	var root_point = Vector3(0, 1.72, 1.08)
	var tip = Vector3(0, 1.0, 1.28)
	_limb(root, root_point, tip, 0.06, 0.035, wool)
	_blob(root, tip + Vector3(0, -0.12, 0.02), Vector3(0.1, 0.22, 0.1), DARK)
