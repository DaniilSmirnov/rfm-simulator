extends "res://tests/harness.gd"
# Climbing onto things (perches.gd): cars, furniture, a person lying on the
# ground, boxes and rocks; too high stays a wall; riding a moving car, and
# how a room shows somebody standing on a car.
const Perches = preload("res://scripts/player/perches.gd")
const NetProtocol = preload("res://scripts/net/net_protocol.gd")
const Props = preload("res://scripts/core/props.gd")
const StageRecords = preload("res://scripts/stages/stage_records.gd")
const PeerView = preload("res://scripts/net/peer_view.gd")

var game

func _initialize() -> void:
	call_deferred("run")

func face(target: Vector3) -> void:
	var to = target - game.walker
	game.view_yaw = atan2(-to.x, -to.z)

# Walk (optionally after a jump) towards `target` for `seconds`.
func approach(target: Vector3, seconds: float, leap: bool) -> void:
	face(target)
	Input.action_press("forward")
	if leap:
		game.jump()
	for i in range(int(seconds * 60.0)):
		face(target)
		game._walk(1.0 / 60.0)
	Input.action_release("forward")

func idle(seconds: float) -> void:
	for i in range(int(seconds * 60.0)):
		game._walk(1.0 / 60.0)

func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func ground() -> float:
	return game.stage.ground(game.walker)

func place(node: Node3D, at: Vector3, yaw: float) -> void:
	node.position = at
	node.position.y = game.stage.ground(at)
	node.rotation = Vector3(0, yaw, 0)

func stand_beside(target: Vector3, offset: Vector3) -> void:
	game.walker = target + offset
	game.walker.y = game.stage.ground(game.walker)
	game.jump_height = 0
	game.jump_velocity = 0
	game.player.perches.clear()

