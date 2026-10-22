extends RefCounted
# A crew's driver on the shared tyre model (player_handling.gd). The traffic
# plan still decides where the crew should be: a point on its line and a
# speed. The driver steers at that line with pure pursuit, counter-steers when
# the rear steps out and works the pedals; the tyres decide how the car
# actually turns, slides and loses speed. An assist, the driver's skill, pulls
# the car back towards its line with at most `assist` g and catches slides
# past `max_slip`; a weaker assist lets the car run wide and leave the road.
const CarRegistry = preload("res://scripts/cars/car_registry.gd")
const Mistakes = preload("res://scripts/traffic/rally_mistakes.gd")
const STEP = 1.0 / 120.0
# Rally cars: four-wheel drive, a short wheelbase and a nimble body.
const WHEELBASE = 2.5
const INERTIA = 1.3
const REAR_BIAS = 0.5
# Pure pursuit looks LOOK_BASE + LOOK_TIME * speed metres ahead.
const LOOK_BASE = 3.0
const LOOK_TIME = 0.35
# Assist spring (1/s²) and damping (1/s) on the sideways error from the line.
const ASSIST_STIFFNESS = 20.0
const ASSIST_DAMPING = 8.0
# Threading past a blocker the driver concentrates: the assist is this much
# stronger, so the car keeps the passing line the plan cleared.
const AVOID_ASSIST = 3.0
# Speed (m/s) below which the assist fades out.
const ASSIST_SPEED = 3.0
# Deceleration (m/s²) of a crawling car told to stop.
const CRAWL_BRAKE = 8.0
# Below CREEP_SPEED (m/s) a crew shuffles sideways onto its line at up to
# CREEP_SHUFFLE m/s, as a slow car would with a few turns of the wheel.
const CREEP_SPEED = 3.0
const CREEP_SHUFFLE = 0.8
# How fast (1/s) a creeping car's sideways drift dies away.
const CREEP_SETTLE = 8.0
# Body slip held at the grip limit (rad) and how hard the driver works the
# yaw towards it (1/s²).
const DRIFT = 0.4
const SLIP_CATCH = 8.0
# Pedals: throttle and brake per m/s of speed gap; the brake pedal's full
# travel (m/s²) before the driver stamps on it.
# Height (m) of the body origin above the ground at which the tyres lose grip.
const AIRBORNE = 0.45
const THROTTLE_GAIN = 0.6
const BRAKE_GAIN = 0.25
const PARTIAL_BRAKE = 10.0

# Below this speed (m/s) a crew holding for a red flag counts as stopped.
const HOLD_SPEED = 0.5

# Competitors and zero cars drive on the tyre model; police, ambulances and
# the park convoy keep to their planned line.
static func applies(racer: Dictionary) -> bool:
	return str(racer.get("role", "racer")) in ["racer", "zero"]

# The profile player_handling.advance uses for a crew's car.
static func spec(launch: float) -> Dictionary:
	return {"rear_bias": REAR_BIAS, "wheelbase": WHEELBASE, "launch": launch, "inertia": INERTIA}

# Front wheel lock (rad) at `speed`, as player_handling narrows it.
static func lock(speed: float) -> float:
	return lerpf(0.48, 0.22, clampf(speed / 20, 0, 1)) * lerpf(1.0, 0.5, clampf((speed - 20) / 40, 0, 1))

