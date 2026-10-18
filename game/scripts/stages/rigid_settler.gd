extends RefCounted
# The contact solver owns resting poses and sleep; low speed alone is not support.
static func configure(body: RigidBody3D, _upright: bool = false) -> void:
	body.linear_damp = 0.35
	body.angular_damp = 0.5
	body.can_sleep = true
	body.continuous_cd = true

static func update(body: RigidBody3D, _ground: float, _delta: float) -> bool:
	return body.sleeping
