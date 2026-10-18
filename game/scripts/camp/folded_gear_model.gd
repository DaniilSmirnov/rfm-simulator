extends RefCounted
# The camp table and chair as they travel: packed, in the trunk and in the
# hands. They take the place of the plain gear box (0.34 x 0.30 x 0.48, its
# bottom at -0.15) so the trunk layout and the carrying pose stay as they are.
#   FoldedGearModel.build(root, "chairs")   # the chair in its stuff sack
#   FoldedGearModel.build(root, "table")    # the roll-up top bundled with the legs
# The +Z end carries a cream tag with the name (the carried gear turns that end
# away from the carrier, so others can read it). Each kind is baked into one
# mesh shared by every trunk and every pair of hands.
const P = preload("res://scripts/core/props.gd")
const MeshMerge = preload("res://scripts/core/mesh_merge.gd")
const Loc = preload("res://scripts/ui/loc.gd")
const BOTTOM = -0.15
const FRAME = Color("9aa1a6")
const FRAME_DARK = Color("4a4f55")
const RUBBER = Color("26292b")
const CANVAS = Color("cf703e")
const OLIVE = Color("4f5a3c")
const OLIVE_DARK = Color("3b442d")
const SLAT = Color("a17d52")
const SLAT_ALT = Color("94714a")
const STRAP = Color("d8572d")
const TAG = Color("ead9b6")
const INK = Color("18292e")

static func build(root: Node3D, kind: String) -> void:
	if kind == "table":
		_table(root)
	else:
		_chair(root)
	MeshMerge.bake(root, "gear:%s:%s" % [kind, Loc.current])

# A cylinder lying along Z, `length` long, centred at `center`.
static func _along_z(root: Node3D, center: Vector3, radius: float, length: float, color: Color, sides: int = 12) -> MeshInstance3D:
	var node = P.cylinder(root, center, radius, radius, length, color, sides)
	node.rotation.x = PI / 2
	return node

# The name tag on the +Z end cap: a cream disc and the word on it.
static func _tag(root: Node3D, title: String, y: float, z: float) -> void:
	_along_z(root, Vector3(0, y, z + 0.002), 0.095, 0.004, TAG, 16)
	P.label_3d(root, Vector3(0, y, z + 0.006), title, 36, 0.0018, INK, 0)

static func _chair(root: Node3D) -> void:
	# The sack: olive canvas, a cord round its mouth, a webbing strap on top and
	# the folded chair spilling out of the open end.
	var radius = 0.14
	var y = BOTTOM + radius
	var front = 0.19
	_along_z(root, Vector3(0, y, 0.01), radius, 0.36, OLIVE)
	_along_z(root, Vector3(0, y, -0.165), radius + 0.006, 0.02, OLIVE_DARK)
	_along_z(root, Vector3(0, y, -0.12), radius + 0.008, 0.022, RUBBER)
	_along_z(root, Vector3(0, y, 0.08), radius + 0.006, 0.03, STRAP)
	P.box(root, Vector3(0, y + radius + 0.004, -0.02), Vector3(0.04, 0.008, 0.3), STRAP)
	# Folded canvas with the aluminium tubes and their rubber feet poking out.
	P.faceted(root, Vector3(0, y + 0.01, -0.19), Vector3(0.22, 0.2, 0.09), CANVAS, 8, 4)
	for spot in [Vector2(-0.06, 0.05), Vector2(0.06, 0.05), Vector2(0.0, -0.045)]:
		_along_z(root, Vector3(spot.x, y + spot.y, -0.2), 0.013, 0.12, FRAME, 8)
		_along_z(root, Vector3(spot.x, y + spot.y, -0.265), 0.02, 0.02, RUBBER, 8)
	_tag(root, "СТУЛ", y, front)

static func _table(root: Node3D) -> void:
	# The roll-up top of slats on top, its tube legs and spine bundled beneath,
	# two straps round both and a carrying handle between them.
	var radius = 0.12
	var back = 0.21
	_along_z(root, Vector3(0, 0, -0.01), radius, 0.44, SLAT, 14)
	# The rolled end shows the slats as a spiral.
	for i in range(3):
		_along_z(root, Vector3(0, 0, -0.232 - i * 0.002), 0.095 - i * 0.03, 0.004, SLAT_ALT if i % 2 == 0 else SLAT, 14)
	for x in [-0.1, -0.05, 0.0, 0.05, 0.1]:
		_along_z(root, Vector3(x, BOTTOM + 0.014, 0.0), 0.014, 0.46, FRAME, 8)
		_along_z(root, Vector3(x, BOTTOM + 0.014, -0.235), 0.02, 0.02, RUBBER, 8)
	for z in [-0.12, 0.12]:
		_along_z(root, Vector3(0, 0, z), radius + 0.008, 0.032, STRAP)
		P.box(root, Vector3(0, BOTTOM + 0.014, z), Vector3(0.25, 0.034, 0.032), STRAP)
	for x in [-0.045, 0.045]:
		P.box(root, Vector3(x, radius + 0.015, 0.0), Vector3(0.012, 0.03, 0.02), STRAP)
	P.box(root, Vector3(0, radius + 0.036, 0.0), Vector3(0.102, 0.012, 0.02), STRAP)
	_tag(root, "СТОЛ", 0.0, back)
