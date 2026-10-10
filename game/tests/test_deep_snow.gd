extends "res://tests/harness.gd"
const Stage = preload("res://scripts/stage.gd")
const Motion = preload("res://scripts/vehicle_motion.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var stage = Stage.new(1)
	var point = stage.at(180) + stage.side(180) * 12.0
	var fresh = stage.vehicle_ground(point)
	check(stage.DeepSnow.depth(stage, point) > 0.6 and stage.terrain_surface_height(point) - fresh > 0.4, "fresh forest snow has depth and lets tyres sink")
	check(is_equal_approx(stage.vehicle_ground(stage.at(140)), stage.ground(stage.at(140))), "ploughed road retains normal tyre contact")
	check(stage.DeepSnow.depth(stage, stage.clearings[0]) == 0, "parking remains cleared")
	var actor = Node3D.new()
	actor.position = point
	var motion = Motion.new()
	motion.velocity = Vector3(0, 0, -5)
	motion.suspension(actor, stage, 1.0 / 120, 0)
	check(actor.position.y < stage.terrain_surface_height(point) - 0.3, "car body actually sinks below visible snow")
	check(motion.velocity.length() < 5, "fresh snow resists vehicle motion")
	var grip = stage.grip(point)
	for tick in range(120 * 8):
		motion.suspension(actor, stage, 1.0 / 120, 0)
	check(stage.snow.packed(point) > 0.7, "vehicle weight compacts snow under the wheels")
	check(stage.vehicle_ground(point) > fresh + 0.12 and stage.grip(point) > grip + 0.1, "packed track gives firmer support and better traction")
	var fresh_drift = stage.at(400) + stage.side(400) * 12.0
	check(stage.snow_sink(point) < stage.snow_sink(fresh_drift) * 0.6, "packed tyre track carries the walker better than fresh snow")
	var guest = Stage.new(1)
	guest.snow.authoritative = false
	guest.snow.apply_snapshot(stage.snow.snapshot())
	check(absf(guest.vehicle_ground(point) - stage.vehicle_ground(point)) < 0.003, "shared snapshot reproduces tyre support")
	var before = guest.snow.snapshot()
	guest.snow.stamp(guest, point, 1)
	check(guest.snow.snapshot() == before, "guest prediction cannot double stamp snow")
	guest.snow.apply_snapshot([])
	check(guest.snow.cells.is_empty(), "snapshot reconciles removed tracks")
	# Inspect one actual terrain tile, without generating the entire mountain map.
	var surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var origin = Vector3(floorf(point.x / 2) * 2, 0, floorf(point.z / 2) * 2)
	var vertices = [origin, origin + Vector3(2, 0, 0), origin + Vector3(0, 0, 2), origin + Vector3(2, 0, 0), origin + Vector3(2, 0, 2), origin + Vector3(0, 0, 2)]
	for vertex in vertices:
		vertex.y = stage.terrain_vertex_height(vertex.x, vertex.z)
		surface.set_color(Color.WHITE)
		surface.add_vertex(vertex)
	surface.generate_normals()
	var node = MeshInstance3D.new()
	node.mesh = surface.commit()
	var tile = Vector2i(floori(point.x / 64), floori(point.z / 64))
	stage.snow.register_chunk(stage, tile, node)
	var base: PackedVector3Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	stage.snow.dirty[tile] = true
	stage.snow.update(0.5)
	var changed: PackedVector3Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var depressed = false
	for i in range(base.size()): depressed = depressed or changed[i].y < base[i].y - 0.05
	check(depressed, "terrain mesh visibly depresses in the packed track")
	stage.snow.dirty[tile] = true
	stage.snow.update(0.5)
	check(node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == changed, "mesh refresh does not accumulate deformation")
	for i in range(1000): stage.snow.stamp(stage, Vector3(60 + i * 3, 0, -140), 0.2)
	check(stage.snow.cells.size() <= stage.snow.MAX_CELLS and JSON.stringify(stage.snow.snapshot()).length() < 18000, "track state and multiplayer payload remain bounded")
	motion.grounded = false
	actor.position = point + Vector3.UP * 20
	var packed_before = stage.snow.packed(point)
	motion.suspension(actor, stage, 1.0 / 120, 0)
	check(stage.snow.packed(point) == packed_before, "airborne vehicle cannot compact snow")
	# Walkers break through loose snow; packed tracks and the road hold them up.
	var drift = stage.at(400) + stage.side(400) * 12.0
	check(stage.snow_sink(drift) > 0.45 and stage.walking_ground(drift) < stage.terrain_surface_height(drift) - 0.3, "walker sinks thigh-deep into an untouched drift")
	check(stage.snow_sink(stage.at(400)) == 0.0, "walker stays on top of the ploughed road")
	# Flat glades beside straights keep deep snow and no trees.
	check(stage.snow_glades.size() >= 5, "winter stage has several roadside glades")
	for glade in stage.snow_glades:
		var lowest = INF
		var highest = -INF
		for a in range(12):
			for r in [0.0, 2.5, 5.0]:
				var h = stage.base_ground(glade + Vector3(cos(a * 0.52), 0, sin(a * 0.52)) * r)
				lowest = minf(lowest, h)
				highest = maxf(highest, h)
		var s = stage.road_s(glade)
		var near_road = absf(glade.y - stage.ground(stage.at(s))) < 2.5
		var clear = true
		for tree in stage.trees: clear = clear and Vector2(tree.x - glade.x, tree.z - glade.z).length() > stage.GLADE_FLAT
		check(highest - lowest < 0.02 and near_road and stage.DeepSnow.depth(stage, glade) > 0.6 and stage.road_distance(glade) > 9.0 and clear, "glade at %.0f is level, near the road, snowy and tree-free" % s)
	actor.free()
	node.free()
	stage.free()
	guest.free()
	print("DEEP SNOW RESULT: ", failures, " failures")
	finish()
