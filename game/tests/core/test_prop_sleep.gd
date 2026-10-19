extends "res://tests/harness.gd"
# A loaded stage at rest costs little physics: the NPC camps' chairs, tables,
# grills and cars settle, people standing or sitting still get no pushing
# collider, and standing trunks are not re-posed every tick. Before this the
# camps never slept and the physics step alone took 50-95 ms (2-5 fps).
const PropActors = preload("res://scripts/core/prop_actors.gd")
class ExhaustiveSolids:
	extends "res://scripts/stages/stage_solids.gd"
	func candidates(_start: Vector3, _end: Vector3, _radius: float) -> Array:
		return range(obstacles.size())

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://scripts/core/game.gd").new()
	game.defer_world = true
	root.add_child(game)
	await process_frame
	game.select_stage(4)
	game.rng.seed = 20261008
	await game.start_game()
	game.paused = false
	for i in range(240):
		await physics_frame
	var physics_ms = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	check(physics_ms < 30.0, "a stage at rest steps its physics in %.1f ms" % physics_ms)
	var actors = game.stage.solids.prop_ground.get_node_or_null("Actors") if game.stage.solids.prop_ground != null else null
	var still = 0
	if actors != null:
		for key in actors._still:
			if int(actors._still[key]) >= PropActors.STILL_TICKS and not actors.bodies.has(key):
				still += 1
	check(actors == null or still > 0, "people who stand still near props carry no collider (%d)" % still)
	# Starting play unfroze every prop, which woke it; the service parks' tyre
	# stacks and benches then crept or sank through the terrain and never slept.
	var awake_parks = 0
	var sunk = 0
	for body in game.find_children("PropBody*", "RigidBody3D", true, false):
		if body.moving and str(body.record.key).begins_with("ServicePark_"): awake_parks += 1
		var center: Vector3 = body.global_transform * body.center_of_mass
		if center.y < game.stage.ground(center) - 1.0: sunk += 1
	check(awake_parks == 0, "service-park props stay asleep until touched (%d awake)" % awake_parks)
	check(sunk == 0, "no prop sinks through the terrain (%d below ground)" % sunk)
	# Awake props are bucketed per tick and swap in and out of the static grid
	# one by one; queries must match a full scan whatever their state.
	var solids = game.stage.solids
	var reference = ExhaustiveSolids.new()
	reference.stage = game.stage
	reference.obstacles = solids.obstacles
	var keys: Array = []
	for record in solids.movables:
		if str(record.key).begins_with("ServicePark_0:") and keys.size() < 24: keys.append(record.key)
	var random = RandomNumberGenerator.new()
	random.seed = 20261019
	var origin: Vector3 = game.stage.parks.ends[0].origin
	var matches = true
	for phase in range(3):
		for i in range(keys.size()):
			solids.set_dynamic(keys[i], phase == 1 and i % 2 == 0)
		if phase == 2:
			for body in game.find_children("PropBody*", "RigidBody3D", true, false):
				if body.record.key == keys[1]: body.global_position += Vector3(0.6, 0, -0.4)
			await process_frame
		for sample in range(300):
			var begin = origin + Vector3(random.randf_range(-30, 30), random.randf_range(0, 2), random.randf_range(-50, 10))
			var end = begin + Vector3(random.randf_range(-8, 8), random.randf_range(-1, 1), random.randf_range(-8, 8))
			var radius = random.randf_range(0.05, 2.6)
			var actual = solids.hit(begin, end, radius)
			var expected = reference.hit(begin, end, radius)
			matches = matches and actual.is_empty() == expected.is_empty()
			if not actual.is_empty() and not expected.is_empty():
				matches = matches and actual.position.distance_to(expected.position) < 0.001
	check(not keys.is_empty() and matches, "bucketed prop collisions match a full scan while props wake, sleep and move")
	check(solids.indexed_obstacle_count == solids.obstacles.size(), "waking and settling props does not rebuild the whole collision index")
	reference.free()
	game.free()
	print("PROP SLEEP RESULT: %d checks, %d failures" % [checks, failures])
	finish()
