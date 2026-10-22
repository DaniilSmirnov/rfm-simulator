extends "res://tests/harness.gd"
const RoadChunks = preload("res://scripts/stages/road_chunks.gd")
const Stage = preload("res://scripts/stages/stage.gd")
const Form = preload("res://scripts/stages/canyon/canyon_form.gd")
const Castles = preload("res://scripts/stages/canyon/canyon_castles.gd")
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
	_check_bridge(stage, canyon.bridge)
	_check_castle_colliders(canyon)
	_check_render_chunks(stage)
	_check_contact_cache(stage)
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

func _check_render_chunks(stage) -> void:
	var terrain = stage.find_children("TerrainTile_*", "MeshInstance3D", false, false)
	var local_bounds = true
	var triangles = 0
	for node in terrain:
		var box: AABB = node.mesh.get_aabb()
		local_bounds = local_bounds and box.size.x <= 64.01 and box.size.z <= 64.01
		triangles += node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() / 3
	check(terrain.size() > 100 and local_bounds and triangles == 171462, "the same canyon terrain is culled in local 64 m chunks (%d triangles)" % triangles)
	var towers = stage.get_node("CanyonValleyTowers")
	var local_towers = towers.get_child_count() > 15
	triangles = 0
	for node in towers.get_children():
		var box: AABB = node.mesh.get_aabb()
		local_towers = local_towers and box.size.x < 180.0 and box.size.z < 180.0
		triangles += node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() / 3
	check(local_towers and triangles == 47952, "all castle geometry is retained with local culling bounds (%d triangles)" % triangles)

func _check_contact_cache(stage) -> void:
	var exact = true
	# Compare cold and warm runtime queries with uncached analytic vertices,
	# across both walls, the road, hairpin, grove and service parks.
	for station in [10.0, 140.0, 500.0, 760.0, 1000.0, 1650.0, 1950.0, 2030.0]:
		for lateral in [-40.3, -16.2, -3.1, 0.0, 3.1, 16.2, 40.3]:
			var p = stage.at(station) + stage.side(station) * lateral
			stage._set_terrain_cache(true)
			var expected: float = stage.terrain_surface_height(p)
			stage._set_terrain_cache(false)
			for repeat in range(2):
				exact = exact and absf(stage.terrain_surface_height(p) - expected) < 0.00001
	check(exact, "cached contact matches exact terrain interpolation before and after warming")
	var canyon = stage.canyon
	# Travel far enough to evict both working sets, then revisit an old sample.
	var point = stage.at(1000.0) + stage.side(1000.0) * 16.2
	var expected: float = stage.terrain_surface_height(point)
	for i in range(canyon.CONTACT_CACHE_LIMIT + 8):
		stage.terrain_vertex_height(float(i % 100) * 4.0 - 200.0, float(i / 100) * -4.0)
		stage.terrain_tile_step(float(i % 100) * 4.0 - 200.0, float(i / 100) * -4.0)
	check(canyon.contact_heights.size() <= canyon.CONTACT_CACHE_LIMIT and canyon.contact_steps.size() <= canyon.CONTACT_CACHE_LIMIT, "terrain contact working sets stay bounded while travelling")
	check(absf(stage.terrain_surface_height(point) - expected) < 0.00001, "eviction and revisiting a cliff do not change contact heights")

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
	for camp_name in ["SteppeYurtCamp", "GroveYurtCamp"]:
		var pot = stage.get_node_or_null(camp_name + "/YurtKuyrdak")
		check(pot != null and pot.get_meta("servings", 0) == 10 and pot.get_node("Rice").visible, "a baked yurt camp has ready kuyrdak: " + camp_name)
	for node_name in ["CanyonValleyTowers", "SteppeYurtCamp", "GroveYurtCamp", "LedgeMarkers"]:
		check(stage.get_node_or_null(node_name) != null, "%s is built" % node_name)

