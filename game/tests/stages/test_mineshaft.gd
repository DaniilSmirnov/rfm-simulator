extends "res://tests/harness.gd"
const Stage = preload("res://scripts/stages/stage.gd")
const StageRegistry = preload("res://scripts/stages/stage_registry.gd")
const CarRegistry = preload("res://scripts/cars/car_registry.gd")
const BlockText = preload("res://scripts/core/block_text.gd")
func _initialize() -> void:
	call_deferred("run")

func turning(stage, from: float, to: float) -> float:
	var total = 0.0
	for s in range(int(from), int(to), 2):
		var a = stage.direction(s)
		var b = stage.direction(s + 2)
		total += absf(atan2(a.cross(b).y, a.dot(b)))
	return total

func drive_over(stage, mine, speed: float) -> Dictionary:
	var car = Node3D.new()
	root.add_child(car)
	var motion = preload("res://scripts/cars/vehicle_motion.gd").new()
	var s = mine.LIP - 30.0
	# The longest flight and where it ends.
	var result = {"airborne": 0.0, "landed": INF}
	var flight = 0.0
	car.position = stage.at(s)
	while s < mine.CORNER_BEGIN + 10.0:
		s += speed / 60.0
		var p = stage.at(s)
		car.position = Vector3(p.x, car.position.y, p.z)
		var direction = stage.direction(s)
		motion.suspension(car, stage, 1.0 / 60.0, atan2(-direction.x, -direction.z))
		if not motion.grounded:
			flight += 1.0 / 60.0
		elif flight > 0.0:
			if flight > result.airborne:
				result.airborne = flight
				result.landed = s
			flight = 0.0
	car.free()
	return result

