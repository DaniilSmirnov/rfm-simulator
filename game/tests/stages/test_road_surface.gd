extends "res://tests/harness.gd"

# The road is drawn as a mesh per surface kind and per 64 m of its length.
func _road_meshes(stage, kind: String) -> Array:
	return stage.find_children("StageRoadSurface_%s_*" % kind, "MeshInstance3D", false, false)

const Stage = preload("res://scripts/stages/stage.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	for variant in [0, 2]:
		var stage = Stage.new(variant)
		root.add_child(stage)
		if variant == 2:
			check(stage.road_width(400.0) < stage.road_width(120.0) and stage.road_width(470.0) < stage.road_width(400.0), "village lanes narrow from the plateau road to the church lane")
		stage._build_road()
		if variant == 2:
			var kinds = ["asphalt", "cobble", "gravel"]
			var present = kinds.filter(func(kind): return not stage.find_children("StageRoadSurface_%s_*" % kind, "MeshInstance3D", false, false).is_empty())
			check(present.size() == 3, "village road is split into asphalt, cobble and gravel meshes")
			check(_road_meshes(stage, "cobble")[0].material_override.albedo_texture != null, "cobbles carry a sett texture")
		var chunks = _road_meshes(stage, "default" if variant == 0 else "cobble")
		var vertex_count = 0
		var index_count = 0
		var valid = true
		for chunk in chunks:
			var arrays = chunk.mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			vertex_count += vertices.size()
			index_count += indices.size()
			valid = valid and arrays[Mesh.ARRAY_NORMAL].size() == vertices.size() and vertices.size() < indices.size()
			for vertex in vertices:
				valid = valid and is_finite(vertex.x) and is_finite(vertex.y) and is_finite(vertex.z)
		check(index_count > (840 * 6 * 4 if variant == 0 else 238 * 6 * 8) and vertex_count < index_count, "road has extra geometry and shares indexed vertices")
		check(valid, "road geometry and smooth normals are finite")
		check(chunks.size() > 2, "the road is split along its length so the frustum can drop what is behind")
		var p = stage.road_surface_vertex(435.25, 1.85)
		check(is_equal_approx(p.y, stage.ground(p) + 0.04), "subdivided road retains terrain contact height")
		check(stage.road_surface_color(p, 435.0) == stage.road_surface_color(p, 436.0), "neighbouring gravel triangles share colours at a common vertex")
		stage.free()
	print("ROAD SURFACE RESULT: %d failures" % failures)
	finish()