# Spectators, camps and the life of the steppe.
func _check_people(stage, canyon) -> void:
	check(stage.clearings.size() == canyon.CAMPS.size() + 1, "every spectator area is placed, the meadow over the bridge last")
	var tilted: Array = []
	for i in range(stage.clearings.size()):
		if not canyon.camp_supported(stage.clearings[i]):
			tilted.append(canyon.CAMPS[i][0] if i < canyon.CAMPS.size() else "meadow")
	check(tilted.is_empty(), "every spectator area is level enough for camp furniture %s" % str(tilted))
	var life = canyon.canyon_life
	check(life.camels.size() >= 12 and life.eagles.size() >= 6, "camel herds graze the steppe under circling eagles")
	var on_steppe = true
	for camel in life.camels:
		on_steppe = on_steppe and camel.node.position.y > Form.rim_level(camel.node.position) - 6.0
	check(on_steppe, "camels stay on the table and never spawn in the gorge")
	var camel_model: Node3D = life.camels[0].node
	check(camel_model.get_node_or_null("Graze") != null and camel_model.get_node_or_null("StepA") != null, "the camel model carries its grazing and walking poses")

# The footbridge over the gorge: on the table at both ends, high over the
# bench road, clear of the rim road, the rock and the drawn land.
func _check_bridge(stage, bridge) -> void:
	var a: Vector3 = bridge.a
	var b: Vector3 = bridge.b
	check(Form.offset(a) > Form.rim_edge(a.z, 1.0) and Form.offset(b) < -Form.rim_edge(b.z, -1.0), "the footbridge runs from one table to the other, right across the gorge")
	check(b.distance_to(a) > 80.0 and absf(b.y - a.y) < 4.0, "a span of %.0f m with an easy slope" % b.distance_to(a))
	var lowest = INF
	for s in range(0, int(stage.length), 2):
		var p = stage.at(s)
		var local: Vector2 = bridge.local(p)
		if local.x > 0.0 and local.x < 1.0 and absf(local.y) < 6.0:
			lowest = minf(lowest, bridge.deck(local.x).y - p.y)
	check(lowest > 30.0 and lowest < INF, "the bench road passes %.0f m under the deck" % lowest)
	var clear_of_road = true
	for end in [a, b]:
		clear_of_road = clear_of_road and stage.road_distance(end, 60.0) > 20.0
	for rock in stage.rocks:
		if bridge.keeps_clear(rock.pos) and not rock.has("building") and not rock.has("post"):
			clear_of_road = clear_of_road and rock.pos.y + rock.height < a.y - 4.0
	check(clear_of_road, "the rim road keeps 20 m off its ends and no rock rises into it")
	# The last metre of each end, where people step on, may meet the soil.
	var drawn = true
	var dug = true
	var span = b.distance_to(a)
	for i in range(0, 101):
		var p: Vector3 = bridge.deck(lerpf(1.2 / span, 1.0 - 1.2 / span, i / 100.0))
		for side in [-1.0, 0.0, 1.0]:
			var q = p + bridge.across * side * bridge.HALF_WIDTH
			drawn = drawn and stage.terrain_surface_height(q) < q.y - 0.05
			dug = dug and stage.ground(q) < q.y
	check(drawn and dug, "the drawn land never shows through the glass deck")
	var middle = bridge.deck(0.5)
	check(absf(stage.solids.walking_floor(middle, middle.y) - middle.y) < 0.01, "people walk on the deck")
	var below = Vector3(middle.x, stage.ground(middle), middle.z)
	check(absf(stage.solids.walking_floor(below, below.y) - below.y) < 0.01, "nobody in the gorge is lifted on to the deck above")
	var canyon = stage.canyon
	check(canyon.walk_blocked(middle + bridge.across * (bridge.HALF_WIDTH + 0.1), middle.y), "the railings hold people on the deck")
	check(not canyon.walk_blocked(middle + bridge.along * 0.3, middle.y), "the deck itself is open to walk along")
	check(not canyon.walk_blocked(below + bridge.across * (bridge.HALF_WIDTH + 0.1), below.y), "the railings do not stop people far below")
	var entrance = a + bridge.along * 0.5
	var car = stage.rock_hit(entrance - bridge.along * 4.0 + Vector3.UP * 0.3, entrance + bridge.along * 2.0 + Vector3.UP * 0.3, 0.85)
	var person = stage.rock_hit(entrance - bridge.along * 3.0 + bridge.across * 0.6 + Vector3.UP * 0.3, entrance + bridge.along * 2.0 + bridge.across * 0.6 + Vector3.UP * 0.3, 0.3)
	check(not car.is_empty() and person.is_empty(), "a bollard keeps cars off the deck, not people")
	var meadow: Vector3 = stage.clearings[-1]
	check(meadow == bridge.meadow and Form.offset(meadow) < -Form.rim_edge(meadow.z, -1.0) - 10.0, "the meadow lies on the far table, back from the lip")
	check(bridge.path_distance(b) < 0.01 and bridge.path_distance(meadow) < 6.0, "a path leads from the bridge to the meadow")
	var lookout: Vector3 = canyon.spectator_watch(meadow)
	check(lookout != Vector3.INF and absf(lookout.y - Form.rim_level(lookout)) < 3.0 and canyon.spectator_watch(stage.clearings[2]) == Vector3.INF, "the far camp watches from the far lip, the others from the road")
	check(stage.get_node_or_null("CharynFootbridge/Glass") != null and stage.get_node_or_null("CharynFootbridge/MeadowPath") != null, "the bridge and its path are built")

