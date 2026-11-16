extends RefCounted
# Bactrian camel of «Чарынский каньон», facing -z, about 2.3 m to the top of
# the humps. One smooth, vertex-coloured skin per pose, lofted along spines:
# a deep barrel tucked up at the flank, two soft humps with long dark hair on
# their crowns, the neck that dips forward out of the chest and rises in an
# S to a long head (heavy brow, small ears, a split, drooping upper lip), a
# shaggy beard under the throat and "trousers" of long hair on the upper
# forelegs, thin legs with knobbly calloused knees and broad two-toed pads.
# Four poses share one node — "Stand", "Graze" (head down in the feather
# grass) and the two halves of a walk, "StepA" and "StepB" — and
# canyon_life.gd shows one of them at a time.
const Props = preload("res://scripts/core/props.gd")
const MeshMerge = preload("res://scripts/core/mesh_merge.gd")

const WOOL = Color("b39069")
const BULL = Color("94704c")
const SHAG = Color("6f5236")
const BELLY = Color("cdb894")
const MUZZLE = Color("8c7458")
const DARK = Color("2c221a")
const PAD = Color("4e4033")
const SIDES = 12

static func build(bull: bool) -> Node3D:
	var camel = Node3D.new()
	camel.name = "Camel"
	var wool = BULL if bull else WOOL
	var key = "camel2:%s:" % ("bull" if bull else "cow")
	for pose_name in ["Stand", "Graze", "StepA", "StepB"]:
		var pose_node = Node3D.new()
		pose_node.name = pose_name
		camel.add_child(pose_node)
		var st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_body(st, wool, pose_name)
		st.generate_normals()
		_counts.erase(st)
		var skin = MeshInstance3D.new()
		skin.name = "Skin"
		skin.mesh = st.commit()
		skin.material_override = Props.material(Color.WHITE)
		skin.material_override.vertex_color_use_as_albedo = true
		pose_node.add_child(skin)
		MeshMerge.bake(pose_node, key + pose_name)
		pose_node.visible = pose_name == "Stand"
	if bull:
		camel.scale = Vector3.ONE * 1.12
	return camel

# Shows one of the four poses by name.
static func pose(camel: Node3D, pose_name: String) -> void:
	for child in camel.get_children():
		child.visible = child.name == pose_name

# ---------------------------------------------------------------- skin

# A smooth tube through `spine`, each ring an ellipse of half sizes
# (sideways, up) in `sizes`; the ends are closed with a point.
static func _tube(st: SurfaceTool, spine: Array, sizes: Array, colors: Array) -> void:
	var count = spine.size()
	var base = _vertex_count(st)
	var rings: Array = []
	for i in range(count):
		var tangent: Vector3 = (spine[mini(i + 1, count - 1)] - spine[maxi(i - 1, 0)]).normalized()
		var reference = Vector3.UP if absf(tangent.y) < 0.85 else Vector3.FORWARD
		var side = reference.cross(tangent).normalized()
		var up = tangent.cross(side).normalized()
		if up.y < 0.0 or (absf(up.y) < 0.01 and up.z > 0.0):
			up = -up
			side = -side
		rings.append([side, up])
	for i in range(count):
		var size: Vector2 = sizes[i]
		var color: Color = colors[i] if colors.size() == count else colors[0]
		for k in range(SIDES):
			var angle = k * TAU / SIDES
			st.set_color(color.darkened(0.08 * maxf(0.0, -sin(angle))))
			st.add_vertex(spine[i] + rings[i][0] * cos(angle) * size.x + rings[i][1] * sin(angle) * size.y)
	for i in range(count - 1):
		for k in range(SIDES):
			var a = base + i * SIDES + k
			var b = base + i * SIDES + (k + 1) % SIDES
			var c = a + SIDES
			var d = b + SIDES
			for index in [a, c, b, b, c, d]:
				st.add_index(index)
	# End caps: a point a little beyond each end ring.
	for e in range(2):
		var end = 0 if e == 0 else count - 1
		var outward: Vector3 = (spine[end] - spine[1 if end == 0 else count - 2]).normalized()
		var size: Vector2 = sizes[end]
		st.set_color(colors[end] if colors.size() == count else colors[0])
		st.add_vertex(spine[end] + outward * minf(size.x, size.y) * 0.6)
		var tip = base + count * SIDES + e
		for k in range(SIDES):
			var a = base + end * SIDES + k
			var b = base + end * SIDES + (k + 1) % SIDES
			if end == 0:
				for index in [tip, a, b]:
					st.add_index(index)
			else:
				for index in [tip, b, a]:
					st.add_index(index)

