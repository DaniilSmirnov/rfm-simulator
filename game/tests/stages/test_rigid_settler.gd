extends "res://tests/harness.gd"
const Settler = preload("res://scripts/stages/rigid_settler.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var body = RigidBody3D.new()
	var collider = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(2, 1, 1)
	collider.shape = box
	body.add_child(collider)
	root.add_child(body)
	Settler.configure(body)
	body.position = Vector3(0, 0.5, 0)
	body.rotation = Vector3(0.35, 0.2, -0.25)
	body.linear_velocity = Vector3(0.05, 0, 0)
	body.angular_velocity = Vector3(0.05, 0.02, 0.04)
	var pose = body.transform
	Settler.update(body, 0, 1.0 / 30.0)
	check(body.transform == pose, "settling never changes position or restores an upright orientation")
	check(not body.sleeping and body.linear_velocity != Vector3.ZERO and body.angular_velocity != Vector3.ZERO, "a slow unsupported body is left to the physics solver")
	check(body.can_sleep, "native sleeping remains enabled")
	body.queue_free()
	finish()
