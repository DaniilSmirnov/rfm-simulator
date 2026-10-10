extends "res://tests/harness.gd"
const Stage = preload("res://scripts/stage.gd")
const RallyProps = preload("res://scripts/props.gd")
# Names and bounds of the parts baked into a car's (or hinge's) merged mesh.
func baked(node: Node) -> Dictionary:
	return node.get_meta("baked_parts", {}) if node != null else {}

func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var collision = Stage.new()
	collision.trees.append(Vector3.ZERO)
	collision.forest_data.append({"height": 8.0})
	check(collision.obstacle_hit(Vector3(-3, 0, 0), Vector3(3, 0, 0), 0.95, true) == 0, "escape allowance preserves swept impact from outside")
	check(collision.obstacle_hit(Vector3(0, 0, 0.5), Vector3(0, 0, 0.7), 0.95, true) == -1, "overlapping car can reverse away from standing tree")
	check(collision.obstacle_hit(Vector3(0, 0, 0.5), Vector3(0, 0, 0.3), 0.95, true) == 0, "overlapping car cannot drive deeper into tree")
	collision.fell(0, Vector3.RIGHT)
	collision.fallen[0].age = 1.3
	check(collision.obstacle_hit(Vector3(2, 0, 0.1), Vector3(2, 0, 0.2), 0.95, true) == -1, "car can escape fully fallen trunk volume")
	check(collision.obstacle_hit(Vector3(2, 0, 0.1), Vector3(2, 0, 0), 0.95, true) == 0, "fallen trunk still blocks motion toward its axis")
	check(collision.obstacle_hit(Vector3(2, 0, 0.1), Vector3(2, 0, -0.3), 0.95, true) == 0, "escape cannot tunnel across trunk to opposite side")
	collision.free()
	var host = load("res://main.tscn").instantiate()
	var guest = load("res://main.tscn").instantiate()
	for game in [host, guest]:
		root.add_child(game)
	await process_frame
	for game in [host, guest]:
		game.set_process(false)
		game.room.set_process(false)
	check(host.car_choice.item_count == 10 and host.stage_choice.item_count == 5, "menu offers ten cars and five stages")
	check(host.car.get_meta("model_source", "") == "granta_detailed" and host.car.get_meta("variant", -1) == 0, "first vehicle uses standalone detailed Granta model")
	check(baked(host.car).has("BodyShellGranta") and host.car.get_node_or_null("TrunkHinge") != null, "detailed Granta preserves body and animated trunk")
	var original_granta_hinge = host.car.get_node("TrunkHinge")
	RallyProps.update_player_trunk(host.car, true, [true, true, true, true, true], 1.0)
	check(original_granta_hinge.rotation.x < -0.8, "detailed Granta trunk opens")
	RallyProps.update_player_trunk(host.car, false, [true, true, true, true, true], 1.0)
	check(absf(original_granta_hinge.rotation.x) < 0.01, "detailed Granta trunk closes")
	host.car_choice.cycle(-1)
	check(host.selected_car == 9 and host.car.get_meta("model") == "Спортивный седан", "previous arrow wraps to red Sport F80")
	host.select_player_car(8)
	var obj_asset_script = load("res://scripts/camping_hatchback_asset.gd")
	check(obj_asset_script.PARTS.size() == 8, "camping hatchback supports eight independently imported OBJ parts")
	check(host.car.get_meta("roof_cargo", "") == "inflatable_boat", "camping hatchback retains inflatable roof boat configuration")
	var camping_lid = host.car.get_node_or_null("TrunkHinge")
	var imported_lid_names = ["BodyShellHatchback_Lid", "Camping_glass_Lid", "Camping_trim_Lid", "Camping_lights_Lid"]
	var imported_hatch_complete = camping_lid != null
	# The lid parts are baked into one mesh on the hinge; their bounds stay in its meta.
	var lid_parts: Dictionary = baked(camping_lid) if camping_lid != null else {}
	for lid_name in imported_lid_names:
		imported_hatch_complete = imported_hatch_complete and lid_parts.has(lid_name)
	check(imported_hatch_complete and camping_lid.get_node_or_null("BakedLid") != null, "imported hatch moves rear body, glass, trim and lamps together")
	var rear_hatch_only = imported_hatch_complete
	for lid_name in lid_parts:
		var box: AABB = lid_parts[lid_name]
		if box.position.z + camping_lid.position.z < 1.19:
			rear_hatch_only = false
	check(rear_hatch_only, "2112 trunk lid contains only the rear hatch, never passenger cabin panels")
	var body_parts = baked(host.car)
	var boat_static = body_parts.has("Camping_boat")
	check(body_parts.has("Camping_headlights") and body_parts.Camping_headlights.get_center().z < -1.0, "imported OBJ parts rotate 180 degrees to match game driving direction")
	check(lid_parts.has("Camping_glass_Lid"), "rear glazing remains attached to the hatch after correcting forward axis")
	check(boat_static and not lid_parts.has("Camping_boat_Lid"), "inflatable roof boat remains fixed when trunk opens")
	var original_hatch_position = camping_lid.transform if camping_lid != null else Transform3D.IDENTITY
	RallyProps.update_player_trunk(host.car, true, [true, true, true, true, true], 1.0)
	check(camping_lid != null and camping_lid.rotation.x < -0.8 and host.car.get_node("TrunkBoxes").visible, "imported rear hatch opens and exposes stored cargo")
	RallyProps.update_player_trunk(host.car, false, [true, true, true, true, true], 1.0)
	check(camping_lid != null and absf(camping_lid.rotation.x) < 0.01, "imported rear hatch closes completely")
	check(baked(host.car).has("BodyShellHatchback") and host.car.get_node_or_null("RoofHatchback") != null, "2112 has dedicated body, short roof and sloped-glasshouse geometry")
	host.car_choice.select(9)
	host.car_choice.cycle(1)
	check(host.selected_car == 0, "next arrow returns to first car")
	host.car_choice.item_selected.emit(5)
	host.stage_choice.item_selected.emit(1)
	check(host.car.get_meta("model") == "Дорожный седан" and host.stage.winter, "menu selection applies car and winter terrain before start")
	var summer = Stage.new()
	check(host.stage.at(310).distance_to(summer.at(310)) > 15, "winter stage has its own alignment and elevation")
	check(host.stage.grip(host.stage.at(310)) < summer.grip(summer.at(310)), "winter surface has lower grip")
	summer.free()
	var city = Stage.new(2)
	city.build()
	check(city.provence and city.clearings.size() == 4, "Provençal village stage has four spectator spots")
	var counts: Dictionary = city.village.counts
	check(int(counts.get("houses", 0)) >= 40 and city.get_node_or_null("VillageChurch") != null, "village has terraced stone houses and a church")
	var grape_collectibles = city.collectibles.filter(func(item): return item.get("name", "") == "виноград")
	check(int(counts.get("vines", 0)) > 500 and grape_collectibles.size() == int(counts.vines)
		and int(counts.get("lavender", 0)) > 1000,
		"lavender plateau before the village, collectible grapes in the vineyards after it")
	city.free()
	guest.select_player_car(2)
	host.room.transport.request_kind = "create"
	host.room._response(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify({"player": "host", "token": "h", "host": true, "room": "ABC123", "slot": 0, "car_model": 5, "stage": 1}).to_utf8_buffer())
	guest.room.transport.request_kind = "join"
	guest.room._response(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify({"player": "guest", "token": "g", "host": false, "slot": 1, "car_model": 2, "stage": 1}).to_utf8_buffer())
	check(guest.stage.winter and guest.playing and not guest.selection_controls.visible, "guest enters host winter stage before gameplay")
	check(guest.stage.trails.is_empty(), "winter stage keeps its original forest without spectator footpaths")
	check(guest.car.get_meta("model") == "Лесной внедорожник" and host.car.get_meta("model") == "Дорожный седан", "room handshake preserves individual car choices")
	check(host.stage.trees == guest.stage.trees and host.stage.points == guest.stage.points, "winter forest and terrain match on every client")
	var winter_tree_height_ok = true
	for tree in host.stage.trees:
		winter_tree_height_ok = winter_tree_height_ok and absf(tree.y - (host.stage.terrain_surface_height(tree) - 0.03)) < 0.005
	check(winter_tree_height_ok, "winter forest tree bases match visible terrain triangles")
	var summer_sample = Stage.new()
	var forest_position = Vector3(68.25, 0.0, -420.75)
	var x0 = floorf(forest_position.x / 4.0) * 4.0
	var z0 = floorf(forest_position.z / 4.0) * 4.0
	check(summer_sample.terrain_surface_height(forest_position) <= summer_sample.ground(forest_position) + 1.0, "rendered terrain height follows the sampled mesh rather than the continuous height function")
	summer_sample.free()

	host.room._update_peers([{"id": "guest", "name": "Друг", "slot": 1, "car_model": 2, "state": guest.room.local_state()}])
	check(host.room.peers.guest.car.get_meta("model") == "Лесной внедорожник", "peer model uses selected car instead of room slot")
	guest.select_player_car(9)
	host.room._update_peers([{"id": "sport_guest", "name": "Друг на Sport sedan", "slot": 1, "car_model": 9, "state": guest.room.local_state()}])
	check(host.room.peers.sport_guest.car.get_meta("model") == "Спортивный седан" and baked(host.room.peers.sport_guest.car).has("BodyShellSportSedan"), "friends receive dedicated Sport sedan geometry")
	var red = false
	var body_mesh: Mesh = guest.car.get_node("Baked").mesh
	for surface in range(body_mesh.get_surface_count()):
		for colour in body_mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]:
			red = red or Vector3(colour.r - 0.788, colour.g - 0.145, colour.b - 0.188).length() < 0.01
	check(red, "Sport sedan body has requested red paint")
	check(baked(guest.car).has("SportGrille"), "sport sedan has a single unbranded grille")
	check(baked(guest.car).keys().filter(func(n): return str(n).begins_with("SportExhaust")).size() == 4, "Sport sedan has four visible exhaust tips")
	host.stage.fell(0, Vector3.RIGHT)
	host.stage.update_fallen(2)
	guest.room.apply_world(host.room.world_state())
	check(guest.stage.fallen.has(0), "winter fallen trees replicate onto the same forest")
	host.room.connected = false
	host.room._update_peers([])
	host.stage.fallen.clear()
	var start = host.car.position
	host.stage.trees.clear()
	host.stage.trees.append(start + Vector3(0, 0, -0.5))
	host.heading = 0
	host.speed = 0
	host.vehicle_motion.velocity = Vector3.ZERO
	Input.action_press("back")
	for i in range(36):
		host._drive(1.0 / 24.0)
	Input.action_release("back")
	check(host.car.position.z > start.z + 2 and not host.dead, "actual car physics reverses out of initial tree overlap at 24 FPS")
	for game in [host, guest]:
		await game._shutdown_audio()
		game.queue_free()
	await process_frame
	print("SELECTION RESULT: %d checks, %d failures" % [checks, failures])
	finish()
