extends "res://tests/harness.gd"
# "Зимний Турини" as a Monte-Carlo col: route, mixed tarmac, scenery and life.
# Deep snow, banks and digging keep their own tests (deep_snow, snowbanks, shovel).
const Stage = preload("res://scripts/stage.gd")
const Banks = preload("res://scripts/snowbanks.gd")
func _initialize() -> void: call_deferred("run")

func run() -> void:
	var stage = Stage.new(1)
	var alpine = stage.alpine
	# ---------------------------------------------------------------- route
	var monotonic = true
	var gentle = true
	for i in range(stage.points.size() - 1):
		var a: Vector3 = stage.points[i]
		var b: Vector3 = stage.points[i + 1]
		monotonic = monotonic and b.z < a.z
		gentle = gentle and absf(b.x - a.x) / absf(b.z - a.z) < 1.3
	check(monotonic and gentle, "route keeps advancing down the map; bends stay within the stage's road model")
	var tightest = INF
	for i in range(int(stage.LENGTH)):
		var k = absf(alpine.curvature(float(i)))
		if k > 0.0: tightest = minf(tightest, 1.0 / k)
	check(tightest > 14.0 and tightest < 24.0, "lacet hairpins are tight but wider than the snowbanks (%.1f m)" % tightest)
	var lacets = 0
	for bend in alpine.bends:
		if float(bend.radius) < 32.0: lacets += 1
	check(lacets >= 10, "two ladders of tight lacets (%d bends)" % lacets)
	var col_height = stage.at(alpine.COL_STATION).y
	check(col_height - stage.at(0).y > 25.0 and col_height - stage.at(stage.LENGTH).y > 15.0, "road climbs to the col and descends to the finish")
	check(alpine.rally_speed(float(alpine.bends[3].s)) < alpine.rally_speed(60.0) - 4.0, "crews brake for the lacets and run fast on the corniche")
	# ---------------------------------------------------------------- surface
	var dry = stage.grip(stage.at(40.0) + stage.side(40.0) * 0.95)
	var plain = 250.0
	while alpine.ice(plain, 0.0) > 0.0 or alpine.ice(plain, 0.95) > 0.0:
		plain += 1.0
	var snowy = stage.grip(stage.at(plain))
	var track = stage.grip(stage.at(plain) + stage.side(plain) * 0.95)
	check(dry > 0.6 and snowy < 0.45 and track > snowy + 0.12, "dry tarmac grips, snow is slippery, wheel tracks through the snow grip better")
	var glazed = INF
	for s in range(436, 456):
		glazed = minf(glazed, stage.grip(stage.at(float(s)) + stage.side(float(s)) * 0.4))
	check(glazed < 0.25, "black ice on the shaded col is the slipperiest surface (%.2f)" % glazed)
	var bounded = true
	var clean = true
	for s in range(2, int(stage.LENGTH) - 2, 2):
		for lateral in [-3.5, -2.0, -0.9, 0.0, 0.9, 2.0, 3.5]:
			var p = stage.at(float(s)) + stage.side(float(s)) * lateral
			var g = stage.grip(p)
			bounded = bounded and g >= 0.15 and g <= 0.75
			clean = clean and stage.DeepSnow.depth(stage, p) == 0.0 and is_equal_approx(stage.vehicle_ground(p), stage.ground(p))
	check(bounded, "every carriageway point has a valid winter grip")
	check(clean, "deep snow never lies on the ploughed carriageway, even in the lacets")
	# ---------------------------------------------------------------- scenery
	root.add_child(stage)
	stage.build()
	var scenery = stage.get_node("AlpineScenery")
	for name in ["ArmcoRails", "ArmcoPosts", "StoneParapets", "SnowPoles", "CutRocks", "Icicles", "FrozenWaterfall"]:
		check(scenery.has_node(name), "scenery has " + name)
	check(stage.has_node("BlackIce") and stage.has_node("DistantAlps"), "glazed ice and the distant Alps are built")
	var houses = 0
	for child in scenery.get_children():
		if String(child.name).begins_with("Col"): houses += 1
	check(houses == 4 and alpine.chimneys.size() == 3, "col hamlet: chapel, hotel and two chalets with smoking chimneys")
	var barriers_ok = true
	var barrier_count = 0
	for rock in stage.rocks:
		if not rock.get("barrier", false): continue
		barrier_count += 1
		barriers_ok = barriers_ok and stage.road_distance(rock.pos) > stage.WIDTH * 0.5 + Banks.WIDTH
		for center in stage.clearings + stage.snow_camps:
			barriers_ok = barriers_ok and Vector2(rock.pos.x - center.x, rock.pos.z - center.z).length() > 8.0
	check(barrier_count > 100 and barriers_ok, "barriers stand beyond the banks and leave every camp and clearing open")
	var blocked = false
	for rock in stage.rocks:
		if rock.get("barrier", false) and stage.road_s(rock.pos) > 50.0 and stage.road_s(rock.pos) < 100.0:
			var s = stage.road_s(rock.pos)
			var from = stage.at(s)
			from.y = stage.vehicle_ground(from)
			var to = rock.pos + (rock.pos - from).normalized() * 3.0
			to.y = from.y
			blocked = not stage.rock_hit(from, to, 0.85).is_empty()
			break
	check(blocked, "armco above the drop stops a sliding car")
	var trees_ok = true
	for tree in stage.trees:
		trees_ok = trees_ok and stage.road_distance(tree) >= 9.0 and not alpine.reserved(tree, 1.0)
	check(trees_ok and stage.trees.size() > 400, "spruce forest keeps off the road and the hamlet (%d trees)" % stage.trees.size())
	var hotel: Dictionary = alpine.hamlet[1]
	var approach = stage.at(float(hotel.s))
	approach.y = stage.ground(approach)
	check(not stage.rock_hit(approach, hotel.pos, 0.3).is_empty(), "hotel walls are solid for walkers")
	# ---------------------------------------------------------------- life
	var life = stage.alpine_life
	check(life.flags.size() >= 5 and life.flares.size() >= 2 and life.birds.size() >= 15 and life.snowfall != null, "flags, flares, choughs and falling snow")
	var strip: Node3D = life.flags[0].strips[3]
	life.update(0.2, life.flags[0].node.position)
	var before = strip.rotation.y
	life.update(0.3, life.flags[0].node.position)
	check(not is_equal_approx(before, strip.rotation.y), "flags wave in the wind")
	check(life.snowfall.position.distance_to(life.flags[0].node.position + Vector3.UP * 12.0) < 0.01, "snowfall follows the player")
	# ---------------------------------------------------------------- determinism
	var guest = Stage.new(1)
	check(guest.points == stage.points and guest.alpine.ice_patches == alpine.ice_patches and guest.snow_glades == stage.snow_glades, "every client builds the same col")
	guest.free()
	stage.queue_free()
	await process_frame
	print("ALPINE WINTER RESULT: ", failures, " failures")
	finish()
