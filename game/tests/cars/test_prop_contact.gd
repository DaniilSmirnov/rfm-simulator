extends "res://tests/harness.gd"
const Contact = preload("res://scripts/cars/prop_contact.gd")
const Registry = preload("res://scripts/core/prop_registry.gd")
const Props = preload("res://scripts/core/props.gd")
const Motion = preload("res://scripts/cars/vehicle_motion.gd")
const Stage = preload("res://scripts/stages/stage.gd")
const Predictor = preload("res://scripts/net/drive_prediction.gd")
var driving_finished = false

func _initialize() -> void:
	call_deferred("run")

func prop(stage, position: Vector3, mass: float, key: String, anchored: bool = false, size: Vector3 = Vector3(0.6, 1, 0.6)) -> Node3D:
	var node = Node3D.new()
	stage.add_child(node)
	node.position = position
	Props.box(node, Vector3.UP * 0.5, size, Color.RED)
	Registry.register(stage.solids, node, mass, anchored, key)
	return node

func run() -> void:
	for mass in [3.0, 5.0, 25.0, 120.0, 900.0]:
		var stage = Stage.new()
		root.add_child(stage)
		prop(stage, Vector3(3, 0, 0), mass, "target")
		var motion = Motion.new()
		motion.velocity = Vector3.RIGHT * 20
		var result = Contact.resolve(stage, motion, Vector3.ZERO, Vector3.RIGHT * 6, 1.0 / 120)
		check(result.hits.size() == 1, "impact transfers to the original prop, mass %.0f" % mass)
		if mass <= Contact.SMALL_MASS:
			check(motion.velocity == Vector3.RIGHT * 20 and not result.blocked and result.position.x == 6, "chair/cone does not stop or slow the car")
		elif mass < Contact.BLOCKING_MASS:
			check(motion.velocity.x >= 17 and motion.velocity.x < 20 and not result.blocked, "medium prop takes only a small share of speed")
			var retained = motion.velocity
			for tick in range(120): Contact.resolve(stage, motion, Vector3.ZERO, Vector3.RIGHT * 6, 1.0 / 120)
			check(motion.velocity == retained, "a sustained contact does not multiply speed loss every tick")
			for tick in range(31): Contact.resolve(stage, motion, Vector3.ZERO, Vector3.LEFT, 1.0 / 120)
			Contact.resolve(stage, motion, Vector3.ZERO, Vector3.RIGHT * 6, 1.0 / 120)
			check(motion.velocity.x < retained.x, "a separate later impact can slow the car again")
		else:
			check(motion.velocity == Vector3.ZERO and result.blocked and result.position.x < 3, "heavy object stops the car before penetration")
		stage.free()
	var table_stage = Stage.new()
	root.add_child(table_stage)
	prop(table_stage, Vector3(3, 0, 0), 12, "table", false, Vector3(2.2, 1, 1.2))
	var table_motion = Motion.new()
	table_motion.velocity = Vector3.RIGHT * 20
	Contact.resolve(table_stage, table_motion, Vector3.ZERO, Vector3.RIGHT * 6, 0.01)
	check(table_motion.velocity.x > 19 and table_motion.velocity.x < 20, "a broad lightweight table slows the car slightly")
	table_stage.free()
	var stage = Stage.new()
	root.add_child(stage)
	prop(stage, Vector3(2, 0, 0), 3, "cone")
	prop(stage, Vector3(4, 0, 0), 5, "chair")
	var wall = Node3D.new()
	stage.add_child(wall)
	wall.position = Vector3(6, 0, 0)
	stage.solids.solid(wall, Vector3.UP, Vector3(0.3, 2, 4), "wall")
	var motion = Motion.new()
	motion.velocity = Vector3.RIGHT * 20
	var result = Contact.resolve(stage, motion, Vector3.ZERO, Vector3.RIGHT * 10, 1.0 / 120)
	check(result.hits.size() == 3 and result.blocked and motion.velocity == Vector3.ZERO and result.position.x < 6, "small props cannot hide a wall behind them in the same sweep")
	stage.free()
	stage = Stage.new()
	root.add_child(stage)
	var sign_node = prop(stage, Vector3(2, 0, 0), 5, "sign", true)
	motion = Motion.new()
	motion.velocity = Vector3.RIGHT * 3
	check(Contact.resolve(stage, motion, Vector3.ZERO, Vector3.RIGHT * 4, 0.01).blocked, "an attached pole resists a slow contact")
	sign_node.set_meta("prop_anchored", false)
	motion.velocity = Vector3.RIGHT * 3
	check(not Contact.resolve(stage, motion, Vector3.ZERO, Vector3.RIGHT * 4, 0.01).blocked, "an already knocked pole does not anchor itself again")
	stage.free()
	prediction()
	await driving()
	check(driving_finished, "all vehicle integration checks reach completion")
	finish()

