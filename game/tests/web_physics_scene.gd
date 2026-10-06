extends Node3D
const Stage = preload("res://scripts/stage.gd")
func _ready() -> void:
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
