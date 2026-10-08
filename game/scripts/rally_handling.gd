extends RefCounted
# Tyre load, slide recovery and off-road momentum share the 120 Hz suspension step.
const STEP = 1.0 / 120.0

static func slide(racer: Dictionary, bend: float, speed: float, grip: float, delta: float) -> float:
	var steps = maxi(1, int(ceil(delta / STEP)))
	var dt = delta / steps
	var demand = bend * speed * speed
	var support = 1.0 if racer.motion.grounded else 0.12
	var capacity = maxf(0.2, grip * 17.0 * support)
	for i in range(steps):
		var excess = signf(demand) * maxf(0.0, absf(demand) - capacity)
		var correction = clampf(-racer.slide * 9.0 - racer.slide_speed * 4.5, -capacity, capacity)
		racer.slide_speed += (demand * 0.06 + excess + correction) * dt
		racer.slide += racer.slide_speed * dt
	var target = clampf(atan2(racer.slide_speed, maxf(speed, 2.0)) + demand / maxf(capacity, 1.0) * 0.07, -0.55, 0.55)
	racer.drift_yaw = lerpf(float(racer.get("drift_yaw", 0.0)), target, 1.0 - exp(-delta * 5.0))
	return demand

static func departure(racer: Dictionary, velocity: Vector3, side: Vector3, bend: float) -> void:
	# Keep forward and lateral momentum: never aim an accident at the spectator.
	racer.motion.velocity = Vector3(velocity.x, 0.0, velocity.z)
	var lateral = racer.motion.velocity.dot(side)
	var outward = signf(lateral) if absf(lateral) > 0.5 else signf(bend)
	if outward == 0.0:
		outward = 1.0 if int(racer.id) % 2 else -1.0
	racer.exit_side = outward
	racer.yaw_rate = -outward * (0.65 if racer.kind == "crash" else 0.35)

static func free_step(racer: Dictionary, stage, dt: float) -> void:
	var node: Node3D = racer.node
	var motion = racer.motion
	var grip: float = stage.grip(node.position)
	var lateral_accel = 0.0
	if motion.grounded:
		var forward = Vector3(-sin(node.rotation.y), 0, -cos(node.rotation.y))
		var side = forward.cross(Vector3.UP)
		var lateral: float = motion.velocity.dot(side)
		var corrected = move_toward(lateral, 0.0, grip * 7.0 * dt)
		lateral_accel = (corrected - lateral) / dt
		motion.velocity += side * (corrected - lateral)
		# Braking and rolling resistance depend on the surface under the wheels.
		motion.velocity = motion.velocity.move_toward(Vector3.ZERO, (1.5 + grip * 9.0) * dt)
		var x_slope: float = (stage.ground(node.position + Vector3.RIGHT) - stage.ground(node.position - Vector3.RIGHT)) * 0.5
		var z_slope: float = (stage.ground(node.position + Vector3.BACK) - stage.ground(node.position - Vector3.BACK)) * 0.5
		motion.velocity += Vector3(-x_slope, 0, -z_slope) * 9.8 * dt
	var turn = float(racer.get("yaw_rate", 0.0)) * clampf(motion.velocity.length() / 12.0, 0.0, 1.0)
	racer.yaw_rate = float(racer.get("yaw_rate", 0.0)) * exp(-dt * (0.45 if motion.grounded else 0.05))
	node.position += motion.velocity * dt
	motion.suspension(node, stage, dt, node.rotation.y + turn * dt, lateral_accel)

# Resample in world metres before smoothing: village stations have clustered
# vertices at junctions. A uniform cubic B-spline rounds those corners without
# inheriting their near-zero tangent lengths. Keep the original road untouched.
static func path(stage, station: float) -> Vector3:
	if not stage.has_meta("rally_path"):
		var distances = PackedFloat32Array([0.0])
		for i in range(1, stage.points.size()):
			distances.append(distances[-1] + stage.points[i].distance_to(stage.points[i-1]))
		var samples = PackedVector3Array()
		var segment = 0
		var end_direction = (stage.points[-1] - stage.points[-2]).normalized()
		for i in range(ceili(distances[-1] / 4.0) + 3):
			var distance = i * 4.0
			while segment < stage.points.size() - 2 and distances[segment+1] < distance:
				segment += 1
			if distance > distances[-1]:
				samples.append(stage.points[-1] + end_direction * (distance-distances[-1]))
			else:
				samples.append(stage.points[segment].lerp(stage.points[segment+1], (distance-distances[segment]) / maxf(0.001, distances[segment+1]-distances[segment])))
		stage.set_meta("rally_path", {"distances": distances, "samples": samples})
	var s = clampf(station, 0, stage.LENGTH - 0.001)
	var index = int(s / stage.STEP)
	var cache: Dictionary = stage.get_meta("rally_path")
	var distance = lerpf(cache.distances[index], cache.distances[index+1], fmod(s, stage.STEP)/stage.STEP)
	var cell = int(distance / 4.0)
	var t = fmod(distance, 4.0) / 4.0
	var samples: PackedVector3Array = cache.samples
	var p0 = samples[cell-1] if cell > 0 else samples[0]*2-samples[1]
	return (p0 * pow(1-t, 3) + samples[cell] * (3*t*t*t-6*t*t+4) + samples[cell+1] * (-3*t*t*t+3*t*t+3*t+1) + samples[cell+2] * t*t*t) / 6.0

static func direction(stage, station: float, reverse: bool = false) -> Vector3:
	var center = clampf(station, 0.1, stage.LENGTH - 0.101)
	return (path(stage, center + 0.1) - path(stage, center - 0.1)).normalized() * (-1.0 if reverse else 1.0)

static func offset_path(stage, station: float, offset: float) -> Vector3:
	return path(stage, station) + direction(stage, station).cross(Vector3.UP).normalized() * offset

static func metric(stage, station: float, offset: float = 0.0) -> float:
	var low = maxf(0, station - 0.05)
	var high = minf(stage.LENGTH - 0.001, station + 0.05)
	var difference = offset_path(stage, high, offset) - offset_path(stage, low, offset) if absf(offset) > 0.001 else path(stage, high) - path(stage, low)
	return maxf(Vector2(difference.x, difference.z).length() / maxf(high - low, 0.001), 0.1)

static func advance(stage, progress: float, metres: float, reverse: bool, offset: float = 0.0) -> float:
	var sign_value = -1.0 if reverse else 1.0
	var station = stage.LENGTH - progress if reverse else progress
	var lateral = offset * sign_value
	var prediction = metres / metric(stage, station, lateral)
	prediction = metres / metric(stage, station + sign_value * prediction * 0.5, lateral)
	# A step may cross a station boundary with a different metre scale.
	# Correct against the travelled chord rather than trusting one derivative.
	var start = offset_path(stage, station, lateral)
	var end = offset_path(stage, station + sign_value * prediction, lateral)
	var travelled = Vector2(end.x - start.x, end.z - start.z).length()
	if absf(travelled - metres) <= 0.001:
		return prediction
	var low = 0.0
	var high = prediction
	for expansion in range(6):
		if travelled >= metres:
			break
		high *= 2.0
		end = offset_path(stage, station + sign_value * high, lateral)
		travelled = Vector2(end.x - start.x, end.z - start.z).length()
	for iteration in range(14):
		prediction = (low + high) * 0.5
		end = offset_path(stage, station + sign_value * prediction, lateral)
		travelled = Vector2(end.x - start.x, end.z - start.z).length()
		if travelled > metres:
			high = prediction
		else:
			low = prediction
	return prediction
