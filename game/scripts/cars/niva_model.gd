extends RefCounted

# Original, unbranded low-poly three-door off-roader: boxy body, flat bonnet,
# round headlamps in a wide grille, flared arches and an upright tailgate.
# Original work for this project, built from primitives at load time; it
# replaced an OBJ conversion of a third-party model and uses no imported files.
# Forward is -Z. Static parts live under NivaStaticParts so the trunk clipper
# leaves them alone; only the tailgate assembly pivots on TrunkHinge.
const P = preload("res://scripts/core/props.gd")
const CarParts = preload("res://scripts/cars/car_parts.gd")
const VARIANT = 2
const HINGE = Vector3(0.0, 1.56, 1.42)
const WHEEL_RADIUS = 0.34
const WHEEL_WIDTH = 0.25
const WHEEL_TRACK = 0.76
const WHEEL_AXLE = 1.16
const WHEEL_Y = 0.345
# Tailgate edges in the side view (y, z): hinge line and bottom sill.
const GATE_TOP = Vector2(1.525, 1.43)
const GATE_BOTTOM = Vector2(0.785, 1.80)
# Dark olive paint and black bumpers, as on the car this replaces.
const PAINT = Color("24361f")
const TRIM = Color("1f2526")
const GLASS = Color("1e2f38")
const DARK = Color("101517")
const GRILLE = Color("1a2022")
const LAMP_RIM = Color("5d6466")
const LENS = Color("d8ded6")
const AMBER = Color("e0841c")
const RED = Color("93212a")
const REVERSE = Color("d4d4c4")
const METAL = Color("8b918c")

static func _box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, part: String = "") -> MeshInstance3D:
	var node = P.box(parent, pos, size, color)
	if part != "":
		node.name = part
	return node

# A convex side-view outline (z, y) extruded across x0..x1, for the rear
# corner pillars that carry the tail lamps.
static func _prism(parent: Node3D, outline: PackedVector2Array, x0: float, x1: float, color: Color) -> MeshInstance3D:
	var vertices = PackedVector3Array()
	var count = outline.size()
	for i in range(1, count - 1):
		for x in [x0, x1]:
			vertices.append_array(PackedVector3Array([Vector3(x, outline[0].y, outline[0].x), Vector3(x, outline[i].y, outline[i].x), Vector3(x, outline[i + 1].y, outline[i + 1].x)]))
	for i in range(count):
		var a = outline[i]
		var b = outline[(i + 1) % count]
		vertices.append_array(PackedVector3Array([Vector3(x0, a.y, a.x), Vector3(x1, a.y, a.x), Vector3(x1, b.y, b.x), Vector3(x0, a.y, a.x), Vector3(x1, b.y, b.x), Vector3(x0, b.y, b.x)]))
	# Godot treats clockwise triangles as front faces: wind each one clockwise
	# as seen from outside, or the double-sided material lights it from inside.
	var middle = Vector3((x0 + x1) * 0.5, 0, 0)
	for point in outline:
		middle += Vector3(0, point.y, point.x) / count
	for i in range(0, vertices.size(), 3):
		var normal = (vertices[i + 1] - vertices[i]).cross(vertices[i + 2] - vertices[i])
		if normal.dot(vertices[i] + vertices[i + 1] + vertices[i + 2] - middle * 3.0) > 0.0:
			var swap = vertices[i + 1]
			vertices[i + 1] = vertices[i + 2]
			vertices[i + 2] = swap
	var node = MeshInstance3D.new()
	node.mesh = P.panel_mesh(vertices)
	node.material_override = P.material(color)
	node.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	parent.add_child(node)
	return node

# A flat panel wound clockwise as seen from outside the cabin (see _prism).
static func _panel(parent: Node3D, points: PackedVector3Array, color: Color) -> MeshInstance3D:
	var normal = (points[1] - points[0]).cross(points[2] - points[0])
	var middle = (points[0] + points[1] + points[2] + points[3]) * 0.25
	if normal.dot(middle - Vector3(0, 1.0, 0.4)) > 0.0:
		points = PackedVector3Array([points[0], points[3], points[2], points[1]])
	return P.quad_panel(parent, points, color)

