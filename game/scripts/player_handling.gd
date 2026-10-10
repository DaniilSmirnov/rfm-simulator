extends RefCounted
# Game-tuned two-axle tyre model. Forces are accelerations (mass-normalized).
# Positive steering/yaw_rate turns right; Godot's heading turns left.
var steering = 0.0
var yaw_rate = 0.0
var slip = 0.0
var longitudinal_accel = 0.0
var lateral_accel = 0.0
const STEP = 1.0 / 120.0

const CarRegistry = preload("res://scripts/car_registry.gd")

# Deliberate handling differences, not claimed factory specifications; the
# values live with each car in res://data/cars.json.
static func profile(variant: int) -> Dictionary:
	var handling: Dictionary = CarRegistry.car(variant).handling
	return {"rear_bias": CarRegistry.rear_bias(variant), "wheelbase": float(handling.wheelbase), "acceleration": float(handling.acceleration), "inertia": float(handling.inertia)}

func advance(motion, heading: float, throttle: float, steer: float, brake: bool, grip: float, max_speed: float, variant: int, dt: float) -> float:
	var spec = profile(variant)
	var forward = Vector3(-sin(heading), 0, -cos(heading))
	var right = forward.cross(Vector3.UP)
	var longitudinal: float = motion.velocity.dot(forward)
	var lateral: float = motion.velocity.dot(right)
	var magnitude = absf(longitudinal)
	var target_steering = clampf(steer, -1, 1) * lerpf(0.48, 0.22, clampf(magnitude / 20, 0, 1))
	steering = move_toward(steering, target_steering, dt * 1.8)
	var adhesion = maxf(0.05, grip) * 12.0 if motion.grounded else 0.0
	var drive: float = throttle * float(spec.acceleration)
	# Opposite pedal brakes first; reverse engages only after slowing down.
	if throttle * longitudinal < -0.2:
		drive = throttle * 10.0
	var limit = max_speed if throttle >= 0 else max_speed * 0.4
	if throttle * longitudinal > 0 and magnitude > limit:
		drive *= clampf((limit + 1.0 - magnitude), 0, 1)
	var resistance = (0.65 + magnitude * magnitude * 0.008) * signf(longitudinal)
	if brake:
		drive = -signf(longitudinal) * 16.0
	var transfer = clampf(-longitudinal_accel * 0.014, -0.12, 0.16)
	var front_load = 0.52 + transfer
	var front_capacity = adhesion * front_load
	var rear_capacity = adhesion * (1.0 - front_load)
	var front_drive: float = drive * (1.0 - float(spec.rear_bias))
	var rear_drive: float = drive * float(spec.rear_bias)
	if brake or throttle * longitudinal < -0.2:
		front_drive = drive * 0.65
		rear_drive = drive * 0.35
	var traction_share = 0.96 if brake else 0.85
	front_drive = clampf(front_drive, -front_capacity * traction_share, front_capacity * traction_share)
	rear_drive = clampf(rear_drive, -rear_capacity * traction_share, rear_capacity * traction_share)
	var front_grip = sqrt(maxf(0, front_capacity * front_capacity - front_drive * front_drive))
	var rear_grip = sqrt(maxf(0, rear_capacity * rear_capacity - rear_drive * rear_drive))
	var axle: float = float(spec.wheelbase) * 0.5
	var front_slip = atan2(lateral + yaw_rate * axle, maxf(1.5, magnitude)) - steering * signf(longitudinal)
	var rear_slip = atan2(lateral - yaw_rate * axle, maxf(1.5, magnitude))
	var front_force = clampf(-front_slip * 23.0, -front_grip, front_grip)
	var rear_force = clampf(-rear_slip * 25.0, -rear_grip, rear_grip)
	longitudinal_accel = front_drive * cos(steering) + rear_drive - front_force * sin(steering) - (resistance if motion.grounded else 0.0)
	lateral_accel = front_force * cos(steering) + front_drive * sin(steering) + rear_force
	var next_longitudinal = longitudinal + longitudinal_accel * dt
	if (brake or is_zero_approx(throttle)) and longitudinal * next_longitudinal < 0:
		next_longitudinal = 0
	if brake and magnitude < 0.08:
		next_longitudinal = 0
	if magnitude < 2.5 and motion.grounded:
		# Parking/reversing remains controllable without unstable low-speed slip angles.
		yaw_rate = lerpf(yaw_rate, longitudinal * tan(steering) / float(spec.wheelbase), 1 - exp(-dt * 10))
		lateral = move_toward(lateral, 0, adhesion * dt)
	else:
		yaw_rate += (front_force - rear_force) * axle / float(spec.inertia) * dt
		yaw_rate *= exp(-dt * (0.45 if motion.grounded else 0.1))
		lateral += lateral_accel * dt
	yaw_rate = clampf(yaw_rate, -2.2, 2.2)
	motion.velocity = forward * next_longitudinal + right * lateral
	slip = atan2(lateral, maxf(1.0, magnitude))
	return heading - yaw_rate * dt
