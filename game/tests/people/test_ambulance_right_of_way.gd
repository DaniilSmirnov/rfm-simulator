extends "res://tests/harness.gd"
# The ambulance always gets through: it goes round or, at walking pace,
# through parked cars and scenery, but never drives into a person.
const Traffic = preload("res://scripts/traffic/rally_traffic.gd")
const ServiceTraffic = preload("res://scripts/traffic/service_traffic.gd")

func _initialize() -> void:
	call_deferred("run")

func place(game, node: Node3D, station: float, line: float) -> void:
	node.position = game.race_at(station) + game.race_side(station) * line
	node.position.y = game.stage.ground(node.position)
	node.rotation.y = atan2(-game.race_direction(station).x, -game.race_direction(station).z)

func ambulance(game, station: float) -> Dictionary:
	for old in game.racers:
		old.node.queue_free()
	game.racers.clear()
	game.spawn_course_car("ambulance", 900 + game.racers.size())
	var van: Dictionary = game.racers[-1]
	van.s = station
	place(game, van.node, station, 0.0)
	return van

# Drives until the van is past `station`; returns the closest it came to any
# person, or -1 when it did not get past within the time limit.
func drive_past(game, van: Dictionary, station: float, seconds: float) -> float:
	var closest = INF
	for i in range(ceili(seconds * 30)):
		game.crews.update_racers_step(1.0 / 30.0)
		for person in game.injuries.people():
			closest = minf(closest, person.pos.distance_to(van.node.position))
		if float(van.s) > station:
			return closest
	return -1.0

func stopped_car(game, station: float, line: float) -> Dictionary:
	game.spawn_racer("pass")
	var car: Dictionary = game.racers[-1]
	car.state = "stopped"
	car.s = station
	place(game, car.node, station, line)
	return car

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
	# A probe that once failed is checked again after a short wait even if
	# the car has not moved: a momentary obstruction must not stop it forever.
	var van = ambulance(game, 60.0)
	van.path_probes = {"s": van.s, "line": van.line, "age": van.age, 1.5: {"distance": 20.0, "clear": false}}
	check(not Traffic._clear_path_cached(game, van, 1.5, 20.0), "fresh probe result is reused")
	van.age += Traffic.PROBE_MAX_AGE + 0.1
	check(Traffic._clear_path_cached(game, van, 1.5, 20.0), "stale probe result expires while standing still")

	# 1. The player's car left in the middle of the road.
	van = ambulance(game, 60.0)
	place(game, game.car, 120.0, 0.0)
	var closest = drive_past(game, van, 150.0, 60.0)
	check(closest >= 0.0, "ambulance gets past a car parked in the middle of the road")
	check(van.state == "racing", "ambulance stays on its route instead of bouncing off")

	# 2. A wall of cars across the whole road and verge.
	van = ambulance(game, 60.0)
	place(game, game.car, 120.0, 0.0)
	stopped_car(game, 120.0, -3.2)
	stopped_car(game, 120.0, 3.2)
	closest = drive_past(game, van, 150.0, 60.0)
	check(closest >= 0.0, "ambulance gets past cars blocking the full width")
	check(ServiceTraffic.priority(van) or float(van.s) > float(van.get("priority_until", 0.0)) - ServiceTraffic.PRIORITY_DISTANCE, "a blocked ambulance takes priority")

	# 3. A person standing in the middle of the road.
	van = ambulance(game, 60.0)
	place(game, game.car, 20.0, 6.0)
	game.in_car = false
	game.walker = game.race_at(200.0)
	game.walker.y = game.stage.ground(game.walker)
	closest = drive_past(game, van, 230.0, 90.0)
	check(closest >= 0.0, "ambulance drives round a person standing on the road")
	check(closest >= ServiceTraffic.PERSON_CLEARANCE - 0.3, "ambulance never comes close to the person (%.2f m)" % closest)

	# 4. The road is walled off by people: the ambulance waits, it never pushes through.
	van = ambulance(game, 60.0)
	game.walker = game.race_at(120.0)
	game.walker.y = game.stage.ground(game.walker)
	var fence: Array[Node3D] = []
	for line in [-6.0, -3.0, 3.0, 6.0]:
		var marker = Node3D.new()
		game.add_child(marker)
		place(game, marker, 120.0, line)
		game.spectators.people.append({"id": 9000 + fence.size(), "avatar": marker})
		fence.append(marker)
	closest = drive_past(game, van, 125.0, 20.0)
	check(closest < 0.0, "people across the whole road hold the ambulance")
	var nearest = INF
	for person in game.injuries.people():
		nearest = minf(nearest, person.pos.distance_to(van.node.position))
	check(nearest >= ServiceTraffic.PERSON_CLEARANCE - 0.3, "waiting ambulance keeps its distance (%.2f m)" % nearest)
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	print("AMBULANCE RIGHT OF WAY RESULT: %d checks, %d failures" % [checks, failures])
	finish()