static func _body(parts: Node3D, paint: Color) -> void:
	# Lower body (z, half width, bottom, top): the bottom edge rises over both
	# axles, which cuts faceted wheel arches out of the sides.
	P.car_shell(parts, [
		Vector4(-1.88, 0.76, 0.46, 0.97),
		Vector4(-1.84, 0.82, 0.38, 1.02),
		Vector4(-1.62, 0.83, 0.36, 1.04),
		Vector4(-1.53, 0.83, 0.62, 1.045),
		Vector4(-1.40, 0.83, 0.75, 1.05),
		Vector4(-0.92, 0.83, 0.75, 1.06),
		Vector4(-0.79, 0.83, 0.62, 1.065),
		Vector4(-0.70, 0.83, 0.32, 1.07),
		Vector4(0.70, 0.83, 0.32, 1.08),
		Vector4(0.79, 0.83, 0.62, 1.08),
		Vector4(0.92, 0.83, 0.75, 1.08),
		Vector4(1.30, 0.83, 0.75, 1.08),
	], paint).name = "NivaBody"
	# Boot floor and rear valance under the tailgate.
	P.car_shell(parts, [
		Vector4(1.29, 0.83, 0.75, 0.785),
		Vector4(1.40, 0.83, 0.75, 0.785),
		Vector4(1.53, 0.83, 0.62, 0.785),
		Vector4(1.62, 0.83, 0.36, 0.785),
		Vector4(1.84, 0.82, 0.38, 0.785),
		Vector4(1.88, 0.77, 0.45, 0.775),
	], paint).name = "NivaRearValance"
	for side in [-1.0, 1.0]:
		# Corner pillars beside the tailgate; the tail lamps sit on their faces.
		var corner = PackedVector2Array([Vector2(1.29, 0.78), Vector2(1.875, 0.78), Vector2(1.875, 0.95), Vector2(1.74, 1.08), Vector2(1.29, 1.08)])
		_prism(parts, corner, side * 0.685, side * 0.83, paint).name = "NivaRearCorner"
	P.car_shell(parts, [
		Vector4(-0.27, 0.68, 1.49, 1.58),
		Vector4(-0.20, 0.71, 1.49, 1.605),
		Vector4(1.38, 0.71, 1.49, 1.605),
		Vector4(1.44, 0.69, 1.50, 1.585),
	], paint).name = "NivaRoof"
	# Dark cabin behind the glass, also the back of the rear seats.
	_box(parts, Vector3(0, 1.0, 0.44), Vector3(1.30, 0.9, 1.68), DARK, "NivaCabin")
	_box(parts, Vector3(0, 0.728, 0.0), Vector3(1.40, 0.02, 3.2), DARK, "NivaWheelWells")

static func _glasshouse(parts: Node3D, paint: Color) -> void:
	_panel(parts, PackedVector3Array([
		Vector3(-0.71, 1.08, -0.66), Vector3(0.71, 1.08, -0.66),
		Vector3(0.645, 1.50, -0.25), Vector3(-0.645, 1.50, -0.25),
	]), GLASS).name = "NivaWindscreen"
	_box(parts, Vector3(0, 1.085, -0.70), Vector3(1.36, 0.02, 0.08), DARK, "NivaCowl")
	for side in [-1.0, 1.0]:
		var low = side * 0.765
		var high = side * 0.672
		_panel(parts, PackedVector3Array([
			Vector3(low, 1.09, -0.61), Vector3(low, 1.09, 0.50),
			Vector3(high, 1.49, 0.50), Vector3(high, 1.49, -0.26),
		]), GLASS).name = "NivaDoorGlass"
		_panel(parts, PackedVector3Array([
			Vector3(low, 1.09, 0.58), Vector3(low, 1.09, 1.42),
			Vector3(high, 1.49, 1.33), Vector3(high, 1.49, 0.58),
		]), GLASS).name = "NivaQuarterGlass"
		P.car_beam(parts, Vector3(side * 0.735, 1.07, -0.67), Vector3(side * 0.675, 1.52, -0.25), 0.07, paint)
		_box(parts, Vector3(side * 0.725, 1.29, 0.54), Vector3(0.07, 0.43, 0.08), paint, "NivaBPillar")
		# Wide rear pillar, from the quarter glass back to the tailgate edge.
		_panel(parts, PackedVector3Array([
			Vector3(side * 0.775, 1.08, 1.41), Vector3(side * 0.775, 1.08, 1.70),
			Vector3(side * 0.70, 1.52, 1.43), Vector3(side * 0.68, 1.50, 1.32),
		]), paint).name = "NivaRearPillar"
		_panel(parts, PackedVector3Array([
			Vector3(side * 0.775, 1.08, 1.70), Vector3(side * 0.70, 1.52, 1.43),
			Vector3(side * 0.68, 1.52, 1.43), Vector3(side * 0.685, 1.08, 1.70),
		]), paint)

