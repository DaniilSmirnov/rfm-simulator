extends SceneTree
const Stage = preload('res://scripts/stage.gd')
var failures = 0
func check(ok: bool, title: String):
	print(('PASS: ' if ok else 'FAIL: ') + title)
	if not ok: failures += 1
func brute(stage, p: Vector3) -> Dictionary:
	var best = INF
	var station = 0.0
	var point = stage.flat(p)
	for i in range(stage.road_segment_starts.size()):
		var a = stage.road_segment_starts[i]
		var segment = stage.road_segment_deltas[i]
		var ratio = clampf((point - a).dot(segment) / maxf(segment.length_squared(), 0.000001), 0, 1)
		var distance = point.distance_squared_to(a + segment * ratio)
		if distance < best:
			best = distance
			station = (i + ratio) * stage.route_segment_step
	return {'s': station, 'distance': sqrt(best)}
func _initialize():
	call_deferred('run')
func run():
	var stage = Stage.new(2)
	root.add_child(stage)
	var random = RandomNumberGenerator.new()
	random.seed = 20261008
	var exact = true
	for i in range(2000):
		var p = Vector3(random.randf_range(-450, 450), 0, random.randf_range(-1100, 200))
		var expected = brute(stage, p)
		var actual = stage.route_nearest(p)
		exact = exact and absf(expected.s - actual.s) < 0.001 and absf(expected.distance - actual.distance) < 0.001
	check(exact, 'bounded route search matches exhaustive projection, including distant points')
	var stations = true
	for s in range(0, 840, 3):
		stations = stations and absf(stage.road_s(stage.at(s)) - s) < 0.6
	check(stations, 'station of every route point is recovered through the square corner and the hairpin')
	# No cliffs where the nearest road switches between two legs of a bend.
	var smooth = true
	var worst = 0.0
	for z in range(-700, 1, 4):
		for x in range(-160, 161, 4):
			var p = Vector3(x, 0, z)
			var q = p + Vector3(0, 0, 0.5)
			var r = p + Vector3(0.5, 0, 0)
			if stage.road_distance(p) < 6 or stage.road_distance(q) < 6 or stage.road_distance(r) < 6:
				continue
			var difference = maxf(absf(stage.ground(p) - stage.ground(q)), absf(stage.ground(p) - stage.ground(r)))
			worst = maxf(worst, difference)
			smooth = smooth and difference < 0.2
	check(smooth, 'terrain has no nearest-road cliffs (max half-metre rise %.3f m)' % worst)
	var contact = true
	var largest_gap = 0.0
	stage._set_terrain_cache(true)
	for s in range(0, 840, 2):
		for lateral in [-1.4, 0.0, 1.4]:
			var road = stage.road_surface_vertex(s, lateral)
			var gap = road.y - stage.terrain_surface_height(road)
			largest_gap = maxf(largest_gap, absf(gap))
			contact = contact and gap > 0 and gap < 0.50
	check(contact, 'road follows refined terrain (largest gap %.3f m)' % largest_gap)
	var kerbs = true
	for s in [300.0, 340.0, 490.0, 510.0]:
		var half = stage.road_width(s) * 0.5
		var road = stage.at(s)
		var pavement = road + stage.side(s) * (half + 0.7)
		kerbs = kerbs and absf(stage.ground(pavement) - road.y - stage.village.Layout.KERB) < 0.01
	check(kerbs, 'village pavements stand one kerb above the street')
	stage._build_terrain()
	stage._set_terrain_cache(false)
	var tiles = stage.find_children('TerrainTile_*', 'MeshInstance3D', false, false)
	var triangles = 0
	var local_bounds = true
	for tile in tiles:
		triangles += tile.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() / 3
		local_bounds = local_bounds and tile.mesh.get_aabb().size.x <= 64.01 and tile.mesh.get_aabb().size.z <= 64.01
	check(tiles.size() > 80 and local_bounds and triangles > 51204 and triangles < 140000, 'refined roadside terrain stays within geometry budget and local culling bounds (%d triangles)' % triangles)
	stage.free()
	print('VILLAGE TERRAIN/PERFORMANCE RESULT: %d failures' % failures)
	quit(1 if failures else 0)
