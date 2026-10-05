extends SceneTree
const Motion = preload("res://scripts/vehicle_motion.gd")
const Stage = preload("res://scripts/stage.gd")
var failures = 0
func check(ok: bool, title: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + title)
	if not ok:
		failures += 1

func traverse(fps: float) -> Dictionary:
	var stage = Stage.new()
	var node = Node3D.new()
	root.add_child(node)
	var motion = Motion.new()
	var airborne = 0
	var max_clearance = 0.0
	for frame in range(int(10 * fps)):
		var s = 20.0 + (frame + 1) / fps * 27.0
		var old_y = node.position.y
		node.position = stage.at(s)
		if motion.initialized:
			node.position.y = old_y
		motion.suspension(node, stage, 1 / fps, 0)
		if not motion.grounded:
			airborne += 1
		max_clearance = maxf(max_clearance, node.position.y - stage.ground(node.position))
		if not is_finite(node.position.y):
			check(false, "suspension stays finite")
	var result = {"height": node.position.y, "clearance": max_clearance, "airborne": airborne}
	node.free()
	stage.free()
	return result

func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var low = traverse(24)
	var high = traverse(60)
	check(low.airborne > 0 and high.airborne > 0, "fast cars leave the ground on road crests")
	check(low.clearance < 2 and high.clearance < 2, "suspension returns without uncontrolled launches")
	check(absf(low.height - high.height) < 0.25, "24 and 60 FPS have comparable suspension")
	check(Motion.swept_hit(Vector3(-3, 1, 0), Vector3(3, 1, 0), Vector3(0, 1, 0), 0.4), "fast stones cannot tunnel through spectators")
	check(not Motion.swept_hit(Vector3(-3, 3, 0), Vector3(3, 3, 0), Vector3(0, 1, 0), 0.4), "stones above heads miss")
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	scene.room.set_process(false)
	scene.start_game()
	scene.car.position = scene.stage.at(200)
	scene.heading = 0
	scene.speed = 18
	Input.action_press("right")
	Input.action_press("forward")
	scene._drive(0.4)
	Input.action_release("right")
	Input.action_release("forward")
	var forward = Vector3(-sin(scene.heading), 0, -cos(scene.heading))
	check(absf(scene.vehicle_motion.velocity.dot(forward.cross(Vector3.UP))) > 1.0, "tyres slide sideways in a fast turn")
	scene.in_car = false
	scene.walker = scene.stage.clearings[0]
	scene.racing = true
	scene.spawn_racer("pass")
	scene._update_stones(0.1)
	check(scene.stones.size() > 0 and scene.stones.size() <= 48, "moving crews throw bounded gravel particles")
	var stone = scene.stones[0]
	stone.node.position = scene.walker + Vector3(-1, 1, 0)
	stone.velocity = Vector3(20, 0, 0)
	scene.stone_clock = 10
	scene._update_stones(0.1)
	check(scene.impact_shake > 0, "stone crossing spectator triggers impact")
	var world = scene.room.world_state()
	check(world.has("stones") and world.has("impacts") and world.racers[0].has("tilt"), "room snapshot includes gravel, impacts and suspension tilt")
	await scene._shutdown_audio()
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
