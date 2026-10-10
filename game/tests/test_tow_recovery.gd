extends "res://tests/harness.gd"
# Towing and pushing by hand (recovery.gd): ropes pull from any side, helpers
# add up, a crew is recovered once it stands on the road, and players can tow
# each other's cars.
func _initialize() -> void:
	call_deferred("run")

func strand(game, racer, station: float = 300, side: float = 8.0) -> void:
	game._cancel_tow()
	racer.state = "stranded"
	racer.kind = "crash"
	racer.node.position = game.stage.at(station) + game.stage.side(station) * side
	racer.node.position.y = game.stage.ground(racer.node.position)
	racer.previous = racer.node.position
	for key in ["towed", "recovery_helpers"]:
		racer.erase(key)

func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

# A helper `reach` metres from the crew towards (or away from) the road.
func person(game, racer, pull: bool, push: bool = false, reach: float = 4.0, toward_road: bool = true) -> Dictionary:
	var road = game.Recovery.road_direction(game, racer) * (1.0 if toward_road else -1.0)
	var pos: Vector3 = racer.node.position + road * (reach if pull else -2.0)
	pos.y = game.stage.ground(pos)
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
	game.car.position = Vector3(170, 0, 0)
	game.course.phase = "racing"
	game.spawn_racer("crash")
	var racer = game.racers[0]
	strand(game, racer)
	game.walker = game.room.v(person(game, racer, true).pos)
	game.mobile_controls._layout()
	check(game.mobile_controls.buttons.any(func(b): return b.action == "tow"), "mobile rope is available on foot beside a stranded crew")

	# One rope: the crew follows the puller, the HUD shows metres to the road.
	Input.action_press("tow")
	var start: Vector3 = racer.node.position
	var gap_before: float = game.Recovery.road_gap(game, start)
	game._update_tow(0.5)
	check(game.tow_target == racer.node and racer.node.position.distance_to(start) > 0.3, "pedestrian rope physically moves the car")
	check(flat_distance(racer.node.position, game.walker) < flat_distance(start, game.walker), "rope pulls the car towards the puller")
	check(game.tow_distance > 0 and game.tow_distance < gap_before, "metres to the road shrink while towing towards it")
	check(game.rope_mesh != null and game.recovery_links.size() == 1, "rope starts at the pedestrian")
	game.hud_state = []
	game._update_hud()
	check(game.info_label.text.contains("ДО ДОРОГИ") and not game.info_label.text.contains("%"), "HUD shows distance to the road, not a percentage")
	Input.action_release("tow")
	var stopped: Vector3 = racer.node.position
	game._update_tow(1)
	check(racer.node.position == stopped and game.rope_mesh == null and game.tow_target == null, "releasing the rope stops the car where it is")
	game._update_racers(20)
	check(game.racers.size() == 1 and racer.state == "stranded", "a partly towed crew stays available")

	# Anywhere: a rope can pull away from the road too.
	strand(game, racer)
	game.walker = game.room.v(person(game, racer, true, false, 4.0, false).pos)
	Input.action_press("tow")
	game._update_tow(1)
	check(game.Recovery.road_gap(game, racer.node.position) > gap_before + 0.5, "a rope pulls the car in any direction, even away from the road")
	# The rope stops short of the puller: it hangs loose within ROPE_SLACK.
	game._update_tow(5)
	check(flat_distance(racer.node.position, game.walker) >= game.Recovery.ROPE_SLACK - 0.05, "the car is never dragged into the puller")
	var resting: Vector3 = racer.node.position
	game._update_tow(1)
	check(racer.node.position == resting and game.tow_target == racer.node, "a slack rope stays attached without moving the car")
	Input.action_release("tow")

	# Recovered only on the carriageway, with no jump along the road.
	strand(game, racer)
	Input.action_press("tow")
	var last: Vector3 = racer.node.position
	for i in range(40):
		if racer.state != "stranded":
			break
		last = racer.node.position
		game.walker = game.room.v(person(game, racer, true).pos)
		game._update_tow(0.25)
	Input.action_release("tow")
	check(game.helped == 1 and racer.state == "racing" and game.rope_mesh == null, "one pedestrian recovers the crew and the rope clears")
	check(game.Recovery.road_gap(game, racer.node.position) == 0.0, "a recovered crew stands on the road")
	check(flat_distance(racer.node.position, last) < 2.0, "the crew restarts where it was pulled onto the road")

	# Walking into the body pushes it without a rope.
	strand(game, racer)
	var direction = game.Recovery.road_direction(game, racer)
	game.walker = racer.node.position - direction * 2
	game.view_yaw = atan2(-direction.x, -direction.z)
	start = racer.node.position
	Input.action_press("forward")
	game._update_tow(1)
	Input.action_release("forward")
	check(racer.node.position.distance_to(start) > 0.5 and game.recovery_links.is_empty(), "body pushing works with walking intent and creates no rope")

	# Helpers add up: two ropes move the crew twice as far as one.
	strand(game, racer)
	start = racer.node.position
	game.Recovery.update(game, {"a": person(game, racer, true, false, 5.5)}, 0.5)
	var solo = flat_distance(racer.node.position, start)
	strand(game, racer)
	game.Recovery.update(game, {"a": person(game, racer, true, false, 5.5), "b": person(game, racer, true, false, 5.5)}, 0.5)
	check(absf(flat_distance(racer.node.position, start) - solo * 2) < 0.05 and racer.recovery_helpers == 2, "two pullers move the crew twice as fast as one")
	check(game.recovery_links.size() == 2 and game.recovery_ropes.size() == 2, "every puller has a separate visible rope")
	var snapshot = game.room.world_state()
	check(snapshot.recovery_links.size() == 2 and snapshot.racers[0].get("towed", false), "snapshot carries the ropes and the towed crew")

	# Inactive, distant, stale and paused helpers do nothing.
	strand(game, racer)
	start = racer.node.position
	var invalid = person(game, racer, true)
	invalid.in_car = true
	game.Recovery.update(game, {"driver": invalid}, 1)
	check(racer.node.position == start, "driver cannot pull or push from their car")
	invalid.in_car = false
	invalid.beers = 30
	game.Recovery.update(game, {"collapsed": invalid}, 1)
	check(racer.node.position == start, "collapsed spectator cannot contribute")
	invalid.beers = 0
	invalid.pos = [180, 0, 0]
	game.Recovery.update(game, {"distant": invalid}, 1)
	check(racer.node.position == start, "distant spectator cannot contribute")
	invalid = person(game, racer, false, true)
	invalid.push = game.room.a(-game.Recovery.road_direction(game, racer))
	game.Recovery.update(game, {"away": invalid}, 1)
	check(racer.node.position == start, "walking away from the car does not push it")
	game.room.peers = {"stale": {"state": person(game, racer, true), "last_state_time": game.room.server_clock() - 2}}
	game.room.update_tow(1)
	check(racer.node.position == start, "stale remote input cannot keep pulling unattended")
	game.room.peers.clear()
	game.paused = true
	game.Recovery.update(game, {"a": person(game, racer, true)}, 10)
	check(racer.node.position == start, "pause freezes towing")
	game.paused = false

	# Players tow each other's cars; nobody tows their own.
	strand(game, racer, 600)
	game.room.connected = true
	game.room.player_id = "host"
	game.walker = Vector3(180, 0, 0)
	var friend_car = game.stage.at(200) + game.stage.side(200) * 12
	friend_car.y = game.stage.ground(friend_car)
	var puller = friend_car + Vector3(4, 0, 0)
	puller.y = game.stage.ground(puller)
	var friend = {"pos": game.room.a(friend_car + Vector3(0, 0, 30)), "car": game.room.a(friend_car), "in_car": false, "tow": false, "push": [0, 0, 0], "beers": 0, "heading": 0.0, "yaw": 0.0, "pitch": 0.0}
	var helper = {"pos": game.room.a(puller), "car": [150, 0, 0], "in_car": false, "tow": true, "push": [0, 0, 0], "beers": 0, "heading": 0.0, "yaw": 0.0, "pitch": 0.0}
	game.room._update_peers([{"id": "friend", "name": "Друг", "state": friend}, {"id": "helper", "name": "Помощник", "state": helper}])
	game.room.update_tow(0.5)
	var moved = game.room.v(game.room.peers.friend.state.car)
	check(flat_distance(moved, puller) < flat_distance(friend_car, puller) - 0.3, "a player tows a friend's car towards themselves")
	check(game.recovery_links.any(func(link): return link.get("car", "") == "friend" and link.player == "helper"), "the rope to a friend's car is shared in the snapshot")
	# The host's own car, towed by a guest: the host sees it moving.
	game.car.position = game.stage.at(220) + game.stage.side(220) * 12
	game.car.position.y = game.stage.ground(game.car.position)
	var own: Vector3 = game.car.position
	helper.pos = game.room.a(own + Vector3(-4, 0, 0))
	game.room.peers.helper.state = helper
	game.room.update_tow(0.5)
	check(flat_distance(game.car.position, own) > 0.3 and game.crews.car_towed, "a guest tows the host's car and the host is told")
	game.hud_state = []
	game._update_hud()
	check(game.info_label.text.contains("ТВОЮ МАШИНУ ТЯНУТ"), "the HUD tells the owner their car is on a rope")
	# Holding the rope beside one's own car does nothing.
	game.room.peers.helper.state.tow = false
	friend.tow = true
	friend.pos = game.room.a(moved + Vector3(4, 0, 0))
	game.room.peers.friend.state = friend
	var parked = game.room.v(game.room.peers.friend.state.car)
	game.room.update_tow(0.5)
	check(game.room.v(game.room.peers.friend.state.car) == parked and game.recovery_links.is_empty(), "nobody tows their own car")
	game.room.peers.clear()

	# Late guests receive all ropes; repeated snapshots do not duplicate them.
	game.room.player_id = ""
	game.room.connected = false
	strand(game, racer)
	game.Recovery.update(game, {"a": person(game, racer, true), "b": person(game, racer, true)}, 0.5)
	var guest = load("res://main.tscn").instantiate()
	root.add_child(guest)
	await process_frame
	guest.set_process(false)
	guest.room.set_process(false)
	guest.start_game()
	guest.room.connected = true
	guest.room.player_id = "a"
	guest.room.apply_world(game.room.world_state())
	guest.room.apply_world(game.room.world_state())
	check(guest.recovery_ropes.size() == 2 and guest.tow_target != null and guest.tow_distance > 0, "late guest sees two ropes and its own tow with metres to the road")
	for g in [game, guest]:
		await g._shutdown_audio()
		g.queue_free()
	await process_frame
	print("COOPERATIVE RECOVERY RESULT: %d failures" % failures)
	finish()
