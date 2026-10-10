extends "res://tests/harness.gd"
# Solid scenery (houses, walls, furniture, lamps) on the Provençal village stage.
const Stage = preload("res://scripts/stage.gd")
const Traffic = preload("res://scripts/rally_traffic.gd")
const Tracks = preload("res://scripts/rally_tracks.gd")
const Solids = preload("res://scripts/stage_solids.gd")
class ExhaustiveSolids:
	extends "res://scripts/stage_solids.gd"
	func candidates(_start: Vector3, _end: Vector3, _radius: float) -> Array:
		if indexed_obstacle_count != obstacles.size():
			index()
		return range(obstacles.size())
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
	var open_route = true
	var open_lines = true
	for s in range(0, 840, 2):
		open_route = open_route and stage.solids.hit(stage.at(s), stage.at(s + 2), 0.85).is_empty()
		var half = stage.road_width(s) * 0.5 - 1.0
		for side in [-1.0, 1.0]:
			var a = stage.at(s) + stage.side(s) * side * half
			var b = stage.at(s + 2) + stage.side(s + 2) * side * half
			open_lines = open_lines and stage.solids.hit(a, b, 0.85).is_empty()
	check(open_route, "full rally route clears houses, walls, trees and lamps")
	check(open_lines, "the widest racing lines on both sides of the road stay clear")
	var reference = ExhaustiveSolids.new()
	reference.stage = stage
	reference.obstacles = stage.solids.obstacles
	var random = RandomNumberGenerator.new()
	random.seed = 20261008
	var collision_matches = true
	for sample in range(800):
		var begin = Vector3(random.randf_range(-110, 60), random.randf_range(8, 40), random.randf_range(-540, -260))
		var end = begin + Vector3(random.randf_range(-45, 45), random.randf_range(-4, 4), random.randf_range(-45, 45))
		var radius = random.randf_range(0.3, 1.7)
		var actual = stage.solids.hit(begin, end, radius, sample % 2 == 0)
		var expected = reference.hit(begin, end, radius, sample % 2 == 0)
		collision_matches = collision_matches and actual.is_empty() == expected.is_empty()
		if not actual.is_empty() and not expected.is_empty():
			collision_matches = collision_matches and actual.position.distance_to(expected.position) < 0.001 and actual.normal.distance_to(expected.normal) < 0.001
	check(collision_matches, "collision grid matches exhaustive swept collision checks for rotated structures and long paths")
	var field = stage.at(120) + stage.side(120) * -40.0
	check(stage.solids.candidates(field, field + Vector3(2, 0, 0), 0.85).size() < stage.solids.obstacles.size() / 3, "movement in the fields checks only nearby solids and movable lamps")
	reference.free()
	var nearest_ok = true
	for s in [30.0, 340.0, 400.0, 420.0, 660.0, 680.0, 790.0]:
		nearest_ok = nearest_ok and absf(stage.road_s(stage.at(s)) - s) < 1
	check(nearest_ok, "route station remains correct through the square corner and the hairpin")
	check(stage.grip(stage.at(330)) < stage.grip(stage.at(120)) and stage.grip(stage.at(760)) < stage.grip(stage.at(330)), "asphalt grips best, cobbles less, gravel least")
	var building = stage.solids.obstacles.filter(func(item): return item.kind == "building")[0]
	var center = stage.solids.relative_pose(building.body).origin
	check(not stage.solids.hit(center + Vector3(-25, 0, 0), center + Vector3(25, 0, 0), 0.85).is_empty(), "fast vehicles cannot tunnel through village solids")
	check(building.body is StaticBody3D, "village solids use real static physics bodies")
	var pebble = Node3D.new()
	game.add_child(pebble)
	pebble.position = center - Vector3(25, 0, 0)
	var stone = {"node": pebble, "velocity": Vector3(100, 0, 0), "bounces": 0}
	game._advance_gravel(stone, 0.5)
	check(stone.velocity.x < 0 and stone.bounces == 1, "airborne stone rebounds from a real house facade")
	pebble.free()
	var lamp = stage.solids.lamps[0]
	check(lamp.body is RigidBody3D and lamp.body.freeze, "lamp is an anchored rigid body before a collision")
	var before: Vector3 = lamp.body.position
	check(stage.solids.knock_lamp(0, Vector3(12, 0, 0)), "strong lamp impact releases rigid body")
	for i in range(30):
		await physics_frame
	check(lamp.body.position.distance_to(before) > 0.1 and lamp.body.rotation.length() > 0.01, "struck lamp moves and tips under real physics")
	game.paused = true
	await physics_frame
	await physics_frame
	check(lamp.body.freeze, "paused game freezes lamp physics")
	game.paused = false
	# Guest may already have bounced and report zero speed when the host polls.
	game.room.player_id = "host"
	var remote = game.room.local_state()
	remote.car = game.room.a(stage.solids.lamps[1].body.position + Vector3(0, -2.0, 1))
	remote.pos = remote.car
	remote.in_car = true
	remote.speed = 0
	remote.lamps = [{"id": 1, "dir": [12, 0, 0]}]
	game.room._update_peers([{"id": "guest", "name": "Test", "slot": 1, "car_model": 1, "state": remote}])
	game.room.check_remote_collisions()
	check(stage.solids.lamps[1].fallen, "queued guest impact survives speed loss after bouncing")
	game.room._update_peers([])
	var snapshot = game.room.world_state()
	check(snapshot.city_lamps.size() == 2, "room snapshot contains fallen lamp transform")
	var other = Stage.new(2)
	root.add_child(other)
	other.build()
	other.solids.apply_snapshot(snapshot.city_lamps)
	check(other.solids.lamps[0].fallen and other.solids.lamps[0].body.position.distance_to(lamp.body.position) < 0.01, "late guest receives fallen lamp position")
	other.free()
	# Every stage owns a solids component; without scenery it never blocks.
	var forest = Stage.new(0)
	check(forest.solids != null and forest.solids.hit(Vector3.ZERO, Vector3(0, 0, -50), 1.0).is_empty() and forest.solids.walking_floor(Vector3(0, 0, -20), 0.0) == forest.walking_ground(Vector3(0, 0, -20)), "stages without solids answer empty contacts and terrain floors")
	forest.free()
	game.in_car = false
	game.walker = stage.clearings[0]
	game.course.phase = "racing"
	game.spawn_racer("pass")
	var racer = game.racers[0]
	racer.s = 400
	racer.focus = 140
	racer.node.position = stage.at(400)
	var battle_speed = Traffic.speed_limit(game, racer, racer.s)
	racer.role = "zero"
	var zero_speed = Traffic.speed_limit(game, racer, racer.s)
	racer.role = "opening_police"
	var police_speed = Traffic.speed_limit(game, racer, racer.s)
	racer.role = "racer"
	# Crews follow their baked driver recordings (or geometry when unavailable).
	var recorded = Tracks.sample(racer.get("track_parts", PackedInt32Array()), racer.s, false, false)
	var expected = minf(Traffic.MAX_COMPETITION_SPEED, float(recorded.speed) * racer.pace) if not recorded.is_empty() else Traffic.competition_target(stage, racer.s, racer.pace)
	check(is_equal_approx(battle_speed, expected) and zero_speed > 0.0 and zero_speed <= battle_speed + 0.001, "rally and zero crews use their recorded pace around the square")
	check(police_speed < 17.0, "course-opening police keeps the village speed limit")
	game._update_racers(0.1)
	check(game.racers.size() == 1 and racer.s > 400.0, "rally crew advances around the square")
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	print("STAGE SOLIDS RESULT: %d failures" % failures)
	finish()