func run() -> void:
	var index = -1
	for i in range(Stage.STAGES.size()):
		if StageRegistry.entry(i).id == "mineshaft":
			index = i
	check(index >= 0, "Mineshaft is registered as a stage")
	var stage = Stage.new(index)
	root.add_child(stage)
	stage.build()
	var mine = stage.biome
	check(Stage.STAGES[index].begins_with("Майншафт"), "stage is called Майншафт in the menu")

	# --- Route character from the real stage.
	check(turning(stage, mine.OPENING_BEGIN, mine.OPENING_END) > 4.0, "opening complex is a run of linked bends (%.2f rad)" % turning(stage, mine.OPENING_BEGIN, mine.OPENING_END))
	check(turning(stage, mine.OPENING_END + 30.0, mine.LIP) < 0.25, "long straight before the jump (%.2f rad)" % turning(stage, mine.OPENING_END + 30.0, mine.LIP))
	check(mine.LIP - mine.OPENING_END > 350.0, "the straight is long")
	check(stage.at(mine.LIP).y - stage.at(mine.OPENING_END + 30.0).y > 3.0, "the straight climbs to the lip")
	# The slowest car of the fleet, leaving the opening bends at 40 km/h,
	# passes 100 km/h well before the lip on full throttle.
	var slowest = INF
	for car in CarRegistry.cars:
		slowest = minf(slowest, CarRegistry.launch(float(car.handling.zero_to_100)))
	var v = 40.0 / 3.6
	var at_hundred = INF
	var x = mine.OPENING_END + 20.0
	while x < mine.LIP:
		v += CarRegistry.pull(slowest, v) * 0.05
		x += v * 0.05
		if v >= 100.0 / 3.6 and at_hundred == INF:
			at_hundred = x
	check(at_hundred < mine.LIP - 40.0, "the slowest car reaches 100 km/h %.0f m before the lip (%.0f km/h there)" % [mine.LIP - at_hundred, v * 3.6])
	var drop = stage.at(mine.LIP).y - stage.at(mine.LIP + mine.DROP_LENGTH).y
	check(drop > 12.0, "the road plunges %.1f m past the lip" % drop)
	var steepest = 0.0
	for s in range(int(mine.LIP), int(mine.LIP + mine.DROP_LENGTH)):
		steepest = maxf(steepest, stage.at(s).y - stage.at(s + 1).y)
	check(rad_to_deg(atan(steepest)) > 30.0, "the plunge is steep (%.0f° at its steepest)" % rad_to_deg(atan(steepest)))
	check(stage.at(mine.LIP - 3.0).y > stage.at(mine.LIP - 12.0).y, "a kicker rises to the lip")
	check(turning(stage, mine.CORNER_BEGIN - 4.0, mine.CORNER_END + 4.0) > 0.7, "a corner follows the landing")
	check(turning(stage, mine.CLOSING_BEGIN, mine.CLOSING_END) > 3.0, "short section of linked bends before the finish")
	check(stage.rally_speed(mine.CORNER_BEGIN + 5.0) < stage.rally_speed(mine.LIP - 60.0), "crews brake for the corner after the jump")
	# --- Drivers may misjudge the plunge: some brake properly, some too little,
	# some not at all. Everything else about their pace is unchanged.
	var Traffic = preload("res://scripts/traffic/rally_traffic.gd")
	var clean = 0
	var partial = 0
	var bold = 0
	for id in range(1, 201):
		var n = Traffic.nerve(id)
		check(n == Traffic.nerve(id), "a driver's nerve is repeatable")
		if n == 0.0:
			clean += 1
		elif n < 1.0:
			partial += 1
		else:
			bold += 1
	check(clean > 50 and partial > 40 and bold > 25, "drivers differ: %d brake, %d brake short, %d do not lift" % [clean, partial, bold])
	var zone: Vector2 = mine.jump_zone()
	var lift = Traffic.competition_target(stage, mine.LIP - 5.0)
	var half = Traffic.competition_target(stage, mine.LIP - 5.0, 1.0, false, 0.5)
	var flat = Traffic.competition_target(stage, mine.LIP - 5.0, 1.0, false, 1.0)
	check(lift < half and half < flat, "braking for the plunge shrinks with nerve (%.0f, %.0f, %.0f km/h)" % [lift * 3.6, half * 3.6, flat * 3.6])
	check(flat > 100.0 / 3.6, "a driver who does not lift takes the lip above 100 km/h (%.0f km/h)" % (flat * 3.6))

	var inside = true
	for s in range(0, int(stage.length), 4):
		inside = inside and absf(stage.at(s).x) < 120.0
	check(inside, "route stays well inside the map")

	# --- At 100 km/h a car flies off the lip and lands on the slope before the
	# corner; at walking pace it rolls down on its wheels.
	var fast = drive_over(stage, mine, 100.0 / 3.6)
	check(fast.airborne > 0.8 and fast.landed > mine.LIP + mine.DROP_LENGTH * 0.5 and fast.landed < mine.LIP + mine.DROP_LENGTH, "at 100 km/h a car flies %.2f s and lands on the slope %.0f m past the lip" % [fast.airborne, fast.landed - mine.LIP])
	var slow = drive_over(stage, mine, 15.0 / 3.6)
	check(slow.airborne < 0.1, "at 15 km/h a car rolls down the plunge on its wheels (%.2f s in the air)" % slow.airborne)
	var middle = drive_over(stage, mine, 50.0 / 3.6)
	print("INFO: at 50 km/h %.2f s in the air, lands %.0f m past the lip" % [middle.airborne, middle.landed - mine.LIP])

	# --- Australian bush and landmarks.
	var c = mine.scenery.counts
	check(int(c.get("gums", 0)) > 150, "open eucalyptus woodland (%d gum trees)" % int(c.get("gums", 0)))
	check(stage.trees.size() > int(c.get("gums", 0)) + 300, "gum trees and the pine plantation stop cars (%d trees)" % stage.trees.size())
	check(int(c.get("tussocks", 0)) > 2000 and int(c.get("boulders", 0)) > 40 and int(c.get("termite_mounds", 0)) > 60, "tussock grass, granite tors and termite mounds")
	var pines_at_jump = true
	for i in range(stage.trees.size() - int(c.get("gums", 0))):
		pines_at_jump = pines_at_jump and mine.in_plantation(stage.trees[i])
	check(pines_at_jump, "pines grow only in the plantation around the jump")
	check(stage.get_node_or_null("MineshaftCreek") != null and stage.get_node_or_null("JumpScorecards") != null, "creek at the bottom and fans' scorecards at the jump")
	var clear_road = true
	for tree in stage.trees:
		clear_road = clear_road and stage.road_distance(tree) > 9.0
	check(clear_road, "no tree grows on the road")
	# Measured against the centre line itself: in the opening bends the road
	# runs up to 50° off -z, where a station read from -z put rocks on the road.
	var rocks_off_road = true
	for rock in stage.rocks:
		var s0: float = stage.road_s(rock.pos)
		rocks_off_road = rocks_off_road and stage.woodland.road_clearance(rock.pos, s0) - float(rock.radius) >= stage.road_width(s0) * 0.5 - 0.001
	check(rocks_off_road, "no rock lies on the road, even in the opening bends")
	for structure in ["MineHeadframe", "Homestead", "MineshaftSign"]:
		var node = stage.get_node_or_null(structure)
		check(node != null and node.has_meta("baked_parts"), "%s is built as a merged mesh" % structure)
	var drive_left = stage.get_node("DriveLeftSigns")
	var posts = drive_left.get_children().filter(func(n): return not n is MeshInstance3D)
	check(posts.size() == 2, "two Drive On Left signs")
	check(posts.all(func(post): return post.has_meta("prop_key") and post.get_meta("baked_text", []).has("DRIVE") and post.get_meta("baked_text", []).has("IN AUSTRALIA")), "independent movable Drive On Left signs carry their lettering")
	var verge = true
	for sign in posts:
		verge = verge and stage.road_distance(sign.global_position) > stage.road_width(0.0) * 0.5 + 1.0
	check(verge, "Drive On Left signs stand off the road")
	# Every sign caption fits the plate it is printed on.
	var plates = Node3D.new()
	root.add_child(plates)
	mine.scenery._kangaroo_sign(plates)
	mine.scenery._drive_left_sign(plates)
	var fits = true
	var captions = 0
	for label in plates.get_children():
		if label is Label3D:
			captions += 1
			var extent = BlockText.cells(label.text) * BlockText.label_pixel(label)
			var box: Vector2 = label.get_meta("fit_box")
			fits = fits and extent.x <= box.x + 0.0001 and extent.y <= box.y + 0.0001
	fits = fits and mine.scenery.KANGAROO_CAPTION.x < mine.scenery.KANGAROO_PLATE.x and mine.scenery.KANGAROO_CAPTION.y < mine.scenery.KANGAROO_PLATE.y
	fits = fits and mine.scenery.DRIVE_LEFT_CAPTION.x < mine.scenery.DRIVE_LEFT_PLATE.x - 0.2
	check(captions == 4 and fits, "sign lettering stays inside its plates")
	plates.free()
	check(stage.get_node_or_null("Homestead/WindmillRotor") != null, "the windmill rotor can turn")
	check(stage.road_distance(mine.mine) > 15.0, "mine headframe stands clear of the jump")
	check(stage.clearings.size() == mine.CLEARINGS.size(), "spectator areas at the bends and both banks of the jump")
	for clearing in stage.clearings:
		check(stage.road_distance(clearing) > 10.0, "spectator area is off the road")

	# --- Wildlife: kangaroos bound away from people, cockatoos and the windmill move.
	var life = mine.outback_life
	check(life.kangaroos.size() >= 18 and life.cockatoos.size() >= 15, "mobs of kangaroos and flocks of cockatoos")
	var roo: Dictionary = life.kangaroos[0]
	var start: Vector3 = roo.node.position
	var bounded = false
	for i in range(40):
		life.update(0.05, start + Vector3(3, 0, 0))
		bounded = bounded or roo.node.get_node("Bound").visible
	check(bounded and not (roo.node.get_node("Bound").visible and roo.node.get_node("Stand").visible), "a fleeing kangaroo switches to its bounding pose")
	check(roo.node.position.distance_to(start) > 4.0 and life.hops > 0, "kangaroos hop away from a person")
	check(absf(roo.node.position.y - stage.ground(roo.node.position)) < 1.6, "kangaroos stay on the ground")
	var rotor_angle = life.rotor.rotation.z
	life.update(0.1, Vector3(0, 0, 400))
	check(life.rotor.rotation.z != rotor_angle, "windmill turns")

	# --- Determinism across room members.
	var copy = Stage.new(index)
	check(stage.points == copy.points and stage.clearings == copy.clearings, "route and spectator areas match across clients")
	copy.free()
	stage.free()
	print("MINESHAFT RESULT: %d failures" % failures)
	finish()
