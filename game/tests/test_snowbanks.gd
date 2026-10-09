extends SceneTree
const Stage = preload("res://scripts/stage.gd")
const Banks = preload("res://scripts/snowbanks.gd")
var failures = 0
func check(ok: bool, description: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + description)
	if not ok: failures += 1
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var stage = Stage.new(1)
	stage._build_road()
	check(stage.find_children("Snowbank*", "MeshInstance3D", false, false).size() == 2, "winter road builds two continuous bank meshes")
	for edge in [-1.0, 1.0]:
		var node: MeshInstance3D = stage.get_node("SnowbankLeft" if edge < 0 else "SnowbankRight")
		var arrays = node.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var valid = true
		var shared_edges = {}
		for i in range(0, indices.size(), 3):
			for side in range(3):
				var a = indices[i + side]
				var b = indices[i + (side + 1) % 3]
				var key = Vector2i(mini(a, b), maxi(a, b))
				shared_edges[key] = int(shared_edges.get(key, 0)) + 1
		var boundary_edges = 0
		for key in shared_edges:
			valid = valid and shared_edges[key] in [1, 2]
			if shared_edges[key] == 1: boundary_edges += 1
		# SurfaceTool may reorder vertices while computing smooth normals.
		# A closed ribbon has only two long borders and its two end borders.
		var expected_boundary = 2 * (vertices.size() / (Banks.STRIPS + 1) - 1) + 2 * Banks.STRIPS
		valid = valid and boundary_edges == expected_boundary
		check(valid, "adjacent rings share indexed edges without gaps (side %s)" % edge)
		check(normals.size() == vertices.size() and normals[5].y > 0.5, "smooth upward-facing normals (side %s)" % edge)
		var follows = true
		var rounded = true
		for station in range(12, 829, 4):
			var toe = Banks.vertex(stage, station, edge, 0.0)
			var crest = Banks.vertex(stage, station, edge, 0.5)
			var outer = Banks.vertex(stage, station, edge, 1.0)
			follows = follows and absf(toe.y - stage.terrain_surface_height(toe) + 0.035) < 0.0001 and absf(outer.y - stage.terrain_surface_height(outer) + 0.035) < 0.0001
			if stage.DeepSnow.camp_mask(stage, crest) > 0.999:
				rounded = rounded and crest.y - stage.terrain_surface_height(crest) > 0.70
			var near_toe = Banks.vertex(stage, station, edge, 0.01)
			var height = near_toe.y - stage.terrain_surface_height(near_toe) + 0.035
			rounded = rounded and height < 0.002
		check(follows, "both toes meet rendered terrain across the entire stage (side %s)" % edge)
		check(rounded, "raised rounded crest and gentle toes (side %s)" % edge)
		check(vertices.size() < 12000 and indices.size() / 3 < 20000, "geometry has a bounded budget (side %s)" % edge)
	var station = 220.0
	var crest = Banks.vertex(stage, station, 1.0, 0.5)
	check(absf(Banks.surface_height(stage, crest) - crest.y) < 0.0001, "bank tyre support matches actual visible mesh")
	check(stage.vehicle_ground(crest) >= crest.y and stage.ground(crest) >= crest.y, "cars and walkers cannot pass below bank surface")
	var car = Node3D.new()
	car.position = crest
	var motion = preload("res://scripts/vehicle_motion.gd").new()
	motion.suspension(car, stage, 1.0 / 120, 0.0)
	check(car.position.y >= crest.y, "vehicle body stays above crest even between wheel samples")
	car.free()
	for center in stage.snow_camps:
		var clear = true
		for x in [-4.0, 0.0, 4.0]:
			for z in [-4.0, 0.0, 4.0]:
				clear = clear and stage.DeepSnow.depth(stage, center + Vector3(x, 0, z)) == 0.0
		check(clear, "NPC camp furniture footprint starts cleared")
	stage.free()
	print("SNOWBANKS RESULT: ", failures, " failures")
	quit(1 if failures else 0)
