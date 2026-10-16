extends "res://tests/harness.gd"
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
	check(host.grill.get_child_count() >= 11 and int(host.grill.get_meta("servings")) == 0 and not host.camp_grill.lit, "a new grill is cold and empty")
	host.camp_grill.lit = true
	host.camp_grill.fire_time = 12
	check(host.start_grill(origin + Vector3(0, 0, -4), 1.4) and host.camp_grill.fire_time == 12, "moving grill preserves its fire")
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
	# Find an actual permitted hillside rather than a flattened camp clearing.
	var slope = Vector3.INF
	for x in range(-180, 181, 6):
		for z in range(-180, 181, 6):
			var candidate = Vector3(x, 0, z)
			candidate.y = host.stage.ground(candidate)
			var up = host.stage.terrain_basis(candidate, 0.0, host.stage.ground).y
			if up.dot(Vector3.UP) < 0.98 and up.dot(Vector3.UP) > 0.85 and host.valid_furniture_spot(candidate, "table"):
				slope = candidate
				break
		if slope != Vector3.INF:
			break
	check(slope != Vector3.INF, "a permitted sloping campsite exists")
	if slope != Vector3.INF:
		host.walker = slope
		var yaw = 0.7
		var expected = host.stage.terrain_basis(slope, yaw, host.stage.ground)
		check(host.place_table(slope, yaw), "table can be moved onto a hillside")
		check(host.camp.basis.is_equal_approx(expected), "placed table follows both slope axes")
		host.walker = slope + Vector3(sin(host.view_yaw), 0, cos(host.view_yaw)) * 2.5
		host.placement_preview = Node3D.new()
		host.add_child(host.placement_preview)
		host.placement_kind = "flag"
		host.placement_yaw = yaw
		host.camp_actions.update_placement()
		check(host.placement_preview.basis.is_equal_approx(expected), "preview uses the same terrain tilt as installed gear")
		host.cancel_placement()
		# Exercise all models through the common pose operation, including reset
		# from a slope to a level clearing and repeated snapshot reconstruction.
		for node in [host.camp, host.personal_chairs["host"], host.grill, placed_flag]:
			host.camp_actions.ground_item(node, slope, yaw)
			host.camp_actions.ground_item(node, origin, -0.4)
			check(node.basis.y.is_equal_approx(Vector3.UP), "returning to level ground clears the previous tilt")
			host.camp_actions.ground_item(node, slope, yaw)
		host.walker = slope
		check(host.camp_cooking.deploy_fire(slope + Vector3(4, 0, 0), yaw), "fire can be deployed beside a hillside camp")
		var fire = host.camp_cooking.fire
		if fire != null:
			host.walker = fire.position
			check(host.camp_cooking.place_pot(fire.position, yaw), "pot can be placed over a hillside fire")
			check(fire.basis.is_equal_approx(host.camp_cooking.pot.basis), "pot and fire share the slope")
		var sloped_snapshot = host.room.world_state()
		for repeat in range(2):
			guest.room.apply_world(sloped_snapshot)
			for pair in [[host.camp, guest.camp], [host.personal_chairs["host"], guest.personal_chairs["host"]], [host.grill, guest.grill], [placed_flag, guest.personal_flags["host"][0]], [fire, guest.camp_cooking.fire], [host.camp_cooking.pot, guest.camp_cooking.pot]]:
				if pair[0] != null and pair[1] != null:
					check(pair[0].basis.is_equal_approx(pair[1].basis), "repeated room snapshots preserve slope and heading")
	for game in [host, guest]:
		await game._shutdown_audio()
		game.queue_free()
	await process_frame
	finish()
