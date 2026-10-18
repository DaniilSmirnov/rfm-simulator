extends "res://tests/harness.gd"
# Wheel ruts and puddles are part of the road: dug into the height that tyres and
# feet read, cut into the road mesh and filled with a thin disc of water, not
# boxes and cylinders lying on the surface.
const Stage = preload("res://scripts/stages/stage.gd")
func _initialize() -> void:
	call_deferred("run")

func plain(stage, s: float, lat: float) -> float:
	return stage.biome.base_ground(Vector3(stage.at(s).x + lat, 0, -s))

func dug(stage, s: float, lat: float) -> float:
	var pos = Vector3(stage.at(s).x + lat, 0, -s)
	return stage.biome.base_ground(pos) - stage.ground(pos)

func run() -> void:
	for variant in [1, 2]:
		var other = Stage.new(variant)
		root.add_child(other)
		check(not other.relief.enabled(), "stage %d has no ruts to dig" % variant)
		other.free()
	for variant in [0, 4]:
		var stage = Stage.new(variant)
		root.add_child(stage)
		var relief = stage.relief
		check(relief.enabled(), "stage %d digs its ruts and puddles" % variant)
		# --- the tracks: two grooves that come and go, none between them
		var deepest = 0.0
		var deepest_s = 0.0
		var rutted = 0
		var stations = 0
		var between = 0.0
		for i in range(80, 1500):
			var s = i * 0.5
			stations += 1
			var d = maxf(dug(stage, s, 1.0), dug(stage, s, -1.0))
			if d > 0.02:
				rutted += 1
			var puddle_near = absf(s - float(relief.site(s).get("s", -1000.0))) < 5.0
			if d > deepest and not puddle_near:
				deepest = d
				deepest_s = s
			if not puddle_near:
				between = maxf(between, absf(dug(stage, s, 0.0)))
		check(deepest > 0.05 and deepest < 0.13, "the deepest wheel track is %.3f m below the road" % deepest)
		check(rutted > stations * 0.12 and rutted < stations * 0.7, "tracks are broken stretches, %d of %d stations" % [rutted, stations])
		check(between < 0.01, "the crown between the tracks is left alone (%.4f)" % between)
		check(dug(stage, deepest_s, 1.0) > dug(stage, deepest_s, 1.45) + 0.02 and dug(stage, deepest_s, 1.0) > dug(stage, deepest_s, 0.5) + 0.02, "a track is a groove %.2f m across (%.3f beside it)" % [0.6, dug(stage, deepest_s, 1.45)])
		var wheel = Vector3(stage.at(deepest_s).x + 1.0, 0, -deepest_s)
		wheel.y = stage.ground(wheel)
		check(is_equal_approx(stage.vehicle_ground(wheel), wheel.y), "tyres rest at the bottom of the groove")
		var smooth = true
		for i in range(40, 1600):
			var s = i * 0.25
			var near = stage.relief.site(s)
			if not near.is_empty() and absf(s - near.s) < 6.0:
				continue
			smooth = smooth and absf(dug(stage, s, 1.0) - dug(stage, s + 0.25, 1.0)) < 0.03
		check(smooth, "the track runs without steps along the road")
		# --- a puddle: a level basin with water in it
		var puddle = relief.site(28.0)
		check(not puddle.is_empty() and absf(float(puddle.s) - 28.0) <= 8.0, "the first puddle lies near station 28 (%s)" % str(puddle.get("s", -1)))
		var centre = Vector3(stage.at(puddle.s).x + puddle.lat, 0, -puddle.s)
		var bottom = stage.ground(centre)
		check(puddle.level - bottom > 0.09 and puddle.level - bottom < 0.21, "the basin is %.3f m deep" % (puddle.level - bottom))
		var rim = Vector3(centre.x + relief.PUDDLE_RX * 1.2, 0, centre.z)
		check(stage.ground(rim) > puddle.level - 0.045 and stage.ground(rim) < puddle.level + 0.06, "its rim lies level with the water")
		var far = Vector3(centre.x, 0, centre.z - relief.PUDDLE_RZ * 3.0)
		check(absf(stage.ground(far) - stage.biome.base_ground(far)) < 0.1, "the basin does not spread over the road")
		# --- the mesh carries the relief
		stage._build_road()
		var vertices = PackedVector3Array()
		var indices = PackedInt32Array()
		for piece in stage.road_meshes():
			var arrays = piece.mesh.surface_get_arrays(0)
			vertices.append_array(arrays[Mesh.ARRAY_VERTEX])
			indices.append_array(arrays[Mesh.ARRAY_INDEX])
		check(indices.size() > 840 * 6 * 2 * 20 and indices.size() < 350000, "the road is cut finely across the tracks (%d indices)" % indices.size())
		var station = roundf(deepest_s)
		var wanted = stage.road_surface_vertex(station, 1.0)
		var crown = stage.road_surface_vertex(station, 0.0)
		var found = false
		for vertex in vertices:
			if vertex.distance_to(wanted) < 0.02:
				found = true
				break
		check(found and wanted.y < crown.y - 0.0 and is_equal_approx(wanted.y, stage.ground(Vector3(wanted.x, 0, wanted.z)) + 0.04), "a mesh vertex sits in the groove at station %d" % int(station))
		var water = stage.get_node_or_null("RoadPuddle_0")
		check(water != null and absf(water.position.y - (puddle.level - relief.WATER_DROP)) < 0.001, "the first puddle holds a disc of water at its level")
		check(water != null and water.position.y > bottom + 0.05 and water.position.y < stage.ground(rim) + 0.001, "the water is above the basin floor and under its rim")
		check(stage.get_children().filter(func(node): return node is MeshInstance3D and node.mesh is BoxMesh).is_empty(), "no loose boxes lie on the road")
		if variant == 4:
			var ff = stage.finnish_forest
			var fade = true
			for s in range(int(ff.FORD_STATION) - 30, int(ff.FORD_STATION) + 31, 2):
				fade = fade and absf(dug(stage, float(s), 1.0)) < 0.001
			check(fade, "no ruts are dug in the ford itself")
			check(stage.biome.rut_strength(ff.FORD_STATION + 45.0) > 0.0 and stage.biome.rut_strength(ff.FORD_STATION + 45.0) < 1.0, "ruts fade in beside the ford")
		var again = Stage.new(variant)
		root.add_child(again)
		check(again.ground(wheel) == stage.ground(wheel) and again.relief.site(28.0).s == puddle.s, "every member of a room digs the same road")
		again.free()
		stage.free()
	print("ROAD RELIEF RESULT: %d failures" % failures)
	finish()
