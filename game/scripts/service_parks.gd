extends RefCounted
# The two service parks (парк сервиса) past the ends of the stage road. Each
# is a level gravel paddock reached by a short lane from the end of the road:
# team tents and equipment along its sides, and a bay for every car of the
# convoy and every crew, in the order they start. Pass 1 leaves the park at
# the start (end 0) and parks in the one at the finish (end 1); pass 2 runs
# back the other way.
#
# Park space: x across (right of the way into the park), z from the end of the
# road (0) into the park. The land is levelled to the height of the road end:
# ground(), the drawn terrain and the tyres all meet the same flat surface.
const ServiceParkModel = preload("res://scripts/service_park_model.gd")
const LANE = 12.0
const DEPTH = 34.0
const HALF_WIDTH = 19.0
const LANE_HALF = 4.5
# The levelled surface (gravel, ploughed snow, tyres on ground()) ends this far
# past the paddock (m); the first APRON metres stay exactly level, so terrain
# triangles reaching over the edge cannot tilt the paddock...
const MARGIN = 8.0
const APRON = 4.0
# ...while the land around it eases towards the park level over a distance
# that grows with the height to make up, up to MAX_BLEND: no slope steeper
# than about 1 in SLOPE. The stage road itself is never lifted or cut.
const SLOPE = 1.6
const MAX_BLEND = 40.0
const SLOT_X = 6.0
const SLOT_Z0 = 17.0
const SLOT_PITCH = 3.3
# Departure order of a pass; a key's index also picks its bay.
const KEYS = ["police_open", "zero1", "zero2", "zero3", "crew0", "crew1", "crew2", "crew3", "crew4", "crew5", "crew6", "crew7", "crew8", "crew9", "police_close"]
# The players' row: across the front of the paddock, clear of the bays, the
# tents and the cars' way in and out; a slot per room member.
const VISITOR_X = [11.0, -11.0, 13.4, -13.4, 15.8, -15.8, 18.2, -18.2]
const VISITOR_Z = 15.0
const CRUISE = 5.0
const REVERSE = 1.8

var stage
var ends: Array[Dictionary] = []
# World z range of the stage and both parks (see z_range()).
var z_limits = Vector2(-835.0, 10.0)
# Plan positions of the road ends: a cheap first test for every ground query.
var _centers = PackedVector2Array()

func configure(owner) -> void:
	stage = owner
	ends.clear()
	for index in range(2):
		var station = 0.0 if index == 0 else stage.LENGTH
		var road_end: Vector3 = stage.at(station)
		var along: Vector3 = stage.direction(0.0) if index == 0 else stage.direction(stage.LENGTH - 0.01)
		var forward = -along if index == 0 else along
		forward.y = 0.0
		forward = forward.normalized()
		# Measured before the parks level anything: the height of the road end.
		road_end.y = stage.biome.ground(road_end)
		ends.append({"origin": road_end, "forward": forward, "right": forward.cross(Vector3.UP).normalized(), "height": road_end.y, "station": station})
	z_limits = _z_limits()
	_centers = PackedVector2Array([Vector2(ends[0].origin.x, ends[0].origin.z), Vector2(ends[1].origin.x, ends[1].origin.z)])

func local(end: Dictionary, pos: Vector3) -> Vector2:
	var offset = pos - end.origin
	return Vector2(offset.dot(end.right), offset.dot(end.forward))

func world(index: int, x: float, z: float) -> Vector3:
	var end: Dictionary = ends[index]
	return end.origin + end.right * x + end.forward * z

# Distance from the lane and paddock in park space; 0 inside.
static func _outside(p: Vector2) -> float:
	var lane = Vector2(maxf(absf(p.x) - LANE_HALF, 0.0), maxf(maxf(-p.y, p.y - LANE), 0.0)).length()
	var paddock = Vector2(maxf(absf(p.x) - HALF_WIDTH, 0.0), maxf(maxf(LANE - p.y, p.y - LANE - DEPTH), 0.0)).length()
	return minf(lane, paddock)

