extends "res://tests/harness.gd"
# The cell index of the winding village route must give exactly what the full
# search gives: the same station and plan distance, including at hairpins,
# perpendicular streets and far from the road where it falls back.
const Stage = preload("res://scripts/stage.gd")

func _initialize() -> void:
	call_deferred("run")

# Every segment, no index: the reference answer.
func brute(stage, pos: Vector3) -> Dictionary:
	var p = Vector2(pos.x, pos.z)
	var best = INF
	var station = 0.0
	var index = stage.route_index
	for i in range(index.starts.size()):
		var a = index.starts[i]
		var segment = index.deltas[i]
		var ratio = clampf((p - a).dot(segment) * index.inverse_lengths[i], 0.0, 1.0)
		var distance = p.distance_squared_to(a + segment * ratio)
		var candidate = (i + ratio) * index.step
		if distance < best or (distance == best and candidate < station):
			best = distance
			station = candidate
	return {"s": station, "distance": sqrt(best)}

func run() -> void:
	var stage = Stage.new(2)
	root.add_child(stage)
	check(stage.winding and not stage.route_index.cells.is_empty(), "village route is indexed in cells")
	var rng = RandomNumberGenerator.new()
	rng.seed = 20261010
	var mismatches = 0
	var near = 0
	for i in range(3000):
		var s = rng.randf_range(0.0, stage.LENGTH)
		var lateral = rng.randf_range(-3.0, 3.0) if i % 3 == 0 else rng.randf_range(-40.0, 40.0)
		var pos = stage.at(s) + stage.side(s) * lateral + Vector3(rng.randf_range(-2, 2), 0, rng.randf_range(-2, 2))
		var fast = stage.route_nearest(pos)
		var full = brute(stage, pos)
		if fast.distance < stage.RouteIndex.ROUTE_CELL:
			near += 1
		if fast.s != full.s or fast.distance != full.distance:
			mismatches += 1
	check(mismatches == 0, "indexed nearest station equals the full search (%d mismatches)" % mismatches)
	check(near > 800, "most samples were answered from the cells (%d)" % near)
	stage.free()
	print("ROUTE INDEX RESULT: %d failures" % failures)
	finish()
