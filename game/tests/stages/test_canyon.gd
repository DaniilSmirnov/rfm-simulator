extends "res://tests/harness.gd"
const Stage = preload("res://scripts/stages/stage.gd")
func _initialize() -> void:
	call_deferred("run")

# Samples the slope of a wall across its run and counts the near-flat benches
# and the steep bands between them.
func wall_bands(stage, s: float, side: float) -> Vector2i:
	var canyon = stage.canyon
	var p: Vector3 = stage.at(s)
	var foot: float = canyon.wall_foot(s, canyon.floor_half(s))
	var run: float = canyon.wall_run(s, side)
	var step = run / 24.0
	var previous: float = stage.ground(p + stage.side(s) * side * foot)
	var benches = 0
	var cliffs = 0
	for i in range(1, 25):
		var height: float = stage.ground(p + stage.side(s) * side * (foot + step * i))
		var slope = (height - previous) / step
		previous = height
		if slope < 0.6:
			benches += 1
		elif slope > 1.8:
			cliffs += 1
	return Vector2i(benches, cliffs)

func run() -> void:
	var stage = Stage.new(3)
	root.add_child(stage)
	stage.build()
	var canyon = stage.canyon
	check(stage.desert and not stage.provence and not stage.winter, "fourth stage is a distinct desert biome")
	check(stage.collectibles.is_empty(), "no woodland food grows in the gorge")
	var grove = not stage.trees.is_empty()
	for tree in stage.trees:
		var station = stage.road_s(tree)
		grove = grove and station > 540.0 and station < 712.0 and tree.y < canyon.PLATEAU - 40.0
	check(grove, "the ash grove stands only on the floor of the dry bed")
	check(stage.at(100).y - stage.at(500).y > 35.0 and stage.at(800).y - stage.at(500).y > 30.0, "route descends into a deep canyon and climbs back out")
	check(stage.clearings.size() == canyon.CAMPS.size(), "every spectator area stands on the ground")
	check(absf(stage.at(60).y - canyon.PLATEAU) < 4.0 and absf(stage.at(820).y - canyon.PLATEAU) < 4.0, "the stage starts and finishes on the steppe table")
	check(stage.get_node_or_null("CanyonValleyTowers") != null and stage.get_node_or_null("CanyonGate") != null, "the Valley of Castles has its towers and the gate on the rim")
	check(stage.get_node_or_null("CanyonBenchTowers") != null, "pinnacles stand on the benches of the walls")
	check(stage.get_node_or_null("SteppeYurtCamp") != null and stage.get_node_or_null("GorgeYurtCamp") != null, "yurt camps stand on the steppe and down in the gorge")
	var level = true
	for clearing in stage.clearings:
		level = level and canyon.camp_supported(clearing)
	check(level, "every spectator area is level enough for camp furniture")
	var enclosed = true
	var narrow = true
	for s in range(420, 701, 20):
		# The amphitheatres are meant to open out; the corridor between them is not.
		if canyon.floor_half(s) > 55.0:
			continue
		var p = stage.at(s)
		var highest = -INF
		for lateral in [-110.0, -80.0, -60.0, -40.0, 40.0, 60.0, 80.0, 110.0]:
			highest = maxf(highest, stage.ground(p + stage.side(s) * lateral) - p.y)
		enclosed = enclosed and highest > 40.0
	for s in [530.0, 540.0, 550.0, 700.0, 710.0]:
		narrow = narrow and canyon.floor_half(s) < 35.0
	check(enclosed, "walls of the gorge stand far above the road along the whole floor")
	check(narrow, "the floor between the amphitheatres is a narrow corridor")
	check(canyon.floor_half(462.0) > 70.0 and canyon.floor_half(616.0) > 65.0, "the gorge opens into an amphitheatre twice")
	var banded = true
	var climbed = 0.0
	for s in [448.0, 540.0, 596.0, 668.0]:
		for side in [-1.0, 1.0]:
			var bands = wall_bands(stage, s, side)
			banded = banded and bands.x >= 3 and bands.y >= 5
			# Walk out from the foot of the wall, jumping at every step.
			var foot: float = canyon.wall_foot(s, canyon.floor_half(s))
			var start: float = stage.ground(stage.at(s) + stage.side(s) * side * foot)
			var feet = start
			for i in range(1, 40):
				var next = stage.at(s) + stage.side(s) * side * (foot + i)
				if canyon.walk_blocked(next, feet + 0.75):
					break
				feet = stage.ground(next)
				climbed = maxf(climbed, feet - start)
	check(banded, "each wall climbs in cliff bands separated by benches of fallen rock")
	check(climbed < 4.0, "walls stop a walker at their foot: the gorge cannot be climbed out of")
	var ledge = true
	for s in [250.0, 270.0, 280.0]:
		var p = stage.at(s)
		ledge = ledge and stage.ground(p + stage.side(s) * 22.0) - p.y > 5.0
		ledge = ledge and stage.ground(p - stage.side(s) * 22.0) - p.y < -10.0
	check(ledge, "the descent is a ledge with the wall above it and the gorge below")
	check(absf(stage.ground(stage.at(600) + stage.side(600) * 2) - stage.ground(stage.at(600) - stage.side(600) * 2)) > 0.1, "road has physical crossfall")
	var min_height = INF
	var max_height = -INF
	for s in range(570, 650):
		var p = stage.at(s)
		var relief = stage.ground(p) - p.y
		min_height = minf(min_height, relief)
		max_height = maxf(max_height, relief)
	check(max_height - min_height > 0.5, "dry riverbed contains physical waves and crests")
	var life = canyon.canyon_life
	check(life.camels.size() >= 12 and life.eagles.size() >= 4, "camel herds graze the steppe under circling eagles")
	var on_steppe = true
	for camel in life.camels:
		on_steppe = on_steppe and camel.node.position.y > canyon.PLATEAU - 8.0
	check(on_steppe, "camels stay on the steppe and never spawn in the gorge")
	var camel_model: Node3D = life.camels[0].node
	check(camel_model.get_node_or_null("Graze") != null and camel_model.get_node_or_null("StepA") != null, "the camel model carries its grazing and walking poses")
	var road: ArrayMesh = stage.get_node("StageRoadSurface").mesh
	var vertices: PackedVector3Array = road.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var contact = true
	for i in range(0, vertices.size(), 37):
		contact = contact and absf(vertices[i].y - stage.ground(vertices[i]) - 0.04) < 0.001
	check(contact, "visible road follows the driving contact surface")
	var copy = Stage.new(3)
	check(stage.points == copy.points and stage.clearings == copy.clearings, "route and spectator areas match across clients")
	copy.free()
	stage.free()
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.room.set_process(false)
	game.select_stage(3)
	await game.start_game()
	game.in_car = false
	var parked = true
	for group in game.spectators.groups:
		parked = parked and absf(group.car.position.y - game.stage.vehicle_ground(group.car.position)) < 0.01
	check(game.spectators.groups.size() >= game.stage.clearings.size(), "NPC camps stand at every spectator area")
	check(parked, "NPC cars rest on the ground of the gorge and the steppe")
	var camp_spot: Vector3 = game.stage.clearings[4] + Vector3(2.5, 0, 0)
	camp_spot.y = game.stage.ground(camp_spot)
	check(game.place_table(camp_spot) and absf(game.camp.position.y - game.stage.ground(camp_spot)) < 0.001, "a real table rests on the floor of the gorge")
	await game._shutdown_audio()
	game.free()
	print("CANYON RESULT: %d failures" % failures)
	finish()
