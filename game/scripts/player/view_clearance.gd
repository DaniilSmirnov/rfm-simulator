extends RefCounted
# Keeps the view out of scenery it would otherwise sit in. The chase camera is
# pulled in front of whatever stands between it and the car (service tents,
# walls, signs: the stage solids; conifer crowns), and a fan getting out of a
# car steps out on the side where his eyes are not inside a crown.
# A conifer's three crown layers (stage_forest.shared_tree_pose) are tested as
# one cone; solids reuse StageSolids.hit(). One segment per frame, a few trees.
const CROWN_BOTTOM = 0.225
const CROWN_TOP = 1.075
const CROWN_RADIUS = 0.28
const MARGIN = 0.35
const MIN_DISTANCE = 1.6
const STEPS = 24
const EYE_HEIGHT = 1.72

# The farthest point on from..to the camera can take with a clear view of from.
static func clear_view(stage, from: Vector3, to: Vector3, ignored: Node3D = null) -> Vector3:
	var travel = to - from
	var length = travel.length()
	if length <= MIN_DISTANCE:
		return to
	var t = crown_fraction(stage, from, to)
	var hit: Dictionary = stage.solids.hit(from, to, MARGIN, false, Vector3.ZERO, ignored)
	if not hit.is_empty():
		t = minf(t, from.distance_to(hit.position) / length)
	return to if t >= 1.0 else from + travel * maxf(t, MIN_DISTANCE / length)

# The chase camera does not huddle against the car when scenery (a tent roof
# behind the park bay, a crown) cuts its line short: it rises over the car,
# steeper until most of the distance is clear, and never comes closer than
# `reach` (that is inside the car body); with nothing clear it stays at
# `reach` on its own line.
static func chase_view(stage, pivot: Vector3, to: Vector3, car: Node3D, reach: float) -> Vector3:
	var seen = clear_view(stage, pivot, to, car)
	var length = pivot.distance_to(to)
	if length <= reach or pivot.distance_to(seen) >= maxf(reach, length * 0.75):
		return seen
	var best = seen if pivot.distance_to(seen) >= reach else pivot + (to - pivot) / length * reach
	var flat = Vector3(to.x - pivot.x, 0, to.z - pivot.z).normalized()
	for lift in [0.75, 1.05, 1.35]:
		var rise = clear_view(stage, pivot, pivot + (flat * cos(lift) + Vector3.UP * sin(lift)) * length, car)
		if pivot.distance_to(rise) > pivot.distance_to(best) + 0.5:
			best = rise
		if pivot.distance_to(best) >= length * 0.75:
			break
	return best

# Fraction of from..to before it first enters a standing tree's crown (1 = never).
static func crown_fraction(stage, from: Vector3, to: Vector3) -> float:
	if stage.trees.is_empty():
		return 1.0
	var best = 1.0
	var a = Vector2(from.x, from.z)
	var b = Vector2(to.x, to.z)
	for index in stage.trees_near(a.min(b), a.max(b), 0.0):
		if stage.fallen.has(index):
			continue
		var base: Vector3 = stage.trees[index]
		var height = _height(stage, index)
		var foot = Vector2(base.x, base.z)
		if foot.distance_to(Geometry2D.get_closest_point_to_segment(foot, a, b)) > height * CROWN_RADIUS + MARGIN:
			continue
		for step in range(STEPS + 1):
			var f = float(step) / STEPS
			if f >= best:
				break
			if in_crown(base, height, from.lerp(to, f)):
				best = f
				break
	return best

static func in_crown(base: Vector3, height: float, p: Vector3, margin: float = MARGIN) -> bool:
	var bottom = height * CROWN_BOTTOM
	var top = height * CROWN_TOP
	var y = p.y - base.y
	if y < bottom - margin or y > top:
		return false
	var radius = height * CROWN_RADIUS * clampf((top - y) / (top - bottom), 0.0, 1.0) + margin
	return Vector2(p.x - base.x, p.z - base.z).length_squared() < radius * radius

# True when eyes at p sit inside a standing tree's crown.
static func eyes_in_crown(stage, p: Vector3) -> bool:
	var eye = p + Vector3.UP * EYE_HEIGHT
	var flat = Vector2(p.x, p.z)
	for index in stage.trees_near(flat, flat, 0.0):
		if not stage.fallen.has(index) and in_crown(stage.trees[index], _height(stage, index), eye, 0.2):
			return true
	return false

# Where to stand after getting out: the first spot (on the ground) where the
# fan's head is not inside a crown, else the first one.
static func exit_spot(stage, spots: Array) -> Vector3:
	var first = Vector3.ZERO
	for i in range(spots.size()):
		var spot: Vector3 = spots[i]
		spot.y = stage.walking_ground(spot)
		if i == 0:
			first = spot
		if not eyes_in_crown(stage, spot):
			return spot
	return first

static func _height(stage, index: int) -> float:
	return float(stage.forest_data[index].height) if index < stage.forest_data.size() else 8.0
