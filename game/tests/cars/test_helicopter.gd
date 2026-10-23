extends "res://tests/harness.gd"
const Predictor = preload("res://scripts/net/drive_prediction.gd")
const Props = preload("res://scripts/core/props.gd")
const Protocol = preload("res://scripts/net/net_protocol.gd")

class Solids extends RefCounted:
	var obstacles: Array = []
	func candidates(_a, _b, _r) -> Array:
		return range(obstacles.size())

class FlatStage extends RefCounted:
	var parks = {"z_limits": Vector2(-500, 500)}
	var solids = Solids.new()
	var trees: Array = []
	var forest_data: Array = []
	var tree_cells: Dictionary = {}
	var indexed_tree_count = 0
	var fallen: Dictionary = {}
	func ground(_p) -> float: return 0.0
	func rocks_in_bounds(_a, _b) -> Array: return []
	func _tree_cell(_p) -> Vector2i: return Vector2i.ZERO

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var stage = FlatStage.new()
	var client = Predictor.new()
	var host = Predictor.new()
	client.reset(Vector3(0, 0.06, 0), 0)
	host.reset(client.node.position, 0)
	client.coalesce = true
	for i in range(30): client.predict(12, 0, 0, false, stage, 11, false, 1)
	check(client.node.position.y > 12 and not client.motion.grounded, "Space lifts the helicopter off the ground")
	host.accept(client.pending, stage, 11, 2000)
	check(client.node.position.is_equal_approx(host.node.position), "host reproduces altitude and velocity from lift inputs")
	client.reconcile(host.snapshot(), stage, 11)
	for i in range(20): client.predict(12, 0, 0, false, stage, 11)
	var hover = client.node.position.y
	for i in range(20): client.predict(12, 0, 0, false, stage, 11)
	check(absf(client.node.position.y - hover) < 0.01, "released lift input maintains hover")
	client.pending.clear()
	for i in range(30): client.predict(12, 1, 0.3, false, stage, 11)
	check(Vector2(client.node.position.x, client.node.position.z).length() > 10 and absf(client.yaw) > 0.1, "WASD flies forward and turns while hovering")
	client.pending.clear()
	for i in range(80): client.predict(12, 0, 0, false, stage, 11, false, -1)
	check(client.motion.grounded and is_equal_approx(client.node.position.y, 0.06), "Shift lands safely on the skid footprint")
	# A low roof blocks the vertical sweep before either duct can pass through.
	var roof = StaticBody3D.new()
	root.add_child(roof)
	stage.solids.obstacles = [{"body": roof, "collision_pose": Transform3D(Basis.IDENTITY, Vector3(0, 4, 0)), "half": Vector3(8, 0.1, 8), "kind": "wall", "id": 0}]
	client.reset(Vector3(0, 0.06, 0), 0)
	for i in range(30): client.step({"ticks": 12, "throttle": 0, "steer": 0, "lift": 1}, stage, 11)
	check(client.node.position.y < 1.3, "vertical sweep stops cabin and ducts below a roof")
	stage.solids.obstacles.clear()
	stage.trees = [Vector3.ZERO]
	stage.forest_data = [{"height": 8.0}]
	client.reset(Vector3(0, 12, 0), 0)
	client.step({"ticks": 12, "throttle": 1, "steer": 0, "lift": 0}, stage, 11)
	check(client.node.position.z < 0, "flight above a tree clears its finite height")
	client.reset(Vector3(20, 15, 20), 0)
	client.predict(1, 0, 0, false, stage, 11, false, 1)
	client.predict(1, 0, 0, false, stage, 11, false, -1)
	check(client.pending.size() == 2, "opposite lift inputs never coalesce into one command")
	client.condition = 0
	client.step({"ticks": 120, "throttle": 1, "steer": 1, "lift": 1}, stage, 11)
	check(client.node.position.y < 15 and is_zero_approx(client.yaw), "damaged aircraft descends with horizontal controls disabled")
	var clean = Protocol.clean_state({"pos": [0,0,0], "car": [0,0,0], "heading": 0, "yaw": 0, "pitch": 0, "in_car": true, "drive_inputs": [{"seq":1,"ticks":12,"throttle":0,"steer":0,"brake":false,"lift":-1}, {"seq":2,"ticks":12,"throttle":0,"steer":0,"brake":false,"lift":2}]})
	check(clean.drive_inputs.size() == 1 and clean.drive_inputs[0].lift == -1, "direct transport preserves bounded lift and rejects forged altitude input")
	roof.queue_free()
	# Real game integration: selection, physical keyboard actions, cargo and touch.
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.select_stage(3)
	game.select_player_car(11)
	check(game.selected_car == 11, "helicopter is offered in Charyn canyon")
	game.start_game()
	game.car.position = game.stage.at(15) + Vector3(0, 35, 0)
	game.vehicle_motion.initialized = true
	Input.action_press("jump")
	var initial_y: float = game.car.position.y
	game.player.drive(0.1)
	Input.action_release("jump")
	check(game.car.position.y > initial_y, "real local drive uses Space lift through the shared flight solver")
	game.player.toggle_car()
	check(game.in_car, "pilot cannot exit in the air")
	game.enable_mobile()
	game.apply_mobile_safe_rect(Rect2(0, 0, 960, 540))
	var controls = game.mobile_controls
	controls._process(0)
	controls._layout()
	var up: Dictionary = {}
	var down: Dictionary = {}
	for b in controls.buttons:
		if b.action == "jump": up = b
		if b.action == "sprint": down = b
	check(not up.is_empty() and not down.is_empty() and up.hold and down.hold, "mobile cockpit exposes two held altitude buttons")
	if not up.is_empty():
		controls.touch_begin(51, up.rect.get_center())
		check(Input.is_action_pressed("jump"), "touch ascend presses the same action as Space")
		controls.touch_end(51)
	if not down.is_empty():
		controls.touch_begin(52, down.rect.get_center())
		check(Input.is_action_pressed("sprint"), "touch descend presses the same action as Shift")
		controls.touch_end(52)
	controls.reset_input()
	game.in_car = false
	game.speed = 0
	Props.animate_wheels(game.car)
	var left_rotor = game.car.get_node("RotorLeft")
	var right_rotor = game.car.get_node("RotorRight")
	check(not is_zero_approx(left_rotor.rotation.y) and is_equal_approx(left_rotor.rotation.y, -right_rotor.rotation.y), "both preserved rotor meshes animate in opposite directions")
	var pose = game.cargo.poses()[game.chair_owner()]
	var access: Vector3 = game.cargo.point(pose)
	check(game.car.to_local(access).x > 1, "cargo access is on the right side")
	game.walker = access
	game.cargo.update(1)
	check(game.car.get_node("TrunkHinge").position.z > 1 and game.cargo.take("chairs"), "side cargo opens and releases equipment through the real inventory")
	# The walker steps under the duct right up to the side door.
	game.car.position.y = game.stage.vehicle_ground(game.car.position)
	var door_blocked = false
	for i in range(24):
		var from: Vector3 = game.car.to_global(Vector3(4.0 - i * 0.1, 0, 0))
		var to: Vector3 = game.car.to_global(Vector3(3.9 - i * 0.1, 0, 0))
		from.y = game.stage.walking_ground(from)
		to.y = game.stage.walking_ground(to)
		door_blocked = door_blocked or game.player.contact_blocked(from, to, false)
	check(not door_blocked, "walker reaches the side door under the duct")
	check(game.player.contact_blocked(game.car.to_global(Vector3(1.5, 0.05, 0)), game.car.to_global(Vector3(1.0, 0.05, 0)), false), "cabin side still stops the walker")
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	print("HELICOPTER RESULT: %d failures" % failures)
	finish()
