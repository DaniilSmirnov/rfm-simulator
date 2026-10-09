extends RefCounted
# Small deterministic solver: tyre friction, inertia and unilateral spring contact.
var handling = preload("res://scripts/player_handling.gd").new()
var drive_clock = 0.0
var velocity = Vector3.ZERO
var vertical_speed = 0.0
var grounded = true
var initialized = false
var pitch = 0.0
var roll = 0.0

func suspension(node: Node3D, stage, delta: float, yaw: float, lateral_accel: float = 0.0) -> void:
	var forward = Vector3(-sin(yaw), 0, -cos(yaw))
	var right = forward.cross(Vector3.UP)
	var snowy = stage.has_method("vehicle_ground") and stage.winter
	var front: float = stage.vehicle_ground(node.position + forward * 1.15) if snowy else stage.ground(node.position + forward * 1.15)
	var rear: float = stage.vehicle_ground(node.position - forward * 1.15) if snowy else stage.ground(node.position - forward * 1.15)
	var left: float = stage.vehicle_ground(node.position - right * 0.7) if snowy else stage.ground(node.position - right * 0.7)
	var opposite: float = stage.vehicle_ground(node.position + right * 0.7) if snowy else stage.ground(node.position + right * 0.7)
	var floor_height: float = (front + rear + left + opposite) * 0.25 + 0.06
	if not initialized:
		node.position.y = floor_height
		initialized = true
	var steps = maxi(1, int(ceil(delta / (1.0 / 120.0))))
	var dt = delta / steps
	for i in range(steps):
		var compression = floor_height - node.position.y
		grounded = compression > -0.12
		var force = maxf(0, 160.0 * (compression + 0.10) - 13.0 * vertical_speed) if grounded else 0.0
		vertical_speed += (force - 16.0) * dt
		node.position.y += vertical_speed * dt
		if node.position.y < floor_height - 0.17:
			node.position.y = floor_height - 0.17
			vertical_speed = maxf(0, -vertical_speed * 0.15)
	pitch = lerpf(pitch, atan2(front - rear, 2.3), 1.0 - exp(-delta * 9))
	roll = lerpf(roll, clampf(atan2(opposite - left, 1.4) - lateral_accel * 0.012, -0.24, 0.24), 1.0 - exp(-delta * 8))
	node.rotation = Vector3(pitch, yaw, roll)
	if snowy and grounded:
		var thickness: float = stage.snow.loose_depth(stage, node.position)
		if thickness > 0.001:
			var compression: float = stage.snow.packed(node.position)
			velocity = velocity.move_toward(Vector3.ZERO, thickness * lerpf(2.2, 0.35, compression) * delta)
			for wheel in [node.position + forward * 1.15 - right * 0.7, node.position + forward * 1.15 + right * 0.7, node.position - forward * 1.15 - right * 0.7, node.position - forward * 1.15 + right * 0.7]:
				stage.snow.stamp(stage, wheel, delta * 0.35)


static func swept_hit(start: Vector3, end: Vector3, target: Vector3, radius: float) -> bool:
	var segment = end - start
	var t = clampf((target - start).dot(segment) / maxf(segment.length_squared(), 0.0001), 0, 1)
	return (start + segment * t).distance_to(target) < radius

# Preserve tangential momentum instead of reversing the whole velocity.
func rock_impulse(normal: Vector3, yaw: float) -> float:
	var closing = maxf(0.0, -velocity.dot(normal))
	if closing <= 0.001:
		return 0.0
	velocity += normal * closing * 1.25
	velocity *= 0.82
	vertical_speed = maxf(vertical_speed, minf(2.8, closing * 0.17))
	var right = Vector3(-sin(yaw), 0, -cos(yaw)).cross(Vector3.UP)
	roll = clampf(roll + normal.dot(right) * closing * 0.018, -0.35, 0.35)
	pitch = clampf(pitch - closing * 0.008, -0.35, 0.35)
	return closing
