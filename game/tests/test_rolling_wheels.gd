extends SceneTree
var failed := 0

func verify(ok: bool, message: String) -> void:
	if not ok:
		failed += 1
		push_error(message)
	else:
		print("PASS: " + message)

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
	verify(wheel != null, "player car includes rolling wheel mesh")
	if wheel == null:
		quit(1)
		return
	props.animate_wheels(car)
	var start_rotation = wheel.quaternion
	car.position.z -= 1.0
	props.animate_wheels(car)
	verify(not wheel.quaternion.is_equal_approx(start_rotation), "moving forwards rotates wheels")
	var forward_rotation = wheel.quaternion
	car.position.z += 1.0
	props.animate_wheels(car)
	verify(wheel.quaternion.is_equal_approx(start_rotation), "driving backward reverses rotation")
	props.animate_wheels(car)
	verify(wheel.quaternion.is_equal_approx(start_rotation), "idle car wheels do not rotate")
	car.position.z -= 100
	props.animate_wheels(car)
	verify(wheel.quaternion.is_equal_approx(start_rotation), "teleports do not spin wheels")
	car.free()

	var rally = props.rally_car(0)
	root.add_child(rally)
	props.animate_wheels(rally)
	var rally_part: Node3D = null
	for part in rally.find_children("*", "Node3D", true, false):
		if part is Node3D and part.has_meta("rolling_wheel_radius") and not part.get_meta("rolling_wheel_radius") is String:
			rally_part = part
			break
	verify(rally_part != null, "rally car includes rolling wheel mesh")
	if rally_part == null:
		quit(1)
		return
	var before = rally_part.quaternion
	rally.position.z -= 2
	props.animate_wheels(rally)
	verify(not rally_part.quaternion.is_equal_approx(before), "moving rally car spins wheels")
	rally.free()

	print("ROLLING WHEELS RESULT: %d failures" % failed)
	quit(1 if failed else 0)
