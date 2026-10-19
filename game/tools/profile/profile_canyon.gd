extends SceneTree
# Structural culling and CPU probe; headless counts are potential submitted
# triangles, not GPU timings. Run with --headless --path game --script
# res://tools/profile/profile_canyon.gd. Also works with a real renderer.
const Stage = preload("res://scripts/stages/stage.gd")
const SAMPLES = 200

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1280, 720)
	var stage = Stage.new(3)
	root.add_child(stage)
	stage.build()
	var terrain = stage.find_children("TerrainTile_*", "MeshInstance3D", false, false)
	var towers = stage.get_node("CanyonValleyTowers")
	var rocks: Array = [towers] if towers is MeshInstance3D else towers.get_children()
	var camera = Camera3D.new()
	root.add_child(camera)
	camera.far = 1100.0
	camera.fov = 70.0
	print("CANYON_GEOMETRY terrain=", _triangles(terrain), " towers=", _triangles(rocks), " terrain_chunks=", terrain.size(), " tower_chunks=", rocks.size())
	for station in [80.0, 500.0, 1000.0, 1650.0, 1950.0]:
		var p = stage.at(station)
		camera.position = p - stage.direction(station) * 6.0 + Vector3.UP * 3.0
		camera.look_at(p + stage.direction(station) * 30.0 + Vector3.UP)
		var planes = camera.get_frustum()
		print("CANYON_CULL station=", station, " terrain=", _triangles(terrain, planes), " towers=", _triangles(rocks, planes))
		for lateral in [0.0, 16.0]:
			var points: Array[Vector3] = []
			for i in range(SAMPLES):
				var s = station + float(i) * 0.01
				points.append(stage.at(s) + stage.side(s) * lateral)
			# Warm both paths with the same exact queries.
			for point in points:
				stage.vehicle_ground(point)
			var timings: Array = []
			for point in points:
				var started = Time.get_ticks_usec()
				stage.vehicle_ground(point)
				timings.append(Time.get_ticks_usec() - started)
			var total = 0
			for timing in timings:
				total += timing
			timings.sort()
			print("CANYON_CPU station=", station, " lateral=", lateral, " vehicle_ground_avg_us=", float(total) / SAMPLES, " p95_us=", timings[int(SAMPLES * 0.95)])
	# The local scenery helpers retain their biome; release those references
	# in this short-lived standalone probe before freeing its world.
	stage.canyon.scenery.biome = null
	stage.canyon.canyon_life.biome = null
	stage.free()
	camera.free()
	quit()

func _triangles(nodes: Array, planes: Array = []) -> int:
	var count = 0
	for node in nodes:
		if not node is MeshInstance3D or node.mesh == null:
			continue
		var box: AABB = node.global_transform * node.get_aabb()
		var inside = true
		for plane in planes:
			if plane.distance_to(box.get_support(-plane.normal)) > 0:
				inside = false
				break
		if not inside:
			continue
		for surface in range(node.mesh.get_surface_count()):
			var arrays = node.mesh.surface_get_arrays(surface)
			var indices = arrays[Mesh.ARRAY_INDEX]
			count += (indices.size() if indices != null and not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()) / 3
	return count
