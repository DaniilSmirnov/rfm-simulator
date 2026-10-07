extends SceneTree
const Handling = preload("res://scripts/rally_handling.gd")
const Motion = preload("res://scripts/vehicle_motion.gd")
class Surface:
	extends RefCounted
	var traction = 0.78
	var slope = 0.0
	func grip(_point: Vector3) -> float:
		return traction
	func ground(point: Vector3) -> float:
		return point.x * slope
var failures = 0
func check(ok: bool, title: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + title)
	if not ok:
		failures += 1
func crew() -> Dictionary:
	return {"id": 1, "kind": "crash", "node": Node3D.new(), "motion": Motion.new(), "slide": 0.0, "slide_speed": 0.0, "drive_speed": 24.0}
func corner(grip: float, fps: int, bend: float = 0.02) -> Dictionary:
	var r = crew()
	for i in range(fps * 2):
		Handling.slide(r, bend, 24.0, grip, 1.0 / fps)
	r.node.free()
	return r
func coast(grip: float, speed: float, fps: int = 60) -> float:
	var r = crew()
	var surface = Surface.new()
	surface.traction = grip
	r.motion.velocity = Vector3(0, 0, -speed)
	for i in range(fps * 20):
		for step in range(maxi(1, int(ceil(120.0 / fps)))):
			Handling.free_step(r, surface, 1.0 / (fps * maxi(1, int(ceil(120.0 / fps)))))
		if r.motion.velocity.length() < 0.01:
			break
	var distance = -r.node.position.z
	r.node.free()
	return distance
func _initialize() -> void:
	var gravel = corner(0.78, 60)
	var ice = corner(0.22, 60)
	check(absf(ice.slide) > absf(gravel.slide) + 1.0, "slippery turns lose lateral grip and produce a real outward slide")
	check(ice.drift_yaw > 0.05, "oversteer rotates the body relative to its path")
	var reverse = corner(0.22, 60, -0.02)
	check(absf(reverse.slide + ice.slide) < 0.001, "opposite turn reverses outward slip")
	for fps in [24, 144]:
		check(absf(corner(0.22, fps).slide - ice.slide) < 0.08, "slide integration stays stable at %d FPS" % fps)
	var r = crew()
	r.slide = 1.0
	r.slide_speed = 2.0
	for i in range(360):
		Handling.slide(r, 0.0, 18.0, 0.78, Handling.STEP)
	check(absf(r.slide) < 0.05 and absf(r.slide_speed) < 0.1, "tyres progressively catch the slide on a straight")
	r.slide_speed = 3.0
	Handling.departure(r, Vector3.FORWARD, Vector3.RIGHT, 0.01)
	check(r.motion.velocity == Vector3(3, 0, -24), "departure preserves forward and sideways momentum")
	var surface = Surface.new()
	var previous: Vector3 = r.node.position
	Handling.free_step(r, surface, Handling.STEP)
	check(r.node.position.z < previous.z - 0.19 and r.node.position.x > previous.x, "first departure step continues forward rather than jumping sideways")
	r.motion.initialized = true
	r.node.position = Vector3(0, 4, 0)
	r.motion.grounded = false
	r.motion.velocity = Vector3(2, 0, -12)
	var airborne: Vector3 = r.motion.velocity
	Handling.free_step(r, surface, Handling.STEP)
	check(r.motion.velocity == airborne and r.motion.vertical_speed < 0, "airborne tyres preserve planar momentum while gravity lowers the car")
	r.node.position = Vector3.ZERO
	r.motion.grounded = true
	r.motion.velocity = Vector3.ZERO
	surface.slope = 0.2
	Handling.free_step(r, surface, Handling.STEP)
	check(r.motion.velocity.x < 0, "terrain gradient accelerates a departing car downhill")
	r.node.free()
	check(coast(0.22, 24) > coast(0.78, 24) * 1.6, "ice has a longer stopping distance than gravel")
	check(coast(0.78, 30) > coast(0.78, 15) * 3.5, "exit distance grows with kinetic energy rather than a fixed endpoint")
	check(absf(coast(0.78, 24, 24) - coast(0.78, 24, 144)) < 0.15, "free departures agree at 24 and 144 FPS")
	print("RALLY HANDLING RESULT: %d failures" % failures)
	quit(1 if failures else 0)