# Vertices added so far per SurfaceTool, which does not report its count.
static var _counts: Dictionary = {}

static func _vertex_count(st: SurfaceTool) -> int:
	return _counts.get(st, 0)

# A soft lump: an ellipsoid lofted along its height axis, tipped by `pitch`.
static func _lump(st: SurfaceTool, at: Vector3, size: Vector3, color: Color, pitch: float = 0.0) -> void:
	var spine: Array = []
	var sizes: Array = []
	var axis = Vector3(0, cos(pitch), -sin(pitch))
	for i in range(6):
		var t = -1.0 + 2.0 * (i + 0.5) / 6.0
		var r = sqrt(maxf(0.0, 1.0 - t * t))
		spine.append(at + axis * t * size.y * 0.5)
		sizes.append(Vector2(size.x * 0.5 * r, size.z * 0.5 * r))
	_loft(st, spine, sizes, [color])

# _tube() plus its vertex bookkeeping.
static func _loft(st: SurfaceTool, spine: Array, sizes: Array, colors: Array) -> void:
	_tube(st, spine, sizes, colors)
	_counts[st] = _vertex_count(st) + spine.size() * SIDES + 2

# ---------------------------------------------------------------- body

static func _body(st: SurfaceTool, wool: Color, pose_name: String) -> void:
	_counts[st] = 0
	# Barrel from rump (+z) to chest (-z): deepest behind the elbows, tucked
	# up at the flank, the brisket low and forward.
	var barrel = [Vector3(0, 1.56, 1.16), Vector3(0, 1.55, 1.02), Vector3(0, 1.52, 0.72), Vector3(0, 1.47, 0.3), Vector3(0, 1.44, -0.12), Vector3(0, 1.43, -0.5), Vector3(0, 1.45, -0.82), Vector3(0, 1.42, -1.02), Vector3(0, 1.4, -1.12)]
	var girth = [Vector2(0.14, 0.18), Vector2(0.33, 0.37), Vector2(0.42, 0.45), Vector2(0.46, 0.5), Vector2(0.49, 0.55), Vector2(0.47, 0.56), Vector2(0.41, 0.52), Vector2(0.3, 0.36), Vector2(0.12, 0.2)]
	var tones: Array = []
	for i in range(barrel.size()):
		tones.append(wool.lerp(BELLY, 0.12 if i in [3, 4, 5] else 0.0))
	_loft(st, barrel, girth, tones)
	# A paler belly under the barrel.
	_lump(st, Vector3(0, 1.06, -0.08), Vector3(0.66, 1.5, 0.32), BELLY.darkened(0.06), PI * 0.5)
	# Two humps, the front one taller and leaning forward, crowned by long
	# dark hair.
	_hump(st, Vector3(0, 1.86, -0.46), 0.5, 0.36, -0.14, wool)
	_hump(st, Vector3(0, 1.86, 0.5), 0.43, 0.33, 0.12, wool)
	var grazing = pose_name == "Graze"
	_neck(st, wool, grazing)
	for side in [-1.0, 1.0]:
		_foreleg(st, side, wool, _swing(pose_name, side > 0.0))
		_hindleg(st, side, wool, _swing(pose_name, side < 0.0))
	_tail(st, wool)

# How far this leg is thrown forward in the pose, metres along -z.
static func _swing(pose_name: String, leading: bool) -> float:
	if pose_name == "StepA":
		return -0.3 if leading else 0.26
	if pose_name == "StepB":
		return 0.26 if leading else -0.3
	return 0.0