# One driven step of `dt` (substeps of STEP). `line_point` is where the plan
# wants the car now, `aim` the point on the line ahead, `side` the road's right,
# `line_rate` how fast the planned line moves sideways (m/s). Moves racer.node
# and racer.motion; returns the car's sideways error from its line (m).
static func drive(racer: Dictionary, stage, line_point: Vector3, aim: Vector3, side: Vector3, line_rate: float, speed: float, dt: float) -> float:
	var node: Node3D = racer.node
	var motion = racer.motion
	var handling = motion.handling
	var car = spec(float(racer.get("launch", CarRegistry.launch(2.0))))
	var assist = float(racer.get("assist", 1.0)) * float(racer.get("assist_share", 1.0)) * 9.8 * (AVOID_ASSIST if racer.get("avoiding", false) else 1.0)
	var max_slip = float(racer.get("max_slip", 0.45))
	var steps = maxi(1, int(ceil(dt / STEP)))
	var h = dt / steps
	var error = 0.0
	for i in range(steps):
		var heading: float = node.rotation.y
		var flat = Vector3(motion.velocity.x, 0, motion.velocity.z)
		var velocity = flat.length()
		var forward = Vector3(-sin(heading), 0, -cos(heading))
		var course = atan2(-flat.x, -flat.z) if velocity > 2.0 else heading
		# Steer the travel direction at the aim point; the wheels are set
		# relative to the body, so a car sliding wide gets opposite lock.
		var to = aim - node.position
		var reach = maxf(Vector2(to.x, to.z).length(), 2.0)
		var alpha = wrapf(atan2(-to.x, -to.z) - course, -PI, PI)
		var wheel = atan(2.0 * WHEELBASE * sin(alpha) / reach) + wrapf(course - heading, -PI, PI)
		var steer = clampf(-wheel / lock(velocity), -1.0, 1.0)
		var along = flat.dot(forward)
		var gap = speed - along
		# `pull` eases a towed crew back into the race (rally_crews.gd).
		var throttle = clampf(gap * THROTTLE_GAIN, 0.0, float(racer.get("pull", 1.0)))
		var stamp = false
		if gap < -0.5:
			# Opposite pedal brakes in player_handling: throttle * 10 m/s².
			throttle = -clampf(-gap * BRAKE_GAIN, 0.0, 1.0)
			# Told to stop (red flag, a queue): full brakes down to a standstill.
			stamp = -gap * BRAKE_GAIN > 1.2 or speed <= 0.0
		var grip: float = stage.grip(node.position)
		# Over gravel bumps the springs unload for a moment; the tyres still
		# bite until the car is really off the ground.
		var bouncing = motion.grounded
		motion.grounded = node.position.y - stage.ground(node.position) < AIRBORNE
		# Told to stop and down to a crawl, the car simply comes to rest
		# whichever way its last slide left it pointing.
		if speed <= 0.0 and velocity < ASSIST_SPEED:
			motion.velocity = motion.velocity.move_toward(Vector3(0, motion.velocity.y, 0), CRAWL_BRAKE * h)
			handling.yaw_rate = move_toward(handling.yaw_rate, 0.0, CRAWL_BRAKE * h)
			heading -= handling.yaw_rate * h
		else:
			heading = handling.advance(motion, heading, throttle, steer, stamp, grip, CarRegistry.TOP_SPEED, 0, h, car)
		motion.grounded = bouncing
		# Assist: pull the car towards its line, never harder than its skill.
		error = (node.position - line_point).dot(side)
		var drift = motion.velocity.dot(side) - line_rate
		# It fades out at a crawl, where rally_crews.gd shuffles the car across.
		var reach_assist = assist * clampf(velocity / ASSIST_SPEED, 0.0, 1.0)
		motion.velocity += side * clampf(-error * ASSIST_STIFFNESS - drift * ASSIST_DAMPING, -reach_assist, reach_assist) * h
		# Rally style: the driver holds the nose into the bend by a share of the
		# grip used (`drift`, rad at the limit); past `max_slip` a slide is caught.
		var slip = wrapf(heading - course, -PI, PI)
		if velocity > 3.0 and not stamp:
			var turning = flat.length() * (wrapf(atan2(-motion.velocity.x, -motion.velocity.z) - course, -PI, PI) / h) if motion.velocity.length() > 2.0 else 0.0
			var load = clampf(turning / maxf(grip * 12.0, 1.0), -1.0, 1.0)
			var wanted = signf(load) * sqrt(absf(load)) * float(racer.get("drift", DRIFT))
			wanted = clampf(wanted, -max_slip, max_slip)
			handling.yaw_rate -= (wanted - slip) * SLIP_CATCH * h
		node.position += Vector3(motion.velocity.x, 0, motion.velocity.z) * h
		node.rotation.y = heading
		line_point += side * line_rate * h
	return error

