extends RefCounted
# How other room members look on this client: their car and avatar, the name
# label, carried gear, eating, drinking, sitting and walking. Pure presentation
# driven by the peer's last reported state and the interpolation buffers.
const Props = preload("res://scripts/core/props.gd")
const SnapshotMotion = preload("res://scripts/net/snapshot_motion.gd")
const NetProtocol = preload("res://scripts/net/net_protocol.gd")
const CharacterRig = preload("res://scripts/people/character_rig.gd")

static func create(game: Node, p: Dictionary) -> Dictionary:
	var car = Props.player_car(int(p.get("car_model", p.get("slot", 0))))
	game.add_child(car)
	var avatar = Props.player_avatar(int(p.get("slot", 0)))
	game.add_child(avatar)
	var carried_box = Props.carried_gear(avatar, "table")
	carried_box.hide()
	var arm = CharacterRig.hand(avatar)
	var label = Props.label_3d(game, Vector3.ZERO, p.name, 26, 0.012, Color("fff1cb"))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	var peer = {"id": p.id, "car": car, "avatar": avatar, "arm": arm, "held_box": carried_box, "held_kind": "table", "can": arm.get_node("BeerCan"), "skewer": arm.get_node("Skewer"), "eat_time": -1.0, "eat_sample": -1.0, "drink_time": -1.0, "drink_sample": -1.0, "label": label, "last_car": null, "state": null, "car_motion": SnapshotMotion.new(), "avatar_motion": SnapshotMotion.new()}
	if p.state != null:
		car.position = room_v(p.state.car)
		avatar.position = room_v(p.state.pos)
	return peer

static func remove(peer: Dictionary) -> void:
	for node in [peer.car, peer.avatar, peer.label]:
		node.queue_free()
	for node in peer.get("relief", {}).values():
		if node is Node:
			node.queue_free()

static func room_v(pos: Array) -> Vector3:
	return Vector3(pos[0], pos[1], pos[2])

# One frame of presentation. `clock` is the shared room clock, `frozen` stops
# interpolation while the host or this client is paused.
static func animate(game: Node, peer: Dictionary, delta: float, clock: float, frozen: bool, world_paused: bool) -> void:
	var state = peer.state
	var car_pose = peer.car_motion.render(clock, frozen)
	peer.car.position = car_pose.position
	peer.car.rotation = car_pose.rotation
	Props.animate_wheels(peer.car)
	if game.injuries.holds(peer.avatar):
		peer.avatar.visible = true
		return
	var avatar_pose = peer.avatar_motion.render(clock, frozen)
	peer.avatar.position = avatar_pose.position
	# On a car: placed on this client's copy of it, not where it was a packet ago.
	var standing = game.player.perches.resolve(state)
	if standing != null:
		peer.avatar.position = standing
		state.pos = [standing.x, standing.y, standing.z]
	peer.avatar.rotation.y = avatar_pose.rotation.y
	peer.avatar.visible = not state.in_car
	Props.update_player_trunk(peer.car, bool(game.cargo.opened.get(peer.id, false)), game.cargo.boxes(peer.id), delta)
	var carry = game.cargo.held.get(peer.id, {})
	var kind = str(carry.get("kind", ""))
	if kind != "" and kind != peer.held_kind:
		peer.held_box.queue_free()
		peer.held_box = Props.carried_gear(peer.avatar, kind)
		peer.held_kind = kind
	peer.held_box.visible = kind != "" and not state.in_car
	var sitting = bool(state.get("seated", false)) and not state.in_car
	var collapsed = int(state.get("beers", 0)) >= 30
	peer.avatar.rotation.z = lerp_angle(peer.avatar.rotation.z, PI / 2 if collapsed else 0.0, 1.0 - exp(-delta * 8))
	if collapsed:
		peer.avatar.position.y = avatar_pose.position.y + 0.25
	var hands = _animate_hands(peer, state, delta, world_paused or game.paused)
	var moving = room_v(state.get("push", [0, 0, 0])).length() > 0.1
	var pose = {"gait": (2 if bool(state.get("running", false)) else 1) if moving and not sitting else 0, "time": clock,
		"seed": float(hash(str(peer.id)) % 628) / 100.0, "airborne": bool(state.get("airborne", false)),
		"arms": "limp" if collapsed else ("radio" if bool(state.get("radio", false)) else hands.arms), "lift": hands.lift}
	if peer.held_box.visible and hands.arms == "":
		pose.arms = Props.carry_arms(peer.held_kind)
	if bool(state.get("relief", false)) and not collapsed:
		pose.arms = "relief"
	if sitting:
		pose.seat = Props.CHAIR_SEAT
		pose.ground = avatar_pose.position.y
	CharacterRig.pose(peer.avatar, pose)
	game.player.relief.draw_peer(peer, state)
	peer.label.position = _seat_label(game, peer, state) if state.in_car else peer.avatar.position + Vector3(0, 2.3, 0)

# A driver's name hangs over their car; passengers' names stack above the
# friend's car they ride in.
static func _seat_label(game: Node, peer: Dictionary, state: Dictionary) -> Vector3:
	var owner = str(state.get("ride", ""))
	var ride_car: Node3D = game.rides.car_node(owner)
	if ride_car == null:
		return peer.car.position + Vector3(0, 2.8, 0)
	return ride_car.position + Vector3(0, 3.3 + 0.45 * maxi(0, game.rides.riders(owner).find(str(peer.id))), 0)

# Eating and drinking run locally from the last reported start time so the
# arm moves smoothly between snapshots.
static func _animate_hands(peer: Dictionary, state: Dictionary, delta: float, paused: bool) -> Dictionary:
	var eat_duration = NetProtocol.duration("eat")
	var drink_duration = NetProtocol.duration("drink")
	var food_sample = float(state.get("eat", -1))
	if food_sample != peer.eat_sample:
		peer.eat_time = food_sample
		peer.eat_sample = food_sample
	if peer.eat_time >= 0 and not paused:
		peer.eat_time = minf(eat_duration, peer.eat_time + delta)
	peer.skewer.visible = peer.eat_time >= 0 and peer.eat_time < eat_duration and not state.in_car
	var drink_sample = float(state.beer)
	if drink_sample != peer.drink_sample:
		peer.drink_time = drink_sample
		peer.drink_sample = drink_sample
	if peer.drink_time >= 0 and not paused:
		peer.drink_time = minf(drink_duration, peer.drink_time + delta)
	peer.can.visible = peer.drink_time >= 0 and peer.drink_time < drink_duration and not peer.skewer.visible and not state.in_car
	if peer.skewer.visible:
		var lift = Props.food_lift(peer.eat_time)
		peer.skewer.rotation.x = -lift
		Props.pose_food(peer.skewer, peer.eat_time, str(state.get("food_kind", "meat")))
		Props.style_mushrooms(peer.skewer, str(state.get("food_species", "edible")))
		return {"arms": "eat", "lift": lift}
	if peer.can.visible:
		var lift = smoothstep(0.8, 1.25, peer.drink_time) * (1.0 - smoothstep(2.5, drink_duration, peer.drink_time))
		peer.can.rotation.x = 0.35 * lift
		return {"arms": "drink", "lift": lift}
	return {"arms": "", "lift": 0.0}
