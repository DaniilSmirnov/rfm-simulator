extends "res://tests/harness.gd"
# «Асбестовский карьер»: over the spoil dumps and down a haul road into an open
# pit. Checks the stepped walls, the haul road's grade and windrow, the floor
# and its machines, the white dust behind moving cars, the spectators and that
# every room member builds the same pit.
const Stage = preload("res://scripts/stages/stage.gd")
const StageRegistry = preload("res://scripts/stages/stage_registry.gd")
const RoadChunks = preload("res://scripts/stages/road_chunks.gd")
const Form = preload("res://scripts/stages/quarry/quarry_form.gd")
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var index = -1
	for i in range(Stage.STAGES.size()):
		if StageRegistry.entry(i).id == "quarry":
			index = i
	check(index >= 0, "the quarry is registered as a stage")
	check(Stage.STAGES[index].begins_with("Асбестовский карьер"), "stage is called Асбестовский карьер in the menu")
	var stage = Stage.new(index)
	root.add_child(stage)
	stage.build()
	var quarry = stage.biome
	_check_route(stage, quarry)
	_check_pit(stage, quarry)
	_check_scenery(stage, quarry)
	_check_people(stage, quarry)
	_check_dust(stage, quarry)
	var vertices = PackedVector3Array()
	for piece in RoadChunks.meshes(stage):
		vertices.append_array(piece.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
	var contact = true
	for i in range(0, vertices.size(), 37):
		contact = contact and absf(vertices[i].y - stage.ground(vertices[i]) - 0.04) < 0.001
	check(contact, "visible road follows the driving contact surface")
	var guest = Stage.new(index)
	check(guest.points == stage.points and guest.clearings == stage.clearings and guest.length == stage.length, "every room member builds the same pit")
	guest.free()
	stage.queue_free()
	await process_frame
	print("QUARRY RESULT: ", failures, " failures")
	finish()

func _check_route(stage, quarry) -> void:
	check(stage.winding, "the road winds back on itself round the pit")
	check(int(stage.length) % int(stage.STEP) == 0 and stage.length > 1100.0, "a stage of %.0f m, whole road samples" % stage.length)
	check(quarry.ramp_begin > 300.0 and quarry.ramp_end - quarry.ramp_begin > 450.0, "a fast run over the dumps, then %.0f m of haul road" % (quarry.ramp_end - quarry.ramp_begin))
	var top = stage.at(quarry.ramp_begin).y
	var bottom = stage.at(quarry.ramp_end).y
	check(top - bottom > Form.DEPTH - 3.0, "the haul road drops %.0f m to the floor" % (top - bottom))
	var steepest = 0.0
	for s in range(int(quarry.ramp_begin) + 10, int(quarry.ramp_end) - 10):
		steepest = maxf(steepest, stage.at(s).y - stage.at(s + 1).y)
	check(steepest < 0.12, "the haul road is graded for trucks (steepest %.1f%%)" % (steepest * 100.0))
	var inside = true
	for s in range(int(quarry.ramp_begin) + 20, int(quarry.ramp_end)):
		inside = inside and Form.in_pit(stage.at(s))
	check(inside, "the haul road runs down inside the pit")
	var on_floor = true
	for s in range(int(quarry.ramp_end) + 10, int(stage.length)):
		on_floor = on_floor and Form.on_floor(stage.at(s), 4.0)
	check(on_floor, "the stage finishes along the floor of the pit")
	var turned = stage.direction(quarry.ramp_begin + 20.0).dot(stage.direction(quarry.ramp_end + 20.0))
	check(turned < -0.8, "the road comes back up the floor the way it went down the wall")
	check(stage.road_width(quarry.ramp_begin + 50.0) > stage.road_width(50.0), "the haul road is wider than the track over the dumps")
	check(stage.rally_speed(800.0) < stage.rally_speed(100.0), "crews slow for the turn round the end of the pit")
	var crest = 0.0
	for item in quarry.Route.CRESTS:
		var c = float(item[0])
		crest = maxf(crest, stage.at(c).y - (stage.at(c - 14.0).y + stage.at(c + 14.0).y) * 0.5)
	check(crest > 0.4, "the dumps throw cars over crests (%.1f m)" % crest)
	var bounds: Rect2 = quarry.world_bounds()
	var in_map = true
	for s in range(0, int(stage.length), 4):
		var p = stage.at(s)
		in_map = in_map and bounds.grow(-30.0).has_point(Vector2(p.x, p.z))
	check(in_map, "route stays well inside the map")

func _check_pit(stage, quarry) -> void:
	# Across the east wall away from the road: steep faces and level berms.
	var z = -470.0
	var faces = 0
	var berms = 0
	var previous = stage.ground(Vector3(Form.AXIS_X - Form.FLOOR, 0.0, z))
	for i in range(1, Form.RUN):
		var height = stage.ground(Vector3(Form.AXIS_X - Form.FLOOR - i, 0.0, z))
		var rise = height - previous
		previous = height
		if rise > 1.5:
			faces += 1
		elif absf(rise) < 0.15:
			berms += 1
	var west = stage.ground(Vector3(Form.AXIS_X - Form.RIM - 4.0, 0.0, z)) - stage.ground(Vector3(Form.AXIS_X, 0.0, z))
	check(west > Form.DEPTH - 2.0, "the pit is %.0f m deep" % west)
	check(faces >= Form.BENCHES and berms > Form.BENCHES * 6, "the walls stand in benches (%d face metres, %d berm metres)" % [faces, berms])
	var walker = Vector3(Form.AXIS_X - Form.FLOOR - 2.0, 0.0, z)
	check(quarry.walk_blocked(walker, Form.FLOOR_LEVEL), "a walker cannot climb a face")
	var car = Vector3(Form.AXIS_X - Form.FLOOR - 1.0, 0.0, z)
	car.y = stage.ground(car)
	check(quarry.drive_blocked(car, car + Vector3(-1, 0, 0)), "a car cannot climb a face")
	check(not quarry.drive_blocked(stage.at(quarry.ramp_begin + 100.0), stage.at(quarry.ramp_begin + 98.0)), "a car drives up the haul road")
	var dark = quarry.terrain_color(Vector3(Form.AXIS_X + Form.FLOOR + 3.0, 16.0, z))
	var dusty = quarry.terrain_color(Vector3(Form.AXIS_X + Form.FLOOR + 10.0, 22.0, z))
	check(dark.get_luminance() < 0.5 and dusty.get_luminance() > 0.6, "dark serpentinite in the faces, white dust on the berms (%.2f, %.2f)" % [dark.get_luminance(), dusty.get_luminance()])
	check(quarry.road_color(stage.at(600.0), 600.0).get_luminance() > 0.65, "the haul road is white with dust")

func _check_scenery(stage, quarry) -> void:
	var counts: Dictionary = quarry.scenery.counts
	check(int(counts.get("windrow", 0)) > 300, "a rock windrow along the open edge of the haul road (%d rocks)" % int(counts.get("windrow", 0)))
	# The windrow is on the pit side: across the road from the wall above.
	var s = quarry.ramp_begin + 120.0
	var side = quarry.scenery.pit_side(s)
	var below = stage.at(s) + stage.side(s) * side * 12.0
	var above = stage.at(s) - stage.side(s) * side * 12.0
	check(stage.ground(below) < stage.ground(above) - 3.0, "the windrow guards the drop, not the cut")
	var edge = stage.at(s) + stage.side(s) * side * (stage.road_width(s) * 0.5 + quarry.scenery.WINDROW_OFFSET)
	edge.y = stage.ground(edge)
	var e = Vector3(0.01, 0, 0)
	check(not stage.rock_hit(edge - e, edge + e, 0.3, false).is_empty(), "the windrow stops a car")
	check(int(counts.get("bund_rocks", 0)) > 600 and int(counts.get("talus", 0)) > 600, "boulder bunds on the berms and fallen blocks under the faces")
	for name in ["QuarryShovel", "QuarryBelazLoading", "QuarryBelazWaiting", "QuarryBelazRim", "QuarryDrill", "QuarryPowerLine", "QuarryMill"]:
		var node = stage.get_node_or_null(name)
		check(node != null and node.has_meta("baked_parts"), "%s is built as a merged mesh" % name)
	var shovel: Node3D = stage.get_node("QuarryShovel")
	check(shovel.get_node_or_null("ShovelHouse/ShovelStick") != null, "the shovel's house and stick can move")
	check(Form.on_floor(shovel.global_position) and stage.road_distance(shovel.global_position) > 20.0, "the shovel works the floor away from the road")
	for name in ["QuarryShovel", "QuarryBelazLoading", "QuarryBelazWaiting", "QuarryBelazRim", "QuarryDrill"]:
		var p: Vector3 = stage.get_node(name).global_position
		p.y = stage.ground(p)
		check(not stage.solids.hit(p - e, p + e, 0.3, false).is_empty(), "%s is solid" % name)
		check(stage.road_distance(p) > stage.road_width(stage.road_s(p)) * 0.5 + 6.0, "%s stands clear of the road" % name)
	check(stage.get_node_or_null("QuarrySump") != null and stage.get_node_or_null("QuarrySign") != null, "water in the sump and a sign at the top of the haul road")
	check(int(counts.get("birches", 0)) > 80, "birch copses on the land round the pit")
	var trees_clear = true
	for tree in stage.trees:
		trees_clear = trees_clear and not Form.in_pit(tree) and stage.road_distance(tree) > 9.0
	check(trees_clear and stage.trees.size() > 200, "trees grow round the pit, not in it or on the road (%d)" % stage.trees.size())

func _check_people(stage, quarry) -> void:
	check(stage.clearings.size() == quarry.camps().size(), "%d spectator areas" % stage.clearings.size())
	var floor = 0
	var level = true
	for clearing in stage.clearings:
		if Form.on_floor(clearing):
			floor += 1
		level = level and quarry.camp_allowed(clearing, "table")
		level = level and stage.road_distance(clearing) > stage.road_width(stage.road_s(clearing)) * 0.5 + 6.0
	check(floor >= 2, "spectators watch from the floor under the walls (%d areas)" % floor)
	check(level, "every spectator area is level and off the road")
	check(not quarry.roadside_spectators(), "no one stands on the haul road's verge")
	for station in quarry.marshal_stations():
		check(station > 0.0 and station < stage.length, "a marshal post at %.0f m" % station)

func _check_dust(stage, quarry) -> void:
	var life = quarry.quarry_life
	check(life.trails.size() == life.DUST_TRAILS, "dust clouds ready for %d cars" % life.trails.size())
	# A bare stage has no game around it: the clouds stay down.
	life.update(0.1, stage.at(100.0))
	check(life.trails.all(func(trail): return not trail.emitting), "no car, no dust")
	var game = Node3D.new()
	game.set_script(_fake_game())
	var parent = stage.get_parent()
	parent.remove_child(stage)
	game.add_child(stage)
	root.add_child(game)
	var car = Node3D.new()
	game.add_child(car)
	game.car = car
	car.position = stage.at(500.0)
	life.update(1.0 / 30.0, car.position)
	car.position = stage.at(501.0)
	life.update(1.0 / 30.0, car.position)
	check(life.trails[0].emitting and life.trails[0].position.distance_to(car.position) < 4.0, "a moving car drags a white cloud")
	for i in range(3):
		life.update(1.0 / 30.0, car.position)
	check(not life.trails[0].emitting, "a car at rest raises none")
	var house: Node3D = quarry.scenery.shovel.get_node("ShovelHouse")
	var swung = 0.0
	for i in range(int(life.SHOVEL_CYCLE * 10.0)):
		life.update(0.1, car.position)
		swung = maxf(swung, house.rotation.y)
	check(swung > 1.4, "the shovel swings to the truck")
	var shuttle_from = life.shuttle.position
	var shuttled = 0.0
	var on_berm = true
	for i in range(100):
		life.update(0.1, car.position)
		shuttled = maxf(shuttled, life.shuttle.position.distance_to(shuttle_from))
		on_berm = on_berm and Form.berm(life.shuttle.position).x == life.SHUTTLE_BENCH
	check(shuttled > 20.0 and on_berm, "a BelAZ shuttles along a berm (%.0f m)" % shuttled)
	game.remove_child(stage)
	parent.add_child(stage)
	game.free()

# The few fields of game.gd the dust reads.
func _fake_game() -> GDScript:
	var script = GDScript.new()
	script.source_code = "extends Node3D\nvar car: Node3D\nvar racers: Array = []\nvar room = {\"peers\": {}}\n"
	script.reload()
	return script
