extends RefCounted
# Wheels shared by every car. A wheel is one pivot (rolling metadata for
# RallyProps.animate_wheels) with one merged, vertex-coloured mesh: tyre, rim
# and a radial pattern - spokes, holes or slots. A plain disc on a smooth tyre
# looks still while it turns, so every style has features that visibly travel.
# The pivot's own axle is +X; LEFT is the rolling axis for forward travel.
#
#   CarParts.wheel(root, Vector3(0.9, 0.36, -1.3), 0.36, 0.26, 1.0, {"style": "spokes", "count": 6})
#
# look: style ("steel", "dish", "spokes", "hubcap"), count, color (rim),
# detail (holes, gaps), tyre, rim (rim radius as a share of the tyre radius).
const STYLES = ["steel", "dish", "spokes", "hubcap"]
const CACHE_LIMIT = 96
static var _meshes: Dictionary = {}
static var _material: StandardMaterial3D

static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 0.82
	return _material

static func wheel(parent: Node3D, centre: Vector3, radius: float, width: float, side: float, look: Dictionary = {}) -> Node3D:
	var pivot = Node3D.new()
	pivot.name = str(look.get("name", "Wheel"))
	parent.add_child(pivot)
	pivot.position = centre
	pivot.set_meta("rolling_wheel_radius", radius)
	pivot.set_meta("rolling_wheel_axis", Vector3.LEFT)
	var mesh = MeshInstance3D.new()
	mesh.name = "WheelMesh"
	mesh.mesh = wheel_mesh(radius, width, signf(side) if side != 0.0 else 1.0, look)
	mesh.material_override = material()
	pivot.add_child(mesh)
	return pivot

static func wheel_mesh(radius: float, width: float, side: float, look: Dictionary) -> ArrayMesh:
	var key = "%.3f|%.3f|%d|%s" % [radius, width, int(side), JSON.stringify(look, "", true)]
	if _meshes.has(key):
		return _meshes[key]
	var parts = {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray()}
	var axle = Basis(Vector3.BACK, PI / 2)
	var tyre_color = Color(look.get("tyre", "1b2022"))
	_cylinder(parts, radius, width, 16, Transform3D(axle, Vector3.ZERO), tyre_color)
	# Sidewall ring a shade lighter than the tread, so the tyre edge reads.
	_cylinder(parts, radius * 0.94, width + 0.012, 16, Transform3D(axle, Vector3.ZERO), tyre_color.lightened(0.08))
	var face = side * (width * 0.5 + 0.006)
	var rim_radius = radius * float(look.get("rim", 0.66))
	var rim_color = Color(look.get("color", "b8c0bf"))
	var detail = Color(look.get("detail", "262d30"))
	var count = maxi(3, int(look.get("count", 5)))
	_cylinder(parts, rim_radius, 0.03, 16, Transform3D(axle, Vector3(face, 0, 0)), rim_color)
	var out = face + side * 0.018
	match str(look.get("style", "steel")):
		"spokes":
			_cylinder(parts, rim_radius * 0.84, 0.02, 16, Transform3D(axle, Vector3(face + side * 0.008, 0, 0)), detail)
			for i in range(count):
				_radial(parts, out, TAU * i / count, rim_radius * 0.16, rim_radius * 0.9, rim_radius * 0.17, rim_color)
		"hubcap":
			for i in range(count):
				_radial(parts, out, TAU * i / count, rim_radius * 0.38, rim_radius * 0.86, rim_radius * 0.07, detail)
		"dish":
			for i in range(count):
				_radial(parts, out, TAU * (i + 0.5) / count, rim_radius * 0.54, rim_radius * 0.82, rim_radius * 0.24, detail)
		_:
			for i in range(count):
				_radial(parts, out, TAU * (i + 0.5) / count, rim_radius * 0.48, rim_radius * 0.68, rim_radius * 0.17, detail)
	# Centre cap and one lighter nut, so even a slow wheel shows its turn.
	_cylinder(parts, rim_radius * 0.2, 0.05, 8, Transform3D(axle, Vector3(face + side * 0.012, 0, 0)), detail.lightened(0.25))
	_radial(parts, out + side * 0.012, 0.0, rim_radius * 0.05, rim_radius * 0.15, rim_radius * 0.06, rim_color.lightened(0.2))
	var mesh = _commit(parts)
	if _meshes.size() < CACHE_LIMIT:
		_meshes[key] = mesh
	return mesh

# A ring of `count` dark holes for an imported wheel that has a plain disc hub.
# Returned as a mesh in the wheel pivot's space; `face` is the hub's outer x.
static func hub_holes(ring: float, hole: float, count: int, face: float, color: Color) -> ArrayMesh:
	var parts = {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray()}
	for i in range(count):
		_radial(parts, face, TAU * (i + 0.5) / count, ring - hole * 0.5, ring + hole * 0.5, hole, color)
	_radial(parts, face, 0.0, ring * 0.15, ring * 0.45, hole * 0.45, color.lightened(0.5))
	return _commit(parts)

# A flat box in the wheel's face plane (x = `x`), from radius r0 to r1 at angle.
static func _radial(parts: Dictionary, x: float, angle: float, r0: float, r1: float, thickness: float, color: Color) -> void:
	var box = BoxMesh.new()
	box.size = Vector3(0.016, r1 - r0, thickness)
	var basis = Basis(Vector3.RIGHT, angle)
	_append(parts, box, Transform3D(basis, Vector3(x, 0, 0) + basis * Vector3(0, (r0 + r1) * 0.5, 0)), color)

static func _cylinder(parts: Dictionary, radius: float, height: float, sides: int, xform: Transform3D, color: Color) -> void:
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	cylinder.radial_segments = sides
	cylinder.rings = 1
	_append(parts, cylinder, xform, color)

static func _append(parts: Dictionary, mesh: PrimitiveMesh, xform: Transform3D, color: Color) -> void:
	var arrays = mesh.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for index in indices:
		parts.v.append(xform * vertices[index])
		parts.n.append((xform.basis * normals[index]).normalized())
		parts.c.append(color)

static func _commit(parts: Dictionary) -> ArrayMesh:
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = parts.v
	arrays[Mesh.ARRAY_NORMAL] = parts.n
	arrays[Mesh.ARRAY_COLOR] = parts.c
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
