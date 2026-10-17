extends "res://tests/harness.gd"
const Stage = preload("res://scripts/stages/stage.gd")
const Form = preload("res://scripts/stages/canyon/canyon_form.gd")
func _initialize() -> void:
	call_deferred("run")

# Samples a wall across its run and counts the near-flat benches and the
# steep bands between them.
func wall_bands(stage, z: float, side: float) -> Vector2i:
	var foot: float = Form.wall_foot(z, side)
	var run: float = Form.wall_run(z, side)
	var step = run / 24.0
	var previous: float = stage.ground(Vector3(Form.axis_x(z) + side * foot, 0.0, z))
	var benches = 0
	var cliffs = 0
	for i in range(1, 25):
		var p = Vector3(Form.axis_x(z) + side * (foot + step * i), 0.0, z)
		var height: float = stage.ground(p)
		var slope = (height - previous) / step
		previous = height
		if slope < 0.5:
			benches += 1
		elif slope > 1.6:
			cliffs += 1
	return Vector2i(benches, cliffs)

func run() -> void:
	var stage = Stage.new(3)
	root.add_child(stage)
	stage.build()
	var canyon = stage.canyon
	check(stage.desert and not stage.provence and not stage.winter, "fourth stage is a distinct desert biome")
	check(stage.collectibles.is_empty(), "no woodland food grows in the gorge")
	_check_route(stage)
	_check_gorge(stage)
	_check_grove(stage, canyon)
	_check_people(stage, canyon)
	_check_river(stage)
	var contact = true
	for chunk in stage.find_children("StageRoadSurface_*", "MeshInstance3D", false, false):
		var vertices: PackedVector3Array = chunk.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for i in range(0, vertices.size(), 37):
			contact = contact and absf(vertices[i].y - stage.ground(vertices[i]) - 0.04) < 0.001
	check(contact, "visible road follows the driving contact surface")
	var copy = Stage.new(3)
	check(stage.points == copy.points and stage.clearings == copy.clearings, "route and spectator areas match across clients")
	copy.free()
	stage.free()
	await _check_game()
	print("CANYON RESULT: %d failures" % failures)
	finish()

# The rim, the hairpin and the long way down to the river.
func _check_route(stage) -> void:
	check(stage.canyon.winding_route() and stage.winding, "the road doubles back, so stations are searched for")
	var start = stage.at(20.0)
	var finish_point = stage.at(840.0)
	check(start.y - finish_point.y > 40.0, "the stage drops from the table to the floor of the gorge")
	check(stage.direction(120.0).z > 0.6, "the rim road runs upstream, along the gorge")
	check(stage.direction(300.0).z < -0.6, "past the turn the road runs back down the gorge")
	var apex = stage.at(215.0)
	check(Vector2(apex.x - start.x, apex.z - start.z).length() < 190.0 and stage.at(215.0).z > stage.at(120.0).z, "the hairpin turns at the head of the gorge")
	var steepest = 0.0
	for i in range(1, 420):
		var a = stage.at(i * 2.0)
		var b = stage.at(i * 2.0 + 2.0)
		steepest = maxf(steepest, absf(b.y - a.y) * 0.5)
	check(steepest < 0.22, "no part of the road is steeper than a gravel road can be")
	var on_land = true
	for i in range(0, 42):
		var p = stage.at(i * 20.0)
		on_land = on_land and absf(p.y - Form.surface(p)) < 9.0
	check(on_land, "the road is graded into the hillside, not flown over it")

# The gorge itself: narrow and deep at the castles, walled in cliff bands.
func _check_gorge(stage) -> void:
	var enclosed = true
	for z in range(-180, -461, 40):
		var p = Vector3(Form.axis_x(z), Form.bed_level(z), z)
		var highest = -INF
		for side in [-1.0, 1.0]:
			highest = maxf(highest, stage.ground(Vector3(p.x + side * (Form.rim_edge(z, side) + 4.0), 0.0, z)) - p.y)
		enclosed = enclosed and highest > 34.0
	check(enclosed, "the walls stand far above the bed the whole way through the castles")
	check(Form.floor_half(-300.0) < 22.0 and Form.floor_half(-640.0) > 70.0, "a slot at the castles, a wide gravel floor at the grove")
	var banded = true
	var climbed = 0.0
	for z in [-220.0, -300.0, -380.0, -460.0]:
		for side in [-1.0, 1.0]:
			var bands = wall_bands(stage, z, side)
			banded = banded and bands.x >= 2 and bands.y >= 4
			var foot: float = Form.wall_foot(z, side)
			var start: float = stage.ground(Vector3(Form.axis_x(z) + side * foot, 0.0, z))
			var feet = start
			for i in range(1, 40):
				var next = Vector3(Form.axis_x(z) + side * (foot + i), 0.0, z)
				if stage.canyon.walk_blocked(next, feet + 0.75):
					break
				feet = stage.ground(next)
				climbed = maxf(climbed, feet - start)
	check(banded, "each wall climbs in cliff bands separated by benches of fallen rock")
	check(climbed < 6.0, "the walls stop a walker: the gorge cannot be climbed out of")
	var shelf = true
	for s in [330.0, 400.0, 460.0]:
		var p = stage.at(s)
		shelf = shelf and stage.ground(p + stage.side(s) * 18.0) - p.y > 8.0
		shelf = shelf and stage.ground(p - stage.side(s) * 18.0) - p.y < -8.0
	check(shelf, "the descent is a shelf with the wall above it and the gorge below")