static func _front(parts: Node3D, trim: Color) -> void:
	_box(parts, Vector3(0, 0.83, -1.876), Vector3(1.50, 0.30, 0.03), GRILLE, "NivaGrille")
	for i in range(5):
		_box(parts, Vector3(0, 0.735 + i * 0.05, -1.894), Vector3(0.74, 0.022, 0.02), Color("3a4143"))
	for side in [-1.0, 1.0]:
		var rim = P.cylinder(parts, Vector3(side * 0.59, 0.83, -1.89), 0.135, 0.135, 0.03, LAMP_RIM, 16)
		rim.rotation.x = PI / 2
		rim.name = "NivaHeadlampRim"
		var lens = P.cylinder(parts, Vector3(side * 0.59, 0.83, -1.903), 0.108, 0.108, 0.02, LENS, 16)
		lens.rotation.x = PI / 2
		_box(parts, Vector3(side * 0.56, 0.87, -1.915), Vector3(0.05, 0.03, 0.01), Color("f6f6ee"))
		_box(parts, Vector3(side * 0.59, 0.645, -1.886), Vector3(0.18, 0.05, 0.03), AMBER, "NivaIndicator")
		_box(parts, Vector3(side * 0.80, 0.53, -1.86), Vector3(0.08, 0.14, 0.22), trim)
		_box(parts, Vector3(side * 0.80, 0.53, 1.86), Vector3(0.08, 0.14, 0.22), trim)
		# Bonnet shut lines.
		P.car_beam(parts, Vector3(side * 0.72, 1.036, -1.80), Vector3(side * 0.72, 1.074, -0.72), 0.012, DARK)
	_box(parts, Vector3(0, 0.53, -1.94), Vector3(1.66, 0.14, 0.10), trim, "NivaFrontBumper")
	_box(parts, Vector3(0, 0.42, -1.86), Vector3(1.30, 0.08, 0.08), DARK)

static func _sides(parts: Node3D, paint: Color) -> void:
	var flare = paint.darkened(0.12)
	for side in [-1.0, 1.0]:
		var x = side * 0.84
		for z in [-0.64, 0.53]:
			_box(parts, Vector3(x, 0.74, z), Vector3(0.012, 0.64, 0.012), DARK)
		_box(parts, Vector3(x, 0.98, 0.40), Vector3(0.02, 0.03, 0.12), METAL, "NivaDoorHandle")
		_box(parts, Vector3(x, 0.80, 0.0), Vector3(0.016, 0.04, 1.40), Color("303a3d"), "NivaSideMoulding")
		_box(parts, Vector3(side * 0.80, 0.36, 0.0), Vector3(0.08, 0.08, 1.38), DARK, "NivaSill")
		# Mirror on a short arm at the front of the door.
		_box(parts, Vector3(side * 0.85, 1.12, -0.55), Vector3(0.06, 0.03, 0.05), DARK)
		_box(parts, Vector3(side * 0.90, 1.17, -0.55), Vector3(0.05, 0.10, 0.14), DARK, "NivaMirror")
		# Flared arch lips around both wheels.
		for axle in [-WHEEL_AXLE, WHEEL_AXLE]:
			var points: Array = []
			for i in range(7):
				var angle = PI * i / 6.0
				points.append(Vector3(side * 0.85, WHEEL_Y + 0.02 + sin(angle) * 0.44, axle + cos(angle) * 0.44))
			for i in range(6):
				P.car_beam(parts, points[i], points[i + 1], 0.06, flare)

