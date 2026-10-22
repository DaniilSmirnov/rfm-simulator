extends "res://tests/harness.gd"
# A casualty the doctor cannot reach on foot must not hold the red flag forever.

func _initialize() -> void:
	call_deferred("run")

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
	# Fence the casualty in with a ring of boulders.
	var spot: Vector3 = game.race_at(404.0) + game.race_side(400.0) * 8.0
	spot.y = game.stage.ground(spot)
	for i in range(16):
		var a = i * TAU / 16.0
		var p = spot + Vector3(cos(a), 0, sin(a)) * 2.6
		p.y = game.stage.ground(p)
		game.stage.rocks.append({"pos": p, "radius": 0.8, "height": 3.0})
	var key = "npc:%d" % game.spectators.people[0].id
	var record = {"phase": "lying", "time": 0.0, "pos": spot + Vector3(0, 0.25, 0), "rot": Vector3(0, 0, PI / 2), "treat": 0.0, "limp": 0.0, "ambulance": van.id, "station": game.race_station(spot)}
	game.injuries.records[key] = record
	game.injuries._retarget(van)
	check(van.target_key == key, "the ambulance is sent to the fenced-in casualty")
	var stood_at = -1.0
	for i in range(60 * 30):
		game.injuries.update(1.0 / 30.0)
		game.injuries.ambulance_step(van)
		if record.treat > 0.0:
			check(false, "nobody treats the casualty through the boulders")
			break
		if not game.injuries.records.has(key):
			stood_at = i / 30.0
			break
	check(stood_at >= game.injuries.RESCUE_GIVE_UP - 1.0, "the casualty waits for the doctor before giving up (%.1f s)" % stood_at)
	check(stood_at > 0.0 and stood_at <= game.injuries.RESCUE_GIVE_UP + 2.0, "the unreachable casualty gets up unaided")
	check(game.injuries.records.is_empty(), "nobody is left lying on the stage")
	var boarded = false
	for i in range(40 * 30):
		game.injuries.update(1.0 / 30.0)
		if not game.injuries.medics.active.has(int(van.id)):
			boarded = true
			break
	check(boarded and str(van.get("treating", "")) == "" and van.state == "racing", "the doctor boards and the ambulance drives on")
	# A doctor lost on the way back still boards.
	game.injuries.records.clear()
	var medic = game.injuries.medics._create(int(van.id), spot)
	medic.door = van.node.position + van.node.basis.x * 1.85
	medic.exit_from = medic.door
	medic.state = "returning"
	medic.time = 0.0
	var inside = false
	for i in range(30 * 30):
		game.injuries.update(1.0 / 30.0)
		if not game.injuries.medics.active.has(int(van.id)):
			inside = true
			break
	check(inside, "a doctor who cannot walk back to the door boards after %.0f s" % game.injuries.medics.RETURN_GIVE_UP)
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	print("AMBULANCE UNREACHABLE RESULT: %d failures" % failures)
	finish()
