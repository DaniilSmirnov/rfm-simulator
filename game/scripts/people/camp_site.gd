extends RefCounted
# Where an NPC camp stands and how its gear meets the ground. A camp set on a
# hillside, half its table legs in the slope and half in the air, slid and
# settled for seconds once play started, and still showed legs in the land.
const RoadCut = preload("res://scripts/stages/road_cut.gd")
const Ground = preload("res://scripts/camp/camp_ground.gd")
# Rise per metre across a piece's footprint that the camp settles for at once.
const LEVEL = 0.12
# Gap between the collision floor and the drawn land that counts as much.
const MISMATCH = 0.04
# A leg or a tyre left this far off uneven ground counts as much.
const WARP = 0.05
# Gear, people and the parked car stay this far off the road's centre line.
const ROAD_CLEARANCE = 5.4
# Shifts, along the road and away from it, tried in turn from the stage's spot.
const ALONG = [0.0, 4.0, -4.0, 8.0, -8.0, 12.0, -12.0]
const ASIDE = [0.0, 3.0, 6.0]
# Camps keep this far apart, table to table.
const APART = 14.0

# Where each piece of the camp stands, from the table at `center`.
static func layout(stage, center: Vector3, s: float, count: int) -> Dictionary:
	var forward: Vector3 = stage.direction(s)
	var yaw = atan2(-forward.x, -forward.z)
	var right: Vector3 = Basis(Vector3.UP, yaw).x
	# People stand and sit at the end of the table that faces the road. From
	# the far end they walked round it to go and watch, and shouldered it
	# along a little more every time.
	var roadward = 1.0 if (stage.at(s) - center).dot(right) >= 0.0 else -1.0
	var people: Array[Vector3] = []
	var chairs: Array[Vector3] = []
	for j in range(count):
		var person = center + right * 1.5 * roadward - forward * (0.4 + j * 1.6)
		people.append(person)
		chairs.append(person + forward * 0.85)
	# The car 0.8 m clear of the table: at 0.4 m a car settling on a hillside
	# shouldered the table over.
	return {"forward": forward, "yaw": yaw, "table": center, "grill": center - forward * 2.4, "car": center + forward * 3.6, "people": people, "chairs": chairs}

# The stage's spot when it is level and free, else the nearest one that is;
# failing both, the least sloping of the candidates. {"center", "score"}.
static func choose(stage, center: Vector3, s: float, count: int, ignored: Array = [], taken: Array = []) -> Dictionary:
	var forward: Vector3 = stage.direction(s)
	var away: Vector3 = center - stage.at(s)
	away.y = 0
	away = away.normalized() if away.length_squared() > 0.01 else stage.side(s)
	# Stay off the stage's spectator spots, as far as the stage's own choice
	# did: a camp sliding onto the village square blocked the view from it.
	var keep: Array = []
	for clearing in stage.clearings:
		keep.append([clearing, minf(3.0, _flat(center, clearing))])
	var best = {"center": center, "score": INF}
	var heights = {}
	var memo = {}
	for aside in ASIDE:
		for along in ALONG:
			var candidate: Vector3 = center + forward * along + away * aside
			# Another camp's crowd would walk through this one's table.
			if taken.any(func(other): return _flat(other, candidate) < APART): continue
			var spots = layout(stage, candidate, s, count)
			if keep.any(func(k): return [spots.table, spots.grill, spots.car].any(func(p): return _flat(p, k[0]) < k[1])): continue
			var score = roughness(stage, spots, ignored, best.score, heights, memo)
			if score <= LEVEL:
				return {"center": candidate, "score": score}
			if score < best.score:
				best = {"center": candidate, "score": score}
	return best