# Walks the player over the bridge in the real game and tries to step off it.
func _check_bridge_walk(game) -> void:
	var bridge = game.stage.canyon.bridge
	game.in_car = false
	game.jump_height = 0.0
	game.jump_velocity = 0.0
	# Beside the bollard in the middle of the entrance.
	game.walker = bridge.a - bridge.along * 3.0 + bridge.across * 0.6
	game.walker.y = game.stage.ground(game.walker)
	game.view_yaw = atan2(-bridge.along.x, -bridge.along.z)
	Input.action_press("forward")
	var lowest = INF
	for i in range(60 * 50):
		game.player.walk_step(1.0 / 60.0)
		var t: Vector2 = bridge.local(game.walker)
		if t.x > 0.05 and t.x < 0.95:
			lowest = minf(lowest, game.walker.y - bridge.deck(t.x).y)
		if t.x > 1.05:
			break
	Input.action_release("forward")
	check(bridge.local(game.walker).x > 1.0 and lowest > -0.05, "the player walks right across on the deck (lowest %.2f m)" % lowest)
	game.walker = bridge.deck(0.5)
	game.view_yaw = atan2(-bridge.across.x, -bridge.across.z)
	Input.action_press("forward")
	for i in range(240):
		game.player.walk_step(1.0 / 60.0)
	Input.action_release("forward")
	check(absf(bridge.local(game.walker).y) < bridge.HALF_WIDTH and absf(game.walker.y - bridge.deck(0.5).y) < 0.05, "nobody walks off the deck into the gorge")
	var watching = 0
	for person in game.spectators.people:
		if bridge.far_side(person.home):
			watching += 1
			check(absf(person.watch.y - game.stage.ground(person.watch)) < 0.01 and Form.offset(person.watch) < -Form.rim_edge(person.watch.z, -1.0), "a fan on the far side watches from the table %s" % person.watch)
	check(watching == 2, "a camp of two stands on the meadow (%d)" % watching)

