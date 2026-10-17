extends RefCounted
# Log carpentry of the Russian North shared by the izbas, the granary and the
# church: log frames (срубы) whose log ends stick out past the corners
# (рубка «в обло»), plank gable roofs with snow, triangular gables, carved
# barge boards (причелины) and window surrounds (наличники) with shutters.
# Everything is built in the parent's local space from plain-coloured
# primitives, so MeshMerge.bake() folds a whole building into one mesh.
const Props = preload("res://scripts/core/props.gd")
const SNOW = Color("eef2f2")
const LOG_RADIUS = 0.13
# How far the log ends stick out past each corner.
const LOG_ENDS = 0.3

# A cylinder of the given radius from a to b.
static func log_between(parent: Node3D, a: Vector3, b: Vector3, radius: float, color: Color, sides: int = 6) -> MeshInstance3D:
	var along = b - a
	var node = Props.cylinder(parent, (a + b) * 0.5, radius, radius, along.length(), color, sides)
	var y = along.normalized()
	var x = y.cross(Vector3.UP)
	if x.length_squared() < 0.0001:
		x = Vector3.RIGHT
	x = x.normalized()
	node.transform = Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5)
	return node

# A box from a to b (its length along a->b), height and depth across.
static func beam(parent: Node3D, a: Vector3, b: Vector3, height: float, depth: float, color: Color) -> MeshInstance3D:
	var along = b - a
	var node = Props.box(parent, (a + b) * 0.5, Vector3(along.length(), height, depth), color)
	var x = along.normalized()
	var z = x.cross(Vector3.UP)
	if z.length_squared() < 0.0001:
		z = Vector3.BACK
	z = z.normalized()
	node.transform = Transform3D(Basis(x, z.cross(x), z), (a + b) * 0.5)
	return node

# A rectangular log frame w (along X) by d (along Z), from base.y up h metres,
# centred on base. A plain core behind the logs closes every gap.
static func log_frame(parent: Node3D, base: Vector3, w: float, d: float, h: float, color: Color) -> void:
	Props.box(parent, base + Vector3(0, h * 0.5, 0), Vector3(w - LOG_RADIUS, h, d - LOG_RADIUS), color.darkened(0.3))
	var courses = maxi(1, roundi(h / (LOG_RADIUS * 2.0)))
	var step = h / courses
	for i in range(courses):
		var y = base.y + (i + 0.5) * step
		var shade = color.lightened(0.05) if i % 2 == 0 else color.darkened(0.04)
		for sz in [-1.0, 1.0]:
			log_between(parent, base + Vector3(-w * 0.5 - LOG_ENDS, y - base.y, sz * d * 0.5), base + Vector3(w * 0.5 + LOG_ENDS, y - base.y, sz * d * 0.5), LOG_RADIUS, shade)
		# Side walls sit half a log higher: the courses interlock at the corners.
		var side_y = minf(y + step * 0.5, base.y + h - LOG_RADIUS) - base.y
		for sx in [-1.0, 1.0]:
			log_between(parent, base + Vector3(sx * w * 0.5, side_y, -d * 0.5 - LOG_ENDS), base + Vector3(sx * w * 0.5, side_y, d * 0.5 + LOG_ENDS), LOG_RADIUS, shade.darkened(0.03))

# Wall of vertical boards (тёс) w wide, h high, facing +Z, centred at base.
static func board_wall(parent: Node3D, base: Vector3, w: float, h: float, depth: float, color: Color) -> void:
	Props.box(parent, base + Vector3(0, h * 0.5, 0), Vector3(w, h, depth), color)
	var battens = maxi(2, int(w / 0.9))
	for i in range(battens + 1):
		var x = -w * 0.5 + w * float(i) / battens
		Props.box(parent, base + Vector3(x, h * 0.5, depth * 0.5 + 0.015), Vector3(0.07, h, 0.03), color.darkened(0.18))

# Triangular prism in the XY plane: base w wide at y0, apex at y1, from z
# back to z - depth.
static func gable(parent: Node3D, z: float, w: float, y0: float, y1: float, depth: float, color: Color) -> MeshInstance3D:
	var front = [Vector3(-w * 0.5, y0, z), Vector3(w * 0.5, y0, z), Vector3(0, y1, z)]
	var back = [Vector3(-w * 0.5, y0, z - depth), Vector3(w * 0.5, y0, z - depth), Vector3(0, y1, z - depth)]
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for v in [front[0], front[1], front[2], back[0], back[2], back[1]]:
		st.add_vertex(v)
	for i in range(3):
		var j = (i + 1) % 3
		for v in [front[i], back[i], back[j], front[i], back[j], front[j]]:
			st.add_vertex(v)
	st.generate_normals()
	var node = MeshInstance3D.new()
	node.mesh = st.commit()
	node.material_override = Props.shared_material(color)
	parent.add_child(node)
	return node

