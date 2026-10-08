extends SceneTree
const Granta = preload("res://scripts/granta_model.gd")
const OUT = "res://models/cars/granta/"
var lines: PackedStringArray = []
var mats: Dictionary = {}
var offset = 1
var triangle_count = 0

func color_key(color: Color) -> String:
	return color.to_html(false)

func walk(node: Node, transform: Transform3D) -> void:
	var pose = transform
	if node is Node3D:
		pose = transform * node.transform
	if node is MeshInstance3D and node.visible and node.mesh != null and not node.name.begins_with("Box_"):
		var mesh: Mesh = node.mesh
		for surface in range(mesh.get_surface_count()):
			if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var material: Material = node.material_override
			if material == null:
				material = mesh.surface_get_material(surface)
			var albedo = Color.WHITE
			if material is BaseMaterial3D:
				albedo = material.albedo_color
			var key = color_key(albedo)
			var mat_name = "mat_" + key
			mats[mat_name] = albedo
			var arr = mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count = indices.size() if not indices.is_empty() else vertices.size()
			lines.append("o %s_%d" % [str(node.name).replace(" ", "_"), surface])
			lines.append("usemtl " + mat_name)
			for i in range(0, count, 3):
				for j in range(3):
					var index: int = indices[i + j] if not indices.is_empty() else i + j
					var point: Vector3 = pose * vertices[index]
					lines.append("v %.6f %.6f %.6f" % [point.x, point.y, point.z])
				lines.append("f %d %d %d" % [offset, offset + 1, offset + 2])
				offset += 3
				triangle_count += 1
	for child in node.get_children():
		if child.name == "TrunkBoxes":
			continue
		walk(child, pose)

func _initialize() -> void:
	var car = Granta.build()
	lines.append("# Rally Fans Simulator — compact sedan, unbranded black-blue")
	lines.append("mtllib granta_black_blue.mtl")
	walk(car, Transform3D.IDENTITY)
	var obj = FileAccess.open(OUT + "granta_black_blue.obj", FileAccess.WRITE)
	if obj == null:
		push_error("Cannot create OBJ")
		quit(1)
		return
	obj.store_string("\n".join(lines) + "\n")
	obj.close()
	var mtl = FileAccess.open(OUT + "granta_black_blue.mtl", FileAccess.WRITE)
	for name in mats.keys():
		var c: Color = mats[name]
		mtl.store_string("newmtl %s\nKd %.6f %.6f %.6f\nKa 0.0 0.0 0.0\nKs 0.05 0.05 0.05\nillum 2\n\n" % [name, c.r, c.g, c.b])
	mtl.close()
	print("Granta OBJ exported: %d triangles, %d materials" % [triangle_count, mats.size()])
	car.free()
	quit()
