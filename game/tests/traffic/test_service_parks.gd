extends "res://tests/harness.gd"
# The day that runs through the service parks: cars wait in their bays, pull up under the arch, start on the
# timetable, roll into the park at the finish and back into their bays; pass 2
# leaves from there; the day ends when everybody has driven into a park.
const Stage = preload("res://scripts/stages/stage.gd")
const Parks = preload("res://scripts/traffic/service_parks.gd")

func _initialize() -> void:
	call_deferred("run")

func step(game, seconds: float) -> void:
	for i in range(int(seconds * 30)):
		game.course.update(game, 1.0 / 30.0)
		game._update_racers(1.0 / 30.0)

func mover(game, key: String) -> Dictionary:
	return game.park_traffic.mover(key)

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	await game.start_game()
	var traffic = game.park_traffic
	var parks = game.stage.parks
	check(traffic.parked[0].size() == Parks.KEYS.size() and traffic.parked[1].is_empty(), "the whole convoy waits in the park at the start")
	var police: Node3D = traffic.parked[0]["police_open"]
	check(parks.park_at(police.position) == 0 and absf(police.position.y - game.stage.ground(police.position) - 0.06) < 0.05, "a parked car stands on the paddock")
	check(parks.park_at(game.car.position) == 0 and game.stage.road_distance(game.car.position) > 8.0, "the player's car starts the day in the park, off the road")
	# The first car pulls up under the arch shortly before the stage opens.
	game.course.remaining = 30.0
	step(game, 3.0)
	check(mover(game, "police_open").is_empty(), "nobody leaves the park long before the start")
	game.course.remaining = Parks.CRUISE * 4.0
	step(game, 0.2)
	check(mover(game, "police_open").get("state", "") == "to_start", "the opening police leaves its bay")
	step(game, 14.0)
	var waiting = mover(game, "police_open")
	check(waiting.get("state", "") == "at_start" and waiting.node.position.distance_to(parks.line_pose(0).origin) < 0.6, "it waits at the start line under the arch")
	check(waiting.node == police, "the same car drives out of the park")
	# The stage opens: that very car starts from standing.
	step(game, 7.0)
	var racing: Dictionary = {}
	for racer in game.racers:
		if racer.get("role", "") == "opening_police" and racer.state == "racing":
			racing = racer
	check(not racing.is_empty() and racing.node == police and game.course.phase == "opening_police", "the timetable starts the waiting car")
	var swerve = 0.0
	while racing.s < 30.0 and racing.state == "racing":
		step(game, 0.1)
		swerve = maxf(swerve, absf(racing.line) + (1.0 if racing.avoiding else 0.0))
	check(swerve < 0.5, "it drives off the line straight, with nothing to dodge (%.2f m)" % swerve)
	check(mover(game, "zero1").get("state", "") in ["to_start", "at_start"], "the next car pulls up behind it")
	# Spectators' cars parked on the verge past the start are not in the way:
	# the car keeps its racing line instead of looking for a way round.
	var verge = false
	for group in game.spectators.groups:
		var station: float = game.race_station(group.car.position)
		verge = verge or (station > 30.0 and station < 120.0 and absf((group.car.position - game.race_at(station)).dot(game.race_side(station))) > 5.0)
	var dodged = false
	while racing.s < 120.0 and racing.state == "racing":
		step(game, 0.1)
		dodged = dodged or racing.avoiding
	check(verge and not dodged, "a spectator's car on the verge past the start is no reason for a detour")
	# At the finish it carries on into the other park and backs into its bay.
	racing.s = Stage.LENGTH - 25.0
	racing.node.position = game.race_at(racing.s)
	racing.previous = racing.node.position
	racing.line = 0.0
	racing.slide = 0.0
	racing.drive_speed = 9.0
	step(game, 6.0)
	check(mover(game, "police_open").get("state", "") == "to_park", "past the finish the car drives into the service park")
	check(game.course.phase == "zero", "the timetable moves on when the car crosses the finish")
	step(game, 30.0)
	check(traffic.parked[1].has("police_open") and traffic.parked[1]["police_open"] == police, "it parks in its bay at the other end")
	var bay: Transform3D = parks.slot_pose(1, "police_open")
	check(police.position.distance_to(bay.origin) < 0.8 and absf(wrapf(police.rotation.y - bay.basis.get_euler().y, -PI, PI)) < 0.25, "nose towards the aisle, ready for pass 2")
	# A room guest sees the same parks.
	var guest = load("res://main.tscn").instantiate()
	root.add_child(guest)
	await process_frame
	guest.set_process(false)
	guest.room.set_process(false)
	await guest.start_game()
	guest.park_traffic.apply_snapshot(traffic.snapshot())
	check(guest.park_traffic.parked[1].has("police_open") and not guest.park_traffic.parked[0].has("police_open"), "guests see which cars are parked where")
	# Pass 2 leaves from the park at the end of the route.
	game.course.phase = "intermission"
	game.course.remaining = 1.0
	traffic.settle()
	check(traffic.parked[1].size() == Parks.KEYS.size() and traffic.parked[0].is_empty(), "between passes every car is in the park at the end")
	game.course.remaining = 10.0
	step(game, 0.2)
	check(mover(game, "police_open").get("state", "") == "to_start" and traffic.start_end() == 1, "pass 2 starts from the far park")
	# The day ends in a service park, not merely in the car.
	game.course.pass_index = 2
	game.course.phase = "complete"
	for item in game.packing.items():
		game.packing.remove(item)
	game.in_car = true
	game.car.position = game.stage.at(300.0)
	game._check_finish()
	check(not game.finished, "getting into the car on the stage does not end the day")
	game.car.position = parks.world(0, 0.0, 30.0)
	game._check_finish()
	check(game.finished, "driving into a service park ends it")
	for g in [game, guest]:
		await g._shutdown_audio()
		g.queue_free()
	await process_frame
	print("SERVICE PARKS RESULT: %d checks, %d failures" % [checks, failures])
	finish()
