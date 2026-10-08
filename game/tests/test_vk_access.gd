extends SceneTree
var failures = 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	var service = game.platform_service
	check(service.can_use("car", 9), "standalone keeps all cars")
	service.catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/store_catalog.json"))
	service.entitlements = {"mode": "restricted", "skus": []}
	for i in range(10):
		check(service.can_use("car", i) == (i < 3), "VK car baseline %d" % i)
	game.select_player_car(2)
	game.select_player_car(9)
	check(game.selected_car == 9 and game.car_choice.selected == 9, "locked car can be previewed")
	game.car_choice.select(3)
	game.car_choice.item_selected.emit(3)
	check(game.selected_car == 3 and game.car_choice.selected == 3, "locked preview remains visible without starting")
	game.start_game()
	check(not game.playing, "cannot start on locked preview")
	game.room.connect_room("")
	check(not game.room.busy and not game.room.connected, "cannot create room on locked preview")
	game.car_choice.select(2)
	game.select_stage(1)
	check(game.selected_stage == 1, "locked stage can be previewed")
	game.room.connected = true
	game.room.is_host = false
	game.select_stage(1, true)
	check(game.selected_stage == 1, "room guest can borrow host stage")
	game.room.connected = false
	check(not service.can_use("stage", 1), "guest receives no permanent ownership")
	service.entitlements.skus.append("car_04")
	game.select_player_car(3)
	check(game.selected_car == 3, "future entitlement unlocks only its car")
	game.queue_free()
	await process_frame
	print("VK_ACCESS failures=", failures)
	quit(1 if failures else 0)
