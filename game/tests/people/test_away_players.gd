extends "res://tests/harness.gd"
# A player who walked away from the keyboard cannot hold the stage: police
# waits for the road to clear, then goes through cars at walking pace; any
# service vehicle passes a player standing in its way after PLAYER_PATIENCE,
# never other people; a crew or zero car that cannot get past retires.
const ServiceTraffic = preload("res://scripts/traffic/service_traffic.gd")
const RallyCrews = preload("res://scripts/traffic/rally_crews.gd")

func _initialize() -> void:
	call_deferred("run")

func place(game, node: Node3D, station: float, line: float) -> void:
	node.position = game.race_at(station) + game.race_side(station) * line
	node.position.y = game.stage.ground(node.position)
	node.rotation.y = atan2(-game.race_direction(station).x, -game.race_direction(station).z)

func clear_racers(game) -> void:
	for old in game.racers:
		old.node.queue_free()
	game.racers.clear()

func course_car(game, role: String, station: float) -> Dictionary:
	clear_racers(game)
	game.spawn_course_car(role, 900)
	var car: Dictionary = game.racers[-1]
	car.s = station
	place(game, car.node, station, 0.0)
	return car

func stopped_car(game, station: float, line: float) -> void:
	game.spawn_racer("pass")
	var car: Dictionary = game.racers[-1]
	car.state = "stopped"
	car.s = station
	place(game, car.node, station, line)

# Seconds until `car` is past `station`, or -1 when it is not within `seconds`.
func time_past(game, car: Dictionary, station: float, seconds: float) -> float:
	for i in range(ceili(seconds * 30)):
		game.crews.update_racers_step(1.0 / 30.0)
		if float(car.s) > station:
			return i / 30.0
	return -1.0

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.rng.seed = 120
	game.start_game()
	game.course.phase = "racing"
	game.in_car = true

	# 1. Cars left across the whole road: the police asks, waits, then goes through.
	var police = course_car(game, "opening_police", 60.0)
	place(game, game.car, 120.0, 0.0)
	stopped_car(game, 120.0, -3.2)
	stopped_car(game, 120.0, 3.2)
	var taken = time_past(game, police, 150.0, 90.0)
	check(taken < 0.0 or taken >= ServiceTraffic.POLICE_PRIORITY_AFTER, "police waits for the road to clear first (%.1f s)" % taken)
	check(taken > 0.0, "police gets past cars left across the road")

	# 2. A red flag is no hold: the police does not take priority while it waits.
	police = course_car(game, "opening_police", 60.0)
	game.course.red_flag = true
	for i in range(30 * 30):
		game.crews.update_racers_step(1.0 / 30.0)
	check(not ServiceTraffic.priority(police), "police waiting out a red flag keeps to the rules")
	game.course.red_flag = false

	# 3. A player standing in the road between people on the verges: the
	# police waits for them, then passes the player but keeps clear of the others.
	police = course_car(game, "opening_police", 60.0)
	place(game, game.car, 20.0, 8.0)
	game.in_car = false
	game.walker = game.race_at(120.0)
	game.walker.y = game.stage.ground(game.walker)
	var fence: Array[Node3D] = []
	for line in [-4.6, 4.6]:
		var marker = Node3D.new()
		game.add_child(marker)
		place(game, marker, 120.0, line)
		game.spectators.people.append({"id": 9100 + fence.size(), "avatar": marker})
		fence.append(marker)
	var closest = INF
	taken = -1.0
	for i in range(90 * 30):
		game.crews.update_racers_step(1.0 / 30.0)
		for marker in fence:
			closest = minf(closest, marker.position.distance_to(police.node.position))
		if float(police.s) > 130.0:
			taken = i / 30.0
			break
	check(taken < 0.0 or taken >= ServiceTraffic.PLAYER_PATIENCE - 1.0, "a player in the road holds the police for a while (%.1f s)" % taken)
	check(taken > 0.0, "police passes a player who does not step aside")
	check(closest >= ServiceTraffic.PERSON_CLEARANCE - 0.3, "other people keep their distance (%.2f m)" % closest)
	for marker in fence:
		marker.queue_free()
	game.spectators.people = game.spectators.people.filter(func(person): return person.id < 9100)
	game.in_car = true

	# 4. A competitor behind cars it cannot pass retires and leaves the stage.
	clear_racers(game)
	place(game, game.car, 120.0, 0.0)
	stopped_car(game, 120.0, -3.2)
	stopped_car(game, 120.0, 3.2)
	game.spawn_racer("pass")
	var crew: Dictionary = game.racers[-1]
	crew.s = 60.0
	place(game, crew.node, 60.0, 0.0)
	for i in range((RallyCrews.CREW_PATIENCE + 15.0) * 30):
		game.crews.update_racers_step(1.0 / 30.0)
		if crew.state != "racing":
			break
	check(crew.state == "stopped" and crew.get("retired", false), "a crew held behind the cars retires (%s)" % crew.state)
	for i in range(20 * 30):
		game.crews.update_racers_step(1.0 / 30.0)
	check(not game.racers.any(func(racer): return racer.id == crew.id), "the retired crew leaves the stage")

	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	print("AWAY PLAYERS RESULT: %d checks, %d failures" % [checks, failures])
	finish()
