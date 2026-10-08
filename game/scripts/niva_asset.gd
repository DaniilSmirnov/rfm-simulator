extends RefCounted

# Staging-only loader. No gameplay factory routes here until the Niva v6
# asset, animation, collision and wheel alignment have been checked.
const OBJ_PATH = "res://models/cars/niva/niva_low_poly.obj"
const MTL_PATH = "res://models/cars/niva/niva_low_poly.mtl"

static func has_asset() -> bool:
	return ResourceLoader.exists(OBJ_PATH)

static func create_preview() -> Node3D:
	if not has_asset():
		return null
	var mesh = load(OBJ_PATH) as Mesh
	if mesh == null or mesh.get_surface_count() == 0:
		return null
	var root = Node3D.new()
	root.name = "NivaV6Preview"
	var visual = MeshInstance3D.new()
	visual.name = "NivaV6Mesh"
	visual.mesh = mesh
	root.add_child(visual)
	return root