# The park a point is near (-1 for none), how far outside its surface, and how
# fully it belongs to the levelled surface: 1 on it, 0 past the margin.
func nearest(pos: Vector3, reach: float = MARGIN) -> Dictionary:
	var limit = (LANE + DEPTH + HALF_WIDTH + reach) * (LANE + DEPTH + HALF_WIDTH + reach)
	for index in range(_centers.size()):
		var center: Vector2 = _centers[index]
		if (pos.x - center.x) * (pos.x - center.x) + (pos.z - center.y) * (pos.z - center.y) > limit:
			continue
		var end: Dictionary = ends[index]
		var outside = _outside(local(end, pos))
		if outside < reach:
			return {"index": index, "weight": 1.0 - smoothstep(APRON, MARGIN, outside), "outside": outside}
	return {"index": -1, "weight": 0.0, "outside": INF}

func weight(pos: Vector3) -> float:
	return float(nearest(pos).weight)

# Inside a park (or within `padding` of its levelled surface).
func contains(pos: Vector3, padding: float = 0.0) -> bool:
	for end in ends:
		if _outside(local(end, pos)) <= padding:
			return true
	return false

# Index of the park the point stands in, -1 outside both.
func park_at(pos: Vector3, padding: float = 0.0) -> int:
	for index in range(ends.size()):
		if _outside(local(ends[index], pos)) <= padding:
			return index
	return -1

func level(pos: Vector3, height: float) -> float:
	var hit = nearest(pos, APRON + MAX_BLEND)
	if hit.index < 0:
		return height
	var target = float(ends[hit.index].height)
	var span = clampf(absf(height - target) * SLOPE, MARGIN, MAX_BLEND)
	var w = (1.0 - smoothstep(APRON, APRON + span, float(hit.outside))) * _off_road(pos, hit.index)
	return lerpf(height, target, w)

# 1 away from the stage road, 0 on and beside it once past its very end.
func _off_road(pos: Vector3, index: int) -> float:
	var station: float = stage.road_s(pos)
	var into_stage = station if index == 0 else stage.LENGTH - station
	return 1.0 - (1.0 - smoothstep(5.0, 10.0, stage.road_distance(pos))) * smoothstep(1.0, 6.0, into_stage)

# Terrain vertices lie a quarter metre below ground() in the land, but at the
# park's level on its surface, so tyres and feet meet the drawn gravel.
func vertex(pos: Vector3, height: float) -> float:
	return level(pos, height)

# Tyres: on the paddock its level surface; around it the biome's tyre height,
# lifted with the land, so on the road tyres and ground() still agree. The
# biome's tyre query is costly, and inside the park it is not needed.
func vehicle(pos: Vector3, biome) -> float:
	var land: float = biome.ground(pos)
	var surface = level(pos, land)
	var w = weight(pos)
	if w >= 1.0:
		return surface
	return lerpf(biome.vehicle_ground(pos) + surface - land, surface, w)

# The lane and the aisle continue the road surface; the rest of the paddock is
# gravel, a little darker in the bays.
func paint(v: Vector3, color: Color) -> Color:
	var hit = nearest(v)
	if hit.index < 0:
		return color
	var end: Dictionary = ends[hit.index]
	var p = local(end, v)
	var surface = Color("8d8576").lightened(sin(v.x * 0.37 + v.z * 0.23) * 0.03)
	if absf(p.x) < LANE_HALF - 0.5 and p.y < LANE + DEPTH - 4.0:
		surface = stage.biome.road_color(v, float(end.station))
	elif absf(absf(p.x) - SLOT_X) < 2.6 and p.y > SLOT_Z0 - 2.5 and p.y < SLOT_Z0 + SLOT_PITCH * 7 + 2.5:
		surface = surface.darkened(0.08)
	return color.lerp(surface, smoothstep(0.35, 0.9, float(hit.weight)))

# World z range people and cars may move in: the stage plus both parks.
func z_range() -> Vector2:
	return z_limits

func _z_limits() -> Vector2:
	var low = -stage.LENGTH + 5.0
	var high = 10.0
	for index in range(ends.size()):
		for corner in [Vector2(-HALF_WIDTH, LANE + DEPTH), Vector2(HALF_WIDTH, LANE + DEPTH), Vector2(-HALF_WIDTH, LANE), Vector2(HALF_WIDTH, LANE)]:
			var z = world(index, corner.x, corner.y).z
			low = minf(low, z - 2.0)
			high = maxf(high, z + 2.0)
	return Vector2(low, high)

