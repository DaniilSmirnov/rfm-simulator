extends SceneTree
const Props = preload("res://scripts/props.gd")
var failures = 0
func check(ok: bool, title: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + title)
	if not ok:
		failures += 1
func _initialize() -> void:
	call_deferred("run")
func trunk(game) -> Vector3:
	return game.cargo.point(game.cargo.poses()[game.chair_owner()])
func return_box(game) -> void:
	game.walker = trunk(game)
	check(game.cargo.return_item(trunk(game)), "carried item returns at an open trunk")
func run() -> void:
	for variant in range(10):
		var model = Props.player_car(variant)
		root.add_child(model)
		var hinge = model.get_node_or_null("TrunkHinge")
		check(hinge != null and hinge.get_child_count() > 0 and model.get_node("TrunkBoxes").get_child_count() == 3, "model %d has opening bodywork and three real boxes" % variant)
		Props.update_player_trunk(model, true, [true, false, true], 0.2)
		check(hinge.rotation.x < -0.1 and hinge.rotation.x > -1.18, "model %d opens progressively rather than instantly" % variant)
		Props.update_player_trunk(model, true, [true, false, true], 1)
		check(model.get_node("TrunkBoxes").visible and not model.get_node("TrunkBoxes").get_child(1).visible, "model %d shows the actual remaining boxes" % variant)
		Props.update_player_trunk(model, false, [true, true, true], 1)
		check(absf(hinge.rotation.x) < 0.01 and not model.get_node("TrunkBoxes").visible, "model %d closes and covers cargo" % variant)
		model.free()
	var host = load("res://main.tscn").instantiate()
	var guest = load("res://main.tscn").instantiate()
	for game in [host, guest]:
		root.add_child(game)
	await process_frame
	for game in [host, guest]:
		game.set_process(false)
		game.room.set_process(false)
		game.start_game()
		game.in_car = false
		game.stage.trees.clear()
		game.stage.rocks.clear()
	var origin: Vector3 = host.stage.clearings[0]
	host.walker = origin
	host.car.position = origin + Vector3(0, 0, 8)
	host.heading = 0
	host.begin_placement("table")
	check(host.placement_preview == null and host.cargo.boxes("local") == [true, true, true], "cannot place furniture remotely from a closed trunk")
	for variant in range(Props.PLAYER_MODELS.size()):
		host.select_player_car(variant)
		host.car.position = origin + Vector3(0, 0, 8)
		host.heading = PI / 2 if variant % 2 else 0.0
		host.walker = trunk(host)
		host.camera.position = host.walker + Vector3(0, 1, 0)
		host.camera.look_at(host.camera.position + Vector3(0, 0, 1))
		host.cargo.update(1)
		check(host.cargo.opened.get("local", false) and host.car.get_node("TrunkHinge").rotation.x < -1.0 and host.car.get_node("TrunkBoxes").visible, "model %d opens automatically without aiming or F" % variant)
		var offers: Array = []
		host.cargo.offers(offers, host.interaction)
		check(not offers.any(func(item): return item.action == "trunk"), "model %d has no manual lid action" % variant)
		check(host.cargo.take("chairs"), "model %d allows taking cargo immediately after approaching" % variant)
		check(host.cargo.return_item(trunk(host)), "model %d allows returning cargo without manual opening" % variant)
		host.walker = trunk(host) + Vector3(3.6, 0, 0)
		host.cargo.update(0)
		check(host.cargo.opened.get("local", false), "model %d keeps lid open at the distance boundary" % variant)
		host.walker = trunk(host) + Vector3(4.3, 0, 0)
		host.cargo.update(1)
		check(not host.cargo.opened.get("local", false) and absf(host.car.get_node("TrunkHinge").rotation.x) < 0.01, "model %d closes automatically when everyone leaves" % variant)
		host.walker = host.car.position + Vector3(0, 0, -3).rotated(Vector3.UP, host.heading)
		host.cargo.update(0)
		check(not host.cargo.opened.get("local", false), "model %d does not open when approaching the front" % variant)
		host.walker = trunk(host)
		host.speed = 3
		host.cargo.update(0)
		check(not host.cargo.opened.get("local", false), "model %d stays closed while moving" % variant)
		host.speed = 0
	host.select_player_car(0)
	host.car.position = origin + Vector3(0, 0, 8)
	host.heading = 0
	for kind in ["table", "chairs", "grill"]:
		host.walker = trunk(host)
		host.begin_placement(kind)
		check(host.placement_kind == kind and host.cargo.held.has("local"), "take %s at the open trunk" % kind)
		host.cancel_placement()
		host.walker = origin
		var spot = origin + (Vector3(3, 0, 0) if kind == "chairs" else (Vector3(0, 0, -3) if kind == "grill" else Vector3.ZERO))
		check(host.cargo.deploy(kind, spot, 0), "selected %s deploys at a free spot" % kind)
	check(host.cargo.boxes("local") == [false, false, false], "three boxes disappear only when equipment is deployed")
	check(not host.cargo.deploy("chairs", origin + Vector3(0, 0, 4), 0) and host.personal_chairs.size() == 1, "placement cannot duplicate an item without acquiring it")
	host.course.phase = "complete"
	host.course.pass_index = 2
	host.passed = 10
	for item in host.packing.items():
		host.walker = item.node.position
		check(host.packing.pack(item.node.position), "pick up %s for packing" % item.kind)
		check(host.cargo.pending_returns() == 1, "picked-up item remains pending until deposited")
		host.cargo.opened["local"] = false
		host.walker = trunk(host) + Vector3(5, 0, 0)
		check(not host.cargo.return_item(trunk(host)), "remote equipment cannot be deposited before approaching")
		return_box(host)
	check(host.packing.remaining() == 0 and host.cargo.boxes("local") == [true, true, true], "all three boxes reappear after the camp is loaded")
	host.room.connected = true
	host.room.is_host = true
	host.room.player_id = "host"
	guest.room.connected = true
	guest.room.is_host = false
	guest.room.player_id = "guest"
	host.course.apply_snapshot({})
	guest.course.apply_snapshot({})
	host.car.position = origin + Vector3(0, 0, 20)
	guest.car.position = origin + Vector3(0, 0, 8)
	guest.heading = 0
	guest.walker = trunk(guest)
	host.room._update_peers([{"id": "guest", "name": "Друг", "state": guest.room.local_state(), "car_model": 0}])
	var point = trunk(guest)
	var command = {"player": "guest", "action": "trunk", "state": guest.room.local_state(), "placement": {"pos": guest.room.a(point), "yaw": 0}}
	host.cargo.update(1)
	check(host.cargo.opened.get("guest", false), "guest approach opens their own trunk without a command")
	host.walker = host.cargo.point(host.cargo.poses()["host"])
	host.in_car = true
	guest.walker = host.cargo.point(host.cargo.poses()["host"])
	host.room.peers["guest"].state = guest.room.local_state()
	host.cargo.update(1)
	check(host.cargo.opened.get("host", false), "friend opens a parked owner car by approaching its rear")
	guest.walker = trunk(guest)
	host.room.peers["guest"].state = guest.room.local_state()
	host.cargo.update(1)
	check(not host.cargo.opened.get("host", false), "friend leaving closes owner car even while owner is seated")
	host.in_car = false
	command.action = "take_gear"
	command.placement = {"resource_id": 1}
	host.room._apply_command(command)
	check(host.cargo.held.has("guest") and not host.cargo.held.has("host"), "guest takes their own chair instead of the host's")
	command.action = "chairs"
	command.state.pos = host.room.a(origin)
	command.placement = {"pos": host.room.a(origin + Vector3(-3, 0, 0)), "yaw": 0}
	host.room._apply_command(command)
	check(host.personal_chairs.has("guest") and host.cargo.boxes("guest") == [true, false, true], "guest placement consumes only their chair box")
	guest.room.apply_world(host.room.world_state())
	check(guest.cargo.opened.get("guest", false) == host.cargo.opened.get("guest", false) and guest.cargo.boxes("guest") == [true, false, true], "late world snapshot restores automatic trunk state and correct cargo")
	guest.cargo.update(1)
	check(guest.car.get_node("TrunkBoxes").visible and not guest.car.get_node("TrunkBoxes").get_child(1).visible, "guest cargo geometry reflects authoritative inventory")
	command.action = "grill"
	command.placement = {"pos": host.room.a(origin + Vector3(0, 0, -3)), "yaw": 0}
	host.room._apply_command(command)
	check(host.grill == null, "host rejects placement of a box that was never taken")
	for game in [host, guest]:
		await game._shutdown_audio()
		game.queue_free()
	await process_frame
	print("TRUNK RESULT: %d failures" % failures)
	quit(1 if failures else 0)
