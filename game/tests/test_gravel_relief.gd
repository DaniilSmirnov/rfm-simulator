extends SceneTree
const Stage = preload("res://scripts/stage.gd")
const Motion = preload("res://scripts/vehicle_motion.gd")
var failures = 0
func check(ok: bool, message: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + message)
	if not ok: failures += 1
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var stage = Stage.new(2)
	root.add_child(stage)
	var centre = stage.at(423.0)
	check(stage.gravel_relief(centre, 423.0) > 0.70, "first ramp has a physical crest")
	var hill = stage.village_gravel_landform(centre)
	check(stage.village_gravel_landform(centre + stage.side(423.0) * 8.0) > hill * 0.65, "crest extends into the forest shoulders instead of forming a narrow embankment")
	check(stage.village_gravel_landform(centre - stage.direction(423.0) * 18.0) > 0.25, "gravel hill has a long approach")
	check(stage.village_gravel_landform(centre + stage.direction(423.0) * 18.0) > 0.25, "gravel hill has a long descent")
	var max_slope = 0.0
	for station in range(397, 475):
		var a = stage.at(station)
		var b = stage.at(station + 0.5)
		max_slope = maxf(max_slope, absf(stage.ground(a) - stage.ground(b)) / stage.flat(a - b).length())
	check(max_slope < 0.18, "gravel approaches avoid abrupt grades (max %.3f)" % max_slope)
	var rut = stage.at(435.0) + stage.side(435.0) * 0.8
	check(stage.gravel_relief(rut, 435.0) < stage.gravel_relief(stage.at(435.0), 435.0), "wheel tracks sit below road centre")
	check(stage.gravel_relief(stage.at(382.0), 382.0) == 0.0 and stage.gravel_relief(stage.at(488.0), 488.0) == 0.0, "junctions retain smooth contact")
	check(is_equal_approx(stage.ground(stage.village_main_at(435.0)), 2.0875), "village paving is unaffected")
	var wet = stage.at(412.0) - stage.side(412.0) * 0.55
	check(stage.grip(wet) < stage.grip(stage.at(435.0)), "water-filled rut reduces tyre grip")
	var car = Node3D.new()
	root.add_child(car)
	var motion = Motion.new()
	var airborne = false
	var finite = true
	var progress = 416.0
	car.position = stage.at(progress)
	for frame in range(900):
		var metres = maxf(stage.at(progress + 0.1).distance_to(stage.at(progress)), 0.01)
		progress += (19.0 / 120.0) * 0.1 / metres
		var point = stage.at(progress)
		car.position.x = point.x
		car.position.z = point.z
		var direction = stage.direction(progress)
		motion.suspension(car, stage, 1.0 / 120.0, atan2(-direction.x, -direction.z))
		airborne = airborne or not motion.grounded
		finite = finite and is_finite(car.position.y) and absf(motion.vertical_speed) < 30.0
		if progress > 432.0:
			break
	check(finite, "broad gravel crests keep the suspension stable at road speed")
	check(finite, "ramp crossing remains numerically stable")
	for crest in [178.0, 686.0]:
		motion = Motion.new()
		airborne = false
		finite = true
		progress = crest - 16.0
		car.position = stage.at(progress)
		for frame in range(900):
			progress += 24.0 / 120.0
			var point = stage.at(progress)
			car.position.x = point.x
			car.position.z = point.z
			var direction = stage.direction(progress)
			motion.suspension(car, stage, 1.0 / 120.0, atan2(-direction.x, -direction.z))
			airborne = airborne or not motion.grounded
			finite = finite and is_finite(car.position.y) and absf(motion.vertical_speed) < 30.0
			if progress > crest + 16.0:
				break
		check(finite and (airborne or crest == 686.0), "country crests keep suspension stable; sharper entry still launches")
	for station in [407.0, 469.0]:
		var offset = 0.5 if station < 440.0 else -0.5
		var puddle = stage.at(station) + stage.side(station) * offset
		check(stage.grip(puddle) < 0.45, "new puddle reduces grip")
	var cross_slope = 0.0
	for station in [410.0, 435.0, 460.0]:
		var right = stage.at(station) + stage.side(station) * 1.4
		var left = stage.at(station) - stage.side(station) * 1.4
		cross_slope = maxf(cross_slope, absf(stage.ground(right) - stage.ground(left)))
	check(cross_slope > 0.1, "gravel retains physical banking through the forest")
	stage._build_road()
	for station in [407.0, 412.0, 463.0, 469.0]:
		var mesh = stage.get_node("GravelPuddle_%d" % int(station)).mesh
		var arrays = mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var level = vertices[0].y
		var horizontal = true
		for vertex in vertices:
			horizontal = horizontal and absf(vertex.y - level) < 0.0001
		check(horizontal and arrays[Mesh.ARRAY_NORMAL][0].y > 0.99, "water has a horizontal upward-facing surface bounded by road relief")
	car.free()
	stage.free()
	print("GRAVEL RELIEF RESULT: %d failures" % failures)
	quit(1 if failures else 0)
