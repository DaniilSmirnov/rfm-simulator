extends RefCounted

# Niva v6 is pre-split in the asset pipeline, not cut at runtime. This keeps
# the rear seats, roof, side panels and rear lamps stationary while the hatch
# (bodywork plus opaque rear glass) pivots as a single assembly.
const OBJ_PATH = "res://models/cars/niva/niva_low_poly.obj"
const MTL_PATH = "res://models/cars/niva/niva_low_poly.mtl"
const BODY_PATH = "res://models/cars/niva/niva_body_static.obj"
const TAILGATE_PATH = "res://models/cars/niva/niva_tailgate.obj"
const WHEELS_PATH = "res://models/cars/niva/niva_wheels.obj"
const HINGE = Vector3(0.0, 1.56, 1.42)

static func has_asset() -> bool:
	return ResourceLoader.exists(OBJ_PATH) and ResourceLoader.exists(BODY_PATH) and ResourceLoader.exists(TAILGATE_PATH) and ResourceLoader.exists(WHEELS_PATH)

static func _mesh(path: String) -> Mesh:
	var resource = load(path)
	return resource as Mesh

static func create_preview() -> Node3D:
	if not has_asset():
		return null
	var mesh = _mesh(OBJ_PATH)
	if mesh == null or mesh.get_surface_count() == 0:
		return null
	var root = Node3D.new()
	root.name = "NivaV6Preview"
	var visual = MeshInstance3D.new()
	visual.name = "NivaV6Mesh"
	visual.mesh = mesh
	root.add_child(visual)
	return root

# Wheel geometry is split by side and axle into individually rotating pivots.
# Keep original OBJ materials and prevent wheel triangles from being rendered twice.
static func _attach_wheels(root: Node3D, mesh: Mesh) -> void:
	for surface_index in range(mesh.get_surface_count()):
		var source = MeshDataTool.new()
		if source.create_from_surface(mesh, surface_index) != OK:
			continue
		var groups: Dictionary = {}
		for face in range(source.get_face_count()):
			var points: Array = []
			for corner in range(3):
				points.append(source.get_vertex(source.get_face_vertex(face, corner)))
			var mid: Vector3 = (points[0] + points[1] + points[2]) / 3.0
			var key: String = "%d_%d" % [1 if mid.x >= 0.0 else -1, 1 if mid.z >= 0.0 else -1]
			if not groups.has(key):
				groups[key] = []
			groups[key].append_array(points)
		for key in groups:
			var points: Array = groups[key]
			if points.is_empty():
				continue
			var lo: Vector3 = points[0]
			var hi: Vector3 = points[0]
			for point in points:
				lo = lo.min(point)
				hi = hi.max(point)
			var pivot = (lo + hi) * 0.5
			var builder = SurfaceTool.new()
			builder.begin(Mesh.PRIMITIVE_TRIANGLES)
			for point in points:
				builder.add_vertex(point - pivot)
			builder.generate_normals()
			var wheel = MeshInstance3D.new()
			wheel.name = "NivaWheel_%d_%s" % [surface_index, key]
			wheel.mesh = builder.commit()
			wheel.position = pivot
			wheel.material_override = mesh.surface_get_material(surface_index)
			wheel.set_meta("rolling_wheel_radius", 0.34)
			wheel.set_meta("rolling_wheel_axis", Vector3.RIGHT)
			root.add_child(wheel)

static func build() -> Node3D:
	if not has_asset():
		push_error("Niva v6 files missing: cannot replace the procedural car")
		return null
	var body_mesh = _mesh(BODY_PATH)
	var door_mesh = _mesh(TAILGATE_PATH)
	var wheel_mesh = _mesh(WHEELS_PATH)
	if body_mesh == null or door_mesh == null or wheel_mesh == null or body_mesh.get_surface_count() == 0 or door_mesh.get_surface_count() == 0 or wheel_mesh.get_surface_count() == 0:
		push_error("Niva v6: static body or tailgate failed to import")
		return null

	var root = Node3D.new()
	root.name = "PlayerCar_2"
	root.set_meta("model", "Лесной внедорожник")
	root.set_meta("variant", 2)
	root.set_meta("model_source", "niva_v6_obj")
	root.set_meta("trunk_lid_start_z", HINGE.z)

	var details = Node3D.new()
	details.name = "NivaStaticParts"
	root.add_child(details)
	var body = MeshInstance3D.new()
	body.name = "NivaBody"
	body.mesh = body_mesh
	details.add_child(body)
	_attach_wheels(details, wheel_mesh)

	# Calls the existing inventory, approach and trunk animation setup.
	# Static geometry is beneath NivaStaticParts and cannot be clipped again.
	var props = load("res://scripts/props.gd")
	props.add_player_trunk(root, 2)
	var hinge: Node3D = root.get_node("TrunkHinge")
	hinge.position = HINGE

	var door = MeshInstance3D.new()
	door.name = "NivaTailgate_Lid"
	door.mesh = door_mesh
	door.position = -HINGE
	hinge.add_child(door)
	return root
