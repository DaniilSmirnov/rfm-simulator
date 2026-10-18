extends "res://tests/harness.gd"
const RoadChunks = preload("res://scripts/stages/road_chunks.gd")
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
			var present = kinds.filter(func(kind): return stage.get_node_or_null("StageRoadSurface_" + kind) != null)
			check(present.size() == 3, "village road is split into asphalt, cobble and gravel meshes")
			check(RoadChunks.meshes(stage, "cobble")[0].material_override.albedo_texture != null, "cobbles carry a sett texture")
		var vertices = PackedVector3Array()
		var indices = PackedInt32Array()
		var normals = PackedVector3Array()
		for piece in RoadChunks.meshes(stage, "default" if variant == 0 else "cobble"):
			var arrays = piece.mesh.surface_get_arrays(0)
			vertices.append_array(arrays[Mesh.ARRAY_VERTEX])
			indices.append_array(arrays[Mesh.ARRAY_INDEX])
			normals.append_array(arrays[Mesh.ARRAY_NORMAL])
		check(indices.size() > (840 * 6 * 4 if variant == 0 else 238 * 6 * 8) and vertices.size() < indices.size(), "road has extra geometry and shares indexed vertices")
		var valid = normals.size() == vertices.size()
		for vertex in vertices:
			valid = valid and is_finite(vertex.x) and is_finite(vertex.y) and is_finite(vertex.z)
		check(valid, "road geometry and smooth normals are finite")
		var pieces = RoadChunks.meshes(stage, "default" if variant == 0 else "cobble")
		var longest = 0.0
		for piece in pieces:
			var box: AABB = piece.mesh.get_aabb()
			longest = maxf(longest, maxf(box.size.x, box.size.z))
		check(pieces.size() >= (8 if variant == 0 else 3) and longest < 130.0, "the road is drawn in %d pieces, none longer than %.0f m, so unseen stretches are culled" % [pieces.size(), longest])
		if variant == 0 and pieces.size() > 2:
			# Normals were smoothed over the whole road: the first shared vertex of
			# two neighbouring pieces carries the same normal in both.
			var first = pieces[1].mesh.surface_get_arrays(0)
			var before = pieces[0].mesh.surface_get_arrays(0)
			var seam_normal = Vector3.ZERO
			var matched = 0
			var smooth_seam = true
			for i in range(first[Mesh.ARRAY_VERTEX].size()):
				var at = before[Mesh.ARRAY_VERTEX].find(first[Mesh.ARRAY_VERTEX][i])
				if at >= 0:
					matched += 1
					smooth_seam = smooth_seam and first[Mesh.ARRAY_NORMAL][i].is_equal_approx(before[Mesh.ARRAY_NORMAL][at])
			check(matched > 4 and smooth_seam, "neighbouring road pieces light the seam alike (%d shared vertices)" % matched)
		var p = stage.road_surface_vertex(435.25, 1.85)
		check(is_equal_approx(p.y, stage.ground(p) + 0.04), "subdivided road retains terrain contact height")
		check(stage.road_surface_color(p, 435.0) == stage.road_surface_color(p, 436.0), "neighbouring gravel triangles share colours at a common vertex")
		stage.free()
	print("ROAD SURFACE RESULT: %d failures" % failures)
	finish()
