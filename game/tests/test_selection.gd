extends SceneTree
const Stage = preload("res://scripts/stage.gd")
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
	check(host.car_choice.item_count == 9 and host.stage_choice.item_count == 3, "menu offers eight cars and three stages")
	host.car_choice.cycle(-1)
	check(host.selected_car == 8 and host.car.get_meta("model") == "ВАЗ-2112 Лодка", "previous arrow wraps through all selectable car models")
	check(host.car.get_node_or_null("BodyShell2112") != null and host.car.get_node_or_null("Roof2112") != null, "2112 has dedicated body, short roof and sloped-glasshouse geometry")
	host.car_choice.cycle(1)
	check(host.selected_car == 0, "next arrow returns to first car")
	host.car_choice.item_selected.emit(5)
	host.stage_choice.item_selected.emit(1)
	check(host.car.get_meta("model") == "Kia Rio" and host.stage.winter, "menu selection applies car and winter terrain before start")
	var summer = Stage.new()
	check(host.stage.at(310).distance_to(summer.at(310)) > 15, "winter stage has its own alignment and elevation")
	check(host.stage.grip(host.stage.at(310)) < summer.grip(summer.at(310)), "winter surface has lower grip")
	summer.free()
	var city = Stage.new(2)
	city.build()
	check(city.urban and city.clearings.size() == 4 and city.trees.is_empty(), "city super stage has four street parking spots")
	var city_buildings = 0
	var city_cross_streets = 0
	for child in city.get_children():
		city_buildings += 1 if child.name.begins_with("ParisPragueBuilding") else 0
		city_cross_streets += 1 if child.name.begins_with("CityCrossStreet") else 0
	check(city_buildings > 100, "city is lined with continuous European building blocks")
	check(city_cross_streets == 6 and city.get_node_or_null("CityCentralSquare") != null, "city has six full cross streets and a central square")
	city.free()
	guest.select_player_car(2)
	host.room.request_kind = "create"
	host.room._response(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify({"player": "host", "token": "h", "host": true, "room": "ABC123", "slot": 0, "car_model": 5, "stage": 1}).to_utf8_buffer())
	guest.room.request_kind = "join"
	guest.room._response(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify({"player": "guest", "token": "g", "host": false, "slot": 1, "car_model": 2, "stage": 1}).to_utf8_buffer())
	check(guest.stage.winter and guest.playing and not guest.selection_controls.visible, "guest enters host winter stage before gameplay")
	check(guest.stage.trails.is_empty(), "winter stage keeps its original forest without spectator footpaths")
	check(guest.car.get_meta("model") == "Lada Niva" and host.car.get_meta("model") == "Kia Rio", "room handshake preserves individual car choices")
	check(host.stage.trees == guest.stage.trees and host.stage.points == guest.stage.points, "winter forest and terrain match on every client")
	host.room._update_peers([{"id": "guest", "name": "Друг", "slot": 1, "car_model": 2, "state": guest.room.local_state()}])
	check(host.room.peers.guest.car.get_meta("model") == "Lada Niva", "peer model uses selected car instead of room slot")
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
