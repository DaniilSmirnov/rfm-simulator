extends SceneTree

var failures := 0
var checks := 0

func check(ok: bool, description: String) -> void:
	checks += 1
	if ok:
		print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var stage = load("res://scripts/stage.gd").new(0)
	root.add_child(stage)
	var mixed_boundaries := 0
	var samples := 0
	# Inspect the exact same 4 m tiles and 2 m refinement rule used by the mesh.
	for z in range(-920, 81, 4):
		for x in range(-204, 204, 4):
			if stage.terrain_tile_step(x, z) != 2.0:
				continue
			if stage.terrain_tile_step(x, z - 4) == 4.0 or stage.terrain_tile_step(x, z + 4) == 4.0:
				var edge_z: float = z if stage.terrain_tile_step(x, z - 4) == 4.0 else z + 4.0
				var expected = (stage.ground(Vector3(x, 0, edge_z)) + stage.ground(Vector3(x + 4, 0, edge_z))) * 0.5 - 0.25
				check(absf(stage.terrain_vertex_height(x + 2, edge_z) - expected) < 0.0001, "fine/coarse X-edge midpoint matches coarse triangle")
				mixed_boundaries += 1
			if stage.terrain_tile_step(x - 4, z) == 4.0 or stage.terrain_tile_step(x + 4, z) == 4.0:
				var edge_x: float = x if stage.terrain_tile_step(x - 4, z) == 4.0 else x + 4.0
				var expected = (stage.ground(Vector3(edge_x, 0, z)) + stage.ground(Vector3(edge_x, 0, z + 4))) * 0.5 - 0.25
				check(absf(stage.terrain_vertex_height(edge_x, z + 2) - expected) < 0.0001, "fine/coarse Z-edge midpoint matches coarse triangle")
				mixed_boundaries += 1
			if samples < 25:
				var midpoint = Vector3(x + 2, 0, z + 2)
				check(is_equal_approx(stage.terrain_surface_height(midpoint), stage.terrain_vertex_height(midpoint.x, midpoint.z)), "tree surface height uses rendered terrain vertex")
				samples += 1
	check(mixed_boundaries > 0, "test covers actual fine/coarse boundaries")
	stage.free()
	print("TERRAIN SEAMS RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
