extends RefCounted
# The cabin seen through the glass of a car_body.gd car: dashboard with an
# instrument hood, steering wheel, centre console and gear lever, two front
# seats with bolsters and headrests, a rear bench, parcel shelf, headliner,
# sun visors and the rear-view mirror. The body shell is closed at the belt
# line, so the cabin is laid out on top of it and scaled to the glasshouse:
# everything stays under the windscreen, the roof and the rear glass.
# Plain boxes, so the whole cabin bakes into the car's one body mesh; the
# instrument faces are marked as "dash" lamps and glow at night (CarLamps).
#
# Profile fields (optional): seat (fabric colour), seat_insert, interior (dash
# and trim colour), lhd (false puts the wheel on the right).
const P = preload("res://scripts/core/props.gd")
const CarLamps = preload("res://scripts/cars/car_lamps.gd")
const SEAT = "3f454c"
const INSERT = "5d646c"
const TRIM = "2a2e33"
const HEADLINER = Color("c8c4b8")
const GAUGES = Color("d9e2e4")
const SEAT_META = "cabin_seats"

static func build(root: Node3D, p: Dictionary, f: Dictionary) -> void:
	var c = cabin(p, f)
	# Where people sit (car_drivers.gd seats the players who drive or ride).
	var seats = c.duplicate()
	seats.erase("rear_glass_at")
	seats.wheel = wheel_centre(p, c)
	root.set_meta(SEAT_META, seats)
	var trim = Color(p.get("interior", TRIM))
	# Floor carpet over the top of the body shell and the door tops at the belt.
	P.box(root, Vector3(0, c.floor - 0.005, (c.front + c.back) * 0.5), Vector3(c.half * 2.0, 0.012, c.back - c.front), trim.darkened(0.2))
	for side in [-1.0, 1.0]:
		P.box(root, Vector3(side * (c.half - 0.02), c.floor + 0.03, (c.front + c.back) * 0.5), Vector3(0.05, 0.06, c.back - c.front - 0.04), trim)
	_dash(root, p, f, c, trim)
	var seat = Color(p.get("seat", SEAT))
	var insert = Color(p.get("seat_insert", INSERT))
	for side in [-1.0, 1.0]:
		_seat(root, Vector3(side * c.seat_x, c.floor, c.front_seat), c.seat_width, c.avail, seat, insert)
	_bench(root, c, seat, insert)
	# Console between the front seats, with the gear lever.
	var console_from: float = c.dash_back - 0.02
	var console_to: float = c.front_seat - 0.12
	if console_to - console_from > 0.1:
		P.box(root, Vector3(0, c.floor + c.avail * 0.08, (console_from + console_to) * 0.5), Vector3(0.18, c.avail * 0.16, console_to - console_from), trim)
		var lever = Vector3(0, c.floor + c.avail * 0.16, console_from + 0.12)
		P.car_beam(root, lever, lever + Vector3(0, c.avail * 0.14, 0.02), 0.018, Color("1c1f22"))
		P.box(root, lever + Vector3(0, c.avail * 0.15, 0.02), Vector3(0.045, 0.045, 0.045), Color("15181a"))
	# Headliner, sun visors and the rear-view mirror under the roof.
	var roof_y: float = f.height - 0.075
	P.box(root, Vector3(0, roof_y, (c.roof_front + c.roof_back) * 0.5), Vector3(c.half * 1.9, 0.01, c.roof_back - c.roof_front), HEADLINER)
	for side in [-1.0, 1.0]:
		P.box(root, Vector3(side * c.half * 0.48, roof_y - 0.015, c.roof_front + 0.1), Vector3(c.half * 0.72, 0.018, 0.16), HEADLINER.darkened(0.08))
	P.box(root, Vector3(0, roof_y - 0.03, c.roof_front + 0.05), Vector3(0.025, 0.05, 0.025), Color("1c1f22"))
	P.box(root, Vector3(0, roof_y - 0.07, c.roof_front + 0.06), Vector3(0.22, 0.055, 0.025), Color("1c1f22"))

