extends SceneTree
# Contract shared by every selectable player car, including imported OBJ cars.
const Props = preload("res://scripts/props.gd")
var failures := 0
func check(ok: bool, description: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + description)
	if not ok:
		failures += 1

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	check(Props.PLAYER_MODELS.size() == 10, "ten player vehicles are registered")
	for index in range(Props.PLAYER_MODELS.size()):
		var car: Node3D = Props.player_car(index)
		if car == null:
			check(false, "vehicle %d builds a non-null scene" % index)
			continue
		root.add_child(car)
		check(car.get_meta("variant", -1) == index, "vehicle %d carries correct selection id" % index)
		check(not str(car.get_meta("model", "")).is_empty(), "vehicle %d has a model label" % index)
		var shell_count := 0
		var wheels: Array[Node3D] = []
		var remaining: Array[Node] = [car]
		while not remaining.is_empty():
			var node = remaining.pop_back()
			for child in node.get_children():
				remaining.append(child)
				if child is MeshInstance3D and child.mesh != null:
					shell_count += 1
				if child is Node3D and child.has_meta("rolling_wheel_radius"):
					if child.get_meta("rolling_wheel_radius") is float or child.get_meta("rolling_wheel_radius") is int:
						wheels.append(child)
		check(shell_count > 0, "vehicle %d has visible geometry" % index)
		check(wheels.size() >= 4, "vehicle %d has four rolling wheel surfaces" % index)
		var axle_positions: Dictionary = {}
		for wheel in wheels:
			var radius = float(wheel.get_meta("rolling_wheel_radius"))
			check(radius > 0.20 and radius < 0.80, "vehicle %d wheel radius is plausible" % index)
			var relative = car.to_local(wheel.global_position)
			var key = Vector2i(roundi(relative.x * 10), roundi(relative.z * 10))
			if axle_positions.has(key):
				check(absf(float(axle_positions[key]) - radius) < 0.02,
					"vehicle %d rim and tyre rotate at the same angular speed" % index)
			else:
				axle_positions[key] = radius
		check(axle_positions.size() >= 4, "vehicle %d has two separate axles and both sides" % index)
		var hinge = car.get_node_or_null("TrunkHinge")
		var boxes = car.get_node_or_null("TrunkBoxes")
		check(hinge != null, "vehicle %d exposes an operable trunk hinge" % index)
		check(boxes != null and boxes.get_child_count() == Props.CARGO_KINDS.size(),
			"vehicle %d retains the standard inventory slots" % index)
		if not wheels.is_empty():
			Props.animate_wheels(car)
			var initial = wheels[0].quaternion
			car.position.z -= 1.0
			Props.animate_wheels(car)
			check(not wheels[0].quaternion.is_equal_approx(initial),
				"vehicle %d wheel geometry actually rotates" % index)
		car.queue_free()
		await process_frame
	print("VEHICLE CONTRACT RESULT: %d failures" % failures)
	quit(1 if failures else 0)
