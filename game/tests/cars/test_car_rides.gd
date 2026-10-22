extends "res://tests/harness.gd"
# Riding in a friend's car and towing a broken car with your own
# (car_rides.gd): five seats with the driver, passengers arrive with the car,
# a broken car stays in the game, and the outing ends only when every car is
# broken.
const NetProtocol = preload("res://scripts/net/net_protocol.gd")
const PeerView = preload("res://scripts/net/peer_view.gd")

func _initialize() -> void:
	call_deferred("run")

func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func on_stage(game, station: float, side: float) -> Vector3:
	var point: Vector3 = game.stage.at(station) + game.stage.side(station) * side
	point.y = game.stage.ground(point)
	return point

func friend_state(game, car: Vector3, in_car: bool, extra: Dictionary = {}) -> Dictionary:
	var state = {"pos": game.room.a(car), "car": game.room.a(car), "in_car": in_car, "tow": false, "push": [0, 0, 0], "beers": 0, "heading": 0.0, "yaw": 0.0, "pitch": 0.0, "speed": 0.0}
	state.merge(extra, true)
	return state

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
	game.room.connected = true
	game.room.is_host = true
	game.room.player_id = "host"
	var rides = game.rides

	# Boarding: the friend's car takes the local player along.
	var friend_car = on_stage(game, 300, 12)
	game.room._update_peers([{"id": "friend", "name": "Друг", "state": friend_state(game, friend_car, true)}])
	game.room._update_members([{"id": "friend", "name": "Друг"}])
	game.in_car = false
	game.car.position = on_stage(game, 500, 12)
	game.walker = friend_car + Vector3(2.5, 0, 0)
	check(rides.occupants("friend") == 1, "the friend at the wheel takes one of five seats")
	rides.board("friend")
	check(game.in_car and rides.ride == "friend", "the player gets into the friend's car")
	check(game.player_position() == game.room.peers.friend.car.position, "a passenger sits in the friend's car, not their own")
	var state = game.room.local_state()
	check(state.in_car and state.ride == "friend" and state.pos == game.room.a(friend_car), "the ride travels in the player's state")
	check(NetProtocol.clean_state(state).ride == "friend", "the host keeps the ride of a state from the direct link")
	state.in_car = false
	check(NetProtocol.clean_state(state).ride == "", "a player on foot rides nobody's car")
	var moved = on_stage(game, 330, 3)
	game.room.peers.friend.car.position = moved
	game._drive(0.1)
	check(game.walker == moved and game.player_position() == moved, "the passenger moves with the friend's car")
	game.mobile_controls._layout()
	check(game.mobile_controls.buttons.any(func(b): return b.action == "interact") and not game.mobile_controls.buttons.any(func(b): return b.action == "forward"), "a passenger has an exit button and no pedals")
	game.hud_state = []
	game._update_hud()
	check(game.info_label.text.contains("ПАССАЖИР"), "the HUD shows the player is a passenger")
	game._toggle_car()
	check(not game.in_car and rides.ride == "" and flat_distance(game.walker, moved) > 1.5 and flat_distance(game.walker, moved) < 3.5, "the passenger gets out beside the friend's car")

	# Five seats with the driver.
	var full: Array = [{"id": "friend", "name": "Друг", "state": friend_state(game, moved, true)}]
	for id in ["a1", "a2", "a3", "a4"]:
		full.append({"id": id, "name": id, "state": friend_state(game, moved, true, {"ride": "friend"})})
	game.room._update_peers(full)
	check(rides.occupants("friend") == 5, "a driver and four passengers fill the car")
	rides.board("friend")
	check(not game.in_car and rides.ride == "", "a sixth person does not fit")
	game.room._update_peers(full.slice(0, 4))
	rides.board("friend")
	check(game.in_car and rides.ride == "friend", "the last free seat can be taken")
	# Two people took the last seat at once: the later one by id gets out.
	game.room._update_peers(full)
	game._drive(0.1)
	check(not game.in_car and rides.ride == "", "a passenger over the limit leaves the car")

	# The outing ends with the passenger arriving in the friend's car.
	var park: Vector3 = game.stage.parks.visitor_pose(0, 2).origin
	game.room._update_peers([{"id": "friend", "name": "Друг", "state": friend_state(game, park, true)}])
	game.room.peers.friend.car.position = park
	game.walker = park + Vector3(2.5, 0, 0)
	rides.board("friend")
	check(game.stage.parks.park_at(game.car.position) < 0, "the player's own car stays out on the stage")
	check(game.park_traffic.everyone_home(), "a passenger counts as arrived with the friend's car in the park")
	var guest_rider = friend_state(game, on_stage(game, 600, 12), true, {"ride": "host"})
	game.car.position = game.stage.parks.visitor_pose(0, 3).origin
	rides.leave(true)
	game.in_car = true
	game.room._update_peers([{"id": "friend", "name": "Друг", "state": friend_state(game, park, true)}, {"id": "guest", "name": "Гость", "state": guest_rider}])
	check(game.park_traffic.everyone_home(), "a guest riding in the host's car arrives with it")
	game.room.peers.friend.state.in_car = false
	check(not game.park_traffic.everyone_home(), "nobody arrives while the driver is still outside")
	# A friend away from the keyboard, or one whose connection is gone, does not hold the day.
	var friend: Dictionary = game.room.peers.friend
	var now = game.room.server_clock()
	PeerView.note_activity(friend, now)
	friend.activity.time = now - PeerView.AWAY_SECONDS - 1.0
	check(game.park_traffic.everyone_home(), "a friend who has not moved for two minutes does not hold the day")
	PeerView.note_activity(friend, now)
	check(game.park_traffic.everyone_home(), "standing still with the same view is no sign of life")
	friend.state.yaw = 1.0
	PeerView.note_activity(friend, now)
	check(not game.park_traffic.everyone_home(), "looking round counts as being back")
	friend.last_state_time = now - PeerView.LOST_SECONDS - 1.0
	check(game.park_traffic.everyone_home(), "a friend not heard from since the reconnect timeout does not hold the day")
	friend.last_state_time = now

	# A broken car no longer ends the outing while a friend's car still drives.
	game.room._update_peers([{"id": "friend", "name": "Друг", "state": friend_state(game, on_stage(game, 300, 3), true)}])
	game.car.position = on_stage(game, 310, 3)
	game.heading = atan2(-game.stage.direction(310).x, -game.stage.direction(310).z)
	game.in_car = true
	game.condition = 0.0
	var parked: Vector3 = game.car.position
	Input.action_press("forward")
	for i in range(30):
		game._drive(1.0 / 30.0)
	Input.action_release("forward")
	check(not game.dead, "a broken car does not end the outing in a room")
	check(flat_distance(game.car.position, parked) < 0.2, "a broken car does not drive")
	check(game.room.local_state().broken, "the broken car is reported to the room")
	rides.toggle_hitch()
	check(rides.hitch == "", "a broken car cannot tow")

	# A friend's car tows the broken one.
	game.condition = 100.0
	var wreck = on_stage(game, 300, 3)
	game.room._update_peers([{"id": "friend", "name": "Друг", "state": friend_state(game, wreck, false, {"broken": true})}])
	game.room.peers.friend.car.position = wreck
	game.car.position = on_stage(game, 306, 3)
	check(rides.hitch_candidate() == "friend", "the friend's broken car can go on the rope")
	rides.toggle_hitch()
	check(rides.hitch == "friend" and game.room.local_state().hitch == "friend", "the rope is hooked and travels in the state")
	game.car.position = on_stage(game, 318, 3)
	game.room.update_tow(0.1)
	var towed = game.room.v(game.room.peers.friend.state.car)
	check(flat_distance(towed, game.car.position) <= rides.TOW_LENGTH + 0.05 and flat_distance(towed, wreck) > 10, "the towed car follows at the length of the rope")
	check(game.recovery_links.any(func(link): return link.get("hitch", false) and link.car == "friend" and link.player == "host"), "the rope between the cars is shared in the snapshot")
	check(game.recovery_ropes.size() == 1, "the rope between the cars is drawn")
	game.hud_state = []
	game._update_hud()
	check(game.info_label.text.contains("ТЯНЕМ МАШИНУ ДРУГА"), "the HUD shows the friend's car on the rope")
	var rest = game.room.v(game.room.peers.friend.state.car)
	game.room.update_tow(0.1)
	check(flat_distance(game.room.v(game.room.peers.friend.state.car), rest) < 0.01, "a slack rope does not move the towed car")
	rides.toggle_hitch()
	check(rides.hitch == "", "T again unhooks the rope")
	game.room.peers.friend.state.broken = false
	game.room.peers.friend.state.in_car = true
	check(rides.hitch_candidate() == "", "a working car with its driver inside is not towed")

	# Only when every car is broken is the outing over.
	game.condition = 0.0
	game._drive(0.1)
	check(not game.dead, "one broken car leaves the outing going")
	game.room.peers.friend.state.broken = true
	game._drive(0.1)
	check(game.dead and game.menu_text.text.contains("Все машины разбиты"), "the outing ends when every car is broken")

	# Alone nobody can help: a broken car still ends the outing.
	game.dead = false
	game.menu.hide()
	game.room.peers.clear()
	game.room.connected = false
	game._drive(0.1)
	check(game.dead, "a solo player's broken car ends the outing")

	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	print("CAR RIDES RESULT: %d failures" % failures)
	finish()