# Steepest rise per metre under any piece of gear; INF where the camp would
# stand on the road, in water, or in a tree, a rock or another solid. Stops
# counting once past `bound`: a worse candidate needs no exact score.
static func roughness(stage, spots: Dictionary, ignored: Array = [], bound: float = INF, heights: Dictionary = {}, memo: Dictionary = {}) -> float:
	var pieces: Array = [[spots.table, 1.0], [spots.grill, 0.6], [spots.car, 2.2]]
	for chair in spots.chairs: pieces.append([chair, 0.4])
	for person in spots.people: pieces.append([person, 0.3])
	var result = 0.0
	# The shape of the land first: it is cheap and rules out most candidates.
	for piece in pieces:
		var spot: Vector3 = piece[0]
		var reach: float = piece[1]
		var middle: float = _land(stage, spot, heights)
		var around: Array[float] = []
		for offset in [Vector3(reach, 0, 0), Vector3(-reach, 0, 0), Vector3(0, 0, reach), Vector3(0, 0, -reach)]:
			around.append(_land(stage, spot + offset, heights))
			result = maxf(result, absf(around.back() - middle) / reach)
		# A hump, a hollow or a twist under it leaves a leg or a tyre in the air
		# however the piece is tilted.
		var warp = maxf(absf(around[0] + around[1] - around[2] - around[3]), absf(around[0] + around[1] + around[2] + around[3] - 4.0 * middle) * 0.5)
		result = maxf(result, warp * 0.5 / WARP * LEVEL)
		if result > bound: return result
	for piece in pieces:
		var spot: Vector3 = piece[0]
		var reach: float = piece[1]
		if stage.road_distance(spot) < ROAD_CLEARANCE + (1.0 if reach > 2.0 else 0.0):
			return INF
		if stage.biome.has_method("water_depth") and stage.biome.water_depth(spot) > -0.3:
			return INF
		var floor_spot = Vector3(spot.x, height(stage, spot) if reach >= 0.6 else _land(stage, spot, heights), spot.z)
		if stage.obstacle_hit(floor_spot, floor_spot, reach) >= 0 or not stage.rock_hit(floor_spot, floor_spot, reach, false).is_empty():
			return INF
		if not stage.solids.hit(floor_spot, floor_spot, reach, false, Vector3(0, 0.35, 0), null, ignored).is_empty():
			return INF
		# Gear rests on the collision floor. Where that is not the drawn land
		# (it lies under it beside the road cut, above the coarse terrain mesh
		# on a curved hillside) gear would sink in or hover. Chairs too: one in
		# Mineshaft hung 9 cm over the drawn land. People stand on the land.
		if reach < 0.4: continue
		result = maxf(result, absf(floor_height(stage, spot, memo) - floor_spot.y) / MISMATCH * LEVEL)
		for offset in [Vector3(reach, 0, 0), Vector3(-reach, 0, 0), Vector3(0, 0, reach), Vector3(0, 0, -reach)]:
			if result > bound: return result
			result = maxf(result, absf(floor_height(stage, spot + offset, memo) - height(stage, spot + offset)) / MISMATCH * LEVEL)
		if result > bound: return result
	return result

static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

# ground() on a 0.5 m lattice, shared by the candidates of one search: their
# footprints overlap, and the search took half a second on a mountainside.
static func _land(stage, pos: Vector3, heights: Dictionary) -> float:
	var cell = Vector2i(roundi(pos.x * 2.0), roundi(pos.z * 2.0))
	if not heights.has(cell):
		heights[cell] = stage.ground(Vector3(cell.x * 0.5, pos.y, cell.y * 0.5))
	return heights[cell]

# The drawn ground: the land as the terrain mesh shows it.
static func height(stage, pos: Vector3) -> float:
	return RoadCut.ground(stage, pos)

# The floor gear rests on once its physics wakes (prop_ground.gd).
static func floor_height(stage, pos: Vector3, memo: Dictionary) -> float:
	var cut: bool = stage.has_method("route_nearest") and not stage.has_snow
	return stage.ground(pos) - (RoadCut.under(stage, pos, memo) if cut else 0.0)

# Stand gear on the plane that best fits the floor under its feet, as its legs
# or tyres would, every foot on the floor and none in it. Set where physics
# leaves it, it does not jump or slide when play starts.
static func put(stage, node: Node3D, spot: Vector3, yaw: float) -> void:
	var memo = {}
	var sampler = func(p): return floor_height(stage, p, memo)
	var level = Basis(Vector3.UP, yaw)
	_feet(node)
	var samples = {}
	for foot in node.get_meta("camp_feet"):
		var offset: Vector3 = level * foot
		var cell = Vector2i(roundi(offset.x * 20.0), roundi(offset.z * 20.0))
		if not samples.has(cell):
			samples[cell] = Vector3(offset.x, sampler.call(spot + offset), offset.z)
	var slope = _slope(samples.values())
	var up = Vector3(-slope.x, 1.0, -slope.y).normalized()
	var right: Vector3 = up.cross(level.z).normalized()
	node.basis = Basis(right, up, right.cross(up).normalized())
	node.position = Vector3(spot.x, Ground.height(node, spot, node.basis, sampler), spot.z)

