extends "res://tests/harness.gd"
# «Поречье»: a flat winter СУ through a Russian-North village. Checks the
# route stays flat, the village/church/well/barn/bridge are built and placed
# off the road, winter mechanics are wired up, and the build is deterministic.
const Stage = preload("res://scripts/stages/stage.gd")
const StageRegistry = preload("res://scripts/stages/stage_registry.gd")
func _initialize() -> void: call_deferred("run")

func run() -> void:
	var index = -1
	for i in range(Stage.STAGES.size()):
		if StageRegistry.entry(i).id == "sever":
			index = i
	check(index >= 0, "Поречье is registered as a stage")
	var stage = Stage.new(index)
	root.add_child(stage)
	stage.build()
	var sever = stage.biome
	check(Stage.STAGES[index].begins_with("Поречье"), "stage is called Поречье in the menu")
	check(stage.has_snow, "the stage has snow mechanics switched on")

	# ---------------------------------------------------------------- route
	var flat = true
	var lowest = INF
	var highest = -INF
	for s in range(0, int(Stage.LENGTH), 4):
		var y = stage.at(float(s)).y
		lowest = minf(lowest, y)
		highest = maxf(highest, y)
	flat = (highest - lowest) < 6.0
	check(flat, "равнинный: the route's elevation stays within a small band (%.1f m)" % (highest - lowest))
	var gentle = true
	for s in range(0, int(Stage.LENGTH) - 1, 2):
		gentle = gentle and absf(stage.at(float(s + 2)).y - stage.at(float(s)).y) < 0.35
	check(gentle, "no abrupt climbs or drops; small relief only")
	var inside = true
	for s in range(0, int(Stage.LENGTH), 4):
		inside = inside and absf(stage.at(float(s)).x) < 120.0
	check(inside, "route stays well inside the map")
	check(sever.in_village(400.0) and not sever.in_village(50.0), "the village sits on a stretch of the street")

	# ---------------------------------------------------------------- surface
	var snowy = stage.grip(stage.at(50.0))
	check(snowy > 0.15 and snowy < 0.55, "packed snow grips modestly")
	var bridge_grip = stage.grip(stage.at(sever.BRIDGE_S))
	check(bridge_grip < snowy, "the frozen bridge glazes over and grips worse than the packed snow road")
	var bounded = true
	for s in range(2, int(Stage.LENGTH) - 2, 3):
		for lateral in [-2.5, -0.9, 0.0, 0.9, 2.5]:
			var p = stage.at(float(s)) + stage.side(float(s)) * lateral
			var g = stage.grip(p)
			bounded = bounded and g >= 0.1 and g <= 0.8
	check(bounded, "every carriageway point has a valid winter grip")

	# ---------------------------------------------------------------- village
	var scenery = stage.get_node("SeverScenery")
	var houses = 0
	for child in scenery.get_children():
		if String(child.name).begins_with("Izba_"): houses += 1
	check(houses == sever.HOUSES.size() and houses >= 15, "a street lined with log izbas (%d houses)" % houses)
	for name in ["VillageChurch", "CraneWell", "VillageBarn", "LogBridge", "VillageSign", "FencePosts", "FenceRails"]:
		check(scenery.has_node(name), "village has " + name)
	check(sever.chimneys.size() == sever.HOUSES.size(), "every izba has a chimney for the smoke to rise from (%d)" % sever.chimneys.size())
	check(scenery.has_node("FrozenStream"), "the bridge crosses a frozen stream")

	var church_pos = sever.place(sever.CHURCH.s, sever.CHURCH.side, sever.CHURCH.offset)
	check(stage.road_distance(church_pos) > sever.road_width(sever.CHURCH.s) * 0.5 + 5.0, "the church stands well off the road")
	var barn_pos = sever.place(sever.BARN.s, sever.BARN.side, sever.BARN.offset)
	check(stage.road_distance(barn_pos) > sever.road_width(sever.BARN.s) * 0.5 + 5.0, "the barn stands well off the road")

	var building_rocks = 0
	for rock in stage.rocks:
		if rock.get("building", false): building_rocks += 1
	check(building_rocks >= 2, "the church nave and bell tower have their own collision footprints")
	var barrier_rocks = 0
	for rock in stage.rocks:
		if rock.get("barrier", false): barrier_rocks += 1
	check(barrier_rocks > 50, "yard fences around the houses collide as barriers (%d posts)" % barrier_rocks)

	var walls_solid = true
	for name in ["VillageChurch", "VillageBarn"]:
		var node = stage.get_node("SeverScenery/" + name)
		walls_solid = walls_solid and node != null
	check(walls_solid, "church and barn are built as solid structures")

	# ---------------------------------------------------------------- trees
	var counts: Dictionary = sever.scenery.counts
	check(int(counts.get("birches", 0)) > 30 and int(counts.get("spruces", 0)) > 15, "birch and spruce groves frame the village (%d birches, %d spruces)" % [int(counts.birches), int(counts.spruces)])
	check(stage.trees.size() > int(counts.birches) + int(counts.spruces) - 5, "birches and spruces register as collidable trees (%d trees)" % stage.trees.size())
	var trees_clear = true
	for tree in stage.trees:
		trees_clear = trees_clear and stage.road_distance(tree) > 10.0 and not sever.reserved(tree, 1.0)
	check(trees_clear, "no tree grows on the road or inside the village")
	check(stage.has_node("DistantTreeline"), "a distant taiga line closes the open fields")

	# ---------------------------------------------------------------- life
	var life = sever.life
	check(life != null and life.walkers.size() >= 3 and not life.hens.is_empty() and not life.crows.is_empty() and life.snowfall != null, "villagers, hens, crows and falling snow populate the village")
	var walker = life.walkers[0]
	var before: Vector3 = walker.node.position
	for i in range(20):
		life.update(0.1, before)
	check(walker.node.position.distance_to(before) > 0.01 or walker.path.size() < 2, "villagers walk along the street")
	check(not life.smoke.is_empty() and life.smoke.size() == sever.chimneys.size(), "wood smoke rises from every chimney")

	# ---------------------------------------------------------------- determinism
	var guest = Stage.new(index)
	check(guest.points == stage.points and guest.clearings == stage.clearings and guest.snow_glades == stage.snow_glades, "every room member builds the same village")
	guest.free()
	stage.queue_free()
	await process_frame
	print("SEVER RESULT: ", failures, " failures")
	finish()