# Every kind of castle, built on flat ground: a walker (0.3 m) never stands
# inside the drawn rock, and the colliders keep nobody off open ground more
# than a little way out from it.
func _check_castle_colliders(biome) -> void:
	var flat_ground = func(_p: Vector3) -> float: return 0.0
	var inside = 0
	var open_rock = 0
	var walled = 0
	var blocked = 0
	for kind in Castles.KINDS:
		for index in [3, 8, 13]:
			var st = SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var circles = Castles.build(st, biome, Vector3.DOWN * 1.5, kind, 24.0, 24.0 * (0.4 if kind == "slab" else 0.25), 0.4, index, 0.0, flat_ground)
			var faces: PackedVector3Array = st.commit().get_faces()
			var rock: Dictionary = {}
			var outside: Array = []
			for z in range(-60, 61):
				var crossings = _crossings(faces, z * 0.5)
				for x in range(-60, 61):
					var p = Vector3(x * 0.5, 1.0, z * 0.5)
					if _inside_row(crossings, p.x):
						rock[Vector2i(x, z)] = true
						inside += 1
						if not _blocked(circles, p, 0.3):
							open_rock += 1
					elif _blocked(circles, p, 0.0):
						outside.append(Vector2i(x, z))
			blocked += outside.size()
			for cell in outside:
				var near = false
				for dx in range(-3, 4):
					for dz in range(-3, 4):
						near = near or rock.has(cell + Vector2i(dx, dz))
				if not near:
					walled += 1
	check(open_rock < inside / 100, "nobody walks into a castle, bastion, fin, block, slab or hoodoo (%d of %d spots inside the rock left open)" % [open_rock, inside])
	check(walled < inside / 50, "castle colliders keep off open ground only next to the rock (%d spots blocked over 1.5 m out)" % walled)

func _blocked(circles: Array, p: Vector3, slack: float) -> bool:
	for circle in circles:
		if Vector2(circle.pos.x - p.x, circle.pos.z - p.z).length() < float(circle.radius) + slack and p.y < circle.pos.y + float(circle.height):
			return true
	return false

# Where the line at height 1 m across the form at z enters and leaves the
# rock: [x, the x of the face normal], ordered along x.
func _crossings(faces: PackedVector3Array, z: float) -> Array:
	var crossings: Array = []
	for i in range(0, faces.size(), 3):
		if minf(minf(faces[i].z, faces[i + 1].z), faces[i + 2].z) > z or maxf(maxf(faces[i].z, faces[i + 1].z), faces[i + 2].z) < z:
			continue
		var hit = Geometry3D.ray_intersects_triangle(Vector3(-100.0, 1.0, z), Vector3.RIGHT, faces[i], faces[i + 1], faces[i + 2])
		if hit != null:
			crossings.append([hit.x, (faces[i + 2] - faces[i]).cross(faces[i + 1] - faces[i]).x])
	crossings.sort_custom(func(a, b): return a[0] < b[0])
	return crossings

# Inside the rock: more faces entered than left on the way along x (the
# towers of a castle overlap).
func _inside_row(crossings: Array, x: float) -> bool:
	var depth = 0
	for crossing in crossings:
		if crossing[0] >= x:
			break
		depth += 1 if crossing[1] < 0.0 else -1
	return depth > 0

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
	var in_rock: Array = []
	var spots: Array = [game.car.position]
	for group in game.spectators.groups:
		spots.append(group.car.position)
	for person in game.spectators.people:
		spots.append(person.home)
	for spot in spots:
		var flat = Vector2(spot.x, spot.z)
		if _blocked(game.stage.rocks_in_bounds(flat - Vector2.ONE, flat + Vector2.ONE).filter(func(rock): return not rock.has("actor")), spot + Vector3.UP * 0.5, 0.0):
			in_rock.append(spot)
	check(in_rock.is_empty(), "no player, NPC car or spectator starts inside a rock %s" % str(in_rock))
	var grove_clearing: Vector3 = game.stage.clearings[game.stage.canyon.CAMPS.size() - 1]
	var toward_road: Vector3 = game.stage.at(game.stage.road_s(grove_clearing)) - grove_clearing
	var camp_spot: Vector3 = grove_clearing + Vector3(toward_road.x, 0, toward_road.z).normalized() * 3.0
	camp_spot.y = game.stage.ground(camp_spot)
	check(game.place_table(camp_spot) and absf(game.camp.position.y - game.stage.ground(camp_spot)) < 0.001, "a real table rests on the floor of the grove")
	_check_bridge_walk(game)
	await game._shutdown_audio()
	game.free()
