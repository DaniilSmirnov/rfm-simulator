extends SceneTree

const Props = preload("res://scripts/props.gd")
const NivaAsset = preload("res://scripts/niva_asset.gd")
var failures = 0

func check(condition: bool, description: String) -> void:
	print(("PASS: " if condition else "FAIL: ") + description)
	if not condition:
		failures += 1

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	check(NivaAsset.has_asset(), "Niva v6 original, static body and tailgate OBJ are available")
	var car: Node3D = Props.player_car(2)
	root.add_child(car)
	check(car.get_meta("model_source", "") == "niva_v6_obj", "variant 2 uses imported Niva v6, not procedural fallback")
	var body: MeshInstance3D = car.get_node_or_null("NivaStaticParts/NivaBody") as MeshInstance3D
	var hinge: Node3D = car.get_node_or_null("TrunkHinge")
	var door: MeshInstance3D = car.get_node_or_null("TrunkHinge/NivaTailgate_Lid") as MeshInstance3D
	check(body != null and body.mesh != null and body.mesh.get_surface_count() > 0, "static body preserves its materials and geometry")
	check(door != null and door.mesh != null and door.mesh.get_surface_count() > 0, "rear hatch is a separate mesh with rear glass")
	check(hinge != null and hinge.get_child_count() == 1, "no rear passenger panels or wheels are parented to trunk hinge")
	if hinge != null and door != null:
		check(hinge.position.distance_to(NivaAsset.HINGE) < 0.001, "rear door hinge located at upper edge of tailgate")
		var door_bounds = door.mesh.get_aabb()
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
	quit(1 if failures > 0 else 0)