# Plank gable roof with the ridge along local Z, over walls of width w that end
# at height `top`; the roof runs from z0 to z1 (overhangs included). The eaves
# drop below `top` so the planes meet the wall heads. Returns the ridge height.
static func gable_roof(parent: Node3D, top: float, w: float, z0: float, z1: float, pitch: float, color: Color, overhang: float = 0.6) -> float:
	var half = w * 0.5 + overhang
	var ridge = top + w * 0.5 * tan(pitch)
	var length = z1 - z0
	for sx in [-1.0, 1.0]:
		var center = Vector3(sx * half * 0.5, ridge - half * 0.5 * tan(pitch), (z0 + z1) * 0.5)
		var plane = Props.box(parent, center, Vector3(half / cos(pitch) + 0.08, 0.14, length), color)
		plane.rotation.z = -sx * pitch
		Props.box(plane, Vector3(-sx * 0.04, 0.12, 0), Vector3(half / cos(pitch), 0.11, length - 0.08), SNOW)
	return ridge

# Carved barge boards (причелины) along the front edges of a gable roof at z,
# with the hanging "towel" board (полотенце) under the apex.
static func barge_boards(parent: Node3D, z: float, top: float, w: float, pitch: float, color: Color, overhang: float = 0.6) -> void:
	var half = w * 0.5 + overhang
	var ridge = top + w * 0.5 * tan(pitch)
	for sx in [-1.0, 1.0]:
		var board = Props.box(parent, Vector3(sx * half * 0.5, ridge - half * 0.5 * tan(pitch) - 0.12, z + 0.04), Vector3(half / cos(pitch), 0.34, 0.06), color)
		board.rotation.z = -sx * pitch
	Props.box(parent, Vector3(0, ridge - 0.62, z + 0.05), Vector3(0.34, 0.95, 0.06), color)

# Ridge log (охлупень) from z0 to z1 ending in a carved horse head (конёк) at
# z1, resting on the ridge.
static func ridge_log(parent: Node3D, ridge: float, z0: float, z1: float, color: Color) -> void:
	log_between(parent, Vector3(0, ridge + 0.1, z0), Vector3(0, ridge + 0.1, z1), 0.17, color)
	var neck = Props.box(parent, Vector3(0, ridge + 0.42, z1 - 0.05), Vector3(0.14, 0.62, 0.24), color)
	neck.rotation.x = -0.35
	Props.box(parent, Vector3(0, ridge + 0.7, z1 + 0.12), Vector3(0.14, 0.2, 0.44), color)

# A window in a wall facing local +Z, glass centred at `at`: carved white
# surround with a peaked pediment (кокошник), a sill and painted shutters.
static func window(parent: Node3D, at: Vector3, size: Vector2, surround: Color, shutters: Color, lit: bool) -> void:
	Props.box(parent, at + Vector3(0, 0, 0.02), Vector3(size.x + 0.28, size.y + 0.28, 0.06), surround)
	var glass = Props.box(parent, at + Vector3(0, 0, 0.05), Vector3(size.x, size.y, 0.03), Color("fcd98f") if lit else Color("26323a"))
	if lit:
		Props.unique_material(glass)
		glass.material_override.emission_enabled = true
		glass.material_override.emission = Color("ffb35a")
		glass.material_override.emission_energy_multiplier = 0.6
	Props.box(parent, at + Vector3(0, 0, 0.065), Vector3(0.05, size.y, 0.02), surround)
	Props.box(parent, at + Vector3(0, size.y * 0.12, 0.065), Vector3(size.x, 0.05, 0.02), surround)
	Props.box(parent, at + Vector3(0, -size.y * 0.5 - 0.18, 0.08), Vector3(size.x + 0.46, 0.08, 0.16), surround)
	Props.box(parent, at + Vector3(0, size.y * 0.5 + 0.2, 0.05), Vector3(size.x + 0.5, 0.14, 0.08), surround)
	gable(parent, at.z + 0.09, size.x + 0.5, at.y + size.y * 0.5 + 0.27, at.y + size.y * 0.5 + 0.6, 0.06, surround)
	for sx in [-1.0, 1.0]:
		Props.box(parent, at + Vector3(sx * (size.x * 0.75 + 0.16), 0, 0.03), Vector3(size.x * 0.5, size.y + 0.1, 0.04), shutters)

# The same window on a wall facing local +X (wall plane at x = at.x).
static func side_window(parent: Node3D, at: Vector3, size: Vector2, surround: Color, shutters: Color, lit: bool, facing: float = 1.0) -> void:
	var holder = Node3D.new()
	parent.add_child(holder)
	holder.position = at
	holder.rotation.y = facing * PI * 0.5
	window(holder, Vector3.ZERO, size, surround, shutters, lit)
