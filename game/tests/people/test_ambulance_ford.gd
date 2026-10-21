extends "res://tests/harness.gd"
# The road on the Finnish lakes stage dips through a ford. An ambulance held
# by a car standing in the ford goes round it through the water instead of
# taking every line across the flooded road for a lake.
const ServiceTraffic = preload("res://scripts/traffic/service_traffic.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.select_stage(4)
	await game.start_game()
	game.course.phase = "racing"
	game.in_car = true
	var ford: float = game.stage.finnish_forest.FORD_STATION
	check(game.stage.water.depth(game.race_at(ford)) > 0.2, "the road is under water in the ford")
	check(not ServiceTraffic.flooded(game, game.race_at(ford) + game.race_side(ford) * 3.0, ford), "the whole ford is drivable")
	check(ServiceTraffic.flooded(game, game.race_at(ford - 40.0) + game.race_side(ford - 40.0) * 30.0, ford - 40.0), "the lake beside the road is not")
	# The player's car left in the middle of the ford.
	game.car.position = game.race_at(ford)
	game.car.position.y = game.stage.ground(game.car.position)
	for old in game.racers:
		old.node.queue_free()
	game.racers.clear()
	game.spawn_course_car("ambulance", 900)
	var van: Dictionary = game.racers[-1]
	van.s = ford - 60.0
	van.node.position = game.race_at(van.s)
	van.node.position.y = game.stage.ground(van.node.position)
	var dry = true
	for i in range(60 * 30):
		game.crews.update_racers_step(1.0 / 30.0)
		dry = dry and not ServiceTraffic.flooded(game, van.node.position, game.race_station(van.node.position))
		if float(van.s) > ford + 40.0:
			break
	check(float(van.s) > ford + 40.0, "ambulance gets through the ford past a stopped car (s=%.1f)" % van.s)
	check(dry, "ambulance stays on the road and out of the lakes")
	await game._shutdown_audio()
	game.free()
	print("AMBULANCE FORD RESULT: %d failures" % failures)
	finish()
