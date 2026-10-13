extends "res://tests/harness.gd"

func _initialize() -> void:
	call_deferred("run")

func patient(game, key: String, position: Vector3, van: Dictionary) -> Dictionary:
	position.y = game.stage.ground(position) + 0.25
	var record = {"phase": "lying", "time": 0.0, "pos": position, "rot": Vector3(0, 0, PI / 2), "treat": 0.0, "limp": 0.0, "ambulance": van.id, "station": game.race_station(position)}
	game.injuries.records[key] = record
	return record

func advance(game, seconds: float) -> void:
	for i in range(ceili(seconds * 30)):
		game.injuries.update(1.0 / 30.0)

func wait_state(game, van: Dictionary, state: String, seconds: float = 20.0) -> bool:
	for i in range(ceili(seconds * 30)):
		game.injuries.update(1.0 / 30.0)
		var medic: Dictionary = game.injuries.medics.active.get(int(van.id), {})
		if not medic.is_empty() and medic.state == state:
			return true
	return false

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.rng.seed = 110
	game.start_game()
	game.in_car = true
	game.stage.trees.clear()
	game.stage.rocks = game.stage.rocks.filter(func(rock): return rock.get("official", false))
	game.spawn_course_car("ambulance", 501)
	game.injuries._serial = 1
	var van: Dictionary = game.racers[-1]
	van.s = 400.0
	van.node.position = game.race_at(400.0)
	van.node.position.y = game.stage.ground(van.node.position)
	van.node.rotation.y = atan2(-game.race_direction(400.0).x, -game.race_direction(400.0).z)
	van.drive_speed = 0.0
	var side: Vector3 = game.race_side(400.0)
	var first = patient(game, "npc:7001", game.race_at(404.0) + side * 5, van)
	var nearby = patient(game, "npc:7002", game.race_at(395.0) + side * 5, van)
	var far = patient(game, "npc:7003", game.race_at(480.0) + side * 5, van)
	van.target_key = "npc:7001"
	van.target_s = first.station
	check(wait_state(game, van, "treating"), "doctor reaches the first patient")
	check(first.treat == 0 and nearby.treat == 0 and far.treat == 0, "there is no remote or simultaneous treatment")
	advance(game, 2.9)
	check(game.injuries.records.has("npc:7001") and nearby.treat == 0, "first patient remains down before three seconds; second patient waits")
	advance(game, 0.1)
	check(not game.injuries.records.has("npc:7001"), "first patient stands after three seconds")
	var medic: Dictionary = game.injuries.medics.active[int(van.id)]
	check(medic.key == "npc:7002" and medic.state == "walking" and van.state == "parked", "doctor walks to a nearby patient behind the ambulance without boarding")
	check(wait_state(game, van, "treating"), "doctor reaches the second patient")
	advance(game, 3.0)
	check(not game.injuries.records.has("npc:7002") and far.treat == 0 and medic.state == "returning", "doctor finishes the second patient and returns instead of treating a distant one")
	check(wait_state(game, van, "entering"), "doctor walks back to the ambulance door")
	check(van.state == "parked", "ambulance cannot leave before the doctor boards")
	advance(game, 0.7)
	check(not game.injuries.medics.active.has(int(van.id)) and van.state == "racing" and van.target_key == "npc:7003", "after boarding the ambulance drives towards the distant casualty")

	# A victim knocked far behind the car must receive a new dispatch.
	far.station = 200.0
	far.pos = game.race_at(200.0) + side * 5
	far.pos.y = game.stage.ground(far.pos) + 0.25
	game.injuries.update(0.1)
	check(int(far.ambulance) != int(van.id) and not game.injuries._ambulance(int(far.ambulance)).is_empty(), "a casualty displaced behind the van is reassigned, not abandoned")

	# Snapshot round trip: guest sees movement/lean, cannot advance treatment,
	# removes the doctor on boarding, and restores an NPC's upright pose.
	game.injuries.records.clear()
	van.s = 400.0
	van.node.position = game.race_at(400.0)
	var actual_key = "npc:%d" % game.spectators.people[0].id
	var actual = patient(game, actual_key, game.race_at(404.0) + side * 5, van)
	van.target_key = actual_key
	van.target_s = actual.station
	check(wait_state(game, van, "treating"), "doctor starts a subsequent rescue")
	advance(game, 0.3)
	var world: Dictionary = game.room.world_state()
	check(world.has("medics") and world.medics.size() == 1 and world.medics[0].state == "treating", "world snapshot carries the medic and treatment pose")
	var guest = load("res://main.tscn").instantiate()
	root.add_child(guest)
	await process_frame
	guest.set_process(false)
	guest.room.set_process(false)
	guest.start_game()
	guest.room.connected = true
	guest.room.is_host = false
	guest.room.player_id = "friend"
	guest.room.apply_world(world)
	guest.injuries.update(0.3)
	check(guest.injuries.medics.active.size() == 1, "late guest creates the medic from the room snapshot")
	var guest_medic: Dictionary = guest.injuries.medics.active[int(van.id)]
	check(guest_medic.avatar.get_node("MedicalTorso").rotation.x < -0.3 and guest_medic.avatar.get_node("RightLeg/RightShin").rotation.x < -1.2, "guest sees the doctor kneel over the patient")
	guest.injuries.update(4.0)
	check(guest.injuries.is_down(actual_key), "guest cannot heal independently of the host")
	advance(game, 3.0)
	guest.injuries.apply_snapshot(game.injuries.snapshot())
	var avatar = guest.injuries.avatar_of(actual_key)
	check(not guest.injuries.is_down(actual_key) and absf(avatar.rotation.z) < 0.01, "a healed guest NPC stands upright when its injury disappears")
	guest.injuries.medics.apply_snapshot([])
	check(guest.injuries.medics.active.is_empty(), "boarding removes the medic on guests")
	# A casualty knocked far from the road: the ambulance stops at the road and
	# the doctor still walks the whole way, however long it is.
	for distance in [30.0, 60.0, 120.0]:
		game.injuries.records.clear()
		for id in game.injuries.medics.active.keys():
			game.injuries.medics._remove(id)
		van.s = 400.0
		van.node.position = game.race_at(400.0)
		van.node.position.y = game.stage.ground(van.node.position)
		van.node.rotation.y = atan2(-game.race_direction(400.0).x, -game.race_direction(400.0).z)
		van.drive_speed = 0.0
		van.state = "racing"
		var remote_key = "npc:%d" % (8000 + int(distance))
		var remote = patient(game, remote_key, game.race_at(404.0) + side * distance, van)
		# The van has driven to its stop level with the casualty.
		van.s = remote.station - 4.0 + (8.0 if distance > 100.0 else 0.0)
		van.node.position = game.race_at(van.s)
		van.node.position.y = game.stage.ground(van.node.position)
		game.injuries._retarget(van)
		var arrived = false
		for i in range(60 * 30):
			game.injuries.update(1.0 / 30.0)
			game.injuries.ambulance_step(van)
			if game.injuries.medics.active.has(int(van.id)) and game.injuries.medics.active[int(van.id)].state == "treating":
				arrived = true
				break
			var m: Dictionary = game.injuries.medics.active.get(int(van.id), {})
		check(arrived, "doctor reaches a casualty %.0f m from the road" % distance)
		advance(game, 3.1)
		check(not game.injuries.records.has(remote_key), "casualty %.0f m from the road is treated" % distance)
		for id in game.injuries.medics.active.keys():
			game.injuries.medics._remove(id)
	# Real marshal casualty, including its official collision record.
	game.injuries.records.clear()
	game.injuries.returning.clear()
	for id in game.injuries.medics.active.keys():
		game.injuries.medics._remove(id)
	var marshal: Dictionary = game.stage.officials.people[1]
	var marshal_key = "marshal:%d" % marshal.id
	var post: Vector3 = marshal.avatar.position
	check(game.injuries.knock(marshal_key, post, Vector3(8, 0, 0), post - Vector3.RIGHT), "marshal is knocked down through the real injury lifecycle")
	var injury: Dictionary = game.injuries.records[marshal_key]
	game.injuries._land(injury)
	van.s = game.race_station(injury.pos) - 4.0
	van.node.position = game.race_at(van.s)
	van.node.position.y = game.stage.ground(van.node.position)
	van.node.rotation.y = atan2(-game.race_direction(van.s).x, -game.race_direction(van.s).z)
	van.drive_speed = 0.0
	injury.ambulance = van.id
	van.target_key = marshal_key
	van.target_s = injury.station
	check(wait_state(game, van, "treating"), "doctor reaches the fallen marshal")
	var marshal_medic: Dictionary = game.injuries.medics.active[int(van.id)]
	check(marshal_medic.avatar.position.distance_to(injury.pos) > game.injuries.medics.REACH, "kneeling on the marshal slope moves the visual root outside treatment reach")
	advance(game, 2.9)
	check(game.injuries.is_down(marshal_key) and injury.treat > 2.8, "kneeling does not interrupt the marshal's three-second treatment")
	advance(game, 0.1)
	check(not game.injuries.is_down(marshal_key), "doctor heals the marshal after three seconds")
	# Recovery owns the NPC until it has walked to its original off-road post.
	game.injuries.returning.clear()
	game.injuries.records.clear()
	var person: Dictionary = game.spectators.people[0]
	var home: Vector3 = game.race_at(420.0) + game.race_side(420.0) * 9.0
	home.y = game.stage.ground(home)
	person.home = home
	var start: Vector3 = game.race_at(420.0)
	start.y = game.stage.ground(start)
	var recovery = patient(game, actual_key, start, van)
	game.injuries._stand(actual_key, recovery)
	check(person.avatar.position.distance_to(start) < 0.01, "healing stands the NPC at the casualty location without teleporting home")
	check(game.injuries.returning.has(actual_key) and not game.injuries.is_down(actual_key), "healed NPC walks home but is no longer a casualty")
	game.injuries.update(0.1)
	var after: Vector3 = person.avatar.position
	check(after.distance_to(start) > 0.01 and after.distance_to(start) <= 0.28, "returning NPC advances at walking speed")
	game.spectators.update(game.elapsed, 0.1, false)
	check(person.avatar.position == after, "ordinary spectator activity cannot override the return walk")
	guest.injuries.apply_snapshot(game.injuries.snapshot())
	guest.injuries.update(0.1)
	check(not guest.injuries.is_down(actual_key) and guest.injuries.holds(avatar), "guest sees recovery movement without treating the NPC as injured")
	advance(game, 6.0)
	check(not game.injuries.returning.has(actual_key) and person.avatar.position.distance_to(home) < 0.21, "NPC finishes walking at its original place beyond the road")
	guest.injuries.apply_snapshot(game.injuries.snapshot())
	check(avatar.position.distance_to(home) < 0.01, "guest finishes at the home position even when the last walking update was skipped")
	# A second collision must retain the original post, not the road position.
	var again = patient(game, actual_key, start, van)
	game.injuries._stand(actual_key, again)
	check(game.injuries.knock(actual_key, start, Vector3(6, 0, 0), start - Vector3.RIGHT), "a healed returning NPC can be hit again")
	check(not game.injuries.returning.has(actual_key) and game.injuries.records[actual_key].home == home, "another impact cancels walking and preserves the original home")
	for g in [game, guest]:
		await g._shutdown_audio()
		g.queue_free()
	await process_frame
	print("AMBULANCE MEDICS RESULT: %d failures" % failures)
	finish()
