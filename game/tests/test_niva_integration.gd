extends "res://tests/harness.gd"

const Props = preload("res://scripts/props.gd")
const NivaAsset = preload("res://scripts/niva_asset.gd")


func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	check(NivaAsset.has_asset(), "Niva v6 original, static body and tailgate OBJ are available")
	var car: Node3D = Props.player_car(2)
	root.add_child(car)
	check(car.get_meta("model_source", "") == "niva_v6_obj", "variant 2 uses imported Niva v6, not procedural fallback")
	# The static body and the tailgate are each baked into one vertex-coloured mesh.
	var body: MeshInstance3D = car.get_node_or_null("Baked") as MeshInstance3D
	var hinge: Node3D = car.get_node_or_null("TrunkHinge")
	var door: MeshInstance3D = car.get_node_or_null("TrunkHinge/BakedLid") as MeshInstance3D
	check(body != null and body.mesh != null and body.mesh.get_surface_count() > 0 and car.get_meta("baked_parts", {}).has("NivaBody"), "static body preserves its geometry in the baked mesh")
	check(door != null and door.mesh != null and door.mesh.get_surface_count() > 0 and hinge.get_meta("baked_parts", {}).has("NivaTailgate_Lid"), "rear hatch is a separate mesh with rear glass")
	check(hinge != null and hinge.get_child_count() == 1, "no rear passenger panels or wheels are parented to trunk hinge")
	var wheels: Array[Node3D] = []
	for part in car.get_node("NivaStaticParts").get_children():
		if part.has_meta("rolling_wheel_radius"):
			wheels.append(part)
	check(wheels.size() == 8, "four Niva wheels each have rubber and metal meshes with rotating pivots")
	if not wheels.is_empty():
		Props.animate_wheels(car)
		var wheel_start: Quaternion = wheels[0].quaternion
		car.position.z -= 1.0
		Props.animate_wheels(car)
		check(not wheels[0].quaternion.is_equal_approx(wheel_start), "Niva wheels turn when driving forwards")
		car.position.z += 1.0
		Props.animate_wheels(car)
		check(wheels[0].quaternion.is_equal_approx(wheel_start), "Niva wheel rotation reverses while backing up")
	if hinge != null and door != null:
		check(hinge.position.distance_to(NivaAsset.HINGE) < 0.001, "rear door hinge located at upper edge of tailgate")
		var door_bounds: AABB = hinge.get_meta("baked_parts").NivaTailgate_Lid
		door_bounds.position += NivaAsset.HINGE
		check(door_bounds.position.z > 1.37 and door_bounds.end.z <= 1.90, "animated door does not contain rear seats, side windows or roof")
		check(door_bounds.position.x >= -0.69 and door_bounds.end.x <= 0.69, "animated hatch excludes side wings and rear lamp mounts")
		check(door_bounds.position.y > 0.74, "animated hatch excludes rear bumper and wheel arches")
		check(body.get_parent() != hinge and body.transform == Transform3D.IDENTITY, "main body remains fixed during hatch rotation")
		var cargo: Node3D = car.get_node("TrunkBoxes")
		check(cargo.get_child_count() == Props.CARGO_KINDS.size(), "five original cargo resources remain available")
		Props.update_player_trunk(car, true, [true, false, true, true, true], 0.25)
		check(hinge.rotation.x < -0.1 and hinge.rotation.x > -1.18, "Niva tailgate opens progressively")
		Props.update_player_trunk(car, true, [true, false, true, true, true], 1.0)
		check(hinge.rotation.x < -1.17 and cargo.visible and not cargo.get_child(1).visible, "Niva trunk opens fully and shows only stored cargo")
		check(body.transform == Transform3D.IDENTITY and car.get_node("NivaStaticParts").transform == Transform3D.IDENTITY, "opening hatch does not rotate passenger compartment")
		Props.update_player_trunk(car, false, [true, true, true, true, true], 1.0)
		check(absf(hinge.rotation.x) < 0.01 and not cargo.visible, "Niva hatch closes and conceals cargo")
	car.queue_free()
	await process_frame
	print("NIVA INTEGRATION RESULT: %d failures" % failures)
	finish()