# One frame of a crew or zero car (`crews` is rally_crews.gd): the driver aims
# along its planned
# line; the road station and the slide then follow where the car really is,
# so a car that runs wide reads as a slide and, far enough, as a departure.
static func follow(crews, racer: Dictionary, speed: float, advance: float, delta: float) -> void:
	var node: Node3D = racer.node
	var s: float = racer.s
	var side = crews.race_side(s)
	var road = crews.race_direction(s)
	var bend_to = crews.race_direction(s + Mistakes.BEND_SPAN)
	var bend = wrapf(atan2(-bend_to.x, -bend_to.z) - atan2(-road.x, -road.z), -PI, PI)
	speed *= Mistakes.update(racer, s, bend, bool(racer.get("avoiding", false)), delta)
	var ahead = s + LOOK_BASE + LOOK_TIME * racer.motion.velocity.length()
	var aim = crews.race_at(ahead) + crews.race_side(ahead) * float(racer.line)
	racer.pull = crews.recovery_pull(racer, delta)
	drive(racer, crews.game.stage, crews.race_at(s) + side * float(racer.line), aim, side, float(racer.get("line_speed", 0.0)), speed, delta)
	# Project the car onto the road; a few steps settle it in tight hairpins,
	# where one tangent step overshoots, and it never runs ahead of the car.
	var station = s
	for i in range(3):
		station += (node.position - crews.race_at(station)).dot(crews.race_direction(station))
	var travelled = Vector2(node.position.x - racer.previous.x, node.position.z - racer.previous.z).length()
	racer.s = clampf(station, s - travelled - 0.5, s + travelled + 0.5)
	racer.s = clampf(racer.s, 0.0, crews.game.stage.length)
	# The plan's room ahead (a queue, a car across the road) is a hard limit:
	# the driver stops short of it even past what the tyres would allow.
	var excess = racer.s - s - advance
	if excess > 0.0:
		var back = crews.race_direction(racer.s) * excess
		node.position -= Vector3(back.x, 0, back.z)
		racer.s -= excess
		racer.motion.velocity *= clampf(advance / maxf(delta, 0.001) / maxf(racer.motion.velocity.length(), 0.001), 0.0, 1.0)
	var slide = (node.position - crews.race_at(racer.s)).dot(crews.race_side(racer.s)) - float(racer.line)
	# Creeping past a blocker the tyres barely turn the car; the driver shuffles
	# across onto the passing line the way the plan expects.
	var creep = maxf(0.0, 1.0 - racer.motion.velocity.length() / CREEP_SPEED)
	if creep > 0.0:
		var across = crews.race_side(racer.s) * racer.motion.velocity.dot(crews.race_side(racer.s))
		racer.motion.velocity -= across * minf(1.0, creep * CREEP_SETTLE * delta)
	if creep > 0.0 and absf(slide) > 0.01:
		var shift = clampf(slide, -CREEP_SHUFFLE * creep * delta, CREEP_SHUFFLE * creep * delta)
		node.position -= crews.race_side(racer.s) * shift
		slide -= shift
	racer.slide_speed = (slide - float(racer.slide)) / maxf(delta, 0.001)
	racer.slide = slide
	node.set_meta("steer_angle", -racer.motion.handling.steering)
	racer.driven = node.position
	racer.drive_speed = racer.motion.velocity.length()

# A car spawned, recovered or moved by a script (it is not where the driver
# left it) starts driving from where it was put: on its line at its station,
# nose along the road, at drive_speed.
static func take_over(crews, racer: Dictionary) -> void:
	var node: Node3D = racer.node
	var driven = racer.get("driven", null)
	if driven != null and Vector2(node.position.x - driven.x, node.position.z - driven.z).length() <= 1.0:
		return
	var s: float = racer.s
	var expected = crews.race_at(s) + crews.race_side(s) * (float(racer.line) + float(racer.slide))
	if Vector2(node.position.x - expected.x, node.position.z - expected.z).length() > 6.0:
		node.position = Vector3(expected.x, node.position.y, expected.z)
	racer.previous = node.position
	var road_yaw = atan2(-crews.race_direction(s).x, -crews.race_direction(s).z)
	# A car that drove back on by itself (rally_rejoin.gd) keeps its heading
	# and momentum; one put down by a script starts clean along the road.
	var speed = float(racer.get("drive_speed", 0.0))
	if absf(wrapf(node.rotation.y - road_yaw, -PI, PI)) < 0.6 and speed > 1.0 and absf(racer.motion.velocity.length() - speed) < 3.0:
		return
	node.rotation.y = road_yaw
	racer.motion.velocity = Vector3(-sin(road_yaw), 0, -cos(road_yaw)) * speed
	racer.motion.handling.yaw_rate = 0.0
