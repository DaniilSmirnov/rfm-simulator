extends SceneTree
# Gravel tracks of the Provençal stage: terraces and the vineyard valley.
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
	var village = stage.village
	check(village.surface(600.0) == "gravel" and village.surface(780.0) == "gravel", "terraces and valley are gravel tracks")
	check(village.surface(120.0) == "asphalt" and village.surface(400.0) == "cobble", "plateau is asphalt and the village is cobbled")
	var rut = stage.at(720.0) + stage.side(720.0) * 0.85
	check(stage.ground(rut) < stage.ground(stage.at(720.0)) - 0.03, "wheel tracks sit below the gravel crown")
	check(stage.grip(stage.at(720.0)) < stage.grip(stage.at(120.0)), "gravel has less grip than asphalt")
	check(stage.grip(stage.at(400.0)) < stage.grip(stage.at(120.0)), "cobbles have less grip than asphalt")
	check(stage.loose_surface(stage.at(720.0)) and not stage.loose_surface(stage.at(120.0)) and not stage.loose_surface(stage.at(400.0)), "only gravel throws stones from the tyres")
	var max_slope = 0.0
	for station in range(530, 836):
		var a = stage.at(station)
		var b = stage.at(station + 0.5)
		max_slope = maxf(max_slope, absf(stage.ground(a) - stage.ground(b)) / stage.flat(a - b).length())
	check(max_slope < 0.16, "the descent from the village avoids abrupt grades (max %.3f)" % max_slope)
	var car = Node3D.new()
	root.add_child(car)
	for start in [560.0, 640.0, 720.0]:
		var motion = Motion.new()
		var finite = true
		var progress = start
		car.position = stage.at(progress)
		for frame in range(600):
			progress += stage.rally_speed(progress) / 120.0
			var point = stage.at(progress)
			car.position.x = point.x
			car.position.z = point.z
			var direction = stage.direction(progress)
			motion.suspension(car, stage, 1.0 / 120.0, atan2(-direction.x, -direction.z))
			finite = finite and is_finite(car.position.y) and absf(motion.vertical_speed) < 30.0
			if progress > start + 60.0:
				break
		check(finite, "suspension stays stable on gravel from station %d" % int(start))
	car.free()
	stage.free()
	print("GRAVEL RELIEF RESULT: %d failures" % failures)
	quit(1 if failures else 0)
