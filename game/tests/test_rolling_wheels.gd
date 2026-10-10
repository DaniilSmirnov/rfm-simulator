extends "res://tests/harness.gd"


func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var props = load("res://scripts/props.gd")
	var car = props.player_car(0)
	root.add_child(car)
	var wheel: Node3D = null
	for part in car.find_children("*", "Node3D", true, false):
		if part is Node3D and part.has_meta("rolling_wheel_radius") and not part.get_meta("rolling_wheel_radius") is String:
			wheel = part
			break
	check(wheel != null, "player car includes rolling wheel pivot")
	if wheel == null:
		# A missing wheel must fail promptly instead of crashing and hanging CI.
		car.free()
		quit(1)
		return
	var wheel_count = 0
	for part in car.get_children():
		if part is Node3D and part.has_meta("rolling_wheel_radius"):
			wheel_count += 1
	check(wheel_count == 4, "Granta has four independently rotating wheels")
	check(wheel.get_node_or_null("WheelMesh") != null,
		"tyre, rim and spokes are one mesh on the rolling pivot")
	props.animate_wheels(car)
	var start_rotation = wheel.quaternion
	car.position.z -= 1.0
	props.animate_wheels(car)
	check(not wheel.quaternion.is_equal_approx(start_rotation), "moving forwards rotates wheels")
	var forward_rotation = wheel.quaternion
	car.position.z += 1.0
	props.animate_wheels(car)
	check(wheel.quaternion.is_equal_approx(start_rotation), "driving backward reverses rotation")
	props.animate_wheels(car)
	check(wheel.quaternion.is_equal_approx(start_rotation), "idle car wheels do not rotate")
	car.position.z -= 100
	props.animate_wheels(car)
	check(wheel.quaternion.is_equal_approx(start_rotation), "teleports do not spin wheels")
	car.free()

	var rally = props.rally_car(0)
	root.add_child(rally)
	props.animate_wheels(rally)
	var rally_part: Node3D = null
	for part in rally.find_children("*", "Node3D", true, false):
		if part is Node3D and part.has_meta("rolling_wheel_radius") and not part.get_meta("rolling_wheel_radius") is String:
			rally_part = part
			break
	check(rally_part != null, "rally car includes rolling wheel mesh")
	if rally_part == null:
		rally.free()
		quit(1)
		return
	var before = rally_part.quaternion
	rally.position.z -= 2
	props.animate_wheels(rally)
	check(not rally_part.quaternion.is_equal_approx(before), "moving rally car spins wheels")
	rally.free()

	# Every car in every fleet: the tread top moves forward when the car does,
	# and the wheel carries visible detail (not a bare cylinder) on its pivot.
	var builders: Array = []
	for i in range(props.PLAYER_MODELS.size()):
		builders.append(func(): return props.player_car(i))
	for i in range(props.RALLY_MODELS.size()):
		builders.append(func(): return props.rally_car(i))
	for role in ["police", "zero"]:
		builders.append(func(): return props.course_car(role, 1))
	for build in builders:
		var vehicle: Node3D = build.call()
		root.add_child(vehicle)
		var label = str(vehicle.get_meta("model", vehicle.name))
		var wheels: Array = []
		for part in vehicle.find_children("*", "Node3D", true, false):
			if part.has_meta("rolling_wheel_radius") and not part.get_meta("rolling_wheel_radius") is String:
				wheels.append(part)
		check(wheels.size() >= 4, "%s has four rolling wheels" % label)
		var detailed = 0
		for part in wheels:
			# A bare 16-sided cylinder has 192 face vertices; patterned wheels have far more.
			var meshes: Array = part.find_children("*", "MeshInstance3D", true, false)
			if part is MeshInstance3D:
				meshes.append(part)
			for child in meshes:
				if child.mesh != null and child.mesh.get_faces().size() > 300:
					detailed += 1
					break
		check(detailed >= 4, "%s wheels carry spokes or holes on the pivot" % label)
		props.animate_wheels(vehicle)
		var probe: Node3D = wheels[0] if not wheels.is_empty() else vehicle
		var top_before = probe.global_transform * Vector3(0, 0.3, 0)
		vehicle.position.z -= 0.1
		props.animate_wheels(vehicle)
		var top_after = probe.global_transform * Vector3(0, 0.3, 0) + Vector3(0, 0, 0.1)
		check(top_after.z < top_before.z - 0.01, "%s tread top rolls forward when driving forward" % label)
		vehicle.free()

	print("ROLLING WHEELS RESULT: %d failures" % failures)
	finish()
