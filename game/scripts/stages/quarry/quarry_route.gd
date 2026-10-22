extends RefCounted
# The stage road over the dumps and down into the pit (quarry_form.gd). Laid
# out as control points on the land, splined and resampled by arc length like
# the Charyn road (canyon_route.gd), so a station is a metre of road.
#
#   0 – ~330      across the dumps north of the pit, fast, over two crests
#   ~330 – ~890   the haul road: in over the east rim, down the east wall,
#                 round the south end and down the west wall to the floor
#   ~890 – end    along the floor of the pit to the finish and service park
#
# The haul road is not drawn on the wall by eye: at every metre it falls
# GRADE and keeps to where the stepped wall, read as an even slope, stands at
# that height (Form.slope_reach), so the cut and fill stay shallow.
const Form = preload("res://scripts/stages/quarry/quarry_form.gd")
const CanyonRoute = preload("res://scripts/stages/canyon/canyon_route.gd")

const PLATEAU = [
	Vector2(14.0, 0.0), Vector2(16.0, -30.0), Vector2(25.0, -62.0), Vector2(42.0, -92.0), Vector2(52.0, -122.0),
	Vector2(49.0, -152.0), Vector2(58.0, -182.0), Vector2(78.0, -208.0), Vector2(90.0, -240.0), Vector2(93.0, -272.0),
	Vector2(86.0, -306.0),
]
# Where the haul road leaves the rim: on the top berm of the east wall.
const RAMP_Z = Form.NORTH_Z - 22.0
# Fall of the haul road per metre, as on a real pit ramp.
const GRADE = 0.09
const RAMP_STEP = 12.0
const FLOOR_ROAD = [
	Vector2(-60.0, -606.0), Vector2(-52.0, -578.0), Vector2(-50.0, -548.0), Vector2(-50.0, -518.0), Vector2(-45.0, -488.0),
	Vector2(-36.0, -458.0), Vector2(-34.0, -428.0), Vector2(-40.0, -398.0), Vector2(-42.0, -372.0), Vector2(-41.0, -340.0),
]
# The road where it finishes, before the run-out into the service park.
const FINISH_Z = -378.0
# Crests on the dumps that throw cars into the air: station, height, half-width.
const CRESTS = [[96.0, 0.9, 6.0], [214.0, 1.1, 7.0]]
const CAMBER = 0.25
const SMOOTH_PASSES = 24
const TABLE_STEP = 1.0

static func plateau_point(p: Vector2) -> Vector3:
	var point = Vector3(p.x, 0.0, p.y)
	point.y = Form.plateau(point)
	return point

# Down the walls from the rim to the floor. Returns the control points and
# the arc length of the descent.
static func _ramp(points: PackedVector3Array) -> float:
	var height = Form.RIM_LEVEL
	var z = RAMP_Z
	var angle = 0.0
	var walked = 0.0
	var since = RAMP_STEP
	while height > Form.FLOOR_LEVEL:
		var r = Form.FLOOR + Form.slope_reach(height)
		var p: Vector3
		if z > Form.SOUTH_Z and angle == 0.0:
			p = Vector3(Form.AXIS_X + r, height, z)
			z -= 1.0
		elif angle < PI:
			p = Vector3(Form.AXIS_X + r * cos(angle), height, Form.SOUTH_Z - r * sin(angle))
			angle = minf(PI, angle + 1.0 / r)
			z = Form.SOUTH_Z
		else:
			p = Vector3(Form.AXIS_X - r, height, z)
			z += 1.0
		if since >= RAMP_STEP:
			points.append(p)
			since = 0.0
		height -= GRADE
		walked += 1.0
		since += 1.0
	return walked

static func control_points() -> PackedVector3Array:
	var points = PackedVector3Array()
	for p in PLATEAU:
		points.append(plateau_point(p))
	_ramp(points)
	for p in FLOOR_ROAD:
		points.append(Vector3(p.x, Form.FLOOR_LEVEL, p.y))
	return points

# The road surface: the profile of the control points eased along its length,
# the crests on the dumps and a little undulation put back in.
static func _grade(plan: PackedVector3Array) -> PackedFloat32Array:
	var heights = PackedFloat32Array()
	for p in plan:
		heights.append(p.y)
	for _pass_index in range(SMOOTH_PASSES):
		var smoothed = heights.duplicate()
		for i in range(1, heights.size() - 1):
			smoothed[i] = (heights[i - 1] + heights[i] * 2.0 + heights[i + 1]) * 0.25
		heights = smoothed
	for i in range(heights.size()):
		var s = float(i) * TABLE_STEP
		heights[i] += CAMBER + sin(s / 29.0) * 0.18 + sin(s / 7.0) * 0.06
		for crest in CRESTS:
			var t = (s - float(crest[0])) / float(crest[2])
			heights[i] += float(crest[1]) * exp(-t * t)
	return heights

# {"plan": (x, z) per metre, "height": surface per metre, "length": stations
# to the finish line on the floor, "ramp": stations where the haul road leaves
# the rim and reaches the floor}.
static func build() -> Dictionary:
	var dense = CanyonRoute.spline(control_points())
	var total = 0.0
	for i in range(dense.size() - 1):
		total += Vector2(dense[i + 1].x - dense[i].x, dense[i + 1].z - dense[i].z).length()
	var plan = CanyonRoute.resample(dense, total)
	var flat = PackedVector2Array()
	for p in plan:
		flat.append(Vector2(p.x, p.z))
	var ramp_begin = 0.0
	var ramp_end = 0.0
	var finish = 0.0
	for i in range(plan.size()):
		var p: Vector3 = plan[i]
		if ramp_begin == 0.0 and p.z < RAMP_Z + 0.5:
			ramp_begin = float(i)
		elif ramp_begin > 0.0 and ramp_end == 0.0 and p.y <= Form.FLOOR_LEVEL + 0.05:
			ramp_end = float(i)
		elif ramp_end > 0.0 and finish == 0.0 and p.z >= FINISH_Z:
			finish = float(i)
	# Shared code samples the road every stage.STEP (4 m) up to its length.
	var length = floorf(finish * TABLE_STEP / 4.0) * 4.0
	return {"plan": flat, "height": _grade(plan), "length": length, "ramp": Vector2(ramp_begin, ramp_end) * TABLE_STEP}
