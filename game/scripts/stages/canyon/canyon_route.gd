extends RefCounted
# The stage road through the Charyn gorge (canyon_form.gd). It is laid out as
# control points on the land, splined, then resampled by arc length, so a
# station is a metre of road however the road turns — including the hairpin,
# where it doubles back and -z is no longer the station.
#
#   0 – 176   along the rim, the gorge opening below on the left
#   176 – 254 the hairpin at the head of the gorge, back over the lip
#   254 – 690 the bench cut into the near wall, descending with the river
#   690 – 840 the gravel floor, down to the ash grove above the Ili
#
# The bench is not drawn on the wall by eye: for every step down the gorge the
# builder asks the wall where it stands at the height the road has reached, so
# the road follows the hillside and the cut stays shallow.
const Form = preload("res://scripts/stages/canyon/canyon_form.gd")

const RIM_START = -196.0
const RIM_END = -24.0
const RIM_STEP = 18.0
# How far back from the lip the rim road runs. It starts well back, where the
# service park needs solid ground, and comes out onto the very edge for the
# run up to the turn.
const RIM_BACK_PARK = 30.0
const RIM_BACK_FAR = 22.0
const RIM_BACK_NEAR = 18.0
const HAIRPIN_STEPS = 9
const DESCENT_STEP = 14.0
const DESCENT_END_Z = -452.0
const FLOOR_STEP = 24.0
const FLOOR_END_Z = -680.0
const TABLE_STEP = 1.0
# The road rides this far over the land it is graded into.
const CAMBER = 0.25
const SMOOTH_PASSES = 30

static func rim_back(z: float) -> float:
	var park = smoothstep(RIM_START + 62.0, RIM_START, z)
	var near = smoothstep(-150.0, RIM_END, z)
	return lerpf(RIM_BACK_FAR, RIM_BACK_NEAR, near) + park * RIM_BACK_PARK + sin(z * 0.041) * 3.5

static func rim_point(z: float) -> Vector3:
	var p = Vector3(Form.axis_x(z) + Form.rim_edge(z, 1.0) + rim_back(z), 0.0, z)
	p.y = Form.rim_level(p)
	return p

# Where the near wall stands at `height`: the lateral offset from the axis at
# which the hillside is that high. The wall climbs with distance, so this is a
# plain bisection.
static func wall_lateral(z: float, height: float) -> float:
	var low = Form.wall_foot(z, 1.0)
	var high = Form.rim_edge(z, 1.0) + 4.0
	for _i in range(20):
		var mid = (low + high) * 0.5
		if Form.surface(Vector3(Form.axis_x(z) + mid, 0.0, z)) < height:
			low = mid
		else:
			high = mid
	return (low + high) * 0.5

# Control points of the road, in order: where it runs and how high it rides.
static func control_points() -> PackedVector3Array:
	var points = PackedVector3Array()
	var z = RIM_START
	while z <= RIM_END + 0.5:
		points.append(rim_point(z))
		z += RIM_STEP
	_hairpin(points)
	_descent(points)
	_floor(points)
	return points

# The turn at the head of the gorge: a half circle on the table that leaves
# the rim road heading upstream and brings it back over the lip.
static func _hairpin(points: PackedVector3Array) -> void:
	var entry: Vector3 = points[points.size() - 1]
	var lip = Form.axis_x(entry.z) + Form.rim_edge(entry.z, 1.0) + 5.0
	var radius = maxf(9.0, (entry.x - lip) * 0.5)
	var center = Vector2(entry.x - radius, entry.z)
	for i in range(1, HAIRPIN_STEPS + 1):
		var angle = PI * float(i) / HAIRPIN_STEPS
		var turn = center + Vector2(cos(angle), sin(angle)) * radius
		var p = Vector3(turn.x, 0.0, turn.y)
		p.y = Form.rim_level(p)
		points.append(p)

# The bench: the road slants down the face of the near wall as the gorge
# deepens, until it reaches the gravel of the floor.
static func _descent(points: PackedVector3Array) -> void:
	var start: float = points[points.size() - 1].z
	var top: float = points[points.size() - 1].y
	var bottom = Form.bed_level(DESCENT_END_Z) + 1.8
	var z = start - DESCENT_STEP
	while z > DESCENT_END_Z:
		var height = lerpf(top, bottom, smoothstep(start, DESCENT_END_Z, z))
		points.append(Vector3(Form.axis_x(z) + wall_lateral(z, height), height, z))
		z -= DESCENT_STEP

# The gravel floor: the road swings across the bed between the banks and runs
# out into the ash grove.
static func _floor(points: PackedVector3Array) -> void:
	var z = DESCENT_END_Z - 6.0
	while z > FLOOR_END_Z:
		var swing = sin((z - DESCENT_END_Z) * 0.017) * minf(Form.floor_half(z) * 0.4, 20.0)
		points.append(Vector3(Form.axis_x(z) + swing, Form.bed_level(z) + 1.6, z))
		z -= FLOOR_STEP

# Catmull-Rom through the control points, sampled fine enough to measure.
static func _spline(points: PackedVector3Array) -> PackedVector3Array:
	var dense = PackedVector3Array()
	for i in range(points.size() - 1):
		var a: Vector3 = points[maxi(i - 1, 0)]
		var b: Vector3 = points[i]
		var c: Vector3 = points[i + 1]
		var d: Vector3 = points[mini(i + 2, points.size() - 1)]
		for step in range(12):
			var t = float(step) / 12.0
			dense.append(b.cubic_interpolate(c, a, d, t))
	dense.append(points[points.size() - 1])
	return dense

# One entry per metre of road, so a station is a metre along it.
static func _plan(length: float) -> PackedVector3Array:
	var dense = _spline(control_points())
	var wanted = int(length / TABLE_STEP) + 4
	var result = PackedVector3Array([dense[0]])
	var walked = 0.0
	var i = 0
	while i < dense.size() - 1 and result.size() < wanted:
		var a: Vector3 = dense[i]
		var b: Vector3 = dense[i + 1]
		var span = Vector2(b.x - a.x, b.z - a.z).length()
		var next = float(result.size()) * TABLE_STEP
		if span < 0.00001 or walked + span < next:
			walked += span
			i += 1
			continue
		result.append(a.lerp(b, (next - walked) / span))
	while result.size() < wanted:
		result.append(result[result.size() - 1] * 2.0 - result[result.size() - 2])
	return result

# The road surface: the graded profile of the control points, eased along its
# length so no kink is left at a join, with a little undulation put back in.
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
		heights[i] += CAMBER + sin(float(i) / 23.0) * 0.35 + sin(float(i) / 7.0) * 0.12
	return heights

# {"plan": one (x, z) per metre, "height": the road surface at each}.
static func build(length: float) -> Dictionary:
	var plan = _plan(length)
	var flat = PackedVector2Array()
	for p in plan:
		flat.append(Vector2(p.x, p.z))
	return {"plan": flat, "height": _grade(plan)}