func prediction() -> void:
	var stage = Stage.new()
	root.add_child(stage)
	var start: Vector3 = stage.at(200)
	prop(stage, start + Vector3(0, 0, -1.6), 120, "grill")
	var client = Predictor.new()
	var host = Predictor.new()
	client.reset(start, 0)
	host.reset(start, 0)
	client.motion.velocity = Vector3.FORWARD * 20
	host.motion.velocity = client.motion.velocity
	for i in range(4): client.predict(3, 0, 0, false, stage, 0)
	var predicted: Vector3 = client.node.position
	var retained: Vector3 = client.motion.velocity
	host.accept(client.pending.slice(0, 2), stage, 0)
	check(host.wire_snapshot().has("prop_contacts"), "wire state retains the current prop contact episode")
	var events: int = client.events.size()
	client.reconcile(host.snapshot(), stage, 0)
	check(client.node.position.distance_to(predicted) < 0.00001 and client.motion.velocity.distance_to(retained) < 0.00001, "partial acknowledgement and replay do not apply prop drag twice")
	check(client.events.size() == events, "reconciliation does not emit duplicate prop impulses")
	host.accept(client.pending, stage, 0)
	client.reconcile(host.snapshot(), stage, 0)
	check(client.pending.is_empty() and client.node.position.distance_to(host.node.position) < 0.00001, "host and guest converge after a prop impact")
	stage.rocks.append({"pos": start + Vector3(0, 0, -3), "radius": 2.0, "height": 4.0})
	client.reset(start, 0)
	client.motion.velocity = Vector3.FORWARD * 20
	client.predict(1, 0, 0, false, stage, 0)
	check(client.motion.velocity == Vector3.ZERO, "large boulder stops the predicted car")
	stage.free()

func reset_car(game, start: Vector3) -> void:
	game.car.position = start
	game.heading = -PI / 2
	game.vehicle_motion = Motion.new()
	game.vehicle_motion.velocity = Vector3.RIGHT * 20
	game.speed = 20
	game.condition = 100
	game.rock_impact_timer = 0

func driving() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.start_game()
	game.stage.trees.clear()
	game.stage.rocks.clear()
	var start: Vector3 = game.stage.at(300)
	var cone = prop(game.stage, start + Vector3.RIGHT * 2, 3, "test:cone")
	reset_car(game, start)
	game._drive(0.25)
	check(game.car.position.x > start.x + 3 and game.speed > 15 and game.condition > 99, "real player car drives through a cone without obstacle damage or a full stop")
	check(game.movable_props.records["test:cone"].changed, "player collision knocks the cone while keeping car momentum")
	cone.free()
	game.stage.solids.index()
	game.stage.rocks.append({"pos": start + Vector3.RIGHT * 3, "radius": 2.0, "height": 4.0})
	reset_car(game, start)
	game._drive(0.25)
	check(game.speed == 0 and game.vehicle_motion.velocity == Vector3.ZERO, "large boulder brings the real car to a full stop")
	game.stage.rocks.clear()
	game.stage.trees.append(start + Vector3.RIGHT * 2)
	reset_car(game, start)
	game._drive(0.25)
	check(game.speed == 0 and game.vehicle_motion.velocity == Vector3.ZERO and game.car.position.x < start.x + 2, "tree stops real player car with no reverse rebound")
	game.stage.trees.clear()
	game.car.position = start + Vector3(0, 0, 30)
	game.course.phase = "racing"
	game.spawn_racer("pass")
	var racer: Dictionary = game.racers[-1]
	racer.node.position = start
	racer.node.rotation.y = -PI / 2
	racer.state = "offroad"
	racer.self_rejoin = false
	racer.motion.velocity = Vector3.RIGHT * 20
	var chair = prop(game.stage, start + Vector3.RIGHT * 2, 5, "test:chair")
	game._update_racers(0.25)
	check(racer.node.position.x > start.x + 3 and racer.motion.velocity.x > 15, "off-road rally car also pushes through a light chair")
	chair.free()
	game.stage.solids.index()
	var heavy = prop(game.stage, start + Vector3.RIGHT * 2, 900, "test:heavy")
	reset_racer(racer, start)
	game._update_racers(0.25)
	check(racer.motion.velocity == Vector3.ZERO and racer.drive_speed == 0 and racer.state == "stopped", "heavy prop stops a rally car instead of leaving hidden forward speed")
	heavy.free()
	game.stage.solids.index()
	game.stage.fallen.clear()
	game.stage.trees.append(start + Vector3.RIGHT * 2)
	reset_racer(racer, start)
	game._update_racers(0.25)
	check(racer.motion.velocity == Vector3.ZERO and racer.drive_speed == 0 and racer.node.position.x < start.x + 2, "tree impact also brings a rally car to a full stop")
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	driving_finished = true

func reset_racer(racer: Dictionary, start: Vector3) -> void:
	racer.node.position = start
	racer.node.rotation = Vector3(0, -PI / 2, 0)
	racer.state = "offroad"
	racer.self_rejoin = false
	racer.motion = Motion.new()
	racer.motion.velocity = Vector3.RIGHT * 20
