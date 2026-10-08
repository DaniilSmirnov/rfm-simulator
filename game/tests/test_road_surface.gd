extends SceneTree
const Stage = preload("res://scripts/stage.gd")
var failures = 0
func check(ok: bool, message: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + message)
	if not ok:
		failures += 1
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	for variant in [0, 2]:
		var stage = Stage.new(variant)
		root.add_child(stage)
		if variant == 2:
			check(is_equal_approx(stage.road_width(435.0), 4 * 0.8 + 0.76), "gravel width matches the five cobbled side-lane rows")
			check(is_equal_approx(stage.road_width(180.0), stage.WIDTH), "country main road retains its width")
		stage._build_road()
		if variant == 2:
			check(stage.get_node_or_null("GravelPuddle_412") != null and stage.get_node_or_null("GravelPuddle_463") != null, "gravel depressions contain visible water surfaces")
		var mesh: ArrayMesh = stage.get_node("StageRoadSurface").mesh
		var arrays = mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		check(indices.size() > 840 * 6 * 4 and vertices.size() < indices.size(), "road has extra geometry and shares indexed vertices")
		var valid = normals.size() == vertices.size()
		for vertex in vertices:
			valid = valid and is_finite(vertex.x) and is_finite(vertex.y) and is_finite(vertex.z)
		check(valid, "road geometry and smooth normals are finite")
		var p = stage.road_surface_vertex(435.25, 1.85)
		check(is_equal_approx(p.y, stage.ground(p) + 0.04), "subdivided road retains terrain contact height")
		check(stage.road_surface_color(p, 435.0) == stage.road_surface_color(p, 436.0), "neighbouring gravel triangles share colours at a common vertex")
		stage.free()
	print("ROAD SURFACE RESULT: %d failures" % failures)
	quit(1 if failures else 0)
