extends SceneTree
const Stage = preload("res://scripts/stage.gd")
const Traffic = preload("res://scripts/rally_traffic.gd")
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
	check(stage.at(0).z > stage.at(840).z + 800, "vineyard stage runs from start to finish without a city loop")
	check(stage.village(435) and not stage.village(140), "village sits in the middle of the country stage")
	var open_route = true
	for s in range(0, 840, 4):
		open_route = open_route and stage.city.hit(stage.at(s), stage.at(s + 4), 0.85).is_empty()
	check(open_route, "full rally route clears buildings, monument and lamps")
	var nearest_ok = true
	for s in [30.0, 340.0, 410.0, 650.0, 790.0]:
		nearest_ok = nearest_ok and absf(stage.road_s(stage.at(s)) - s) < 1
	check(nearest_ok, "route station remains correct through reversed and perpendicular streets")
	check(stage.grip(stage.at(435)) < stage.grip(stage.at(140)), "cobblestones have less grip than country asphalt")
	var obstacle = stage.city.obstacles[0]
	var pose = stage.city._relative_pose(obstacle.body)
	var center = pose.origin
	var hit = stage.city.hit(center + Vector3(-20, 0, 0), center + Vector3(20, 0, 0), 0.85)
	check(not hit.is_empty(), "fast vehicles cannot tunnel through city solids")
	check(obstacle.body is StaticBody3D, "city solids use real static physics bodies")
	var building = stage.city.obstacles.filter(func(item): return item.kind == "building")[0]
	var wall_center = stage.city._relative_pose(building.body).origin
	var pebble = Node3D.new()
	game.add_child(pebble)
	pebble.position = wall_center - Vector3(20, 0, 0)
	var stone = {"node": pebble, "velocity": Vector3(80, 0, 0), "bounces": 0}
	game._advance_gravel(stone, 0.5)
	check(stone.velocity.x < 0 and stone.bounces == 1, "airborne stone rebounds from a real city facade")
	pebble.free()
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
	# Guest may already have bounced and report zero speed when the host polls.
	# The queued impact velocity must still be sufficient to release the lamp.
	game.room.player_id = "host"
	var remote = game.room.local_state()
	remote.car = game.room.a(stage.city.lamps[1].body.position + Vector3(0, -2.25, 1))
	remote.pos = remote.car
	remote.in_car = true
	remote.speed = 0
	remote.lamps = [{"id": 1, "dir": [12, 0, 0]}]
	game.room._update_peers([{"id": "guest", "name": "Test", "slot": 1, "car_model": 1, "state": remote}])
	game.room.check_remote_collisions()
	check(stage.city.lamps[1].fallen, "queued guest impact survives speed loss after bouncing")
	game.room._update_peers([])
	var snapshot = game.room.world_state()
	check(snapshot.city_lamps.size() == 2, "room snapshot contains fallen lamp transform")
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
	game.course.phase = "racing"
	game.spawn_racer("pass")
	var racer = game.racers[0]
	racer.s = 435
	racer.focus = 140
	racer.node.position = stage.at(435)
	var battle_speed = Traffic.speed_limit(game, racer, racer.s)
	racer.role = "zero"
	var zero_speed = Traffic.speed_limit(game, racer, racer.s)
	racer.role = "opening_police"
	var police_speed = Traffic.speed_limit(game, racer, racer.s)
	racer.role = "racer"
	check(is_equal_approx(battle_speed, Traffic.competition_target(stage, racer.s, racer.pace)) and is_equal_approx(zero_speed, battle_speed), "rally and zero crews use geometry-based pace on the forest bypass")
	check(police_speed < 17.0, "course-opening police keeps the village speed limit")
	game._update_racers(0.1)
	check(game.racers.size() == 1 and racer.s > 435.0, "rally crew advances through the forest bypass")
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	print("CITY ROUTE/PHYSICS RESULT: %d failures" % failures)
	quit(1 if failures else 0)
