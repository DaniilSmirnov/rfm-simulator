extends "res://tests/harness.gd"
# Repairing a broken car under its bonnet (car_hood.gd, car_repair.gd): every
# car but the helicopter has an opening bonnet over an engine bay; the bonnet
# opens when someone walks up to a broken car, F at the bay starts the
# spanner, and the car drives again when the work is done. A guest's repair
# reaches the host as a "repair_car" command.
const Props = preload("res://scripts/core/props.gd")
const CarHood = preload("res://scripts/cars/car_hood.gd")
const CarRepair = preload("res://scripts/cars/car_repair.gd")
const NetProtocol = preload("res://scripts/net/net_protocol.gd")
const Prediction = preload("res://scripts/net/drive_prediction.gd")

func _initialize() -> void:
	call_deferred("run")

func frames(game, seconds: float, step: float = 0.1) -> void:
	var t = 0.0
	while t < seconds:
		game.player.repair.update(step)
		game.player.repair.update_hoods(step)
		t += step

func aim(game, point: Vector3) -> void:
	game.camera.position = game.walker + Vector3(0, 1.6, 0)
	game.camera.look_at(point)

func run() -> void:
	for variant in range(Props.PLAYER_MODELS.size()):
		var model = Props.player_car(variant)
		root.add_child(model)
		var hinge = model.get_node_or_null("HoodHinge")
		if Props.CarRegistry.flies(variant):
			check(hinge == null and model.get_node_or_null("EngineBay") == null, "model %d (aircraft) has no bonnet" % variant)
			model.free()
			continue
		var bay: Node3D = model.get_node_or_null("EngineBay")
		check(hinge != null and hinge.get_child_count() > 0, "model %d has a bonnet cut from its bodywork" % variant)
		check(bay != null and CarHood.TARGETS.all(func(part): return bay.has_node(part)) and bay.has_node("Wrench"), "model %d has an engine bay with the parts and a spanner" % variant)
		check(not bay.visible, "model %d hides the bay under a shut bonnet" % variant)
		CarHood.animate(model, true, 0.2)
		check(hinge.rotation.x > 0.1 and hinge.rotation.x < CarHood.OPEN_ANGLE and bay.visible, "model %d opens its bonnet progressively" % variant)
		CarHood.animate(model, true, 2.0)
		check(CarHood.is_open(model), "model %d opens its bonnet fully" % variant)
		CarHood.animate(model, false, 2.0)
		check(hinge.rotation.x == 0.0 and not bay.visible, "model %d shuts its bonnet" % variant)
		model.free()

	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.start_game()
	game.stage.trees.clear()
	game.stage.rocks.clear()
	var origin: Vector3 = game.stage.clearings[0]
	game.car.position = origin
	game.heading = 0.0
	game.car.rotation = Vector3.ZERO
	game.in_car = false
	var repair = game.player.repair
	var nose = origin + Vector3(0, 0, -3.2)
	game.walker = nose

	# A working car keeps its bonnet shut and offers no repair.
	frames(game, 1.0)
	check(not CarHood.is_open(game.car), "a working car keeps the bonnet shut")
	var bay = CarHood.bay_point(game.car)
	aim(game, bay)
	check(game.interaction.current().get("action", "") != "repair_car", "a working car offers no repair")

	# Broken: walking up opens the bonnet, F at the bay starts the spanner.
	game.condition = 0.0
	game.walker = origin + Vector3(0, 0, -12)
	frames(game, 1.0)
	check(not CarHood.is_open(game.car), "the bonnet waits for somebody to walk up")
	game.walker = nose
	frames(game, 1.0)
	check(CarHood.is_open(game.car) and game.car.get_node("EngineBay").visible, "walking up to a broken car opens its bonnet")
	aim(game, bay)
	var target = game.interaction.current()
	check(target.get("action", "") == "repair_car" and target.get("label", "") == "Чинить двигатель", "the open bay of a broken car offers a repair")
	game.interaction.activate()
	check(repair.active() and repair.owner == "local", "F at the bay starts the repair")
	check(game.interaction.current().get("action", "") == "repair_stop", "while repairing F abandons the job")
	check(game.room.local_state().get("repair", false), "the repair goes into the room state")

	# The spanner strikes one part after another; the bay parts shudder.
	var wrench: Node3D = game.car.get_node("EngineBay/Wrench")
	var hit_parts = {}
	var t = 0.0
	while t < CarRepair.STRIKE * CarRepair.BLOWS_PER_PART * 2.2:
		frames(game, 0.05, 0.05)
		t += 0.05
		for part in CarHood.TARGETS:
			if game.car.get_node("EngineBay/" + part).scale.y < 0.97:
				hit_parts[part] = true
	check(wrench.visible, "the spanner shows while the car is repaired")
	check(hit_parts.size() >= 2, "the spanner strikes more than one part (%s)" % [hit_parts.keys()])
	check(game.condition <= 0.0, "the car stays broken until the work is done")

	# Walking off abandons it; a full job mends the car and shuts the bonnet.
	game.walker = origin + Vector3(0, 0, -9)
	frames(game, 0.1)
	check(not repair.active() and game.condition <= 0.0, "walking away abandons the repair")
	game.walker = nose
	frames(game, 0.5)
	repair.start("local")
	frames(game, CarRepair.SECONDS + 0.2)
	check(not repair.active() and game.condition == CarRepair.REPAIRED, "a finished repair mends the car")
	frames(game, 1.5)
	check(not CarHood.is_open(game.car) and not wrench.visible, "a mended car shuts its bonnet")

	# After the stage (both passes done, the camp being packed) a broken car
	# can still be mended to drive back to the service park.
	var schedule = [game.course.phase, game.course.pass_index]
	game.course.phase = "complete"
	game.course.pass_index = 2
	check(game.packing.active(), "the stage is over and the camp is being packed")
	game.condition = 0.0
	frames(game, 1.5)
	aim(game, bay)
	check(game.interaction.current().get("action", "") == "repair_car", "after the stage a broken car still offers a repair")
	repair.start("local")
	frames(game, CarRepair.SECONDS + 0.2)
	check(game.condition == CarRepair.REPAIRED, "after the stage the repair mends the car")
	game.course.phase = schedule[0]
	game.course.pass_index = schedule[1]
	frames(game, 1.5)

	# A guest mends a friend's car through the host.
	game.room.connected = true
	game.room.is_host = true
	game.room.player_id = "host"
	var guest_car = origin + Vector3(10, 0, 0)
	var state = {"pos": game.room.a(guest_car + Vector3(0, 0, -3.2)), "car": game.room.a(guest_car), "in_car": false, "tow": false, "push": [0, 0, 0], "beers": 0,
		"heading": 0.0, "yaw": 0.0, "pitch": 0.0, "speed": 0.0, "broken": true, "repair": true}
	game.room._update_peers([{"id": "guest", "name": "Друг", "state": state, "car_model": 3}])
	var solver = Prediction.new()
	solver.condition = 0.0
	game.room.host_drives["guest"] = solver
	var peer_car: Node3D = game.room.peers.guest.car
	peer_car.position = guest_car
	peer_car.rotation = Vector3.ZERO
	game.walker = origin + Vector3(0, 0, -20)
	frames(game, 1.5)
	check(CarHood.is_open(peer_car) and peer_car.get_node("EngineBay/Wrench").visible, "a friend repairing their car opens the bonnet and works the spanner on every client")
	var command = {"player": "guest", "action": "repair_car", "state": state, "placement": {"pos": game.room.a(CarHood.bay_point(peer_car)), "yaw": 0.0}}
	check("repair_car" in NetProtocol.actions(), "repair_car is a room command")
	game.room._apply_command(command)
	check(solver.condition == CarRepair.REPAIRED, "the host mends the guest's car from the command")
	solver.condition = 0.0
	command.placement.pos = game.room.a(CarHood.bay_point(peer_car) + Vector3(3, 0, 0))
	game.room._apply_command(command)
	check(solver.condition == 0.0, "a command away from any bay mends nothing")
	check(NetProtocol.clean_state({"repair": true, "in_car": false, "pos": [0, 0, 0], "car": [0, 0, 0], "heading": 0, "yaw": 0, "pitch": 0}).repair, "the state keeps repair on foot")
	check(not NetProtocol.clean_state({"repair": true, "in_car": true, "pos": [0, 0, 0], "car": [0, 0, 0], "heading": 0, "yaw": 0, "pitch": 0}).repair, "nobody repairs from the driver's seat")

	await game._shutdown_audio()
	game.free()
	finish()