static func _rear(parts: Node3D, trim: Color) -> void:
	for side in [-1.0, 1.0]:
		var x = side * 0.755
		_box(parts, Vector3(x, 0.905, 1.886), Vector3(0.13, 0.05, 0.02), AMBER, "NivaRearIndicator")
		_box(parts, Vector3(x, 0.82, 1.886), Vector3(0.13, 0.11, 0.02), RED, "NivaTailLamp")
		_box(parts, Vector3(x, 0.735, 1.886), Vector3(0.13, 0.05, 0.02), REVERSE, "NivaReverseLamp")
	_box(parts, Vector3(0, 0.53, 1.89), Vector3(1.66, 0.14, 0.08), trim, "NivaRearBumper")

# Tailgate parts are placed in car space, then shifted into hinge space.
static func _tailgate(hinge: Node3D, paint: Color) -> void:
	var run = GATE_TOP - GATE_BOTTOM
	var length = run.length()
	var up = Vector3(0, run.x, run.y) / length
	var out = Vector3(0, -up.z, up.y)
	var centre = Vector3(0, (GATE_TOP.x + GATE_BOTTOM.x) * 0.5, (GATE_TOP.y + GATE_BOTTOM.y) * 0.5)
	var tilt = atan2(-up.z, up.y)
	var parts = [
		["NivaTailgate_Lid", centre, Vector3(1.34, length, 0.05), paint],
		["NivaRearWindow", centre + up * (length * 0.5 - 0.22) + out * 0.027, Vector3(1.22, 0.36, 0.012), GLASS],
		["NivaRearWindowSeal", centre + up * (length * 0.5 - 0.415) + out * 0.027, Vector3(1.28, 0.02, 0.014), DARK],
		["NivaTailgateHandle", centre - up * 0.16 + out * 0.03, Vector3(0.20, 0.035, 0.02), DARK],
	]
	for part in parts:
		var node = _box(hinge, part[1] - HINGE, part[2], part[3], part[0])
		node.rotation.x = -tilt

static func build() -> Node3D:
	var look: Dictionary = P.PLAYER_MODELS[VARIANT]
	var paint = PAINT
	var trim = TRIM
	var root = Node3D.new()
	root.name = "PlayerCar_%d" % VARIANT
	root.set_meta("model", look.name)
	root.set_meta("variant", VARIANT)
	root.set_meta("model_source", "niva_procedural")
	root.set_meta("trunk_lid_start_z", HINGE.z)

	var parts = Node3D.new()
	parts.name = "NivaStaticParts"
	root.add_child(parts)
	_body(parts, paint)
	_glasshouse(parts, paint)
	_front(parts, trim)
	_sides(parts, paint)
	_rear(parts, trim)
	var wheel_look: Dictionary = look.wheel.duplicate()
	wheel_look.color = METAL.to_html(false)
	for side in [-1.0, 1.0]:
		for axle in [-WHEEL_AXLE, WHEEL_AXLE]:
			var wheel = CarParts.wheel(parts, Vector3(side * WHEEL_TRACK, WHEEL_Y, axle), WHEEL_RADIUS, WHEEL_WIDTH, side, wheel_look)
			wheel.name = "NivaWheel_%s%s" % ["F" if axle < 0.0 else "R", "L" if side < 0.0 else "R"]

	# Inventory, approach and opening animation come from the shared trunk.
	# Static parts sit under NivaStaticParts, so nothing is clipped off them.
	P.add_player_trunk(root, VARIANT)
	var hinge: Node3D = root.get_node("TrunkHinge")
	hinge.position = HINGE
	_tailgate(hinge, paint)
	return root
