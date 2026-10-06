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
	game.enable_mobile()
	game.stage.trees.clear()
	game.stage.rocks.clear()
	game.in_car = false
	game.walker = game.stage.at(300) + game.stage.side(300) * 9
	game.spawn_racer("crash")
	var racer = game.racers[0]
	racer.state = "rock_bounce"
	racer.kind = "crash"
	racer.motion.velocity = Vector3.ZERO
	racer.node.position = game.walker + Vector3(3, 0, 0)
	game.car.position = racer.node.position + Vector3(8, 0, 0)
	game._update_racers(0.9)
	check(racer.state == "stranded" and game.can_tow_racer(racer), "crew hitting rocks remains towable after settling")
	game._update_racers(20)
	check(game.racers.size() == 1 and racer.state == "stranded", "crashed crew waits for help instead of disappearing after 18 seconds")
	game.mobile_controls._layout()
	var button = false
	for b in game.mobile_controls.buttons:
		button = button or b.action == "tow"
	check(button, "mobile rope control appears next to a recovered crash")
	# Older room states and collision-stopped passers are also recoverable.
	racer.state = "stopped"
	Input.action_press("tow")
	game._update_tow(0.1)
	check(game.tow_target == racer.node, "rope attaches to stopped as well as stranded crews")
	game._update_racers(20)
	check(game.racers.size() == 1 and game.tow_target == racer.node, "attached crew never disappears during towing")
	game._update_tow(6)
	Input.action_release("tow")
	check(game.helped == 1 and racer.state == "racing" and game.tow_target == null, "single-player rope frees the crashed crew exactly once")
	check(game.stage.road_distance(racer.node.position) < 0.1 and racer.motion.velocity == Vector3.ZERO and racer.slide == 0, "recovered crew restarts on road without its old rock impulse")
	game._update_racers(0.1)
	check(not game.dead and racer.state == "racing", "recovered crew continues safely after towing")
	# The host must use the same recovery path when a guest holds the rope.
	racer.state = "stopped"
	racer.node.position = game.stage.at(420) + game.stage.side(420) * 8
	racer.motion.velocity = Vector3(6, 0, 4)
	racer.slide = 2.0
	game.room.player_id = "host"
	var guest_state = {"pos": game.room.a(racer.node.position + Vector3(3, 0, 0)), "car": game.room.a(racer.node.position + Vector3(8, 0, 0)), "in_car": false, "tow": true, "heading": 0.0, "yaw": 0.0, "pitch": 0.0, "beer": -1.0}
	game.room.peers["guest"] = {"state": guest_state}
	game.room.update_tow(3)
	check(game.tow_target == racer.node and game.room.tow_owner == "guest", "guest can attach rope to collision-stopped crew")
	game.room.update_tow(3.1)
	check(game.helped == 2 and racer.state == "racing" and game.tow_target == null and racer.slide == 0 and racer.motion.velocity == Vector3.ZERO, "guest towing uses the same safe recovery and increments help once")
	game.room.peers.clear()
	# The button is also available before attachment when sitting in a nearby car.
	racer.state = "stopped"
	game.in_car = true
	game.car.position = racer.node.position + Vector3(4, 0, 0)
	game.mobile_controls._layout()
	button = false
	for b in game.mobile_controls.buttons:
		button = button or b.action == "tow"
	check(button, "mobile player can attach a rope from a nearby car")
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	print("TOW RECOVERY RESULT: %d failures" % failures)
	quit(1 if failures else 0)
