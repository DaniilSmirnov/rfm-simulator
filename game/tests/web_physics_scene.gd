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
	var reports = []
	await stage.build_async(func(title, amount):
		reports.append([title, amount])
		await get_tree().process_frame)
	if not stage.loaded_baked or reports.size() < 3 or stage.solids.walk_surfaces.is_empty():
		push_error("WEB_PHYSICS_FAIL: prepared village or loading progress missing")
		get_tree().quit(1)
		return
	var grape = stage.collectibles[0]
	var part = stage.collectible_parts.VineyardGrapes[grape.parts.VineyardGrapes[0]]
	if not stage.harvest(0) or part.mesh.get_instance_transform(part.instance).basis.determinant() != 0:
		push_error("WEB_PHYSICS_FAIL: prepared grape instance cannot be harvested")
		get_tree().quit(1)
		return
	if not stage.solids.bell.pull(stage.solids.bell.handle_position()):
		push_error("WEB_PHYSICS_FAIL: prepared bell cannot be pulled")
		get_tree().quit(1)
		return
	print("WEB_BAKED_VILLAGE_PASS: async scene, progress, walking support, harvest and bell")
	await get_tree().physics_frame
	var lamp: RigidBody3D = stage.solids.lamps[0].body
	var before = lamp.position
	stage.solids.knock_lamp(0, Vector3(12, 0, 0))
	for i in range(60):
		await get_tree().physics_frame
	if lamp.position.distance_to(before) > 0.1 and lamp.rotation.length() > 0.01:
		print("WEB_PHYSICS_PASS: exported rigid body moves and tips")
		# Playwright owns the browser lifetime and closes the page after this
		# marker. Quitting Godot here destroys WebAudio while an engine audio
		# callback may still read AudioContext.currentTime, causing a spurious
		# pageerror *after* physics succeeded. Keep the runtime alive until
		# the browser closes the test page normally.
	else:
		push_error("WEB_PHYSICS_FAIL: exported physics backend is inactive")
		get_tree().quit(1)
