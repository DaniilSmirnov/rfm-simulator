extends "res://tests/harness.gd"
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.start_game()
	game.in_car = false
	game.walker = game.stage.clearings[0]
	for i in range(15):
		game.course.phase = "racing"
		game.spawn_racer("pass")
	check(game.rally_spawn_count == 10 and game.racers.size() == 10, "rally spawns exactly ten crews even with repeated manual requests")
	var racer = game.racers[0]
	game.count_racer(racer)
	game.count_racer(racer)
	check(game.passed == 1, "same crew is counted once")
	game.recover_racer(racer)
	check(game.passed == 1 and game.helped == 1, "towing an already counted crew never increments viewed crews")
	for other in game.racers:
		game.count_racer(other)
	check(game.passed == 10, "ten distinct crews complete the rally count")
	game.count_racer({"counted": false})
	check(game.passed == 10, "crew counter cannot overflow ten")
	game._update_hud()
	check(game.status_label.text.contains("10/10") and game.quest_label.text.contains("10 экипажей"), "HUD and quest use ten-crew target")
	game.camp = Node3D.new()
	game.add_child(game.camp)
	game.has_chairs = true
	game.eaten = true
	game.passed = 9
	game._check_finish()
	check(not game.finished, "picnic with nine crews does not finish the demo")
	game.passed = 10
	game._check_finish()
	check(not game.finished, "picnic with ten crews waits for closing police")
	game.course.phase = "complete"
	game._check_finish()
	check(not game.finished, "first pass cannot finish the outing")
	game.course.pass_index = 2
	game._check_finish()
	check(not game.finished, "second closing police waits for packing")
	game.walker = game.camp.position
	game.packing.pack(game.camp.position)
	game.cargo.opened[game.chair_owner()] = true
	game.walker = game.cargo.point(game.cargo.poses()[game.chair_owner()])
	game.cargo.return_item(game.walker)
	game.car.position = game.stage.at(300.0)
	game.in_car = true
	game._check_finish()
	check(not game.finished, "back in the car on the stage still has to drive to a service park")
	game.car.position = game.park_traffic.parks().world(1, 0.0, 30.0)
	game._check_finish()
	check(game.finished, "two passes, packed equipment and driving into a service park finish the outing")
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	await _fewer_crews()
	print("CREW LIMIT RESULT: %d failures" % failures)
	finish()

# A dedicated server's console sets fewer crews: no more start, the rest stay
# in their bays, and a guest's HUD reads the number from the host.
func _fewer_crews() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.start_game()
	game.rally_crew_limit = 3
	game.course.phase = "racing"
	for i in range(6):
		game.spawn_racer("pass")
	check(game.rally_spawn_count == 3, "three crews start when the server sets three")
	var called = []
	game.park_traffic.called.clear()
	game.park_traffic.called_pass = game.park_traffic.pass_now()
	for key in game.park_traffic.Parks.KEYS:
		if game.park_traffic.crew_of(key) < 0:
			game.park_traffic.called[key] = true
	while game.park_traffic.next_key() != "":
		called.append(game.park_traffic.next_key())
		game.park_traffic.called[called[-1]] = true
	check(called.all(func(key): return game.park_traffic.crew_of(key) < 3), "crews past the third are not called from the park: %s" % [called])
	var progress = game.room.world_sync._progress_snapshot()
	check(progress.get("crews") == 3, "the host sends the crew number to guests")
	game.rally_crew_limit = 10
	game.room.world_sync._progress_apply(progress, 0.0)
	game._update_hud()
	check(game.rally_crew_limit == 3 and game.status_label.text.contains("/3"), "a guest's HUD shows the host's crew number")
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