# The ash grove above the Ili, and the service park standing in it.
func _check_grove(stage, canyon) -> void:
	check(not stage.trees.is_empty(), "the relict ash grove grows above the Ili")
	var grove = true
	for tree in stage.trees:
		grove = grove and Form.grove(tree.z) > 0.25 and tree.y < Form.bed_level(tree.z) + 6.0
	check(grove, "the ash stands only on the floor of the grove reach")
	var park: Dictionary = stage.parks.ends[1]
	check(Form.grove(float(park.origin.z)) > 0.6, "the service park at the finish stands in the grove")
	var level = true
	for corner in [Vector2(-19.0, 14.0), Vector2(19.0, 14.0), Vector2(-19.0, 44.0), Vector2(19.0, 44.0)]:
		var p = stage.parks.world(1, corner.x, corner.y)
		level = level and absf(stage.ground(p) - float(park.height)) < 0.01
	check(level, "its whole paddock is level gravel")
	check(absf(Form.offset(park.origin)) < Form.floor_half(float(park.origin.z)), "it stands between the walls, on the floor of the gorge")
	for node_name in ["CanyonValleyTowers", "SteppeYurtCamp", "GroveYurtCamp", "LedgeMarkers"]:
		check(stage.get_node_or_null(node_name) != null, "%s is built" % node_name)

# The Ili the Charyn runs out into, past the grove and the service park.
func _check_river(stage) -> void:
	check(stage.water != null, "the stage has standing water")
	check(stage.get_node_or_null("WaterSurface_ili") != null, "the river has a drawn surface")
	var wide = true
	var deep = true
	for x in [-190.0, -95.0, 0.0, 95.0, 190.0]:
		var mid = Vector3(x, 0.0, -840.0)
		wide = wide and stage.water.depth(mid) > 1.0
		deep = deep and stage.water.depth(mid) < 8.0
	check(wide, "the Ili runs from one edge of the map to the other")
	check(deep and stage.water.depth(Vector3(0.0, 0.0, -840.0)) > 2.0, "it is a river to swim in, not a canyon of water")
	check(stage.water.depth(Vector3(0.0, 0.0, -916.0)) < 0.0, "its far bank is dry ground, rising away")
	var park: Dictionary = stage.parks.ends[1]
	check(stage.water.depth(park.origin) < -2.0, "the service park stands dry, above the river")
	check(stage.water.depth(stage.at(820.0)) < -1.0, "the road never runs into the water")

# Spectators, camps and the life of the steppe.
func _check_people(stage, canyon) -> void:
	check(stage.clearings.size() == canyon.CAMPS.size(), "every spectator area is placed")
	var level = true
	for clearing in stage.clearings:
		level = level and canyon.camp_supported(clearing)
	check(level, "every spectator area is level enough for camp furniture")
	var standing = true
	for spot in canyon.roadside_spots():
		var s: float = float(spot[0])
		var p = stage.at(s) + stage.side(s) * float(spot[1]) * 7.2
		p.y = stage.ground(p)
		standing = standing and canyon.level_ground(p)
	check(standing, "every roadside spectator has level ground to stand on")
	var life = canyon.canyon_life
	check(life.camels.size() >= 12 and life.eagles.size() >= 6, "camel herds graze the steppe under circling eagles")
	var on_steppe = true
	for camel in life.camels:
		on_steppe = on_steppe and camel.node.position.y > Form.rim_level(camel.node.position) - 6.0
	check(on_steppe, "camels stay on the table and never spawn in the gorge")
	var camel_model: Node3D = life.camels[0].node
	check(camel_model.get_node_or_null("Graze") != null and camel_model.get_node_or_null("StepA") != null, "the camel model carries its grazing and walking poses")

# The real game: parked cars, a table in the grove.
func _check_game() -> void:
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
	check(parked, "parked NPC cars rest on the ground of the gorge and the steppe")
	var camp_spot: Vector3 = game.stage.clearings[5] + Vector3(2.5, 0, 0)
	camp_spot.y = game.stage.ground(camp_spot)
	check(game.place_table(camp_spot) and absf(game.camp.position.y - game.stage.ground(camp_spot)) < 0.001, "a real table rests on the floor of the grove")
	await game._shutdown_audio()
	game.free()
