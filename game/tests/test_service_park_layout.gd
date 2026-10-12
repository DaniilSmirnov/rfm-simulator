extends "res://tests/harness.gd"
# A service park at both ends of every stage: dry and level, clear of trees,
# rocks and mushrooms, with every car's way in and out of its bay unobstructed.
const Stage = preload("res://scripts/stage.gd")
const Parks = preload("res://scripts/service_parks.gd")

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
		var limits: Vector2 = parks.z_limits
		check(parks.world(index, 0, 45).z > limits.x and parks.world(index, 0, 45).z < limits.y, "%s park %d: people and cars may go there" % [name, index])
	stage.queue_free()
	await process_frame

func run() -> void:
	for variant in range(Stage.STAGES.size()):
		await layout(variant)
	print("SERVICE PARK LAYOUT RESULT: %d checks, %d failures" % [checks, failures])
	finish()