func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.start_game()
	game.in_car = false
	game.stage.trees.clear()
	game.stage.rocks.clear()
	# Nobody else around the test spots.
	for person in game.spectators.people:
		person.avatar.position += Vector3(0, -500, 0)
	for group in game.spectators.groups:
		for node in [group.car, group.table]:
			node.visible = false
	var spot: Vector3 = game.stage.at(300)
	var side: Vector3 = game.stage.side(300)
	var yaw = atan2(-game.stage.direction(300).x, -game.stage.direction(300).z)

	var forward: Vector3 = game.stage.direction(300)
	# ---- the player's own car, measured from its meshes
	place(game.car, spot, yaw)
	await process_frame
	var perches = game.player.perches
	perches.gather(game.car.position)
	var bonnet = perches.support(game.car.position + forward * 1.5, game.car.position.y + 5.0) - game.car.position.y
	var roof = perches.support(game.car.position + forward * 0.1, game.car.position.y + 5.0) - game.car.position.y
	print("car tops: bonnet %.2f roof %.2f" % [bonnet, roof])
	check(bonnet > 0.6 and bonnet < 1.15 and roof > bonnet + 0.3 and roof < 1.8, "car height field has a bonnet below the roof")

	stand_beside(game.car.position, side * 2.6)
	approach(game.car.position, 1.5, false)
	check(absf(game.walker.y - ground()) < 0.01 and flat_distance(game.walker, game.car.position) > 0.9, "walking into the car side is blocked on the ground")
	var bonnet_point = game.car.position + forward * 1.5
	stand_beside(bonnet_point, side * 1.9)
	approach(bonnet_point, 0.8, true)
	idle(0.3)
	approach(game.car.position + forward * 0.1, 0.6, false)
	check(game.walker.y - game.car.position.y < bonnet + 0.2, "the windscreen and roof are a wall without a jump")
	approach(game.car.position + forward * 0.1, 0.7, true)
	idle(0.5)
	check(game.jump_height == 0 and absf(game.walker.y - game.car.position.y - roof) < 0.12, "from the bonnet a second jump reaches the roof")
	idle(1.0)
	check(absf(game.walker.y - game.car.position.y - roof) < 0.12, "standing on the roof does not slide off")

	# ---- riding: the car drives and turns, the walker stays where they stood
	var local: Vector3 = game.car.global_transform.affine_inverse() * game.walker
	for i in range(60):
		game.car.position += forward.rotated(Vector3.UP, i * 0.005) * 0.25
		game.car.position.y = game.stage.ground(game.car.position)
		game.car.rotation.y += 0.005
		game._walk(1.0 / 60.0)
	var ridden: Vector3 = game.car.global_transform.affine_inverse() * game.walker
	check(game.car.position.distance_to(spot) > 10.0 and ridden.distance_to(local) < 0.05, "a moving, turning car carries the person standing on it")
	var fields = perches.state_fields()
	check(fields.stand == "car:%s" % game.room.player_id and Vector3(fields.stand_at[0], fields.stand_at[1], fields.stand_at[2]).distance_to(ridden) < 0.01, "the room state names the car and the feet on it")
	var feet = game.walker
	var swept = game.injuries.vehicle_sweep(game.car.position - forward * 0.4, game.car.position, forward * 15.0, 5.0)
	check(not swept and not game.injuries.down and game.walker.distance_to(feet) < 0.001, "the car under a rider does not knock them down")
	# Off the side: a real fall back to the ground, and the ride ends.
	approach(game.car.position + side * 4.0, 0.9, false)
	idle(0.6)
	check(game.jump_height == 0 and absf(game.walker.y - ground()) < 0.01 and perches.stand.is_empty(), "stepping off the roof falls to the ground")
	place(game.car, game.stage.at(30), yaw)

	# ---- furniture: the camp table and a chair (walked through on the ground)
	var table_spot: Vector3 = spot + forward * 8.0
	game.camp = Node3D.new()
	game.add_child(game.camp)
	Props.table(game.camp)
	place(game.camp, table_spot, yaw)
	stand_beside(table_spot, side * 2.5)
	approach(table_spot - side * 2.0, 1.2, false)
	check(absf(game.walker.y - ground()) < 0.01 and flat_distance(game.walker, table_spot) > 1.0, "walking past the table on the ground keeps the feet on the ground")
	stand_beside(table_spot, side * 1.5)
	approach(table_spot, 0.7, true)
	idle(0.4)
	check(game.jump_height == 0 and absf(game.walker.y - game.camp.position.y - 0.885) < 0.1, "a jump lands on the camp table top")
	var chair_spot: Vector3 = spot + forward * 14.0
	game.camp_actions.apply_chair(game.chair_owner(), chair_spot, yaw)
	stand_beside(chair_spot, side * 1.4)
	approach(chair_spot, 0.6, true)
	idle(0.4)
	check(game.jump_height == 0 and absf(game.walker.y - game.stage.ground(chair_spot) - Props.CHAIR_SEAT) < 0.08, "a jump lands on the chair seat")

	# ---- a person lying on the ground after a hit
	var person: Dictionary = game.spectators.people[0]
	var key = "npc:%d" % person.id
	var body_spot: Vector3 = spot + forward * 20.0
	body_spot.y = game.stage.ground(body_spot) + 0.25
	game.injuries.records[key] = {"phase": "lying", "pos": body_spot, "rot": Vector3(0, yaw + PI / 2, PI / 2), "time": 0.0, "treat": 0.0, "limp": 0.0, "ambulance": -1, "station": 300.0}
	game.injuries._pose(key, body_spot, Vector3(0, yaw + PI / 2, PI / 2), 1.0)
	var lying_top = game.stage.ground(body_spot)
	stand_beside(body_spot - forward * 0.7, side * 1.6)
	approach(body_spot - forward * 0.7, 0.6, true)
	idle(0.4)
	print("on the lying person: %.2f above ground" % (game.walker.y - ground()))
	check(game.jump_height == 0 and game.walker.y - lying_top > 0.2 and game.walker.y - lying_top < 0.7, "a jump lands on a person lying on the ground")
	game.injuries.records.erase(key)

	# ---- boxes and rocks: reachable tops are floors, high ones stay walls
	var low_box: Vector3 = spot + forward * 26.0
	low_box.y = game.stage.ground(low_box)
	game.stage.solids.solid(game.stage, low_box + Vector3(0, 0.5, 0), Vector3(1.6, 1.0, 1.6), "test")
	var high_box: Vector3 = spot + forward * 32.0
	high_box.y = game.stage.ground(high_box)
	game.stage.solids.solid(game.stage, high_box + Vector3(0, 0.75, 0), Vector3(1.6, 1.5, 1.6), "test")
	stand_beside(low_box, side * 1.9)
	approach(low_box, 0.8, true)
	idle(0.4)
	check(game.jump_height == 0 and absf(game.walker.y - low_box.y - 1.0) < 0.05, "a jump lands on a 1 m box")
	stand_beside(high_box, side * 1.9)
	approach(high_box, 0.9, true)
	idle(0.5)
	check(absf(game.walker.y - ground()) < 0.01 and flat_distance(game.walker, high_box) > 1.0, "a 1.5 m box is too high to climb")
	var rock_spot: Vector3 = spot + forward * 38.0
	rock_spot.y = game.stage.ground(rock_spot)
	game.stage.rocks.append(StageRecords.rock(rock_spot, 0.7, 0.6))
	stand_beside(rock_spot, side * 1.7)
	approach(rock_spot, 0.7, true)
	idle(0.4)
	check(game.jump_height == 0 and absf(game.walker.y - rock_spot.y - 0.6) < 0.05, "a jump lands on top of a boulder")

	# ---- the room: another member standing on someone's car
	var peer = PeerView.create(game, {"id": "friend", "name": "Друг", "slot": 1, "state": null})
	game.room.peers["friend"] = peer
	place(peer.car, spot + forward * 50.0, yaw)
	var raw = game.room.local_state()
	raw.merge({"in_car": false, "stand": "car:friend", "stand_at": [0.3, 1.4, 0.2]}, true)
	var clean = NetProtocol.clean_state(raw)
	check(clean.stand == "car:friend" and clean.stand_at == [0.3, 1.4, 0.2], "the room keeps a member's perch")
	check(NetProtocol.expand_state(NetProtocol.compact_state(clean)).stand_at == [0.3, 1.4, 0.2], "the direct link keeps a member's perch")
	var bad = raw.duplicate()
	bad.stand = "house:1"
	check(NetProtocol.clean_state(bad).stand == "", "only car keys are accepted as perches")
	var seated = raw.duplicate()
	seated.seated = true
	check(NetProtocol.clean_state(seated).stand == "", "a seated member stands on nothing")
	check(not NetProtocol.compact_state(NetProtocol.clean_state(game.room.local_state())).has("stand_at"), "no perch costs nothing on the wire")
	peer.state = clean
	peer.last_state_time = 0.0
	PeerView.animate(game, peer, 1.0 / 60.0, 0.0, true, false)
	var expected: Vector3 = peer.car.global_transform * Vector3(0.3, 1.4, 0.2)
	check(peer.avatar.position.distance_to(expected) < 0.01 and game.room.v(peer.state.pos).distance_to(expected) < 0.01, "a member standing on a car is shown on this client's copy of it")
	game.room.peers.erase("friend")
	PeerView.remove(peer)

	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	print("PERCHES RESULT: %d failures" % failures)
	finish()
