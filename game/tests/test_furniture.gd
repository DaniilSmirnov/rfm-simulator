extends SceneTree
var failures = 0
func check(ok: bool, title: String) -> void:
	if not ok:
		failures += 1
		push_error(title)
	else:
		print("PASS: " + title)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var host = load("res://main.tscn").instantiate()
	var guest = load("res://main.tscn").instantiate()
	for game in [host, guest]:
		root.add_child(game)
	await process_frame
	for game in [host, guest]:
		game.set_process(false)
		game.room.set_process(false)
		game.start_game()
		game.in_car = false
		game.stage.trees.clear()
		game.room.connected = true
	host.room.is_host = true
	host.room.player_id = "host"
	guest.room.player_id = "guest"
	var origin = host.stage.clearings[0]
	host.walker = origin
	check(host.place_table(origin, 0.5), "table can be positioned and rotated freely")
	var chair_pos = origin + Vector3(3, 0, 0)
	check(host.place_chairs(chair_pos, 0.8), "host places one personal chair")
	check(host.place_chairs(chair_pos + Vector3(0, 0, 2), 1.2) and host.personal_chairs.size() == 1, "repositioning never duplicates a personal chair")
	var command = {"player": "guest", "action": "chairs", "state": {"in_car": false, "pos": host.room.a(origin), "car": host.room.a(host.car.position), "yaw": 0}, "placement": {"pos": host.room.a(origin + Vector3(-3, 0, 0)), "yaw": -0.7}}
	host.cargo.held["guest"] = {"kind": "chairs", "owner": "guest", "returning": false}
	host.room._apply_command(command)
	check(host.personal_chairs.has("guest") and host.personal_chairs.size() == 2, "guest chair has a separate authenticated owner")
	check(host.start_grill(origin + Vector3(0, 0, -3), 0.9), "grill has an independent position")
	check(host.grill.get_child_count() >= 11 and int(host.grill.get_meta("servings")) == 10, "new grill starts with ten visible skewers")
	host.cook_time = 12
	check(host.start_grill(origin + Vector3(0, 0, -4), 1.4) and host.cook_time == 12, "moving grill preserves cooking progress")
	host.place_table(origin + Vector3(0, 0, 1), 1.0)
	var snapshot = host.room.world_state()
	guest.room.apply_world(snapshot)
	check(guest.personal_chairs.size() == 2 and guest.has_personal_chair(), "late guest receives both chairs and recognizes their own")
	check(guest.grill.position.distance_to(host.grill.position) < 0.03 and absf(guest.grill.rotation.y - 1.4) < 0.01, "grill placement and rotation replicate")
	guest.room.apply_world(snapshot)
	check(guest.personal_chairs.size() == 2, "repeated snapshots never duplicate chairs")
	check(not host.valid_furniture_spot(host.stage.at(140), "table"), "furniture cannot be placed on rally road")
	host.walker = origin + Vector3(0, 0, 6)
	host.begin_placement("flag")
	check(host.placement_preview.get_child_count() == 1 and host.placement_preview.find_children("*", "MeshInstance3D", true, false).size() == 6, "flag preview has its pole, opaque cloth and four text meshes attached to the scene")
	host.cancel_placement()
	check(host.place_flag(host.walker + Vector3(2, 0, 0), 0.0), "first personal Rally Fans Map flag can be placed")
	var placed_flag = host.personal_flags["host"][0]
	var flag_cloth = placed_flag.get_child(1)
	check(placed_flag.get_parent() == host and flag_cloth.is_visible_in_tree(), "placed flag and cloth are visible in the game scene")
	var rally_labels = 0
	var maps_labels = 0
	var visible_wordmarks = true
	var text_count = 0
	for node in placed_flag.find_children("*", "MeshInstance3D", true, false):
		if not node.has_meta("wordmark"):
			continue
		text_count += 1
		rally_labels += int(node.get_meta("wordmark") == "RALLY")
		maps_labels += int(node.get_meta("wordmark") == "FANS MAP")
		visible_wordmarks = visible_wordmarks and node.is_visible_in_tree() and not node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].is_empty()
		visible_wordmarks = visible_wordmarks and node.material_override.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and absf(node.position.z) >= 0.03
		check(absf(wrapf(node.rotation.y - (PI if node.position.z < 0 else 0.0), -PI, PI)) < 0.001, "text faces outward without mirroring")
	check(visible_wordmarks and text_count == 4 and rally_labels == 2 and maps_labels == 2, "Rally Fans Map has opaque vector text on both faces")
	check(placed_flag.find_children("*", "Label3D", true, false).is_empty() and flag_cloth.material_override.albedo_texture == null, "flag has no icon texture or transparent text layer")
	check(flag_cloth.mesh is ArrayMesh and flag_cloth.material_override.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and flag_cloth.material_override.cull_mode == BaseMaterial3D.CULL_DISABLED, "flag silhouette is opaque geometry visible on both sides")
	check(host.flag_count() == 1, "flag count is tracked per player")
	check(host.place_flag(host.walker + Vector3(3, 0, 0), 0.4), "second personal flag can be placed")
	check(host.place_flag(host.walker + Vector3(4, 0, 0), 0.8), "third personal flag can be placed")
	check(not host.place_flag(host.walker + Vector3(5, 0, 0), 1.2), "fourth flag is rejected")
	guest.room.apply_world(host.room.world_state())
	var replicated_flags: Array = guest.personal_flags.get("host", [])
	check(replicated_flags.size() == 3, "guest receives all three placed flags")
	var flags_visible = replicated_flags.size() == 3
	for flag in replicated_flags:
		flags_visible = flags_visible and flag.get_parent() == guest and flag.get_child(1).is_visible_in_tree()
	check(flags_visible, "replicated flag poles and cloth belong to the guest scene")
	guest.room.apply_world(host.room.world_state())
	check(guest.personal_flags.get("host", []).size() == 3, "repeated snapshots do not duplicate flags")
	for game in [host, guest]:
		await game._shutdown_audio()
		game.queue_free()
	await process_frame
	quit(1 if failures else 0)
