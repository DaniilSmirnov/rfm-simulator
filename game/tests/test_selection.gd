extends SceneTree
const Stage = preload("res://scripts/stage.gd")
const RallyProps = preload("res://scripts/props.gd")
var checks = 0
var failures = 0
func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(title)
	else:
		print("PASS: " + title)
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
	check(host.car_choice.item_count == 10 and host.stage_choice.item_count == 3, "menu offers ten cars and three stages")
	host.car_choice.cycle(-1)
	check(host.selected_car == 9 and host.car.get_meta("model") == "Спортивный седан", "previous arrow wraps to red Sport F80")
	host.select_player_car(8)
	var obj_asset_script = load("res://scripts/camping_hatchback_asset.gd")
	check(obj_asset_script.PARTS.size() == 8, "camping hatchback supports eight independently imported OBJ parts")
	check(host.car.get_meta("roof_cargo", "") == "inflatable_boat", "camping hatchback retains inflatable roof boat configuration")
	var camping_lid = host.car.get_node_or_null("TrunkHinge")
	var imported_lid_names = ["BodyShellHatchback_Lid", "Camping_glass_Lid", "Camping_trim_Lid", "Camping_lights_Lid"]
	var imported_hatch_complete = camping_lid != null
	for lid_name in imported_lid_names:
		var lid = camping_lid.get_node_or_null(lid_name) if camping_lid != null else null
		imported_hatch_complete = imported_hatch_complete and lid is MeshInstance3D and lid.mesh.get_surface_count() > 0
	check(imported_hatch_complete, "imported hatch moves rear body, glass, trim and lamps together")
	var boat_static = host.car.get_node_or_null("CarModelDetails/Camping_boat") != null
	var boat_mesh = host.car.get_node_or_null("CarModelDetails/Camping_boat") as MeshInstance3D
	check(boat_mesh != null and boat_mesh.transform.basis.z.dot(Vector3.FORWARD) > 0.99, "imported OBJ parts rotate 180 degrees to match game driving direction")
	check(camping_lid != null and camping_lid.get_node_or_null("Camping_glass_Lid") != null, "rear glazing remains attached to the hatch after correcting forward axis")
	check(boat_static and camping_lid.get_node_or_null("Camping_boat_Lid") == null, "inflatable roof boat remains fixed when trunk opens")
	var original_hatch_position = camping_lid.transform if camping_lid != null else Transform3D.IDENTITY
	RallyProps.update_player_trunk(host.car, true, [true, true, true, true, true], 1.0)
	check(camping_lid != null and camping_lid.rotation.x < -0.8 and host.car.get_node("TrunkBoxes").visible, "imported rear hatch opens and exposes stored cargo")
	RallyProps.update_player_trunk(host.car, false, [true, true, true, true, true], 1.0)
	check(camping_lid != null and absf(camping_lid.rotation.x) < 0.01, "imported rear hatch closes completely")
	check(host.car.get_node_or_null("BodyShellHatchback") != null and host.car.get_node_or_null("RoofHatchback") != null, "2112 has dedicated body, short roof and sloped-glasshouse geometry")
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
	check(city.urban and city.clearings.size() == 4 and city.trees.is_empty(), "vineyard stage has four ordinary spectator spots without a separate parking entity")
	check(city.city.village_houses >= 14 and city.get_node_or_null("VillageChurch") != null, "village has detailed houses and church")
	check(city.city.thuja_count > 300, "village is enclosed by a dense thuja forest belt")
	check(city.city.mixed_tree_count >= 900, "village outer forest has increased tree density")
	check(city.city.vine_count > 2000 and city.collectibles.size() > 2000, "vineyards contain continuous rows and collectible grapes")
	city.free()
	guest.select_player_car(2)
	host.room.request_kind = "create"
	host.room._response(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify({"player": "host", "token": "h", "host": true, "room": "ABC123", "slot": 0, "car_model": 5, "stage": 1}).to_utf8_buffer())
	guest.room.request_kind = "join"
	guest.room._response(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify({"player": "guest", "token": "g", "host": false, "slot": 1, "car_model": 2, "stage": 1}).to_utf8_buffer())
	check(guest.stage.winter and guest.playing and not guest.selection_controls.visible, "guest enters host winter stage before gameplay")
	check(guest.stage.trails.is_empty(), "winter stage keeps its original forest without spectator footpaths")
	check(guest.car.get_meta("model") == "Лесной внедорожник" and host.car.get_meta("model") == "Дорожный седан", "room handshake preserves individual car choices")
	check(host.stage.trees == guest.stage.trees and host.stage.points == guest.stage.points, "winter forest and terrain match on every client")
	host.room._update_peers([{"id": "guest", "name": "Друг", "slot": 1, "car_model": 2, "state": guest.room.local_state()}])
	check(host.room.peers.guest.car.get_meta("model") == "Лесной внедорожник", "peer model uses selected car instead of room slot")
	guest.select_player_car(9)
	host.room._update_peers([{"id": "sport_guest", "name": "Друг на Sport sedan", "slot": 1, "car_model": 9, "state": guest.room.local_state()}])
	check(host.room.peers.sport_guest.car.get_meta("model") == "Спортивный седан" and host.room.peers.sport_guest.car.get_node_or_null("BodyShellSportSedan") != null, "friends receive dedicated Sport sedan geometry")
	var body = guest.car.get_node("BodyShellSportSedan")
	check(body.material_override.albedo_color.is_equal_approx(Color("c92530")), "Sport sedan body has requested red paint")
	check(guest.car.get_node_or_null("SportGrille") != null, "sport sedan has a single unbranded grille")
	check(guest.car.get_children().filter(func(n): return str(n.name).begins_with("SportExhaust")).size() == 4, "Sport sedan has four visible exhaust tips")
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
	quit(1 if failures else 0)
