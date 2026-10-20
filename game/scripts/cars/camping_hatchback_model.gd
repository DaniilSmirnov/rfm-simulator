extends RefCounted

# Original, unbranded low-poly five-door wedge hatchback with an inflatable boat
# on the roof. Every surface is lofted here from hand-picked sections; no
# third-party mesh is involved. Front faces -Z, metres, Y up.
# Body, glass, trim and lamps are direct MeshInstance3D children, so
# RallyProps.add_player_trunk() can cut the rear hatch out of each of them.
const CarParts = preload("res://scripts/cars/car_parts.gd")
const COLORS = {
	"body": Color("283f87"),
	"glass": Color("253d49"),
	"trim": Color("202b31"),
	"lights": Color("a6464a"),
	"headlights": Color("e6e4d4"),
	"indicators": Color("e0a24a"),
	"plates": Color("dfe3de"),
	"boat": Color("59636d"),
	"boat_floor": Color("3d454c"),
	"rack": Color("3c3224"),
}
const WHEEL_Y = 0.295
const WHEEL_X = 0.65
const WHEEL_Z = [-1.25, 1.24]
const ARCH = 0.36
# Lower body sections: z, half width, sill, belt line, deck height, deck crown.
# A low wedge nose rises to a level waist, then drops into a short square tail.
const BODY = [
	[-2.085, 0.74, 0.34, 0.60, 0.64, 0.01],
	[-2.06, 0.79, 0.30, 0.66, 0.69, 0.02],
	[-1.98, 0.82, 0.27, 0.72, 0.75, 0.03],
	[-1.80, 0.83, 0.26, 0.77, 0.80, 0.04],
	[-1.40, 0.83, 0.26, 0.84, 0.86, 0.05],
	[-0.95, 0.83, 0.26, 0.90, 0.92, 0.04],
	[-0.40, 0.83, 0.26, 0.925, 0.935, 0.02],
	[0.60, 0.83, 0.26, 0.955, 0.965, 0.02],
	[1.40, 0.83, 0.27, 0.975, 0.985, 0.02],
	[1.90, 0.82, 0.28, 0.97, 0.98, 0.02],
	[2.04, 0.80, 0.32, 0.945, 0.955, 0.01],
	[2.085, 0.76, 0.38, 0.91, 0.92, 0.0],
]
# Glasshouse sections: z, belt height, roof height, belt half width, roof half width.
# Raked windscreen, short flat roof and a long sloping hatch glass.
const CABIN = [
	[-0.97, 0.915, 0.93, 0.77, 0.74],
	[-0.32, 0.935, 1.39, 0.77, 0.65],
	[-0.20, 0.937, 1.42, 0.77, 0.64],
	[0.45, 0.955, 1.42, 0.77, 0.64],
	[0.62, 0.958, 1.385, 0.77, 0.64],
	[1.20, 0.97, 1.20, 0.76, 0.65],
	[1.95, 0.975, 1.0, 0.74, 0.68],
]
const CABIN_CUTS = [-0.70, -0.02, 0.06, 0.55, 0.80, 0.98, 1.50]

static func build() -> Node3D:
	var root = Node3D.new()
	root.name = "PlayerCar_8"
	root.set_meta("model", "Походный хэтчбек")
	root.set_meta("variant", 8)
	root.set_meta("model_source", "camping_hatchback_procedural")
	root.set_meta("roof_cargo", "inflatable_boat")
	# The hatch opens behind the rear passenger seats, unlike the generic hatch template.
	root.set_meta("trunk_lid_start_z", 1.20)
	var parts: Dictionary = {}
	_body(parts)
	_cabin(parts)
	_fascias(parts)
	_side_details(parts)
	_boat(parts)
	var details = Node3D.new()
	details.name = "CarModelDetails"
	root.add_child(details)
	var roof = Node3D.new()
	roof.name = "RoofHatchback"
	root.add_child(roof)
	# Hatch-cut parts first, then static details that must not swing with the lid.
	for part in ["body", "glass", "trim", "lights"]:
		var node = _commit(parts, part)
		node.name = "BodyShellHatchback" if part == "body" else "Camping_" + part
		root.add_child(node)
	for part in ["headlights", "indicators", "plates", "rack", "boat", "boat_floor"]:
		var node = _commit(parts, part)
		node.name = "Camping_" + part
		details.add_child(node)
	for side in [-1.0, 1.0]:
		for index in range(2):
			CarParts.wheel(details, Vector3(side * WHEEL_X, WHEEL_Y, WHEEL_Z[index]), WHEEL_Y, 0.18, side, {
				"name": "RollingWheel_%s_%s" % ["L" if side < 0 else "R", "Front" if index == 0 else "Rear"],
				"style": "hubcap", "count": 8, "color": "899299", "detail": "4c555c", "tyre": "181c20", "rim": 0.74})
	return root

