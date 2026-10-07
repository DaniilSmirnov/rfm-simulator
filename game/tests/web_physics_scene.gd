extends Node3D
const Stage = preload("res://scripts/stage.gd")
const Motion = preload("res://scripts/vehicle_motion.gd")
func _ready() -> void:
	var motion = Motion.new()
	var heading = 0.0
	for step in range(120):
		heading = motion.handling.advance(motion, heading, 1, 0.5, false, 0.78, 19, 0, motion.handling.STEP)
	if not motion.velocity.is_finite() or motion.velocity.length() < 1 or heading >= -0.01:
		push_error("WEB_PHYSICS_FAIL: player tyre model failed in exported Web game")
		get_tree().quit(1)
		return
	print("WEB_HANDLING_PASS: exported player accelerates and steers")
	var stage = Stage.new(2)
	add_child(stage)
	stage.build()
	await get_tree().physics_frame
	var lamp: RigidBody3D = stage.city.lamps[0].body
	var before = lamp.position
	stage.city.knock_lamp(0, Vector3(12, 0, 0))
	for i in range(60):
		await get_tree().physics_frame
	if lamp.position.distance_to(before) > 0.1 and lamp.rotation.length() > 0.01:
		print("WEB_PHYSICS_PASS: exported rigid body moves and tips")
		get_tree().quit()
	else:
		push_error("WEB_PHYSICS_FAIL: exported physics backend is inactive")
		get_tree().quit(1)
