extends RefCounted
# Small policy layer around Godot rigid bodies used for scenery and camp props.
# Physics may tip an object during an impact, but a nearly stopped object must
# not remain suspended or balanced on an edge forever.
const LINEAR_SLEEP = 0.18
const ANGULAR_SLEEP = 0.22
const GROUND_EPSILON = 0.035
const ALIGN_SPEED = 7.0

static func configure(body: RigidBody3D, upright: bool = true) -> void:
	# Use explicit minimum assignments instead of relying on the project default
	# being readable before the body enters the scene tree (Godot can defer it).
	body.linear_damp = 1.8 if body.linear_damp < 1.8 else body.linear_damp
	body.angular_damp = 3.0 if body.angular_damp < 3.0 else body.angular_damp
	body.sleeping = false
	body.set_meta("settle_upright", upright)
	body.set_meta("settle_grounded", false)

static func update(body: RigidBody3D, ground: float, delta: float) -> bool:
	if body.freeze or not body.is_inside_tree():
		return false
	if body.linear_velocity.length() > LINEAR_SLEEP or body.angular_velocity.length() > ANGULAR_SLEEP:
		body.set_meta("settle_grounded", false)
		return false
	var target_y = ground + _ground_offset(body)
	if body.global_position.y < target_y - GROUND_EPSILON or body.global_position.y > target_y + GROUND_EPSILON:
		return false
	body.global_position.y = target_y
	if bool(body.get_meta("settle_upright", true)):
		var rotation = body.global_rotation
		rotation.x = lerp_angle(rotation.x, 0.0, clampf(delta * ALIGN_SPEED, 0.0, 1.0))
		rotation.z = lerp_angle(rotation.z, 0.0, clampf(delta * ALIGN_SPEED, 0.0, 1.0))
		body.global_rotation = rotation
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.sleeping = true
	body.set_meta("settle_grounded", true)
	return true

static func _half_height(body: RigidBody3D) -> float:
	for child in body.get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D:
			return child.shape.size.y * 0.5
		if child is CollisionShape3D and child.shape is CapsuleShape3D:
			return child.shape.height * 0.5
	return 0.0

static func _ground_offset(body: RigidBody3D) -> float:
	if not bool(body.get_meta("settle_upright", true)):
		return 0.15
	return _half_height(body)
