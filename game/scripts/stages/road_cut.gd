extends RefCounted
# The land is drawn below ground() under the road so its triangles stay beneath
# the road ribbon. It used to be cut everywhere, and everything that stands on
# ground() (people, camps, rocks, posts, props) hung a quarter of a metre above
# the drawn land. Past HOLD beside the road a vertex is cut only as far as it
# rises above the road edge (a bank or a wall): a triangle reaching from it
# over the edge then stays under the ribbon. A vertex further than a cell
# diagonal from the edge is in no triangle that reaches the road.
const DEPTH = 0.25
const HOLD = 1.0
const REACH = 7.0
const SLACK = 0.02

# How far the terrain vertex at p is drawn below the land.
static func depth(stage, p: Vector3) -> float:
	# road_distance() overstates the gap in bends of a straight-indexed route.
	var nearest: Dictionary = stage.route_nearest(p, REACH + 20.0)
	if nearest.distance >= REACH + 20.0: return 0.0
	var s: float = nearest.s
	var past_edge = float(nearest.distance) - stage.road_width(s) * 0.5
	if past_edge <= HOLD: return DEPTH
	if past_edge >= REACH: return 0.0
	# A triangle reaches the road from its corner across one cell diagonal.
	var reach = 0.0
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		reach = maxf(reach, stage.terrain_tile_step(floorf((p.x + corner.x * 0.01) / 4.0) * 4.0, floorf((p.z + corner.y * 0.01) / 4.0) * 4.0))
	reach *= 1.45
	if past_edge >= reach + 1.0: return 0.0
	var edge: float = stage.ground(stage.at(s) + stage.side(s) * signf((p - stage.at(s)).dot(stage.side(s))) * stage.road_width(s) * 0.5)
	var rise = clampf(stage.biome.base_ground(p) - edge + SLACK, 0.0, DEPTH)
	return rise * (1.0 - smoothstep(reach, reach + 1.0, past_edge))

# How far the drawn land at pos lies below ground() by the cut alone,
# interpolated like Stage.terrain_surface_height(). Physics tiles for props
# use it: a prop knocked to the verge settles on the land drawn there. Corners
# are memoised per caller (one tile shares most of them).
static func under(stage, pos: Vector3, memo: Dictionary) -> float:
	var cell_x = floorf(pos.x / 4.0) * 4.0
	var cell_z = floorf(pos.z / 4.0) * 4.0
	var cell = Vector3(cell_x, 1, cell_z)
	if not memo.has(cell):
		memo[cell] = stage.terrain_tile_step(cell_x, cell_z)
	var step: float = memo[cell]
	var x = cell_x + floorf((pos.x - cell_x) / step) * step
	var z = cell_z + floorf((pos.z - cell_z) / step) * step
	var u = clampf((pos.x - x) / step, 0.0, 1.0)
	var v = clampf((pos.z - z) / step, 0.0, 1.0)
	var cuts = []
	for corner in [Vector2(x, z), Vector2(x + step, z), Vector2(x, z + step), Vector2(x + step, z + step)]:
		if not memo.has(corner):
			memo[corner] = depth(stage, Vector3(corner.x, 0, corner.y))
		cuts.append(memo[corner])
	var cut: float = cuts[0] + (cuts[1] - cuts[0]) * u + (cuts[2] - cuts[0]) * v if u + v <= 1.0 else cuts[3] + (cuts[2] - cuts[3]) * (1.0 - u) + (cuts[1] - cuts[3]) * (1.0 - v)
	# The road ribbon covers the cut land: things on the road rest on ground().
	return 0.0 if cut <= 0.0 or on_road(stage, pos) else cut

static func on_road(stage, pos: Vector3) -> bool:
	var nearest: Dictionary = stage.route_nearest(pos, 30.0)
	return float(nearest.distance) <= stage.road_width(float(nearest.s)) * 0.5

# Where static scenery is drawn standing. A rock or post set on ground() beside
# the road hung in the air over the cut land. The road ribbon, snowbanks and
# dug floors are drawn where ground() puts them.
static func ground(stage, pos: Vector3) -> float:
	var height: float = stage.ground(pos)
	if absf(height - stage.base_ground(pos)) > 0.001 or on_road(stage, pos):
		return height
	return minf(height, stage.terrain_surface_height(pos))
