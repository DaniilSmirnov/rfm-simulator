extends SceneTree

# Run after placing Niva v6 OBJ/MTL in game/models/cars/niva/:
# godot --headless --path game --script res://tools/verify_niva_asset.gd
const NivaAsset = preload("res://scripts/niva_asset.gd")

func _initialize() -> void:
	if not NivaAsset.has_asset() or not FileAccess.file_exists(NivaAsset.MTL_PATH):
		push_error("Niva v6 OBJ or MTL not staged in game/models/cars/niva/")
		quit(1)
		return
	var preview = NivaAsset.create_preview()
	if preview == null:
		push_error("Niva v6 failed to load as a Godot Mesh")
		quit(1)
		return
	var visual: MeshInstance3D = preview.get_node("NivaV6Mesh")
	var mesh = visual.mesh
	var triangle_count = 0
	for surface_idx in range(mesh.get_surface_count()):
		if mesh.surface_get_primitive_type(surface_idx) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays = mesh.surface_get_arrays(surface_idx)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		triangle_count += indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
	var size = mesh.get_aabb().size
	var valid = triangle_count >= 14500 and triangle_count <= 16500
	valid = valid and size.z > size.x and size.y > 1.0
	if not valid:
		push_error("Niva v6 geometry unexpected: triangles=%d bounds=%s" % [triangle_count, size])
		preview.free()
		quit(1)
		return
	print("PASS Niva v6: %d triangles, %d surfaces, bounds=%s" % [triangle_count, mesh.get_surface_count(), size])
	preview.free()
	quit()