static func _hump(st: SurfaceTool, base: Vector3, height: float, radius: float, lean: float, wool: Color) -> void:
	# A broad base sunk into the back, a soft cone above it, the crown of
	# long dark hair flopping a little to one side.
	var spine: Array = []
	var sizes: Array = []
	var colors: Array = []
	for i in range(8):
		var t = float(i) / 7.0
		spine.append(base + Vector3(t * t * 0.05, t * height, sin(lean) * t * height))
		var r = radius * pow(maxf(0.0, 1.0 - pow(t, 1.7)), 0.65) + 0.03
		sizes.append(Vector2(r, r * 1.2))
		colors.append(wool.lerp(SHAG, smoothstep(0.3, 0.8, t)))
	_loft(st, spine, sizes, colors)

static func _neck(st: SurfaceTool, wool: Color, grazing: bool) -> void:
	# Out of the chest low and forward, then up in an S to the poll.
	var spine: Array
	if grazing:
		spine = [Vector3(0, 1.55, -0.94), Vector3(0, 1.38, -1.24), Vector3(0, 1.12, -1.46), Vector3(0, 0.8, -1.66), Vector3(0, 0.56, -1.8)]
	else:
		spine = [Vector3(0, 1.62, -0.9), Vector3(0, 1.46, -1.28), Vector3(0, 1.58, -1.58), Vector3(0, 1.98, -1.8), Vector3(0, 2.34, -1.84)]
	var sizes = [Vector2(0.24, 0.33), Vector2(0.18, 0.27), Vector2(0.15, 0.22), Vector2(0.13, 0.17), Vector2(0.11, 0.13)]
	_loft(st, spine, sizes, [wool])
	# The shaggy beard down the throat, hanging close under the neck.
	var down = Vector3(0, -1, 0) if not grazing else Vector3(0, -0.4, 0.9).normalized()
	for i in range(3):
		var p: Vector3 = spine[i].lerp(spine[i + 1], 0.5)
		_lump(st, p + down * (sizes[i].y * 0.55), Vector3(0.2 - i * 0.03, 0.36 - i * 0.05, 0.24 - i * 0.025), SHAG.lerp(wool, 0.35 + i * 0.1), 0.35 if not grazing else 1.2)
	_head(st, spine[4], wool, grazing)

static func _head(st: SurfaceTool, poll: Vector3, wool: Color, grazing: bool) -> void:
	# Along the face from the poll to the lip; a grazing head points down.
	var face = Vector3(0, -0.22, -1).normalized() if not grazing else Vector3(0, -0.85, -0.52).normalized()
	var up = Vector3(0, 1, -0.22).normalized() if not grazing else Vector3(0, 0.52, -0.85).normalized()
	var spine = [poll - face * 0.06, poll + face * 0.1, poll + face * 0.24, poll + face * 0.38, poll + face * 0.5 - up * 0.02, poll + face * 0.58 - up * 0.05]
	var sizes = [Vector2(0.1, 0.11), Vector2(0.125, 0.135), Vector2(0.11, 0.12), Vector2(0.085, 0.105), Vector2(0.08, 0.1), Vector2(0.065, 0.075)]
	_loft(st, spine, sizes, [wool, wool, wool.lerp(MUZZLE, 0.4), MUZZLE, MUZZLE, MUZZLE.darkened(0.1)])
	# The split upper lip droops over the lower one.
	for side in [-1.0, 1.0]:
		_lump(st, spine[5] + up * -0.03 + Vector3(side * 0.03, 0, 0) + face * 0.02, Vector3(0.06, 0.08, 0.07), MUZZLE.darkened(0.04))
		# Slit nostrils on top of the muzzle, eyes under a heavy brow.
		_lump(st, spine[4] + up * 0.08 + Vector3(side * 0.045, 0, 0), Vector3(0.02, 0.07, 0.018), DARK, PI * 0.5)
		var brow: Vector3 = spine[1] + up * 0.07 + Vector3(side * 0.11, 0, 0)
		_lump(st, brow, Vector3(0.06, 0.045, 0.1), wool.darkened(0.1), PI * 0.5)
		_lump(st, brow - up * 0.045 + Vector3(side * 0.012, 0, 0) + face * 0.01, Vector3(0.035, 0.035, 0.04), DARK)
		# Small round ears set far back.
		_lump(st, spine[0] + up * 0.1 + Vector3(side * 0.08, 0, 0), Vector3(0.05, 0.08, 0.04), wool.darkened(0.06), -0.3)
	_lump(st, spine[5] - up * 0.08 - face * 0.03, Vector3(0.09, 0.05, 0.09), MUZZLE.darkened(0.12))
	# A forelock of shaggy hair between the ears.
	_lump(st, spine[0] + up * 0.13 + face * 0.02, Vector3(0.12, 0.08, 0.12), SHAG)

