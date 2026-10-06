extends SceneTree
const Stage = preload("res://scripts/stage.gd")
var failures = 0
func check(ok: bool, title: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + title)
	if not ok:
		failures += 1
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.select_stage(2)
	game.start_game()
	var stage = game.stage
	var entry = stage.direction(310)
	var exit = stage.direction(405)
	check(entry.dot(exit) < -0.95, "roundabout reverses rally heading by 180 degrees")
	check(stage.at(350).z < -330 and stage.at(390).x > 20, "route runs around the monument instead of through it")
	var open_route = true
	for s in range(0, 840, 4):
		open_route = open_route and stage.city.hit(stage.at(s), stage.at(s + 4), 0.85).is_empty()
	check(open_route, "full rally route clears buildings, monument and lamps")
	var nearest_ok = true
	for s in [30.0, 340.0, 410.0, 650.0, 790.0]:
		nearest_ok = nearest_ok and absf(stage.road_s(stage.at(s)) - s) < 1
	check(nearest_ok, "route station remains correct through reversed and perpendicular streets")
	check(stage.road_distance(Vector3(80, 2, -150)) < 0.1, "cross streets are driveable asphalt")
	var obstacle = stage.city.obstacles[0]
	var pose = stage.city._relative_pose(obstacle.body)
	var center = pose.origin
	var hit = stage.city.hit(center + Vector3(-20, 0, 0), center + Vector3(20, 0, 0), 0.85)
	check(not hit.is_empty(), "fast vehicles cannot tunnel through city solids")
	check(obstacle.body is StaticBody3D, "city solids use real static physics bodies")
	var lamp = stage.city.lamps[0]
	check(lamp.body is RigidBody3D and lamp.body.freeze, "lamp is an anchored rigid body before a collision")
	var before: Vector3 = lamp.body.position
	check(stage.city.knock_lamp(0, Vector3(12, 0, 0)), "strong lamp impact releases rigid body")
	for i in range(30):
		await physics_frame
	check(lamp.body.position.distance_to(before) > 0.1 and lamp.body.rotation.length() > 0.01, "struck lamp moves and tips under real physics")
	game.paused = true
	await physics_frame
	await physics_frame
	check(lamp.body.freeze, "paused game freezes lamp physics")
	game.paused = false
	var snapshot = game.room.world_state()
	check(snapshot.city_lamps.size() == 1, "room snapshot contains fallen lamp transform")
	var other = Stage.new(2)
	root.add_child(other)
	other.build()
	other.city.apply_snapshot(snapshot.city_lamps)
	check(other.city.lamps[0].fallen and other.city.lamps[0].body.position.distance_to(lamp.body.position) < 0.01, "late guest receives fallen lamp position")
	other.free()
	# A passing car on the city map must reach the loop even when the player
	# chooses the first parking spot, rather than despawning before the square.
	game.in_car = false
	game.walker = stage.clearings[0]
	game.spawn_racer("pass")
	var racer = game.racers[0]
	racer.s = 310
	racer.focus = 140
	racer.node.position = stage.at(310)
	game._update_racers(0.1)
	check(game.racers.size() == 1 and racer.s > 310 and racer.s < 312, "city crew survives past viewer and slows for the roundabout")
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	print("CITY ROUTE/PHYSICS RESULT: %d failures" % failures)
	quit(1 if failures else 0)
