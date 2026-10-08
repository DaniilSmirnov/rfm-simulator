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
	check(airborne, "vehicle suspension launches over ramp at road speed")
	check(finite, "ramp crossing remains numerically stable")
	car.free()
	stage.free()
	print("GRAVEL RELIEF RESULT: %d failures" % failures)
	quit(1 if failures else 0)
