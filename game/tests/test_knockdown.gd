extends "res://tests/harness.gd"
# Knockdowns (injuries.gd): a car throws a person, the body flies on engine
# physics and lies, the stage is red-flagged, an ambulance drives from the
# start, parks, treats, and the person stands up and limps.
func _initialize() -> void:
	call_deferred("run")

func make_game(name: String) -> Node:
	var game = load("res://main.tscn").instantiate()
	game.name = name
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.rng.seed = 110
	game.start_game()
	game.stage.trees.clear()
	# Exercise rescue lifecycle on an unobstructed route. Keep official
	# colliders: their removal on knockdown is checked separately below.
	game.stage.rocks = game.stage.rocks.filter(func(rock): return rock.get("official", false))
	game.course.phase = "racing"
	return game

func ambulance(game) -> Dictionary:
	for racer in game.racers:
		if racer.get("role", "") == "ambulance":
			return racer
	return {}

func run() -> void:
	var game = await make_game("Host")
	var key: String = game.injuries.local_key()
	# A crew runs into the player standing on the road: no game over.
	game.in_car = false
	game.walker = game.race_at(300.0)
	game.walker.y = game.stage.ground(game.walker)
	var start: Vector3 = game.walker
	game.spawn_racer("pass")
	var crew = game.racers[0]
	crew.s = 270.0
	crew.node.position = game.race_at(crew.s)
	crew.previous = crew.node.position
	for i in range(240):
		game._update_racers(1.0 / 60.0)
		if game.injuries.down:
			break
	check(game.injuries.down and not game.dead, "a crew knocks the player down instead of ending the outing")
	check(game.injuries.records[key].phase == "flying" and game.injuries.records[key].body is RigidBody3D, "the body flies as an engine rigid body")
	check(not ambulance(game).is_empty() and ambulance(game).s < 5.0, "an ambulance leaves the start of the stage")
	game.injuries.update(0.0)
	check(game.course.red_flag and game.course.caption().contains("КРАСНЫЙ ФЛАГ"), "the stage is red-flagged")
	game.hud_state = []
	game._update_hud()
	check(game.info_label.text.contains("СКОРАЯ"), "the HUD tells the player an ambulance is coming")
	game.player.toggle_car()
	check(not game.in_car and game.interaction.current().is_empty() and not game.jump(), "a downed player cannot get up, act or jump")

	# The flight ends lying on the ground, away from the impact.
	for i in range(420):
		await physics_frame
		game.injuries.update(1.0 / 60.0)
		if game.injuries.records[key].phase == "lying":
			break
	var lying: Dictionary = game.injuries.records[key]
	check(lying.phase == "lying", "the body comes to rest")
	check(Vector2(lying.pos.x - start.x, lying.pos.z - start.z).length() > 1.0, "the hit throws the body away from where it stood")
	check(absf(lying.pos.y - game.stage.ground(lying.pos) - 0.25) < 0.3 and absf(lying.rot.z - PI / 2) < 0.01, "the person lies on the ground")
	check(game.find_children("KnockedBody", "", true, false).size() <= 1, "the physics body is released once landed")

	# Red flag: no crew starts while the ambulance is out.
	var clock: float = game.spawn_clock
	game.course.update(game, 5.0)
	check(game.spawn_clock == clock, "no new crew starts under the red flag")

	# The ambulance drives up, parks beside the casualty, treats and leaves.
	var van: Dictionary = ambulance(game)
	var parked = false
	for i in range(4000):
		game._update_racers(1.0 / 30.0)
		game.injuries.update(1.0 / 30.0)
		parked = parked or van.state == "parked"
		if not game.injuries.down:
			break
	check(parked and absf(van.s - lying.station) <= 6.0 and van.node.position.distance_to(lying.pos) <= 8.0, "the ambulance parks within safe treatment range")
	check(not game.injuries.down and game.injuries.limp > 55.0, "after treatment the player stands up and limps")
	check(game.injuries.local_avatar == null and game.walker.distance_to(lying.pos) < 1.0, "the player gets up where they lay")
	check(absf(game.injuries.walk_factor() - game.injuries.LIMP_FACTOR) < 0.001, "limping slows walking")
	Input.action_press("sprint")
	Input.action_press("forward")
	check(not game.player.running() and not game.jump(), "no running or jumping while limping")
	Input.action_release("sprint")
	Input.action_release("forward")
	check(game.course.red_flag and not ambulance(game).is_empty(), "red flag remains after treatment until the ambulance exits")
	for i in range(2000):
		game._update_racers(1.0 / 30.0)
		game.injuries.update(1.0 / 30.0)
		if ambulance(game).is_empty():
			break
	check(ambulance(game).is_empty() and not game.course.red_flag, "the ambulance leaves the stage and the red flag is lifted")
	game.injuries.update(61.0)
	game.injuries.update(0.1)
	check(game.injuries.limp == 0.0 and not game.injuries.records.has(key), "the limp wears off")

	# Spectators and marshals are thrown too; slow cars only bump.
	var person = game.spectators.people[0]
	var at: Vector3 = person.avatar.position
	check(not game.injuries.vehicle_sweep(at + Vector3(0, 0, 3), at - Vector3(0, 0, 3), Vector3(0, 0, -3), game.injuries.PLAYER_CAR_SPEED), "a slow player car does not throw anybody")
	check(game.injuries.vehicle_sweep(at + Vector3(0, 0, 3), at - Vector3(0, 0, 3), Vector3(0, 0, -12), game.injuries.PLAYER_CAR_SPEED), "a fast car throws a spectator")
	game.injuries.update(0.0)
	check(game.injuries.holds(person.avatar) and game.spectators.push_helpers().is_empty(), "a thrown spectator is held by the injury, not their routine")
	var marshal = game.stage.officials.people[0]
	var post: Vector3 = marshal.avatar.position
	game.injuries.vehicle_sweep(post + Vector3(3, 0, 0), post - Vector3(3, 0, 0), Vector3(-12, 0, 0), game.injuries.PLAYER_CAR_SPEED)
	check(game.injuries.is_down("marshal:%d" % marshal.id), "a fast car throws a marshal")
	check(game.stage.rock_hit(post + Vector3(2, 0.2, 0), post - Vector3(2, -0.2, 0), 0.85).is_empty(), "a thrown marshal no longer blocks cars like a rock")
	check(ambulance(game).size() > 0, "a new ambulance comes for them")
	# Under the red flag every marshal still standing waves a red flag.
	game.injuries.update(0.0)
	game.stage.officials.update(game, 0.1, false)
	var others = game.stage.officials.people.filter(func(p): return p.id != marshal.id)
	check(not others.is_empty() and others.all(func(p): return p.action == "flag" and p.avatar.get_node("RightArm/RedFlag").visible), "standing marshals wave red flags")
	check(not marshal.avatar.get_node("RightArm/RedFlag").visible, "the knocked-down marshal shows no flag")

	# A crew ramming the player's car damages it; nobody dies.
	game.injuries.records.clear()
	game.course.red_flag = false
	for racer in game.racers.duplicate():
		racer.node.queue_free()
		game.racers.erase(racer)
	game.in_car = true
	game.car.position = game.race_at(500.0)
	game.condition = 100.0
	game.spawn_racer("pass")
	var rammer = game.racers[0]
	# A crew sliding off its line cannot brake for the car in its way.
	rammer.s = 492.0
	rammer.node.position = game.race_at(rammer.s)
	rammer.previous = rammer.node.position
	rammer.state = "offroad"
	rammer.motion.velocity = game.race_direction(rammer.s) * 15.0
	for i in range(120):
		game._update_racers(1.0 / 60.0)
		if rammer.state in ["stopped", "stranded"]:
			break
	check(rammer.state in ["stopped", "stranded"] and game.condition < 100.0 and not game.dead, "a crew ramming the player's car damages it")
	check(game.crews.car_ram_damage(1.0) == 0.0 and game.crews.car_ram_damage(20.0) == game.crews.CAR_RAM_MAX_DAMAGE, "slow contact has no damage while high-speed collisions reach full impact damage")
	check(game.crews.car_ram_damage(10.0) > 0.0 and game.crews.car_ram_damage(10.0) < game.crews.CAR_RAM_MAX_DAMAGE, "intermediate impact velocity causes proportionate vehicle damage")

	# Guests: the host's knockdown of a guest reaches that guest.
	var guest = await make_game("Guest")
	game.room.connected = true
	game.room.is_host = true
	game.room.player_id = "host"
	guest.room.connected = true
	guest.room.player_id = "friend"
	guest.in_car = false
	var spot: Vector3 = game.race_at(200.0)
	spot.y = game.stage.ground(spot)
	game.room.peers = {"friend": {"id": "friend", "state": {"pos": game.room.a(spot), "car": [150, 0, 0], "in_car": false}}}
	game.injuries.vehicle_sweep(spot + Vector3(0, 0, 3), spot - Vector3(0, 0, 3), Vector3(0, 0, -15), game.injuries.CREW_SPEED)
	check(game.injuries.is_down("player:friend"), "the host knocks a guest down")
	guest.room.apply_world(game.room.world_state())
	check(guest.injuries.down and guest.injuries.local_avatar != null, "the guest learns it was knocked down")
	guest.injuries.update(0.1)
	guest.hud_state = []
	guest._update_hud()
	check(guest.info_label.text.contains("ТЕБЯ СБИЛИ"), "the guest HUD shows the knockdown")
	check(guest.course.red_flag or game.course.red_flag, "the red flag reaches the room")
	game.room.peers.clear()
	for g in [game, guest]:
		await g._shutdown_audio()
		g.queue_free()
	await process_frame
	print("KNOCKDOWN RESULT: %d failures" % failures)
	finish()