# The lowest vertices, one per 5 cm: a tyre's tread is hundreds of them, and
# each is a ground query when the piece is set down. Only meshes that reach
# the bottom are read: a laid table holds dozens of dishes.
static func _feet(node: Node3D) -> void:
	if node.has_meta("camp_feet"): return
	var meshes: Array = []
	_meshes(node, Transform3D.IDENTITY, meshes)
	var bottom = INF
	for item in meshes: bottom = minf(bottom, (item[1] * item[0].mesh.get_aabb()).position.y)
	var cells = {}
	for item in meshes:
		var pose: Transform3D = item[1]
		if (pose * item[0].mesh.get_aabb()).position.y > bottom + 0.03: continue
		for vertex in item[0].mesh.get_faces():
			var point: Vector3 = pose * vertex
			if point.y > bottom + 0.03: continue
			var cell = Vector2i(roundi(point.x * 20.0), roundi(point.z * 20.0))
			if not cells.has(cell) or point.y < cells[cell].y: cells[cell] = point
	node.set_meta("camp_feet", PackedVector3Array(cells.values()))

static func _meshes(node: Node3D, pose: Transform3D, found: Array) -> void:
	for child in node.get_children():
		if not child is Node3D or child is CollisionObject3D or not child.visible: continue
		var transform: Transform3D = pose * child.transform
		if child is MeshInstance3D and child.mesh != null: found.append([child, transform])
		_meshes(child, transform, found)

# How far the lowest and the highest foot of a piece, as it stands now, are
# above the drawn ground (negative: sunk in). Diagnostics and tests.
static func clearance(stage, node: Node3D) -> Vector2:
	_feet(node)
	var result = Vector2(INF, -INF)
	for foot in node.get_meta("camp_feet"):
		var point: Vector3 = node.global_transform * foot
		var gap: float = point.y - height(stage, point)
		result = Vector2(minf(result.x, gap), maxf(result.y, gap))
	return result

# Least-squares rise along x and z of the plane through the points; level
# when they all lie in a line (a single foot, a row of feet).
static func _slope(points: Array) -> Vector2:
	var n = float(points.size())
	if n < 3: return Vector2.ZERO
	var mean = Vector3.ZERO
	for point in points: mean += point / n
	var xx = 0.0
	var xz = 0.0
	var zz = 0.0
	var xh = 0.0
	var zh = 0.0
	for point in points:
		var d: Vector3 = point - mean
		xx += d.x * d.x
		xz += d.x * d.z
		zz += d.z * d.z
		xh += d.x * d.y
		zh += d.z * d.y
	var det = xx * zz - xz * xz
	if det < 0.0001: return Vector2.ZERO
	return Vector2((xh * zz - zh * xz) / det, (zh * xx - xh * xz) / det)

# The baked body of a car stops short of its wheels, and a car colliding with
# it alone sank 0.4 m into the ground until its sills touched. A post under
# each corner where the tyres meet the ground carries it instead.
static func car_shapes(car: Node3D) -> Array[AABB]:
	var body: MeshInstance3D = car.get_node("Baked")
	var shell: AABB = body.transform * body.mesh.get_aabb()
	_feet(car)
	var feet: PackedVector3Array = car.get_meta("camp_feet")
	var bottom = INF
	for point in feet: bottom = minf(bottom, point.y)
	var corners = {}
	for point in feet:
		var corner = Vector2i(1 if point.x > 0.0 else -1, 1 if point.z > 0.0 else -1)
		corners[corner] = AABB(point, Vector3.ZERO) if not corners.has(corner) else corners[corner].expand(point)
	var shapes: Array[AABB] = [shell]
	for tread in corners.values():
		var post = AABB(Vector3(tread.position.x, bottom, tread.position.z), Vector3(maxf(tread.size.x, 0.12), maxf(shell.position.y - bottom + 0.05, 0.05), maxf(tread.size.z, 0.12)))
		shapes.append(post)
	return shapes
