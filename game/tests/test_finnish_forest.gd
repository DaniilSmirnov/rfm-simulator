extends "res://tests/harness.gd"
const Stage = preload("res://scripts/stage.gd")
const Motion = preload("res://scripts/vehicle_motion.gd")
func _initialize() -> void:
	call_deferred("run")

func deep_point(stage, minimum: float) -> Vector3:
	for lake in stage.finnish_forest.LAKES:
		for s in range(int(lake.s0) + 20, int(lake.s1) - 20, 4):
			for u in range(30, 60, 4):
				var p = Vector3(stage.at(s).x + u * float(lake.side), 0, -s)
				if stage.water.depth(p) > minimum:
					p.y = stage.ground(p)
					return p
	return Vector3.INF

func run() -> void:
	var stage = Stage.new(4)
	root.add_child(stage)
	stage.build()
	var ff = stage.finnish_forest
	check(stage.lakeland and not stage.desert and not stage.provence and not stage.winter, "fifth stage is a distinct Finnish lake-forest biome")
	check(Stage.STAGES[4].begins_with("Финский лес"), "stage is called Финский лес in the menu")

	# --- Route character: fast crests, a yellow-house jump, sweepers and a chicane.
	var jump = stage.at(ff.YELLOW_HOUSE_STATION).y
	check(jump - stage.at(ff.YELLOW_HOUSE_STATION - 12).y > 1.2 and jump - stage.at(ff.YELLOW_HOUSE_STATION + 12).y > 1.2, "yellow house crest rises and drops sharply")
	var crests = 0
	for s in range(8, int(Stage.LENGTH) - 8, 2):
		var y = stage.at(s).y
		if y > stage.at(s - 6).y + 0.45 and y > stage.at(s + 6).y + 0.45 and y >= stage.at(s - 2).y and y >= stage.at(s + 2).y:
			crests += 1
	check(crests >= 6, "stage has a series of jumps and crests (%d)" % crests)
	var turning = 0.0
	for s in range(ff.CHICANE_BEGIN, ff.CHICANE_END, 2):
		var a = stage.direction(s)
		var b = stage.direction(s + 2)
		turning += absf(atan2(a.cross(b).y, a.dot(b)))
	check(turning > 1.2, "forest chicane has tight alternating bends (%.2f rad)" % turning)
	var sweep = 0.0
	for s in range(20, 280, 4):
		sweep = maxf(sweep, absf(stage.at(s).x))
	check(sweep > 12.0 and stage.rally_speed(150) > stage.rally_speed(480), "fast open sweepers are quicker than the chicane")

	# --- Lakes beside the road, a ford through the strait, dry roadside elsewhere.
	check(stage.water.surfaces.size() == 3, "three rendered lake bodies")
	var lakeside = 0
	var both_sides = 0
	for s in range(0, int(Stage.LENGTH), 2):
		var left = false
		var right = false
		for lat in range(5, 19):
			left = left or stage.water.depth(stage.at(s) + stage.side(s) * -lat) > 0.0
			right = right or stage.water.depth(stage.at(s) + stage.side(s) * lat) > 0.0
		if left or right:
			lakeside += 2
		if left and right:
			both_sides += 2
	check(lakeside >= 200, "road runs within 18 m of a lake for %d m" % lakeside)
	check(both_sides >= 40, "an isthmus has water on both sides for %d m" % both_sides)
	var ford_depth = stage.water.depth(stage.at(ff.FORD_STATION))
	check(ford_depth > 0.25 and ford_depth < 0.6, "the road fords the strait through %.2f m of water" % ford_depth)
	var dry_road = true
	for s in range(0, int(Stage.LENGTH), 3):
		if absf(s - ff.FORD_STATION) > 22.0:
			for lat in [-3.5, 0.0, 3.5]:
				dry_road = dry_road and stage.water.depth(stage.at(s) + stage.side(s) * lat) < 0.0
	check(dry_road, "outside the ford the driving surface stays dry")
	var road: ArrayMesh = stage.get_node("StageRoadSurface").mesh
	var vertices: PackedVector3Array = road.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var contact = true
	for i in range(0, vertices.size(), 41):
		contact = contact and absf(vertices[i].y - stage.ground(vertices[i]) - 0.04) < 0.001
	check(contact, "visible road follows the driving contact surface")
	var islands = 0
	for lake in ff.LAKES:
		for island in lake.islands:
			var p = Vector3(stage.at(island.s).x + island.u * float(lake.side), 0, -island.s)
			if stage.water.depth(p) < 0.0:
				islands += 1
	check(islands >= 2, "lakes contain forested islands above the water")

	# --- Living forest: trees, grass, ant hills, stones, berries and mushrooms on dry land.
	check(stage.trees.size() > 4000, "dense pine forest (%d trees)" % stage.trees.size())
	var trees_dry = true
	for i in range(0, stage.trees.size(), 7):
		trees_dry = trees_dry and stage.water.depth(stage.trees[i]) < -0.3
	check(trees_dry, "no tree grows in a lake")
	check(stage.woodland_details.get("ForestGrass", 0) > 15000, "forest floor is carpeted with grass")
	check(stage.woodland_details.get("AntHills", 0) >= 40, "forest has ant hills")
	check(stage.woodland_details.get("ForestPebbles", 0) > 800 and stage.woodland_details.get("ForestBoulders", 0) > 150, "stones and glacial boulders lie in the forest")
	var berries = 0
	var mushrooms = 0
	var food_dry = true
	for item in stage.collectibles:
		berries += 1 if item.kind == "berries" else 0
		mushrooms += 1 if item.kind == "mushrooms" else 0
		food_dry = food_dry and stage.water.depth(item.pos) < 0.0
	check(berries > 250 and mushrooms > 300, "berries (%d) and mushrooms (%d) can be picked" % [berries, mushrooms])
	check(food_dry, "berries and mushrooms grow on dry land")
	var life = stage.forest_life
	check(life.swaying_nodes > 50, "tree crowns and grass sway in the wind")
	check(life.reed_count > 300 and life.lily_count > 80, "lake shores have reed beds and lily pads")
	check(life.ducks.size() >= 8 and life.birds.size() >= 10 and life.flies.size() >= 10, "ducks, birds and dragonflies live around the lakes")
	check(life.anthills.size() == stage.woodland_details.get("AntHills", 0), "every ant hill can host ants")
	life.update(0.1, life.anthills[0].base)
	check(life.active_ants >= life.ANTS_PER_HILL, "ants crawl over a nearby ant hill")
	var duck = life.ducks[0]
	var duck_start: Vector3 = duck.node.position
	for i in range(30):
		life.update(0.1, duck_start + Vector3(2, 0, 0))
	check(duck.node.position.distance_to(duck_start) > 1.0 and stage.water.depth(duck.node.position) > 0.4, "ducks paddle away from people and stay on the water")
	check(stage.get_node_or_null("YellowHouse") != null and stage.get_node_or_null("LakeSauna") != null and stage.get_node_or_null("RowingBoat") != null, "farmhouse, lake sauna, jetty and boat are built")
	for clearing in stage.clearings:
		check(stage.water.depth(clearing) < -0.5 and stage.road_distance(clearing) > 9.0, "spectator clearing is dry and off the road")

	# --- Water physics.
	var copy = Stage.new(4)
	var deterministic = stage.points == copy.points
	for p in [Vector3(-40, 0, -360), Vector3(30, 0, -600), Vector3(40, 0, -760)]:
		deterministic = deterministic and stage.ground(p) == copy.ground(p) and stage.water.depth(p) == copy.water.depth(p)
	check(deterministic, "route, lake beds and water levels match on every client")
	copy.free()
	stage.water.clock_override = 12.0
	var deep = deep_point(stage, 2.5)
	check(deep != Vector3.INF, "lakes are deep enough to swim and to float a car")
	var level = stage.water.level(deep)
	var floating_car = Node3D.new()
	stage.add_child(floating_car)
	floating_car.position = deep
	var motion = Motion.new()
	for i in range(240):
		motion.suspension(floating_car, stage, 1.0 / 60.0, 0.0)
	check(not motion.grounded and floating_car.position.y > deep.y + 0.6, "a car in deep water is lifted off the lake bed by buoyancy")
	check(floating_car.position.y < level and motion.submerged > 0.3 and motion.submerged < 0.85, "the floating car sits partly submerged")
	for i in range(int((stage.water.FLOOD_SECONDS * 1.5 + 8.0) * 60.0)):
		motion.suspension(floating_car, stage, 1.0 / 60.0, 0.0)
	check(motion.flood >= 1.0 and motion.grounded and floating_car.position.y < deep.y + 0.3, "a flooded car sinks to the bottom")
	var land_motion = Motion.new()
	var land_car = Node3D.new()
	stage.add_child(land_car)
	land_car.position = stage.at(100)
	var water_motion = Motion.new()
	var wet_car = Node3D.new()
	stage.add_child(wet_car)
	wet_car.position = deep
	land_motion.velocity = Vector3(0, 0, -10)
	water_motion.velocity = Vector3(0, 0, -10)
	for i in range(30):
		land_motion.suspension(land_car, stage, 1.0 / 60.0, 0.0)
		water_motion.suspension(wet_car, stage, 1.0 / 60.0, 0.0)
	check(water_motion.velocity.length() < 6.0 and land_motion.velocity.length() > 9.9, "water resistance brakes a moving car (%.1f m/s)" % water_motion.velocity.length())
	check(stage.water.droplets.size() > 0 and stage.water.ripples.size() > 0, "moving through water throws spray and leaves ripples")
	var ford_motion = Motion.new()
	var ford_car = Node3D.new()
	stage.add_child(ford_car)
	ford_car.position = stage.at(ff.FORD_STATION)
	for i in range(120):
		ford_motion.suspension(ford_car, stage, 1.0 / 60.0, 0.0)
	check(ford_motion.grounded and ford_motion.flood == 0.0 and ford_motion.submerged > 0.1, "crews can splash through the shallow ford without floating")
	stage.water.splash(Vector3(deep.x, level, deep.z), 1.0)
	var splashes = stage.water.droplets.size()
	for i in range(240):
		stage.water.update(1.0 / 60.0)
	check(splashes > 0 and stage.water.droplets.is_empty() and stage.water.ripples.is_empty(), "spray falls back into the lake and ripples fade")
	var boat: Node3D = ff.boat
	boat.position.y += 1.0
	for i in range(240):
		stage.water.update(1.0 / 60.0)
	check(absf(boat.position.y - (stage.water.surface(boat.position) - 0.22)) < 0.05, "the rowing boat settles back onto the waves")
	check(stage.water.walk_factor(deep) == 0.5 and stage.water.walk_factor(stage.at(ff.FORD_STATION)) < 1.0 and stage.water.walk_factor(stage.at(100)) == 1.0, "wading slows people down, swimming is half speed")
	check(absf(stage.walk_floor(deep, deep.y) - (level + stage.water.wave(deep.x, deep.z, 12.0) - stage.water.SWIM_DEPTH)) < 0.001, "swimmers float at the surface instead of walking on the bottom")
	var jetty_middle: Vector3 = (ff.jetty.start + ff.jetty.end) * 0.5
	check(stage.walk_floor(jetty_middle, stage.ground(jetty_middle)) == float(ff.jetty.deck) and stage.water.depth(jetty_middle) > 0.0, "the jetty deck is walkable above the water")
	stage.water.clock_override = -1.0
	stage.free()

	# --- Integration with the real game.
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.room.set_process(false)
	game.select_stage(4)
	await game.start_game()
	check(game.stage.lakeland and game.stage.water.surfaces.size() == 3, "game starts on the lake stage")
	var npc_dry = true
	for group in game.spectators.groups:
		npc_dry = npc_dry and game.stage.water.depth(group.car.position) < 0.0 and game.stage.water.depth(group.table.position) < 0.0
	for person in game.spectators.people:
		npc_dry = npc_dry and game.stage.water.depth(person.avatar.position) < 0.0
	check(npc_dry and not game.spectators.groups.is_empty(), "NPC camps are on dry land")
	var officials_dry = true
	for person in game.stage.officials.people:
		officials_dry = officials_dry and game.stage.water.depth(person.avatar.position) < 0.0
	check(officials_dry, "marshals stand on dry ground")
	var lake_spot = deep_point(game.stage, 2.0)
	check(not game.valid_furniture_spot(lake_spot, "table"), "camp furniture cannot be placed in a lake")
	game.spectators.groups.clear()
	game.spectators.people.clear()
	game.in_car = false
	game.walker = lake_spot
	game.walker.y = game.stage.walk_floor(lake_spot, game.stage.ground(lake_spot))
	game.jump_height = 0
	game.jump_velocity = 0
	check(not game.jump(), "no jumping while swimming")
	var start: Vector3 = game.walker
	game.view_yaw = 0
	Input.action_press("forward")
	game._walk(1.0)
	Input.action_release("forward")
	var swum = Vector2(game.walker.x - start.x, game.walker.z - start.z).length()
	check(swum > 0.5 and swum < game.WALK_SPEED * 0.6, "the player swims slowly (%.2f m/s)" % swum)
	check(game.walker.y > game.stage.ground(game.walker) + 0.8, "the swimmer stays afloat above the bed")
	var stone = {"node": game._acquire_gravel(0.1), "velocity": Vector3(0, -2, 0), "life": 2.0, "bounces": 0}
	stone.node.position = Vector3(lake_spot.x, game.stage.water.level(lake_spot) + 0.05, lake_spot.z)
	var before_splashes = game.stage.water.splash_count
	check(not game._advance_gravel(stone, 0.1) and game.stage.water.splash_count > before_splashes, "gravel thrown into the lake sinks with a splash")
	game._release_gravel(stone.node)
	game.in_car = true
	game.car.position = lake_spot
	game.vehicle_motion = Motion.new()
	game.condition = 100.0
	for i in range(4200):
		game._drive(1.0 / 60.0)
		if game.dead:
			break
	check(game.dead and game.menu_text.text.contains("озере"), "a car driven into a lake floods and is lost")
	await game._shutdown_audio()
	game.free()
	print("FINNISH FOREST RESULT: %d failures" % failures)
	finish()
