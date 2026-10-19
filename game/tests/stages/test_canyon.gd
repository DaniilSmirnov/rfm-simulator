extends "res://tests/harness.gd"
const RoadChunks = preload("res://scripts/stages/road_chunks.gd")
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
	var vertices = PackedVector3Array()
	for piece in RoadChunks.meshes(stage):
		vertices.append_array(piece.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
	var contact = true
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
	var forest = Stage.new(0)
	check(stage.length >= 2000.0 and stage.length > forest.length * 2.0, "the longest stage in the game: over two kilometres")
	forest.free()
	var start = stage.at(20.0)
	var finish_point = stage.at(stage.length)
	check(start.y - finish_point.y > 60.0, "the stage drops from the table to the floor of the gorge")
	check(stage.direction(400.0).z > 0.6, "the rim road runs upstream, along the gorge")
	check(stage.direction(1000.0).z < -0.6, "past the turn the road runs back down the gorge")
	var apex = stage.at(760.0)
	check(apex.z > -60.0 and apex.z > stage.at(600.0).z and apex.z > stage.at(900.0).z, "the hairpin turns at the head of the gorge")
	var above = 0
	for s in range(200, 640, 20):
		var rim = stage.at(s)
		for t in range(820, 1380, 4):
			var bench = stage.at(t)
			if Vector2(rim.x - bench.x, rim.z - bench.z).length() < 60.0 and rim.y - bench.y > 12.0:
				above += 1
				break
	check(above > 12, "the rim road runs above the bench road, one over the other (%d)" % above)
	var steepest = 0.0
	for i in range(1, int(stage.length / 2.0)):
		var a = stage.at(i * 2.0)
		var b = stage.at(i * 2.0 + 2.0)
		steepest = maxf(steepest, absf(b.y - a.y) * 0.5)
	check(steepest < 0.22, "no part of the road is steeper than a gravel road can be")
	var on_land = true
	for i in range(0, int(stage.length / 20.0) + 1):
		var p = stage.at(i * 20.0)
		on_land = on_land and absf(p.y - Form.surface(p)) < 9.0
	check(on_land, "the road is graded into the hillside, not flown over it")
	var bounds: Rect2 = stage.canyon.world_bounds()
	var inside = true
	for i in range(0, int(stage.length), 10):
		inside = inside and bounds.grow(-25.0).has_point(Vector2(stage.at(i).x, stage.at(i).z))
	check(inside, "the whole road lies well inside the land of the stage")

# The gorge itself: narrow and deep at the castles, walled in cliff bands.
func _check_gorge(stage) -> void:
	var enclosed = true
	for z in range(-180, -1001, 40):
		var p = Vector3(Form.axis_x(z), Form.bed_level(z), z)
		var highest = -INF
		for side in [-1.0, 1.0]:
			highest = maxf(highest, stage.ground(Vector3(p.x + side * (Form.rim_edge(z, side) + 4.0), 0.0, z)) - p.y)
		enclosed = enclosed and highest > 34.0
	check(enclosed, "the walls stand far above the bed the whole way through the castles")
	check(Form.floor_half(-300.0) < 22.0 and Form.floor_half(-900.0) < 30.0 and Form.floor_half(-1250.0) > 70.0, "a slot through a kilometre of castles, a wide gravel floor at the grove")
	var banded = true
	var climbed = 0.0
	for z in [-300.0, -500.0, -700.0, -900.0]:
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
	for s in [900.0, 1000.0, 1100.0]:
		var p = stage.at(s)
		shelf = shelf and stage.ground(p + stage.side(s) * 18.0) - p.y > 8.0
		shelf = shelf and stage.ground(p - stage.side(s) * 18.0) - p.y < -8.0
	check(shelf, "the descent is a shelf with the wall above it and the gorge below")
	_check_cliffs(stage)
	var kinds: Dictionary = stage.canyon.scenery.counts.castle_kinds
	check(kinds.size() >= 6 and int(stage.canyon.scenery.counts.towers) > 50, "the castles take every form: %s" % str(kinds))

# Cars keep to the road and the steppe: they cannot drive up a wall.
func _check_cliffs(stage) -> void:
	var canyon = stage.canyon
	var stopped = true
	for z in [-700.0, -850.0, -1000.0]:
		for side in [-1.0, 1.0]:
			var foot = Vector3(Form.axis_x(z) + side * (Form.wall_foot(z, side) + Form.wall_run(z, side) * 0.1), 0.0, z)
			foot.y = stage.vehicle_ground(foot)
			var into = foot + Vector3(side * 0.3, 0.0, 0.0)
			stopped = stopped and canyon.drive_blocked(foot, into)
	check(stopped, "a car cannot drive up the face of the gorge")
	var free = true
	for i in range(0, int(stage.length) - 4, 3):
		free = free and not canyon.drive_blocked(stage.at(i), stage.at(i + 0.3))
		free = free and not canyon.drive_blocked(stage.at(i + 3.0), stage.at(i + 2.7))
	check(free, "the road itself is drivable both ways from start to finish")

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

# Spectators, camps and the life of the steppe.
func _check_people(stage, canyon) -> void:
	check(stage.clearings.size() == canyon.CAMPS.size(), "every spectator area is placed")
	var tilted: Array = []
	for i in range(stage.clearings.size()):
		if not canyon.camp_supported(stage.clearings[i]):
			tilted.append(canyon.CAMPS[i][0])
	check(tilted.is_empty(), "every spectator area is level enough for camp furniture %s" % str(tilted))
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
	var astray: Array = []
	for person in game.spectators.people:
		var home: Vector3 = person.home
		if not game.stage.canyon.camp_supported(home) or game.stage.road_distance(home) < 6.0 or absf(home.y - game.stage.ground(home)) > 0.05:
			astray.append(int(person.station))
	check(astray.is_empty(), "every spectator stands on level ground off the road, never on a cliff %s" % str(astray))
	var grove_clearing: Vector3 = game.stage.clearings[-1]
	var toward_road: Vector3 = game.stage.at(game.stage.road_s(grove_clearing)) - grove_clearing
	var camp_spot: Vector3 = grove_clearing + Vector3(toward_road.x, 0, toward_road.z).normalized() * 3.0
	camp_spot.y = game.stage.ground(camp_spot)
	check(game.place_table(camp_spot) and absf(game.camp.position.y - game.stage.ground(camp_spot)) < 0.001, "a real table rests on the floor of the grove")
	await game._shutdown_audio()
	game.free()
