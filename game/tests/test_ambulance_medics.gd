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
	for g in [game, guest]:
		await g._shutdown_audio()
		g.queue_free()
	await process_frame
	print("AMBULANCE MEDICS RESULT: %d failures" % failures)
	finish()
