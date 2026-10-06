extends SceneTree
var failures = 0
func check(ok: bool, title: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + title)
	if not ok:
		failures += 1
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
	check(game.finished, "picnic with ten crews and closing police finishes the demo")
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	print("CREW LIMIT RESULT: %d failures" % failures)
	quit(1 if failures else 0)
