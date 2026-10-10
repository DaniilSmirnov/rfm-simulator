extends "res://tests/harness.gd"
func _initialize() -> void:
	call_deferred("run")
func strand(game, racer, station: float = 300) -> void:
	game._cancel_tow()
	racer.state = "stranded"
	racer.kind = "crash"
	racer.node.position = game.stage.at(station) + game.stage.side(station) * 8
	racer.node.position.y = game.stage.ground(racer.node.position)
	racer.previous = racer.node.position
	for key in ["recovery_start", "recovery_goal", "recovery_progress", "recovery_helpers"]:
		racer.erase(key)
func person(game, racer, pull: bool, push: bool = false) -> Dictionary:
	var road = game.Recovery.road_direction(game, racer)
	var pos: Vector3 = racer.node.position + road * (3 if pull else -2)
	return {"pos": game.room.a(pos), "car": [160, 0, 0], "in_car": false, "tow": pull, "push": game.room.a(road) if push else [0, 0, 0], "beers": 0}
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
	game.car.position = Vector3(170, 0, 0)
	game.course.phase = "racing"
	game.spawn_racer("crash")
	var racer = game.racers[0]
	strand(game, racer)
	game.walker = game.room.v(person(game, racer, true).pos)
	game.mobile_controls._layout()
	check(game.mobile_controls.buttons.any(func(b): return b.action == "tow"), "mobile rope is available on foot beside a stranded crew")
	Input.action_press("tow")
	var start: Vector3 = racer.node.position
	game._update_tow(0.5)
	check(game.tow_target == racer.node and game.tow_progress > 0 and racer.node.position.distance_to(start) > 0, "pedestrian rope physically moves car without a nearby personal vehicle")
	check(game.rope_mesh != null and game.recovery_links.size() == 1, "rope starts at the pedestrian rather than their distant car")
	Input.action_release("tow")
	var stopped: Vector3 = racer.node.position
	var progress: float = racer.recovery_progress
	game._update_tow(1)
	check(racer.node.position == stopped and racer.recovery_progress == progress and game.rope_mesh == null, "releasing rope stops effort and preserves achieved progress")
	game._update_racers(20)
	check(game.racers.size() == 1, "partially recovered crew remains available after helper releases rope")
	Input.action_press("tow")
	for i in range(16):
		if racer.state != "stranded":
			break
		game.walker = game.room.v(person(game, racer, true).pos)
		game._update_tow(0.5)
	Input.action_release("tow")
	check(game.helped == 1 and racer.state == "racing" and game.rope_mesh == null, "one pedestrian can complete recovery and clear rope")
	# Walking into the body provides push effort, even if collision blocks the walker.
	strand(game, racer)
	var direction = game.Recovery.road_direction(game, racer)
	game.walker = racer.node.position - direction * 2
	game.view_yaw = atan2(-direction.x, -direction.z)
	Input.action_press("forward")
	game._update_tow(1)
	Input.action_release("forward")
	check(racer.recovery_progress > 0.15 and game.recovery_links.is_empty(), "body pushing works with walking intent and creates no rope")
	# Two ropes and two pushes stack on the same crew.
	strand(game, racer)
	var solo = {"a": person(game, racer, true)}
	game.Recovery.update(game, solo, 1)
	var solo_progress: float = racer.recovery_progress
	strand(game, racer)
	var team = {"a": person(game, racer, true), "b": person(game, racer, true), "c": person(game, racer, false, true), "d": person(game, racer, false, true)}
	game.Recovery.update(game, team, 1)
	check(absf(racer.recovery_progress - solo_progress * 4) < 0.02 and game.recovery_helpers == 4, "two pullers and two pushers contribute four times solo effort")
	check(game.recovery_links.size() == 2 and game.recovery_ropes.size() == 2, "every puller has a separate visible rope")
	var snapshot = game.room.world_state()
	check(snapshot.recovery_links.size() == 2 and snapshot.recovery_helpers == 4 and snapshot.racers[0].recovery_progress > 0, "snapshot carries shared recovery progress, all helpers and rope endpoints")
	# Host also applies remote cooperation, rather than appointing one owner.
	strand(game, racer)
	game.room.player_id = "host"
	game.room.peers = {"one": {"state": person(game, racer, true)}, "two": {"state": person(game, racer, false, true)}}
	game.walker = Vector3(180, 0, 0)
	game.room.update_tow(1)
	check(game.recovery_helpers == 2 and racer.recovery_progress > 0.3, "host combines remote rope and body push")
	game.room.peers.erase("one")
	game.room.peers.two.state = person(game, racer, false, true)
	var before: float = racer.recovery_progress
	game.room.update_tow(1)
	check(absf(racer.recovery_progress - before - 1.0 / 6) < 0.02 and game.recovery_links.is_empty(), "departed helper drops out while remaining pusher continues")
	game.room.peers.clear()
	# Inactive players, wrong direction, distance and stale inputs must not contribute.
	strand(game, racer)
	var invalid = person(game, racer, true)
	invalid.in_car = true
	game.Recovery.update(game, {"driver": invalid}, 1)
	check(not racer.has("recovery_progress"), "driver cannot pull or push from their car")
	invalid.in_car = false
	invalid.beers = 30
	game.Recovery.update(game, {"collapsed": invalid}, 1)
	check(not racer.has("recovery_progress"), "collapsed spectator cannot contribute")
	invalid.beers = 0
	invalid.pos = [180, 0, 0]
	game.Recovery.update(game, {"distant": invalid}, 1)
	check(not racer.has("recovery_progress"), "distant spectator cannot contribute")
	invalid = person(game, racer, false, true)
	invalid.push = game.room.a(-game.Recovery.road_direction(game, racer))
	game.Recovery.update(game, {"away": invalid}, 1)
	check(not racer.has("recovery_progress"), "walking away does not push a crew")
	game.room.peers = {"stale": {"state": person(game, racer, true), "last_state_time": game.room.server_clock() - 2}}
	game.room.update_tow(1)
	check(not racer.has("recovery_progress"), "stale remote input cannot keep pulling unattended")
	game.room.peers.clear()
	game.paused = true
	game.Recovery.update(game, {"a": person(game, racer, true)}, 10)
	check(not racer.has("recovery_progress"), "pause freezes cooperative recovery")
	game.paused = false
	# Late guests receive all ropes; repeated snapshots do not duplicate them.
	game.Recovery.update(game, {"a": person(game, racer, true), "b": person(game, racer, true)}, 0.5)
	var guest = load("res://main.tscn").instantiate()
	root.add_child(guest)
	await process_frame
	guest.set_process(false)
	guest.room.set_process(false)
	guest.start_game()
	guest.room.connected = true
	guest.room.player_id = "guest"
	guest.room.apply_world(game.room.world_state())
	guest.room.apply_world(game.room.world_state())
	check(guest.recovery_ropes.size() == 2 and guest.recovery_helpers == 2 and guest.tow_progress == game.tow_progress, "late guest sees two ropes and same progress without duplicates")
	for g in [game, guest]:
		await g._shutdown_audio()
		g.queue_free()
	await process_frame
	print("COOPERATIVE RECOVERY RESULT: %d failures" % failures)
	finish()
