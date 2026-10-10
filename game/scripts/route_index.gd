extends RefCounted
# Nearest station on a winding route (the village), whose stations are not
# simply -z. The route is a polyline of segments every `step` stations.
#
# nearest() is exact: it returns the closest segment point, the lower station
# on a tie. Two indexes keep it fast:
# - a fine grid of ROUTE_CELL cells. Every segment not filed in the 3×3 cells
#   around the query lies outside them, at least ROUTE_CELL away, so a hit
#   closer than that is final. Most queries (cars, people) are near the road.
# - groups of GROUP_SIZE consecutive segments with bounding boxes, for the
#   rest: groups that cannot beat the best distance are skipped.
const GROUP_SIZE = 8
const ROUTE_CELL = 4.0

var step = 1.0
var starts = PackedVector2Array()
var deltas = PackedVector2Array()
var inverse_lengths = PackedFloat64Array()
var group_low = PackedVector2Array()
var group_high = PackedVector2Array()
var cells: Dictionary = {}
var _last_group = 0

func build(samples: PackedVector3Array, sample_step: float) -> void:
	step = sample_step
	starts.clear()
	deltas.clear()
	inverse_lengths.clear()
	group_low.clear()
	group_high.clear()
	cells.clear()
	for i in range(samples.size() - 1):
		var a = Vector2(samples[i].x, samples[i].z)
		var b = Vector2(samples[i + 1].x, samples[i + 1].z)
		starts.append(a)
		deltas.append(b - a)
		inverse_lengths.append(1.0 / maxf((b - a).length_squared(), 0.000001))
		var low = (a.min(b) / ROUTE_CELL).floor()
		var high = (a.max(b) / ROUTE_CELL).floor()
		for cx in range(int(low.x), int(high.x) + 1):
			for cz in range(int(low.y), int(high.y) + 1):
				var cell = Vector2i(cx, cz)
				if not cells.has(cell):
					cells[cell] = PackedInt32Array()
				cells[cell].append(i)
		var group = int(i / GROUP_SIZE)
		if i % GROUP_SIZE == 0:
			group_low.append(a.min(b))
			group_high.append(a.max(b))
		else:
			group_low[group] = group_low[group].min(a).min(b)
			group_high[group] = group_high[group].max(a).max(b)

# {"s": station, "distance": plan distance} of the point p (x, z).
func nearest(p: Vector2) -> Dictionary:
	var best = INF
	var station = 0.0
	var home = Vector2i((p / ROUTE_CELL).floor())
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for i in cells.get(home + Vector2i(dx, dz), PackedInt32Array()):
				var a = starts[i]
				var segment = deltas[i]
				var ratio = clampf((p - a).dot(segment) * inverse_lengths[i], 0.0, 1.0)
				var distance = p.distance_squared_to(a + segment * ratio)
				var candidate = (i + ratio) * step
				if distance < best or (distance == best and candidate < station):
					best = distance
					station = candidate
	if best < ROUTE_CELL * ROUTE_CELL:
		return {"s": station, "distance": sqrt(best)}
	best = INF
	station = 0.0
	# Successive queries are spatially coherent: start from the last winning group.
	var seed = clampi(_last_group, 0, group_low.size() - 1)
	for pass_index in range(group_low.size() + 1):
		var group = seed if pass_index == 0 else pass_index - 1
		if pass_index > 0 and group == seed:
			continue
		if p.distance_squared_to(p.clamp(group_low[group], group_high[group])) > best:
			continue
		for i in range(group * GROUP_SIZE, mini((group + 1) * GROUP_SIZE, starts.size())):
			var a = starts[i]
			var segment = deltas[i]
			var ratio = clampf((p - a).dot(segment) * inverse_lengths[i], 0.0, 1.0)
			var distance = p.distance_squared_to(a + segment * ratio)
			var candidate = (i + ratio) * step
			if distance < best or (distance == best and candidate < station):
				best = distance
				station = candidate
	_last_group = int(station / step) / GROUP_SIZE
	return {"s": station, "distance": sqrt(best)}
