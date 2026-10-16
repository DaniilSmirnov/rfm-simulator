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
	# Godot stores these properties as float32: 1.8 reads back just below 1.8.
	check(is_equal_approx(body.linear_damp, 1.8) and is_equal_approx(body.angular_damp, 3.0), "dynamic objects receive the configured damping to settle")
	body.position = Vector3(0, 0.5, 0)
	body.rotation = Vector3(0.35, 0.2, -0.25)
	body.linear_velocity = Vector3(0.05, 0, 0)
	body.angular_velocity = Vector3(0.05, 0.02, 0.04)
	check(Settler.update(body, 0, 1.0 / 30.0), "slow object settles when its collider reaches the ground")
	check(absf(body.position.y - 0.5) < 0.001 and absf(body.rotation.x) < 0.35 and absf(body.rotation.z) < 0.25, "upright object is clamped and gradually aligned")
	check(body.sleeping and body.linear_velocity == Vector3.ZERO and body.angular_velocity == Vector3.ZERO, "settled object sleeps without residual movement")
	body.queue_free()
	finish()