# Inner stations of the cabin in car space: floor height and usable height,
# half width, the windscreen and rear-glass lines, and the seat rows.
static func cabin(p: Dictionary, f: Dictionary) -> Dictionary:
	var shape: Array = f.shape
	var floor_y: float = maxf(f.bonnet, f.deck) + 0.012
	var avail: float = f.height - 0.07 - floor_y
	var half: float = f.glass_half * 0.93
	var front_seat: float = float(p.get("pillar", 0.1)) - 0.08
	var c = {
		"floor": floor_y, "avail": avail, "half": half,
		"front": float(shape[0]) + 0.04, "back": float(shape[3]) - 0.04,
		"roof_front": float(shape[1]), "roof_back": float(shape[2]),
		"seat_x": half * 0.5, "seat_width": clampf(half * 0.62, 0.36, 0.5),
		"front_seat": front_seat,
	}
	# The dashboard top stays a few cm under the windscreen where it starts.
	var dash_top = floor_y + avail * 0.2
	var screen_low: float = f.floor + 0.13
	var screen_high: float = f.height - 0.06
	var t = clampf((dash_top + 0.04 - screen_low) / maxf(0.05, screen_high - screen_low), 0.0, 0.9)
	c.dash_top = dash_top
	c.dash_front = lerpf(float(shape[0]), float(shape[1]), t)
	c.dash_back = minf(c.dash_front + 0.3, front_seat - 0.55)
	# Rear bench behind the front seats, under the roof's back edge.
	c.rear_seat = minf(front_seat + 0.78, float(shape[2]) + 0.1)
	c.has_rear = c.rear_seat + 0.12 < float(shape[3]) and c.rear_seat - front_seat > 0.5
	c.rear_glass_at = func(z: float) -> float: return rear_glass(f, z)
	return c

# Hub of the steering wheel in car space (the driver's hands go to its rim).
static func wheel_centre(p: Dictionary, c: Dictionary) -> Vector3:
	var driver: float = -c.seat_x if p.get("lhd", true) else c.seat_x
	return Vector3(driver, c.dash_top + 0.02, minf(c.dash_back + 0.16, c.front_seat - 0.42))

# Height of the rear glass line at z (the roof's back edge down to the deck).
static func rear_glass(f: Dictionary, z: float) -> float:
	var shape: Array = f.shape
	var t = clampf((z - float(shape[2])) / maxf(0.05, float(shape[3]) - float(shape[2])), 0.0, 1.0)
	return lerpf(f.height - 0.06, f.deck + 0.11, t)

static func _dash(root: Node3D, p: Dictionary, f: Dictionary, c: Dictionary, trim: Color) -> void:
	var depth: float = c.dash_back - c.dash_front
	if depth < 0.08:
		return
	var height: float = c.dash_top - c.floor
	P.box(root, Vector3(0, c.floor + height * 0.5, (c.dash_front + c.dash_back) * 0.5), Vector3(c.half * 1.96, height, depth), trim)
	# A soft lip along the back edge and the vents in the middle.
	P.box(root, Vector3(0, c.dash_top - 0.01, c.dash_back - 0.02), Vector3(c.half * 1.9, 0.03, 0.06), trim.lightened(0.08))
	for x in [-0.09, 0.09]:
		P.box(root, Vector3(x, c.dash_top - height * 0.45, c.dash_back + 0.003), Vector3(0.12, 0.05, 0.01), Color("15181a"))
	var driver: float = -c.seat_x if p.get("lhd", true) else c.seat_x
	# Instrument hood with two dials, lit at night.
	var hood = Vector3(driver, c.dash_top + 0.03, c.dash_back - 0.1)
	P.box(root, hood, Vector3(0.38, 0.07, 0.18), trim.darkened(0.15))
	for dx in [-0.08, 0.08]:
		CarLamps.mark(P.box(root, Vector3(driver + dx, c.dash_top - 0.005, c.dash_back + 0.002), Vector3(0.13, 0.08, 0.008), GAUGES), "dash")
	# Steering wheel on its column, tilted towards the driver.
	var centre = wheel_centre(p, c)
	P.car_beam(root, Vector3(driver, c.dash_top - height * 0.3, c.dash_back - 0.02), centre, 0.04, Color("1c1f22"))
	var wheel = Node3D.new()
	wheel.name = "SteeringWheel"
	root.add_child(wheel)
	wheel.position = centre
	wheel.rotation.x = -0.45
	var radius = minf(0.18, c.avail * 0.36)
	for i in range(10):
		var a = TAU * i / 10.0
		var b = TAU * (i + 1) / 10.0
		P.car_beam(wheel, Vector3(cos(a), sin(a), 0) * radius, Vector3(cos(b), sin(b), 0) * radius, 0.03, Color("1a1c1e"))
	for a in [PI * 0.0, PI, PI * 1.5]:
		P.car_beam(wheel, Vector3.ZERO, Vector3(cos(a), sin(a), 0) * radius, 0.022, Color("2a2d30"))
	P.box(wheel, Vector3.ZERO, Vector3(0.09, 0.07, 0.04), Color("23262a"))

