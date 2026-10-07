extends SceneTree
const Source = preload("res://tools/character_source.gd")

# Bake geometry once; keep the five pivots used by gameplay animations.
func bake(node: Node3D) -> void:
	var groups = {}
	for child in node.get_children():
		if not child is Node3D or not child.visible:
			node.remove_child(child)
			child.free()
			continue
		if child.name in ["LeftArm", "RightArm", "LeftLeg", "RightLeg", "Head"]:
			bake(child)
			continue
		collect(child, child.transform, groups)
		node.remove_child(child)
		child.free()
	var mesh = ArrayMesh.new()
	for key in groups:
		var group = groups[key]
		var arrays = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = group.vertices
		arrays[Mesh.ARRAY_NORMAL] = group.normals
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, group.material)
	var body = MeshInstance3D.new()
	body.name = "Geometry"
	body.mesh = mesh
	node.add_child(body)

func collect(node: Node3D, pose: Transform3D, groups: Dictionary) -> void:
	if node is MeshInstance3D:
		var mat = node.material_override
		var key = mat.albedo_color.to_html()
		if not groups.has(key):
			groups[key] = {"vertices": PackedVector3Array(), "normals": PackedVector3Array(), "material": mat}
		var faces = node.mesh.get_faces()
		for i in range(0, faces.size(), 3):
			var a = pose * faces[i]
			var b = pose * faces[i + 1]
			var c = pose * faces[i + 2]
			var normal = (c - a).cross(b - a).normalized()
			groups[key].vertices.append_array(PackedVector3Array([a, b, c]))
			groups[key].normals.append_array(PackedVector3Array([normal, normal, normal]))
	for child in node.get_children():
		if child is Node3D and child.visible:
			collect(child, pose * child.transform, groups)

func _initialize() -> void:
	for variant in range(4):
		var avatar = Source.player_avatar(variant)
		bake(avatar)
		var state = GLTFState.new()
		var document = GLTFDocument.new()
		assert(document.append_from_scene(avatar, state) == OK)
		assert(document.write_to_filesystem(state, "res://models/characters/spectator_%d.glb" % variant) == OK)
		avatar.free()
	quit()
