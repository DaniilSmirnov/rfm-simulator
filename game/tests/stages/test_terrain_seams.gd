extends "res://tests/harness.gd"
const Stage = preload("res://scripts/stages/stage.gd")
const StageRegistry = preload("res://scripts/stages/stage_registry.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var stage = load("res://scripts/stages/stage.gd").new(0)
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
				var expected = (stage.terrain_vertex_height(x, edge_z) + stage.terrain_vertex_height(x + 4, edge_z)) * 0.5
				check(absf(stage.terrain_vertex_height(x + 2, edge_z) - expected) < 0.0001, "fine/coarse X-edge midpoint matches coarse triangle")
				mixed_boundaries += 1
			if stage.terrain_tile_step(x - 4, z) == 4.0 or stage.terrain_tile_step(x + 4, z) == 4.0:
				var edge_x: float = x if stage.terrain_tile_step(x - 4, z) == 4.0 else x + 4.0
				var expected = (stage.terrain_vertex_height(edge_x, z) + stage.terrain_vertex_height(edge_x, z + 4)) * 0.5
				check(absf(stage.terrain_vertex_height(edge_x, z + 2) - expected) < 0.0001, "fine/coarse Z-edge midpoint matches coarse triangle")
				mixed_boundaries += 1
			if samples < 25:
				var midpoint = Vector3(x + 2, 0, z + 2)
				check(is_equal_approx(stage.terrain_surface_height(midpoint), stage.terrain_vertex_height(midpoint.x, midpoint.z)), "tree surface height uses rendered terrain vertex")
				samples += 1
	check(mixed_boundaries > 0, "test covers actual fine/coarse boundaries")
	stage.free()
	for index in range(StageRegistry.count()):
		_check_land_contact(index)
	print("TERRAIN SEAMS RESULT: %d checks, %d failures" % [checks, failures])
	finish()

# The drawn land is cut below ground() only around the road, where its
# triangles must stay beneath the road ribbon. Elsewhere people, camps, rocks
# and posts stand on ground(): the land they are drawn on must be there too,
# not a quarter of a metre lower.
func _check_land_contact(index: int) -> void:
	var stage = Stage.new(index)
	root.add_child(stage)
	var over = 0
	var hang = 0.0
	var count = 0
	for station in range(12, int(stage.length) - 12, 3):
		var s = float(station)
		var half: float = stage.road_width(s) * 0.5
		for step in range(21):
			var p: Vector3 = stage.at(s) + stage.side(s) * lerpf(-half, half, step / 20.0)
			# A few crests of the road poke through as they always did; lifting
			# the land beside the road must not add any.
			if stage.terrain_surface_height(p) > stage.ground(p) + 0.02 and _lifted(stage, p): over += 1
		if station % 9 != 0: continue
		for side in [-1.0, 1.0]:
			for offset in [10.0, 16.0, 28.0]:
				var p: Vector3 = stage.at(s) + stage.side(s) * side * (half + offset)
				if float(stage.route_nearest(p).distance) < half + stage.RoadCut.REACH or not stage.biome.world_bounds().has_point(Vector2(p.x, p.z)):
					continue
				hang += stage.base_ground(p) - stage.terrain_surface_height(p)
				count += 1
	check(over == 0, "%s: the drawn land stays under the road ribbon (%d points above)" % [stage.stage_id, over])
	check(count > 50 and absf(hang / count) < 0.05, "%s: things standing on the ground touch the drawn land (mean gap %.3f)" % [stage.stage_id, hang / maxi(1, count)])
	stage.free()

# Whether a corner of the drawn triangles around p is cut less than the road.
func _lifted(stage, p: Vector3) -> bool:
	var cell = Vector2(floorf(p.x / 4.0) * 4.0, floorf(p.z / 4.0) * 4.0)
	var size: float = stage.terrain_tile_step(cell.x, cell.y)
	var x = cell.x + floorf((p.x - cell.x) / size) * size
	var z = cell.y + floorf((p.z - cell.y) / size) * size
	for corner in [Vector3(x, 0, z), Vector3(x + size, 0, z), Vector3(x, 0, z + size), Vector3(x + size, 0, z + size)]:
		if stage.RoadCut.depth(stage, corner) < stage.RoadCut.DEPTH - 0.0001: return true
	return false