# ---------------------------------------------------------------- bays

func slot_side(key: String) -> float:
	return 1.0 if KEYS.find(key) % 2 == 0 else -1.0

func slot_local(key: String) -> Vector2:
	var index = maxi(0, KEYS.find(key))
	return Vector2(slot_side(key) * SLOT_X, SLOT_Z0 + (index / 2) * SLOT_PITCH)

# A parked car: in its bay, nose towards the aisle, ready to drive out.
func slot_pose(index: int, key: String) -> Transform3D:
	var end: Dictionary = ends[index]
	var p = slot_local(key)
	var nose: Vector3 = -end.right * slot_side(key)
	return Transform3D(Basis(Vector3.UP, atan2(-nose.x, -nose.z)), world(index, p.x, p.y))

# A player's car at the start of the day: in the players' row, nose towards
# the lane, so the stage road past the start line stays clear for the convoy.
func visitor_pose(index: int, slot: int) -> Transform3D:
	var end: Dictionary = ends[index]
	var nose: Vector3 = -end.forward
	var x: float = VISITOR_X[posmod(slot, VISITOR_X.size())]
	return Transform3D(Basis(Vector3.UP, atan2(-nose.x, -nose.z)), world(index, x, VISITOR_Z))

# The day begins with a player's car in the park at the start (pass 1): puts
# it in its slot and returns its heading.
func park_visitor(car: Node3D, slot: int) -> float:
	var pose = visitor_pose(0, slot)
	car.position = pose.origin
	car.rotation = Vector3(0, pose.basis.get_euler().y, 0)
	return car.rotation.y

# The start line of a pass leaving this park: the end of the road, facing it.
func line_pose(index: int) -> Transform3D:
	var end: Dictionary = ends[index]
	var nose: Vector3 = -end.forward
	return Transform3D(Basis(Vector3.UP, atan2(-nose.x, -nose.z)), end.origin)

# ---------------------------------------------------------------- paths
# A path is a list of {"p": Vector3, "reverse": bool} points about 0.25 m apart;
# the car's nose points along the motion, or against it while reversing.

static func _bezier(a: Vector3, b: Vector3, c: Vector3, d: Vector3, reverse: bool, into: Array) -> void:
	var length = a.distance_to(b) + b.distance_to(c) + c.distance_to(d)
	var count = maxi(4, ceili(length / 0.25))
	for i in range(1 if not into.is_empty() else 0, count + 1):
		var t = float(i) / count
		var u = 1.0 - t
		into.append({"p": a * u * u * u + b * 3.0 * u * u * t + c * 3.0 * u * t * t + d * t * t * t, "reverse": reverse})

# From the bay out along the aisle and the lane to the start line.
func leave_path(index: int, key: String) -> Array:
	var end: Dictionary = ends[index]
	var bay = slot_local(key)
	var start = world(index, bay.x, bay.y)
	var nose: Vector3 = -end.right * slot_side(key)
	var aisle = world(index, 0.0, bay.y - 4.0)
	var path: Array = []
	_bezier(start, start + nose * 2.6, aisle + end.forward * 2.6, aisle, false, path)
	_bezier(aisle, aisle.lerp(end.origin, 0.33), aisle.lerp(end.origin, 0.66), end.origin, false, path)
	return path

# From where a finishing car crosses into the lane, along the aisle past its
# bay, then backing into it.
func arrive_path(index: int, key: String, from: Vector3, heading: Vector3) -> Array:
	var end: Dictionary = ends[index]
	var bay = slot_local(key)
	var target = world(index, bay.x, bay.y)
	var past = world(index, 0.0, bay.y + 4.5)
	heading.y = 0.0
	heading = heading.normalized() if heading.length() > 0.01 else end.forward
	var path: Array = []
	_bezier(from, from + heading * 4.0, past - end.forward * 6.0, past, false, path)
	var outward: Vector3 = end.right * slot_side(key)
	_bezier(past, past - end.forward * 2.6, target - outward * 2.6, target, true, path)
	return path

# ---------------------------------------------------------------- scenery

func build(owner: Node3D) -> void:
	for index in range(ends.size()):
		ServiceParkModel.build(owner, self, index)
