extends SceneTree
const Stage = preload("res://scripts/stage.gd")
var failures = 0
func check(ok: bool, message: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + message)
	if not ok:
		failures += 1
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var stage = Stage.new(3)
	root.add_child(stage)
	stage.build()
	check(stage.desert and not stage.urban and not stage.winter, "fourth stage is a distinct desert biome")
	check(stage.trees.is_empty() and stage.collectibles.is_empty(), "desert contains no forest or woodland food")
	check(stage.at(100).y - stage.at(500).y > 35.0 and stage.at(800).y - stage.at(500).y > 30.0, "route descends into a deep canyon and climbs back out")
	check(stage.canyon.mesas.size() == 4 and stage.clearings.size() == 7, "four climbable summits and three ground spectator areas")
	check(stage.get_node_or_null("CanyonClimbableMesas") != null, "terraced mesas have authored visible geometry")
	check(absf(stage.ground(stage.at(600) + stage.side(600) * 2) - stage.ground(stage.at(600) - stage.side(600) * 2)) > 0.1, "road has physical crossfall")
	var min_height = INF
	var max_height = -INF
	for s in range(560, 640):
		var p = stage.at(s)
		var relief = stage.ground(p) - p.y
		min_height = minf(min_height, relief)
		max_height = maxf(max_height, relief)
	check(max_height - min_height > 0.5, "dry riverbed contains physical waves and crests")
	for mesa in stage.canyon.mesas:
		var center: Vector3 = mesa.center
		check(stage.canyon.camp_supported(stage, center), "summit supports the whole camp footprint")
		check(stage.road_distance(center) > 40 and absf(center.x) + stage.canyon.OUTER_RADIUS < 185, "summit is clear of the road and inside player bounds")
		for tier in range(stage.canyon.TIERS):
			var radius = stage.canyon.OUTER_RADIUS - tier * stage.canyon.LEDGE_WIDTH
			var next = center + Vector3.RIGHT * (radius - 0.1)
			var old = center + Vector3.RIGHT * (radius + 0.1)
			var low = stage.ground(old)
			check(absf(stage.ground(next) - low - stage.canyon.LEDGE_RISE) < 0.005, "each lip is below the existing jump apex")
			check(stage.canyon.walk_blocked(stage, next, low), "lip cannot be climbed by walking")
			check(not stage.canyon.walk_blocked(stage, next, low + 0.75), "jumping feet clear the lip")
			check(not stage.canyon.camp_supported(stage, next), "camp cannot straddle a ledge")
	var road: ArrayMesh = stage.get_node("StageRoadSurface").mesh
	var vertices: PackedVector3Array = road.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var contact = true
	for i in range(0, vertices.size(), 37):
		contact = contact and absf(vertices[i].y - stage.ground(vertices[i]) - 0.04) < 0.001
	check(contact, "visible road follows the driving contact surface")
	var copy = Stage.new(3)
	check(stage.points == copy.points and stage.canyon.mesas == copy.canyon.mesas, "route and jump terraces match across clients")
	copy.free()
	stage.free()
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.room.set_process(false)
	game.select_stage(3)
	await game.start_game()
	game.in_car = false
	var summit_cars = false
	for group in game.spectators.groups:
		for mesa in game.stage.canyon.mesas:
			summit_cars = summit_cars or game.stage.canyon.radius_at(group.car.position, mesa.center) < game.stage.canyon.TOP_RADIUS
	check(not summit_cars, "NPC cars stay off the climbable summits")
	game.spectators.groups.clear()
	game.spectators.people.clear()
	game.view_yaw = 0
	var center: Vector3 = game.stage.canyon.mesas[0].center
	var climbed = true
	for tier in range(game.stage.canyon.TIERS):
		var radius = game.stage.canyon.OUTER_RADIUS - tier * game.stage.canyon.LEDGE_WIDTH
		game.walker = center + Vector3.RIGHT * (radius + 0.3)
		game.walker.y = game.stage.ground(game.walker)
		game.jump_height = 0
		game.jump_velocity = 0
		var before: Vector3 = game.walker
		Input.action_press("left")
		game._walk(0.16)
		Input.action_release("left")
		climbed = climbed and game.walker.x > center.x + radius
		game.walker = before
		climbed = climbed and game.jump()
		game._walk(0.18)
		Input.action_press("left")
		game._walk(0.16)
		Input.action_release("left")
		game._walk(0.6)
		climbed = climbed and game.walker.x < center.x + radius and game.jump_height == 0 and absf(game.walker.y - (center.y + (tier + 1) * game.stage.canyon.LEDGE_RISE)) < 0.01
	check(climbed, "real player controller jumps onto and lands on every tier")
	var camp_spot = center + Vector3(3, 0, 0)
	camp_spot.y = game.stage.ground(camp_spot)
	check(game.place_table(camp_spot) and absf(game.camp.position.y - game.stage.ground(camp_spot)) < 0.001, "real table placement rests on the summit")
	await game._shutdown_audio()
	game.free()
	print("CANYON RESULT: %d failures" % failures)
	quit(1 if failures else 0)
