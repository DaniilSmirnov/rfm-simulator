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

static func departure(racer: Dictionary, direction: Vector3, side: Vector3, bend: float) -> void:
	# Keep forward and lateral momentum: never aim an accident at the spectator.
	racer.motion.velocity = direction * racer.drive_speed + side * racer.slide_speed
	var outward = signf(racer.slide_speed) if absf(racer.slide_speed) > 0.5 else signf(bend)
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