static func _foreleg(st: SurfaceTool, side: float, wool: Color, swing: float) -> void:
	var x = side * 0.27
	var shoulder = Vector3(x, 1.5, -0.74)
	var elbow = Vector3(x, 1.02, -0.68)
	var knee = Vector3(x * 0.95, 0.56, -0.72 + swing * 0.5)
	var fetlock = Vector3(x * 0.95, 0.13, -0.74 + swing)
	_loft(st, [shoulder, shoulder.lerp(elbow, 0.5), elbow], [Vector2(0.15, 0.2), Vector2(0.13, 0.16), Vector2(0.1, 0.11)], [wool])
	_loft(st, [elbow, elbow.lerp(knee, 0.5), knee + Vector3(0, 0.03, 0)], [Vector2(0.085, 0.09), Vector2(0.07, 0.075), Vector2(0.06, 0.065)], [wool.darkened(0.04)])
	_lump(st, knee, Vector3(0.12, 0.13, 0.12), wool.darkened(0.2))
	_loft(st, [knee, knee.lerp(fetlock, 0.5), fetlock], [Vector2(0.05, 0.052), Vector2(0.044, 0.046), Vector2(0.052, 0.054)], [wool.darkened(0.08)])
	# Long hair "trousers" on the upper foreleg.
	_lump(st, elbow + Vector3(side * 0.02, -0.06, -0.02), Vector3(0.2, 0.42, 0.22), SHAG.lightened(0.08))
	_foot(st, fetlock, -1.0)

static func _hindleg(st: SurfaceTool, side: float, wool: Color, swing: float) -> void:
	var x = side * 0.28
	var hip = Vector3(x, 1.55, 0.78)
	var stifle = Vector3(x, 1.0, 0.56)
	var hock = Vector3(x * 0.95, 0.56, 0.96 - swing * 0.4)
	var fetlock = Vector3(x * 0.95, 0.13, 0.86 - swing)
	_loft(st, [hip, hip.lerp(stifle, 0.5), stifle], [Vector2(0.17, 0.26), Vector2(0.15, 0.2), Vector2(0.1, 0.12)], [wool])
	_loft(st, [stifle, stifle.lerp(hock, 0.5), hock], [Vector2(0.09, 0.1), Vector2(0.07, 0.08), Vector2(0.06, 0.07)], [wool.darkened(0.04)])
	_lump(st, hock + Vector3(0, 0, 0.02), Vector3(0.1, 0.12, 0.13), wool.darkened(0.12))
	_loft(st, [hock, hock.lerp(fetlock, 0.5), fetlock], [Vector2(0.05, 0.052), Vector2(0.044, 0.046), Vector2(0.052, 0.054)], [wool.darkened(0.08)])
	_foot(st, fetlock, 1.0)

# A broad soft pad with two toes and their nails in front.
static func _foot(st: SurfaceTool, fetlock: Vector3, _end: float) -> void:
	var sole = fetlock + Vector3(0, -0.08, -0.06)
	_lump(st, sole, Vector3(0.21, 0.27, 0.11), PAD, PI * 0.5)
	for toe in [-0.05, 0.05]:
		_lump(st, sole + Vector3(toe, 0.01, -0.12), Vector3(0.08, 0.06, 0.07), DARK)

static func _tail(st: SurfaceTool, wool: Color) -> void:
	var spine = [Vector3(0, 1.62, 1.12), Vector3(0, 1.4, 1.22), Vector3(0, 1.12, 1.24), Vector3(0, 0.92, 1.22)]
	_loft(st, spine, [Vector2(0.05, 0.06), Vector2(0.04, 0.045), Vector2(0.03, 0.035), Vector2(0.03, 0.03)], [wool])
	_lump(st, Vector3(0, 0.84, 1.22), Vector3(0.09, 0.26, 0.08), DARK.lightened(0.15))
