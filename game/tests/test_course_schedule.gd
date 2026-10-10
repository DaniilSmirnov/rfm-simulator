extends SceneTree
var failures = 0
func check(ok: bool, title: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + title)
	if not ok:
		failures += 1
func _initialize() -> void:
	call_deferred("run")
func finish_vehicle(game) -> void:
	var racer = game.racers[-1]
	racer.s = game.stage.LENGTH - 2.0
	racer.node.position = game.race_at(racer.s)
	racer.previous = racer.node.position
	racer.slide = 0.0
	racer.slide_speed = 0.0
	racer.line = 0.0
	# Slow finish sections (winter col, village) may need a few steps.
	var id = racer.id
	for step in range(40):
		game._update_racers(0.15)
		if not game.racers.any(func(item): return item.id == id):
			break
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	for variant in range(3):
		game.playing = false
		game.select_stage(variant)
		game.start_game()
		game.car.position = Vector3(190, 30, 30)
		game.walker = Vector3(190, 30, 30)
		game.in_car = true
		game.course.update(game, 179.0)
		check(game.course.phase == "countdown" and game.course.remaining == 1 and game.racers.is_empty(), "map %d waits all 180 seconds even when driving" % variant)
		game.spawn_racer("crash")
		check(game.racers.is_empty() and not game.start_rally(), "manual keys cannot bypass countdown")
		game.paused = true
		game.course.update(game, 10)
		check(game.course.remaining == 1, "pause freezes opening countdown")
		game.paused = false
		game.course.update(game, 1)
		check(game.course.phase == "opening_police" and game.racers.size() == 1 and game.racers[0].role == "opening_police", "police opens the convoy on every map")
		var police = game.racers[0]
		check(police.node.get_node_or_null("BeaconBlue") != null and police.node.get_meta("model").contains("Полиция"), "police has marked model and flashing light bar")
		game.count_racer(police)
		check(game.passed == 0 and game.rally_spawn_count == 0, "opening police is excluded from ten competitors")
		game.course.update(game, 100)
		check(game.racers.size() == 1, "zero crews wait until opening police completes route")
		finish_vehicle(game)
		for index in range(1, 4):
			check(game.course.phase == "zero" and game.course.zero_index == index and game.racers.size() == 1, "zero crew %d follows previous vehicle" % index)
			var zero = game.racers[-1]
			check(zero.role == "zero" and zero.node.get_meta("number") == 0, "each safety crew visibly carries number zero")
			game.count_racer(zero)
			check(game.passed == 0 and game.rally_spawn_count == 0, "zero crew does not increment rally counters")
			finish_vehicle(game)
		check(game.course.phase == "racing" and game.racers.is_empty(), "competitors begin only after all three zeros")
		game.course.update(game, 4.99)
		check(game.racers.is_empty(), "first competitor waits for its start gap")
		game.course.update(game, 0.02)
		check(game.rally_spawn_count == 1 and game.racers[0].role == "racer", "first real competitor starts automatically")
		var racer = game.racers[0]
		game.rally_spawn_count = 10
		game.passed = 10
		game.course.update(game, 0.1)
		check(game.course.phase == "racing", "closing police waits until last moving racer finishes")
		racer.state = "stranded"
		game.course.update(game, 0.1)
		check(game.course.phase == "closing_police" and game.racers[-1].role == "closing_police", "closing police follows settled competitors")
		racer.node.free()
		game.racers.erase(racer)
		game.course.update(game, 20)
		check(game.racers.size() == 1, "closing police never spawns twice")
		finish_vehicle(game)
		check(game.course.phase == "intermission" and game.course.pass_index == 1 and game.course.remaining == 60, "first closing police starts a sixty-second turnaround")
		game.course.update(game, 59)
		check(game.racers.is_empty() and game.course.pass_index == 1, "reverse convoy waits for the whole break")
		game.course.update(game, 1)
		check(game.course.pass_index == 2 and game.racers[-1].id == 301 and game.passed == 0 and game.rally_spawn_count == 0, "second pass resets ten-crew counters and uses unique identities")
		var reverse = game.racers[-1]
		check(reverse.node.position.distance_to(game.stage.at(game.stage.LENGTH)) < 0.01, "reverse police starts at the original finish")
		var forward = -reverse.node.basis.z
		check(forward.dot(-game.stage.direction(game.stage.LENGTH)) > 0.99, "reverse car faces the opposite direction immediately")
		finish_vehicle(game)
		for index in range(3):
			check(game.course.phase == "zero" and game.course.zero_index == index + 1, "reverse pass repeats the safety convoy")
			finish_vehicle(game)
		game.course.update(game, 5)
		check(game.racers.size() == 1 and game.racers[0].id == 201, "same first crew returns with a new pass identity")
		game.racers[0].node.free()
		game.racers.clear()
		game.passed = 10
		game.rally_spawn_count = 10
		game.course.update(game, 0.1)
		check(game.racers[-1].id == 305 and game.course.phase == "closing_police", "second pass ends with its own closing police")
		finish_vehicle(game)
		check(game.course.phase == "complete" and game.racers.is_empty(), "only second closing police completes both passes")
		game.course.update(game, 300)
		check(game.racers.is_empty() and game.rally_spawn_count == 10 and game.passed == 10, "closed stage never restarts or creates an eleventh racer")
		game.rally_spawn_count = 0
		game.passed = 0
	# A late guest must see the current host timer, roles and same service model.
	game.playing = false
	game.start_game()
	game.course.update(game, 71)
	var guest = load("res://main.tscn").instantiate()
	root.add_child(guest)
	await process_frame
	guest.set_process(false)
	guest.room.set_process(false)
	guest.select_stage(2)
	guest.start_game()
	guest.room.connected = true
	guest.room.is_host = false
	guest.room.apply_world(game.room.world_state())
	check(guest.course.remaining == 109 and guest.course.phase == "countdown", "late guest inherits host countdown instead of restarting three minutes")
	guest.course.update(guest, 180)
	check(guest.course.remaining == 109 and guest.racers.is_empty(), "guest cannot advance authoritative schedule")
	game.course.update(game, 109)
	guest.room.apply_world(game.room.world_state())
	guest.room.apply_world(game.room.world_state())
	check(guest.racers.size() == 1 and guest.racers[0].role == "opening_police" and guest.racers[0].node.get_node_or_null("BeaconBlue") != null, "police role and model replicate without duplicate service cars")
	finish_vehicle(game)
	guest.room.apply_world(game.room.world_state())
	check(guest.racers.size() == 1 and guest.racers[0].role == "zero" and guest.racers[0].node.get_meta("number") == 0, "late guest sees numbered zero crew and shared phase")
	game.enable_mobile()
	game._update_hud()
	check(game.course_label.visible and game.course_label.text.contains("1/3"), "mobile countdown and phase remain visible without opening map")
	for g in [game, guest]:
		await g._shutdown_audio()
		g.queue_free()
	await process_frame
	print("COURSE SCHEDULE RESULT: %d failures" % failures)
	quit(1 if failures else 0)
