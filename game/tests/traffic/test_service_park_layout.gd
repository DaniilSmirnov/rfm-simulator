extends "res://tests/harness.gd"
# A service park at both ends of every stage: dry and level, clear of trees,
# rocks and mushrooms, with every car's way in and out of its bay unobstructed.
const Stage = preload("res://scripts/stages/stage.gd")
const Parks = preload("res://scripts/traffic/service_parks.gd")
const Hitbox = preload("res://scripts/cars/car_hitbox.gd")

func _initialize() -> void:
	call_deferred("run")

func layout(variant: int) -> void:
	var stage = Stage.new(variant)
	root.add_child(stage)
	stage.build()
	var parks = stage.parks
	var name = Stage.STAGES[variant]
	check(parks.ends.size() == 2, "%s: a service park at each end of the road" % name)
	for index in range(2):
		var end: Dictionary = parks.ends[index]
		var bumps = 0.0
		var wet = 0
		for x in range(-18, 19, 3):
			for z in range(13, 46, 3):
				var p = parks.world(index, x, z)
				bumps = maxf(bumps, absf(stage.ground(p) - end.height))
				bumps = maxf(bumps, absf(stage.terrain_surface_height(p) - end.height))
				if stage.water != null and stage.water.depth(p) > -0.05:
					wet += 1
		check(bumps < 0.05 and wet == 0, "%s park %d: a dry, level paddock (%.2f m)" % [name, index, bumps])
		var trees = stage.trees.filter(func(t): return parks.contains(t, 1.5)).size()
		var rocks = stage.rocks.filter(func(r): return parks.contains(r.pos, 0.5)).size()
		var items = stage.collectibles.filter(func(c): return parks.contains(c.pos, 0.3)).size()
		check(trees == 0 and rocks == 0 and items == 0, "%s park %d: no trees, rocks or mushrooms in it (%d/%d/%d)" % [name, index, trees, rocks, items])
		var bad_path = 0
		for key in Parks.KEYS:
			for point in parks.leave_path(index, key) + parks.arrive_path(index, key, end.origin, end.forward):
				if not parks.contains(point.p, 0.6) or not stage.solids.hit(point.p, point.p, 1.0, false).is_empty():
					bad_path += 1
		check(bad_path == 0, "%s park %d: every car's way in and out stays clear (%d bad points)" % [name, index, bad_path])
		# The players' slots (where everyone's car starts the day, at the far
		# end of the aisle) are on the level ground, clear of the scenery and
		# of every car's way out of its bay. Crews back into their bays from
		# the aisle's end only on the way in, long after the players drove off.
		var crowded = 0
		for slot in range(Parks.VISITORS.size()):
			var spot: Vector3 = parks.visitor_pose(index, slot).origin
			var nose: Vector3 = -end.forward
			if not parks.contains(spot, Parks.APRON - 1.0) or not stage.solids.hit(spot - nose * 2.2, spot + nose * 2.2, 1.0, false).is_empty():
				crowded += 1
			for key in Parks.KEYS:
				for point in parks.leave_path(index, key):
					if point.p.distance_to(spot) < 3.0:
						crowded += 1
			for other in range(slot):
				if parks.visitor_pose(index, other).origin.distance_to(spot) < Hitbox.player(0).size.x + 0.2:
					crowded += 1
		check(crowded == 0, "%s park %d: the players' row is clear (%d clashes)" % [name, index, crowded])
		# Held throttle from every slot carries the car straight down the aisle
		# and the lane to the end of the road and onto it: no tree, rock or
		# fixed prop on the way. The day starts in the park at the start, so
		# only there.
		var stuck = []
		var off_road = []
		for slot in range(Parks.VISITORS.size() if index == 0 else 0):
			var pose: Transform3D = parks.visitor_pose(index, slot)
			var car = Hitbox.shape(Hitbox.player(0), pose.basis.get_euler().y)
			var nose: Vector3 = -pose.basis.z
			var run: float = parks.local(end, pose.origin).y
			if slot < Parks.VISITORS.size() - 1 and stage.road_distance(pose.origin + nose * run) > 4.1 + Hitbox.player(0).size.x * 0.5:
				off_road.append(str(slot))
			for step in range(int(run / 0.5)):
				var a: Vector3 = pose.origin + nose * (step * 0.5)
				var b: Vector3 = a + nose * 0.5
				a.y = stage.ground(a)
				b.y = stage.ground(b)
				if Hitbox.tree(stage, a, b, car) >= 0 or not Hitbox.rocks(stage, a, b, car).is_empty() or _fixed(stage, a, b, car):
					stuck.append("%d at %.1f m" % [slot, step * 0.5])
					break
		check(stuck.is_empty(), "%s park %d: every player's car drives out of the park (%s)" % [name, index, ", ".join(stuck)])
		check(off_road.is_empty(), "%s park %d: every car from the aisle's end reaches the road (%s)" % [name, index, ", ".join(off_road)])
		var limits: Vector2 = parks.z_limits
		check(parks.world(index, 0, 45).z > limits.x and parks.world(index, 0, 45).z < limits.y, "%s park %d: people and cars may go there" % [name, index])
	stage.queue_free()
	await process_frame

# A solid a car cannot push aside: scenery, or a prop too heavy or anchored.
func _fixed(stage, a: Vector3, b: Vector3, car: Dictionary) -> bool:
	var ignored: Array = []
	while true:
		var hit: Dictionary = Hitbox.solids(stage.solids, a, b, car, ignored)
		if hit.is_empty():
			return false
		var prop = stage.solids.movables.filter(func(m): return m.key == hit.get("prop", ""))
		if prop.is_empty() or float(prop[0].mass) >= 500.0 or bool(prop[0].anchored):
			return true
		ignored.append(prop[0].node)
	return false

func run() -> void:
	for variant in range(Stage.STAGES.size()):
		await layout(variant)
	print("SERVICE PARK LAYOUT RESULT: %d checks, %d failures" % [checks, failures])
	finish()
