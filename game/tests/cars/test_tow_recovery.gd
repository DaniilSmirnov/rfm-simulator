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

# Exercise the actual walker collision and recovery together, rather than
# teleporting a helper to a fixed centre radius on every frame.
func continuous_push(game) -> void:
	strand(game, game.racers[0], 600)
	var box = game.Recovery.Hitbox.bounds(game.car)
	for yaw in [0.0, 0.73]:
		for side in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
			var distances = []
			for fps in [24, 60]:
				game.car.position = game.stage.at(180)
				game.heading = yaw
				game.vehicle_motion.follow_ground(game.car, game.stage, yaw)
				var center = box.get_center()
				var edge = center + side * (box.size.x * 0.5 + 0.4 if side.x != 0 else box.size.z * 0.5 + 0.4)
				# Off-centre contact must push into the flank/bumper, even when
				# the car centre lies diagonally away from the walking direction.
				if side.x != 0: edge.z += box.size.z * 0.35
				edge.y = 0
				game.walker = game.car.position + edge.rotated(Vector3.UP, yaw)
				game.walker.y = game.stage.walking_ground(game.walker)
				game.jump_height = 0.0
				game.jump_velocity = 0.0
				game.player.perches.stand = {}
				var direction = -side.rotated(Vector3.UP, yaw)
				game.view_yaw = atan2(-direction.x, -direction.z)
				var start: Vector3 = game.car.position
				var uninterrupted = true
				Input.action_press("forward")
				Input.action_press("sprint")
				for frame in range(fps * 2):
					var before: Vector3 = game.car.position
					game._walk(1.0 / fps)
					game._update_tow(1.0 / fps)
					var travel: float = (game.car.position - before).dot(direction)
					if frame > fps / 2:
						uninterrupted = uninterrupted and absf(travel - game.Recovery.HELPER_SPEED / fps) < 0.002
				Input.action_release("forward")
				Input.action_release("sprint")
				distances.append(flat_distance(start, game.car.position))
				check(uninterrupted and distances[-1] > 1.5, "continuous push from %s at yaw %.2f / %d FPS does not lose contact" % [side, yaw, fps])
				check(absf(angle_difference(yaw, game.heading)) < 0.0001, "a body push preserves the car heading")
			check(absf(distances[0] - distances[1]) < 0.08, "24 and 60 FPS move a pushed car the same distance")

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
	var box = game.Recovery.Hitbox.bounds(racer.node)
	var from_car = -direction.rotated(Vector3.UP, -racer.node.rotation.y)
	var reach = minf(box.size.x * 0.5 / maxf(absf(from_car.x), 0.0001), box.size.z * 0.5 / maxf(absf(from_car.z), 0.0001))
	game.walker = racer.node.position + (box.get_center() + from_car * (reach + 0.4)).rotated(Vector3.UP, racer.node.rotation.y)
	game.walker.y = game.stage.walking_ground(game.walker)
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
	continuous_push(game)

	# Players tow each other's cars and their own.
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
	# A guest can pull their own car on the host.
	game.room.peers.helper.state.tow = false
	friend.tow = true
	friend.pos = game.room.a(moved + Vector3(4, 0, 0))
	game.room.peers.friend.state = friend
	var parked = game.room.v(game.room.peers.friend.state.car)
	game.room.update_tow(0.5)
	check(flat_distance(game.room.v(game.room.peers.friend.state.car), parked) > 0.3, "guest tows their own car on the host")
	check(game.recovery_links.any(func(link): return link.get("car", "") == "friend" and link.player == "friend"), "own-car rope identifies the guest as both owner and puller")
	# The authoritative prediction solver must retain the recovered pose; a
	# later driving snapshot must not restore its old height or spring state.
	var solver = preload("res://scripts/net/drive_prediction.gd").new()
	solver.reset(game.room.v(game.room.peers.friend.state.car), 0.0)
	game.room.host_drives.friend = solver
	game.Recovery.move_car(game, "friend", solver.node.position + Vector3(1, -5, 0), 0.7, 0.25)
	check(solver.node.position.distance_to(game.room.v(game.room.peers.friend.state.car)) < 0.01, "guest solver and peer state share the recovered position")
	check(game.room.peers.friend.state.tilt == game.room.a(solver.node.rotation) and absf(solver.yaw - solver.node.rotation.y) < 0.00001, "guest recovery shares heading and terrain tilt")
	check(solver.motion.initialized and solver.motion.grounded and solver.motion.vertical_speed == 0.0, "recovery resets the guest spring before driving resumes")
	var side = Vector3.RIGHT.rotated(Vector3.UP, solver.yaw)
	var peer_box = game.Recovery.Hitbox.bounds(game.room.peers.friend.car)
	var pushing = helper.duplicate()
	pushing.tow = false
	pushing.push = game.room.a(-side)
	pushing.pos = game.room.a(solver.node.position + Vector3(peer_box.end.x + 0.4, 0, peer_box.get_center().z).rotated(Vector3.UP, solver.yaw))
	var passive = friend.duplicate()
	passive.tow = false
	passive.pos = game.room.a(solver.node.position + Vector3(0, 0, 30))
	var before_push: Vector3 = solver.node.position
	var before_yaw: float = solver.yaw
	game.Recovery.update(game, {"friend": passive, "helper": pushing}, 1.0 / 60)
	check(solver.node.position == before_push, "walking into a player's car does not push it")
	pushing.running = true
	game.Recovery.update(game, {"friend": passive, "helper": pushing}, 1.0 / 60)
	check((before_push - solver.node.position).dot(side) > 0.01 and solver.yaw == before_yaw, "pushing a predicted guest uses the visible car bounds and preserves heading")
	game.room.host_drives.clear()
	game.room.peers.clear()

	# The local car works both in a room and offline (where the owner is "local").
	for online in [true, false]:
		game.room.connected = online
		game.car.position = own
		game.walker = own + Vector3(-4, 0, 0)
		game.walker.y = game.stage.ground(game.walker)
		check(game.nearby_tow_target(), "own car is discoverable on foot")
		game.mobile_controls._layout()
		check(game.mobile_controls.buttons.any(func(b): return b.action == "tow"), "mobile rope is available beside own car")
		Input.action_press("tow")
		if online:
			game.room.update_tow(0.5)
		else:
			game._update_tow(0.5)
		check(flat_distance(game.car.position, own) > 0.3, "owner pulls their car online and offline")
		check(game.tow_target == game.car and game.rope_mesh != null, "own-car rope resolves to the local car")
		game.hud_state = []
		game._update_hud()
		check(game.info_label.text.contains("ТЯНЕМ СВОЮ МАШИНУ"), "HUD identifies own car")
		Input.action_release("tow")
		var released: Vector3 = game.car.position
		if online:
			game.room.update_tow(0.5)
		else:
			game._update_tow(0.5)
		check(game.car.position == released and game.tow_target == null, "releasing own-car rope stops towing")
	game.car.position = Vector3(170, 0, 0)

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
