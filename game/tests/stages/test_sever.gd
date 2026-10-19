extends "res://tests/harness.gd"
# «Поречье»: a winter СУ on the plains of the Russian North. Checks the small
# relief with corners and crests, a bridge cars can cross but not fall off, the
# village (izbas, church, well, granary) standing on the ground off the road,
# trees, life and deterministic generation.
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
	var lowest = INF
	var highest = -INF
	for s in range(0, int(stage.length), 2):
		lowest = minf(lowest, stage.at(float(s)).y)
		highest = maxf(highest, stage.at(float(s)).y)
	check(highest - lowest < 6.0, "plains: the whole route stays within a few metres of height (%.1f m)" % (highest - lowest))
	for item in sever.CRESTS:
		var top = float(item[0])
		check(stage.at(top).y - stage.at(top - 26.0).y > 1.0 and stage.at(top).y - stage.at(top + 18.0).y > 1.0, "a crest (подброс) at %d m" % int(top))
	var tightest = INF
	for bend in sever.bends:
		tightest = minf(tightest, float(bend.radius))
	check(sever.bends.size() >= 8 and tightest > 18.0 and tightest < 32.0, "real corners: %d bends, the tightest %.0f m" % [sever.bends.size(), tightest])
	var after_bridge = sever.CORNERS[7][0]
	check(sever.rally_speed(float(after_bridge)) < sever.rally_speed(20.0) - 6.0, "crews brake for the corner after the bridge")
	var monotonic = true
	for i in range(stage.points.size() - 1):
		monotonic = monotonic and stage.points[i + 1].z < stage.points[i].z
	check(monotonic, "route keeps advancing down the map")
	var inside = true
	for s in range(0, int(stage.length), 4):
		inside = inside and absf(stage.at(float(s)).x) < 120.0
	check(inside, "route stays well inside the map")

	# ---------------------------------------------------------------- surface
	var snowy = stage.grip(stage.at(50.0))
	check(snowy > 0.15 and snowy < 0.55, "packed snow grips modestly")
	check(stage.grip(stage.at(sever.BRIDGE_S)) < snowy, "the bridge deck is icy")
	var bounded = true
	for s in range(2, int(stage.length) - 2, 3):
		for lateral in [-2.2, -0.9, 0.0, 0.9, 2.2]:
			var g = stage.grip(stage.at(float(s)) + stage.side(float(s)) * lateral)
			bounded = bounded and g >= 0.1 and g <= 0.8
	check(bounded, "every carriageway point has a valid winter grip")

	# ---------------------------------------------------------------- bridge
	var s0 = sever.BRIDGE_S - sever.BRIDGE_HALF_LENGTH
	var s1 = sever.BRIDGE_S + sever.BRIDGE_HALF_LENGTH
	var half = sever.road_width(sever.BRIDGE_S) * 0.5
	var clear = true
	var smooth = true
	for lateral in [-half + 0.9, 0.0, half - 0.9]:
		var previous = INF
		var s = s0 - 12.0
		while s < s1 + 12.0:
			var a = stage.at(s) + stage.side(s) * lateral
			var b = stage.at(s + 1.0) + stage.side(s + 1.0) * lateral
			a.y = stage.vehicle_ground(a)
			b.y = stage.vehicle_ground(b)
			clear = clear and stage.solids.hit(a, b, 0.9).is_empty() and stage.rock_hit(a, b, 0.9).is_empty()
			if previous != INF:
				smooth = smooth and absf(a.y - previous) < 0.12
			previous = a.y
			s += 1.0
	check(clear, "nothing blocks a car crossing the bridge anywhere on the carriageway")
	check(smooth, "the deck is level with the road: no step onto or off the bridge")
	var from = stage.at(sever.BRIDGE_S)
	from.y = stage.vehicle_ground(from)
	var sideways = from + stage.side(sever.BRIDGE_S) * (half + 3.0)
	check(not stage.solids.hit(from, sideways, 0.9).is_empty(), "railings stop a car sliding off the bridge")
	check(stage.terrain_surface_height(from) < from.y - 1.8, "the stream gully opens under the deck")
	var scenery = stage.get_node("SeverScenery")
	check(scenery.has_node("LogBridge") and scenery.has_node("BridgeDeck") and scenery.has_node("FrozenStream"), "log bridge with a plank deck over the frozen stream")

	# ---------------------------------------------------------------- village
	var houses = 0
	var grounded = true
	var lowest_gap = 0.0
	for child in scenery.get_children():
		var baked = child.get_node_or_null("Baked")
		if baked == null:
			continue
		if String(child.name).begins_with("Izba_"):
			houses += 1
		var gap = (child.transform * baked.mesh.get_aabb()).position.y - stage.ground(child.position)
		lowest_gap = maxf(lowest_gap, gap)
		grounded = grounded and gap < 0.05
	check(houses == sever.HOUSES.size(), "a street of %d log izbas" % houses)
	check(grounded, "every building stands on the ground (worst gap %.2f m)" % lowest_gap)
	for name in ["VillageChurch", "CraneWell", "VillageBarn", "VillageSign", "FencePosts", "FenceRails"]:
		check(scenery.has_node(name), "village has " + name)
	var church: Node3D = scenery.get_node("VillageChurch")
	var church_top = (church.transform * church.get_node("Baked").mesh.get_aabb()).end.y
	check(church_top - church.position.y > 24.0, "the church tent and dome rise %.0f m" % (church_top - church.position.y))
	check(sever.chimneys.size() == sever.HOUSES.size(), "every izba has a chimney (%d)" % sever.chimneys.size())
	var buildings = 0
	for obstacle in stage.solids.obstacles:
		if obstacle.kind == "building": buildings += 1
	check(buildings >= sever.HOUSES.size() + 5, "izbas, church and granary are solid (%d bodies)" % buildings)
	var off_road = true
	for item in sever.HOUSES:
		var footprint = sever.house_footprint(item)
		off_road = off_road and stage.road_distance(footprint.pos) > footprint.radius * 0.5 + 4.0
	check(off_road, "izbas stand back from the street")

	# ---------------------------------------------------------------- trees
	var counts: Dictionary = sever.scenery.counts
	check(int(counts.get("birches", 0)) > 30 and int(counts.get("spruces", 0)) > 15, "birch and spruce groves (%d birches, %d spruces)" % [int(counts.birches), int(counts.spruces)])
	var trees_clear = true
	for tree in stage.trees:
		trees_clear = trees_clear and stage.road_distance(tree) > 10.0 and not sever.reserved(tree, 1.0) and sever.gully(tree) == 0.0
	check(trees_clear, "no tree on the road, in the village or in the stream")
	check(stage.has_node("DistantTreeline"), "a distant taiga line closes the open fields")

	# ---------------------------------------------------------------- life
	var life = sever.life
	check(life != null and life.walkers.size() >= 3 and not life.hens.is_empty() and not life.crows.is_empty() and life.snowfall != null, "villagers, hens, crows and falling snow")
	var walker = life.walkers[0]
	var before: Vector3 = walker.node.position
	for i in range(20):
		life.update(0.1, before)
	check(walker.node.position.distance_to(before) > 0.01, "villagers walk along the street")
	check(life.smoke.size() == sever.chimneys.size(), "wood smoke rises from every chimney")

	# ---------------------------------------------------------------- determinism
	var guest = Stage.new(index)
	check(guest.points == stage.points and guest.clearings == stage.clearings and guest.snow_glades == stage.snow_glades, "every room member builds the same village")
	guest.free()
	stage.queue_free()
	await process_frame
	print("SEVER RESULT: ", failures, " failures")
	finish()