# --- geometry buckets: one flat-shaded mesh per material ---

static func _tri(parts: Dictionary, part: String, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	if not parts.has(part):
		parts[part] = {"v": PackedVector3Array(), "n": PackedVector3Array()}
	var normal = (b - a).cross(c - a)
	if normal.length_squared() < 1e-12:
		return
	normal = normal.normalized()
	# Two-sided materials flip the normal of faces seen from behind, judged by
	# winding: wind each triangle so its outward side is the front face.
	var points = PackedVector3Array([a, c, b])
	if normal.dot(outward) < 0.0:
		normal = -normal
		points = PackedVector3Array([a, b, c])
	parts[part].v.append_array(points)
	for i in range(3):
		parts[part].n.append(normal)

static func _quad(parts: Dictionary, part: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3) -> void:
	_tri(parts, part, a, b, c, outward)
	_tri(parts, part, a, c, d, outward)

# Flat quad on a plane facing `facing`, nudged off the surface beneath it.
static func _decal(parts: Dictionary, part: String, points: Array, facing: Vector3) -> void:
	var lift = facing * 0.004
	_quad(parts, part, points[0] + lift, points[1] + lift, points[2] + lift, points[3] + lift, facing)

static func _box(parts: Dictionary, part: String, centre: Vector3, size: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	var h = size * 0.5
	for axis in range(3):
		for sign_value in [-1.0, 1.0]:
			var n = Vector3.ZERO
			n[axis] = sign_value
			var u = Vector3.ZERO
			u[(axis + 1) % 3] = 1.0
			var v = Vector3.ZERO
			v[(axis + 2) % 3] = 1.0
			var corners: Array = []
			for k in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				corners.append(centre + basis * ((n + u * k.x + v * k.y) * h))
			_quad(parts, part, corners[0], corners[1], corners[2], corners[3], basis * n)

# Square-section bar between two points, used for rails, straps and pillars.
static func _beam(parts: Dictionary, part: String, a: Vector3, b: Vector3, width: Vector2) -> void:
	var dir = (b - a).normalized()
	var up = Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.BACK
	var side = dir.cross(up).normalized()
	_box(parts, part, (a + b) * 0.5, Vector3(width.x, width.y, a.distance_to(b)), Basis(side, side.cross(dir).normalized() * -1.0, dir).orthonormalized())

# Loft between consecutive rings of equal size. `pick` chooses the material of
# each band from its ring segment index and mid z; empty string skips the band.
static func _loft(parts: Dictionary, rings: Array, pick: Callable, cap: String) -> void:
	for i in range(rings.size() - 1):
		var r0: PackedVector3Array = rings[i]
		var r1: PackedVector3Array = rings[i + 1]
		var centre = (_centroid(r0) + _centroid(r1)) * 0.5
		for j in range(r0.size()):
			var k = (j + 1) % r0.size()
			var part: String = pick.call(j, (r0[j].z + r1[j].z) * 0.5)
			if part != "":
				var mid = (r0[j] + r0[k] + r1[j] + r1[k]) * 0.25
				_quad(parts, part, r0[j], r0[k], r1[k], r1[j], mid - centre)
	for index in [0, rings.size() - 1]:
		var ring: PackedVector3Array = rings[index]
		var middle = _centroid(ring)
		var facing = Vector3(0, 0, -1 if index == 0 else 1)
		for j in range(ring.size()):
			_tri(parts, cap, middle, ring[j], ring[(j + 1) % ring.size()], facing)

static func _centroid(ring: PackedVector3Array) -> Vector3:
	var sum = Vector3.ZERO
	for point in ring:
		sum += point
	return sum / ring.size()

static func _sample(table: Array, z: float) -> Array:
	if z <= table[0][0]:
		return table[0]
	for i in range(1, table.size()):
		if z <= table[i][0]:
			var t = (z - table[i - 1][0]) / (table[i][0] - table[i - 1][0])
			var row: Array = []
			for c in range(table[i].size()):
				row.append(lerpf(table[i - 1][c], table[i][c], t))
			return row
	return table[-1]

static func _commit(parts: Dictionary, part: String) -> MeshInstance3D:
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = parts[part].v
	arrays[Mesh.ARRAY_NORMAL] = parts[part].n
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node = MeshInstance3D.new()
	node.mesh = mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = COLORS[part]
	mat.roughness = 0.3 if part in ["glass", "headlights"] else 0.65
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = mat
	return node

# --- bodywork ---

static func _arch_top(z: float) -> float:
	var top = 0.0
	for cz in WHEEL_Z:
		var d = absf(z - cz)
		if d < ARCH:
			top = maxf(top, WHEEL_Y + sqrt(ARCH * ARCH - d * d))
	return top

static func _body(parts: Dictionary) -> void:
	var zs: Array = []
	for row in BODY:
		zs.append(row[0])
	# Dense sections over the wheels, so the sill follows a round arch.
	for cz in WHEEL_Z:
		for step in range(9):
			zs.append(cz - ARCH * cos(PI * step / 8.0))
		zs.append_array([cz - ARCH - 0.001, cz + ARCH + 0.001])
	zs.sort()
	var rings: Array = []
	for z in zs:
		var s = _sample(BODY, z)
		var sill = maxf(s[2], _arch_top(z))
		var flank = minf(sill + 0.10, (sill + s[3]) * 0.5)
		var shoulder = maxf(flank, s[3] - 0.10)
		var w: float = s[1]
		var half: Array = [Vector2(w * 0.90, sill), Vector2(w, flank), Vector2(w, shoulder), Vector2(w * 0.97, s[3]), Vector2(w * 0.88, s[4]), Vector2(w * 0.45, s[4] + s[5])]
		var ring = PackedVector3Array([Vector3(0, sill, z)])
		for p in half:
			ring.append(Vector3(p.x, p.y, z))
		ring.append(Vector3(0, s[4] + s[5] * 1.1, z))
		for i in range(half.size() - 1, -1, -1):
			ring.append(Vector3(-half[i].x, half[i].y, z))
		rings.append(ring)
	_loft(parts, rings, func(_j, _z): return "body", "body")
	# Dark wheel-well liners behind the arch gap.
	for cz in WHEEL_Z:
		for step in range(8):
			var a0 = PI * step / 8.0
			var a1 = PI * (step + 1) / 8.0
			for side in [-1.0, 1.0]:
				var p0 = Vector3(0, WHEEL_Y + sin(a0) * (ARCH - 0.01), cz - cos(a0) * (ARCH - 0.01))
				var p1 = Vector3(0, WHEEL_Y + sin(a1) * (ARCH - 0.01), cz - cos(a1) * (ARCH - 0.01))
				var inner = Vector3(side * 0.42, 0, 0)
				var outer = Vector3(side * 0.82, 0, 0)
				_quad(parts, "trim", p0 + inner, p0 + outer, p1 + outer, p1 + inner, Vector3(0, WHEEL_Y, cz) - (p0 + p1) * 0.5)

static func _cabin_part(segment: int, z: float) -> String:
	# Ring: 0 side glass, 1 pillar/rail, 2-3 roof or screens, 4 rail, 5 side glass.
	if segment in [1, 4]:
		return "body"
	if segment in [2, 3]:
		return "body" if z > -0.32 and z < 0.55 else "glass"
	if segment == 6:
		return ""
	var pillar = (z > -0.02 and z < 0.06) or z > 0.98
	return "body" if pillar else "glass"

static func _cabin(parts: Dictionary) -> void:
	var zs: Array = CABIN_CUTS.duplicate()
	for row in CABIN:
		zs.append(row[0])
	zs.sort()
	var rings: Array = []
	for z in zs:
		var s = _sample(CABIN, z)
		var rail = minf(0.05, (s[2] - s[1]) * 0.3)
		rings.append(PackedVector3Array([
			Vector3(s[3], s[1], z), Vector3(s[4] + rail, s[2] - rail, z), Vector3(s[4], s[2], z),
			Vector3(0, s[2] + 0.015, z),
			Vector3(-s[4], s[2], z), Vector3(-s[4] - rail, s[2] - rail, z), Vector3(-s[3], s[1], z),
		]))
	_loft(parts, rings, func(j, z): return _cabin_part(j, z), "glass")
	# Black window belt mouldings and a small spoiler over the hatch glass.
	for side in [-1.0, 1.0]:
		var points: Array = []
		for z in [-0.95, -0.40, 0.60, 1.10]:
			var s = _sample(CABIN, z)
			points.append(Vector3(side * (s[3] + 0.012), s[1] + 0.012, z))
		for i in range(points.size() - 1):
			_beam(parts, "trim", points[i], points[i + 1], Vector2(0.025, 0.03))
	_box(parts, "trim", Vector3(0, 1.40, 0.66), Vector3(1.18, 0.035, 0.16), Basis(Vector3.RIGHT, 0.22))
	# Rear wiper resting on the hatch glass.
	_beam(parts, "trim", Vector3(0.02, 1.02, 1.74), Vector3(-0.36, 1.10, 1.52), Vector2(0.025, 0.02))

static func _fascias(parts: Dictionary) -> void:
	var front = Vector3(0, 0, -2.085)
	var back = Vector3(0, 0, 2.085)
	var ahead = Vector3.FORWARD
	for side in [-1.0, 1.0]:
		# Long narrow headlamps that taper toward the wings, amber corner lamps below.
		_decal(parts, "headlights", [front + Vector3(side * 0.23, 0.515, 0), front + Vector3(side * 0.67, 0.50, 0),
			front + Vector3(side * 0.65, 0.625, 0), front + Vector3(side * 0.23, 0.635, 0)], ahead)
		_decal(parts, "indicators", [front + Vector3(side * 0.56, 0.455, 0), front + Vector3(side * 0.70, 0.445, 0),
			front + Vector3(side * 0.69, 0.495, 0), front + Vector3(side * 0.56, 0.50, 0)], ahead)
		# Broad tail lamps meet a red band across the hatch; white reversing lamps below.
		_decal(parts, "lights", [back + Vector3(side * 0.36, 0.70, 0), back + Vector3(side * 0.73, 0.70, 0),
			back + Vector3(side * 0.72, 0.86, 0), back + Vector3(side * 0.36, 0.86, 0)], Vector3.BACK)
		_decal(parts, "plates", [back + Vector3(side * 0.50, 0.655, 0), back + Vector3(side * 0.66, 0.655, 0),
			back + Vector3(side * 0.66, 0.69, 0), back + Vector3(side * 0.50, 0.69, 0)], Vector3.BACK)
	_decal(parts, "lights", [back + Vector3(-0.36, 0.73, 0), back + Vector3(0.36, 0.73, 0),
		back + Vector3(0.36, 0.84, 0), back + Vector3(-0.36, 0.84, 0)], Vector3.BACK)
	# Unbranded slot grille, bumper intake and lip, blank plates.
	_decal(parts, "trim", [front + Vector3(-0.21, 0.555, 0), front + Vector3(0.21, 0.555, 0),
		front + Vector3(0.21, 0.61, 0), front + Vector3(-0.21, 0.61, 0)], ahead)
	_decal(parts, "trim", [front + Vector3(-0.52, 0.375, 0), front + Vector3(0.52, 0.375, 0),
		front + Vector3(0.50, 0.47, 0), front + Vector3(-0.50, 0.47, 0)], ahead)
	_box(parts, "trim", Vector3(0, 0.33, -2.06), Vector3(1.40, 0.04, 0.07))
	_box(parts, "plates", Vector3(0, 0.425, -2.088), Vector3(0.50, 0.10, 0.004))
	_box(parts, "plates", Vector3(0, 0.55, 2.088), Vector3(0.50, 0.11, 0.004))
	_decal(parts, "trim", [back + Vector3(-0.74, 0.43, 0), back + Vector3(0.74, 0.43, 0),
		back + Vector3(0.74, 0.47, 0), back + Vector3(-0.74, 0.47, 0)], Vector3.BACK)
	# Hatch handle strip above the plate, on the opening lid.
	_box(parts, "trim", Vector3(0, 0.875, 2.088), Vector3(0.40, 0.022, 0.004))

static func _side_details(parts: Dictionary) -> void:
	for side in [-1.0, 1.0]:
		var out = Vector3(side, 0, 0)
		var x = side * 0.83
		# Rubbing strip between the arches and five-door shut lines.
		_decal(parts, "trim", [Vector3(x, 0.48, -0.86), Vector3(x, 0.48, 0.86), Vector3(x, 0.54, 0.86), Vector3(x, 0.54, -0.86)], out)
		for seam in [[-0.88, 0.66, 0.89], [0.02, 0.30, 0.93], [0.87, 0.66, 0.95]]:
			_decal(parts, "trim", [Vector3(x, seam[1], seam[0] - 0.006), Vector3(x, seam[1], seam[0] + 0.006),
				Vector3(x, seam[2], seam[0] + 0.006), Vector3(x, seam[2], seam[0] - 0.006)], out)
		for z in [-0.12, 0.74]:
			_box(parts, "trim", Vector3(side * 0.834, 0.82, z), Vector3(0.012, 0.03, 0.13))
		_decal(parts, "indicators", [Vector3(x, 0.72, -1.60), Vector3(x, 0.72, -1.53), Vector3(x, 0.75, -1.53), Vector3(x, 0.75, -1.60)], out)
		# Door mirror on a short arm ahead of the front door glass.
		_beam(parts, "trim", Vector3(side * 0.74, 0.95, -0.84), Vector3(side * 0.80, 0.99, -0.80), Vector2(0.04, 0.03))
		_box(parts, "trim", Vector3(side * 0.80, 1.01, -0.79), Vector3(0.065, 0.10, 0.15))

# Roof bars and an inflatable dinghy: round tubes swept around a pointed bow.
static func _boat(parts: Dictionary) -> void:
	for z in [-0.50, 0.50]:
		for side in [-1.0, 1.0]:
			_box(parts, "rack", Vector3(side * 0.56, 1.46, z), Vector3(0.06, 0.09, 0.10))
		_box(parts, "rack", Vector3(0, 1.525, z), Vector3(1.18, 0.04, 0.06))
	var path: Array = []
	var bow = [Vector2(0.33, -0.45), Vector2(0.31, -0.68), Vector2(0.22, -0.87), Vector2(0.0, -0.98)]
	path.append(Vector3(0.33, 1.66, 1.02))
	for p in bow:
		path.append(Vector3(p.x, 1.66 + 0.05 * (0.45 + p.y) / -0.53, p.y))
	for i in range(bow.size() - 2, -1, -1):
		path.append(Vector3(-bow[i].x, path[i + 1].y, bow[i].y))
	path.append(Vector3(-0.33, 1.66, 1.02))
	var rings: Array = []
	for i in range(path.size()):
		var tangent: Vector3 = (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		var across = tangent.cross(Vector3.UP).normalized()
		var ring = PackedVector3Array()
		for k in range(8):
			var angle = TAU * k / 8.0
			ring.append(path[i] + (across * cos(angle) + Vector3.UP * sin(angle)) * 0.10)
		rings.append(ring)
	_tube(parts, rings)
	# Floor, transom board, two thwarts and tie-down straps over the tubes.
	for i in range(1, path.size() - 2):
		_tri(parts, "boat_floor", Vector3(0, 1.575, 1.0), Vector3(path[i].x * 0.8, 1.575, path[i].z), Vector3(path[i + 1].x * 0.8, 1.575, path[i + 1].z), Vector3.UP)
	_tri(parts, "boat_floor", Vector3(0, 1.575, 1.0), Vector3(-0.26, 1.575, 1.0), Vector3(-0.26, 1.575, -0.45), Vector3.UP)
	_tri(parts, "boat_floor", Vector3(0, 1.575, 1.0), Vector3(0.26, 1.575, -0.45), Vector3(0.26, 1.575, 1.0), Vector3.UP)
	_box(parts, "boat_floor", Vector3(0, 1.66, 1.03), Vector3(0.50, 0.17, 0.04))
	for z in [-0.15, 0.45]:
		_box(parts, "rack", Vector3(0, 1.67, z), Vector3(0.50, 0.035, 0.17))
	for z in [-0.50, 0.50]:
		var strap = [Vector3(-0.59, 1.52, z), Vector3(-0.44, 1.72, z), Vector3(-0.33, 1.775, z), Vector3(0.33, 1.775, z), Vector3(0.44, 1.72, z), Vector3(0.59, 1.52, z)]
		for i in range(strap.size() - 1):
			_beam(parts, "rack", strap[i], strap[i + 1], Vector2(0.008, 0.035))

static func _tube(parts: Dictionary, rings: Array) -> void:
	for i in range(rings.size() - 1):
		var centre = (_centroid(rings[i]) + _centroid(rings[i + 1])) * 0.5
		for j in range(8):
			var k = (j + 1) % 8
			var a: Vector3 = rings[i][j]
			var mid = (a + rings[i][k] + rings[i + 1][j] + rings[i + 1][k]) * 0.25
			_quad(parts, "boat", a, rings[i][k], rings[i + 1][k], rings[i + 1][j], mid - centre)
	for index in [0, rings.size() - 1]:
		var middle = _centroid(rings[index])
		for j in range(8):
			_tri(parts, "boat", middle, rings[index][j], rings[index][(j + 1) % 8], Vector3.BACK)