# One front seat: cushion, reclined backrest with side bolsters and a light
# insert, headrest on two posts. `at` is the foot of the backrest.
static func _seat(root: Node3D, at: Vector3, width: float, avail: float, seat: Color, insert: Color) -> void:
	var cushion = avail * 0.12
	P.box(root, at + Vector3(0, cushion * 0.5, -0.24), Vector3(width, cushion, 0.44), seat)
	P.box(root, at + Vector3(0, cushion + 0.004, -0.24), Vector3(width * 0.6, 0.01, 0.36), insert)
	var back_h = avail * 0.6
	var back = Node3D.new()
	root.add_child(back)
	back.position = at + Vector3(0, back_h * 0.5, 0.0)
	back.rotation.x = 0.2
	P.box(back, Vector3.ZERO, Vector3(width, back_h, 0.1), seat)
	P.box(back, Vector3(0, 0.0, -0.052), Vector3(width * 0.6, back_h * 0.8, 0.01), insert)
	for side in [-1.0, 1.0]:
		P.box(back, Vector3(side * (width * 0.5 - 0.03), -back_h * 0.1, -0.05), Vector3(0.06, back_h * 0.7, 0.08), seat.darkened(0.12))
	var head_h = avail * 0.17
	var post_y = back_h * 0.5 + avail * 0.03
	for dx in [-0.06, 0.06]:
		P.box(back, Vector3(dx, post_y, 0.0), Vector3(0.012, avail * 0.07, 0.012), Color("8d9296"))
	P.box(back, Vector3(0, post_y + avail * 0.035 + head_h * 0.5, 0.0), Vector3(width * 0.6, head_h, 0.09), seat)

# Rear bench across the car with two headrests, and the parcel shelf behind it
# up to the rear glass.
static func _bench(root: Node3D, c: Dictionary, seat: Color, insert: Color) -> void:
	if not c.has_rear:
		return
	var avail: float = c.avail
	var width: float = c.half * 1.84
	var z: float = c.rear_seat
	P.box(root, Vector3(0, c.floor + avail * 0.06, z - 0.24), Vector3(width, avail * 0.12, 0.42), seat)
	var back_h = avail * 0.5
	var back = Node3D.new()
	root.add_child(back)
	back.position = Vector3(0, c.floor + back_h * 0.5, z)
	back.rotation.x = 0.22
	P.box(back, Vector3.ZERO, Vector3(width, back_h, 0.1), seat)
	for side in [-1.0, 1.0]:
		P.box(back, Vector3(side * c.seat_x, 0.0, -0.052), Vector3(c.seat_width * 0.6, back_h * 0.75, 0.01), insert)
		P.box(back, Vector3(side * c.seat_x, back_h * 0.5 + avail * 0.08, 0.02), Vector3(c.seat_width * 0.55, avail * 0.13, 0.08), seat)
	var shelf_y: float = c.floor + back_h + 0.01
	var shelf_from: float = z + 0.1
	var shelf_to: float = c.back
	while shelf_to > shelf_from + 0.05 and c.rear_glass_at.call(shelf_to) < shelf_y + 0.03:
		shelf_to -= 0.05
	if shelf_to - shelf_from > 0.08:
		P.box(root, Vector3(0, shelf_y, (shelf_from + shelf_to) * 0.5), Vector3(width, 0.015, shelf_to - shelf_from), Color(TRIM).darkened(0.1))
