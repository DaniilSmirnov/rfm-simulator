extends RefCounted
const Props = preload("res://scripts/props.gd")
const KINDS = Props.CARGO_KINDS
var game: Node3D
var opened: Dictionary = {}
var held: Dictionary = {}
var context: Dictionary = {}
var hand_box: Node3D
var hand_kind = ""
const SHOVEL_POSITION = Vector3(0.22, -0.05, -1.75)
const SHOVEL_ROTATION = Vector3(-0.25, 0.0, -0.30)
var shovel_swing: Tween

func animate_shovel() -> void:
	if not is_instance_valid(hand_box) or hand_kind != "shovel": return
	if shovel_swing != null and shovel_swing.is_running(): return
	shovel_swing = game.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for pose in [
		[Vector3(0.14, 0.08, -1.75), Vector3(0.10, -0.10, -0.20), 0.18],
		[Vector3(0.25, -0.19, -1.80), Vector3(-0.70, 0.08, -0.45), 0.22],
		[Vector3(0.02, 0.06, -1.75), Vector3(-0.05, -0.35, -0.65), 0.25],
		[SHOVEL_POSITION, SHOVEL_ROTATION, 0.22],
	]:
		shovel_swing.tween_property(hand_box, "position", pose[0], pose[2])
		shovel_swing.parallel().tween_property(hand_box, "rotation", pose[1], pose[2])

func shovel_busy() -> bool:
	return shovel_swing != null and shovel_swing.is_running()


func actor() -> String:
	return str(context.get("owner", game.chair_owner()))

func available() -> bool:
	return game.playing and not game.in_car and not game.paused and not game.dead and not game.finished and game.beers < 30 and (not context.is_empty() or (game.drink_time < 0 and game.eat_time < 0))

func poses() -> Dictionary:
	var result = {}
	var local_owner = game.chair_owner()
	result[local_owner] = {"pos": context.get("host_car", game.car.position), "heading": game.heading, "variant": game.selected_car}
	for owner in game.room.peers:
		var peer = game.room.peers[owner]
		if peer.state != null and peer.has("car"):
			result[owner] = {"pos": game.room.v(peer.state.car), "heading": float(peer.state.heading), "variant": int(peer.car.get_meta("variant", 0))}
	if not context.is_empty():
		result[actor()] = {"pos": context.car, "heading": context.heading, "variant": context.variant}
	return result

func point(pose: Dictionary) -> Vector3:
	var p = Props.trunk_profile(int(pose.variant))
	return pose.pos + Vector3(0, p.floor + 0.42, p.rear + 0.25).rotated(Vector3.UP, pose.heading)

func near(owner: String) -> bool:
	var cars = poses()
	return cars.has(owner) and game.walker.distance_to(point(cars[owner])) < 3.3

# The lid opens in a broad proximity zone; only its rear access area reserves F.
# Side doors remain usable even when the lid is open for a nearby spectator.
func at_open_trunk(owner: String) -> bool:
	var cars = poses()
	if not cars.has(owner) or not opened.get(owner, false) or not near(owner):
		return false
	var pose: Dictionary = cars[owner]
	var profile = Props.trunk_profile(int(pose.variant))
	var offset: Vector3 = (game.walker - pose.pos).rotated(Vector3.UP, -float(pose.heading))
	return offset.z >= profile.rear - 0.75 and absf(offset.x) <= profile.half + 0.85

func owner_of(item: Dictionary) -> String:
	return str(item.get("owner", item.node.get_meta("gear_owner", game.chair_owner())))

func stored(kind: String, owner: String) -> bool:
	for item in game.packing.items():
		if (item.kind == kind or (item.kind == "chair" and kind == "chairs")) and owner_of(item) == owner:
			return false
	for carry in held.values():
		if carry.owner == owner and carry.kind == kind:
			return false
	return true

func boxes(owner: String) -> Array:
	var result = []
	for kind in KINDS:
		result.append(stored(kind, owner))
	return result

func target_owner(spot: Vector3) -> String:
	for owner in poses():
		if point(poses()[owner]).distance_to(spot) < 0.6:
			return str(owner)
	return ""

# Derive lid state from people near the rear, independently of gaze and car model.
# A wider closing radius prevents repeated opening/closing at the edge.
func refresh_opened() -> void:
	var cars = poses()
	var visitors: Array = []
	if game.playing and not game.dead and not game.finished:
		if not game.in_car and game.beers < 30:
			visitors.append(game.walker)
		for id in game.room.peers:
			if not context.is_empty() and id == actor():
				continue
			var peer = game.room.peers[id]
			if peer.state != null and peer.state.has("pos") and not peer.state.in_car and int(peer.state.get("beers", 0)) < 30:
				visitors.append(game.room.v(peer.state.pos))
	for owner in opened.keys():
		if not cars.has(owner):
			opened.erase(owner)
	for owner in cars:
		var moving = absf(game.speed) > 1.0 if owner == game.chair_owner() else false
		if game.room.peers.has(owner) and game.room.peers[owner].state != null:
			moving = absf(float(game.room.peers[owner].state.get("speed", 0))) > 1.0
		if not context.is_empty() and owner == actor():
			moving = absf(float(context.get("speed", 0))) > 1.0
		var radius = 4.1 if opened.get(owner, false) else 3.3
		var present = false
		if not moving:
			for visitor in visitors:
				if visitor.distance_to(point(cars[owner])) < radius:
					present = true
					break
		opened[owner] = present

# Compatibility with queued commands from older clients; proximity owns the lid.
func toggle(spot: Vector3) -> bool:
	refresh_opened()
	var owner = target_owner(spot)
	return available() and owner != "" and near(owner) and opened.get(owner, false)

func take(kind: String) -> bool:
	refresh_opened()
	if kind not in KINDS or not available() or game.packing.active():
		return false
	var owner = actor()
	if held.has(owner):
		return held[owner].kind == kind and not held[owner].returning
	# Moving an existing item does not produce another box or duplicate equipment.
	for item in game.packing.items():
		if (item.kind == kind or (kind == "chairs" and item.kind == "chair")) and owner_of(item) == owner and game.walker.distance_to(item.node.global_position) < 3.5:
			if game.room.submit("take_gear", {"resource_id": KINDS.find(kind)}):
				return true
			held[owner] = {"kind": kind, "owner": owner, "returning": false}
			return true
	if not opened.get(owner, false) or not near(owner) or not stored(kind, owner):
		game.toast("Подойди к задней части своей машины — багажник откроется сам.")
		return false
	if (kind == "table" and game.camp != null) or (kind == "grill" and game.grill != null) or (kind == "firewood" and game.camp_cooking.fire != null) or (kind == "cauldron" and game.camp_cooking.pot != null):
		game.toast("Общий предмет уже установлен. Возьми свой стул.")
		return false
	if game.room.submit("take_gear", {"resource_id": KINDS.find(kind)}):
		return true
	held[owner] = {"kind": kind, "owner": owner, "returning": false}
	return true

func deploy(kind: String, spot: Vector3, yaw: float) -> bool:
	var owner = actor()
	if not available() or game.packing.active() or not held.has(owner) or held[owner].kind != kind or held[owner].returning or game.walker.distance_to(spot) > 5:
		return false
	var existing = game.camp if kind == "table" else (game.grill if kind == "grill" else (game.camp_cooking.fire if kind == "firewood" else (game.camp_cooking.pot if kind == "cauldron" else null)))
	if existing != null and str(existing.get_meta("gear_owner", owner)) != owner:
		game.toast("Общий предмет уже установлен другим игроком. Верни коробку.")
		return false
	var placed = false
	match kind:
		"table": placed = game.place_table(spot, yaw)
		"chairs": placed = game.place_chairs(spot, yaw, owner)
		"grill": placed = game.start_grill(spot, yaw)
		"firewood": placed = game.camp_cooking.deploy_fire(spot, yaw)
		"cauldron": placed = game.camp_cooking.place_pot(spot, yaw)
	if placed:
		var node = game.camp if kind == "table" else (game.grill if kind == "grill" else (game.camp_cooking.fire if kind == "firewood" else (game.camp_cooking.pot if kind == "cauldron" else game.personal_chairs[owner])))
		node.set_meta("gear_owner", owner)
		held.erase(owner)
	return placed

func pick_up(item: Dictionary) -> bool:
	var owner = actor()
	if held.has(owner):
		game.toast("Сначала верни предмет в открытый багажник.")
		return false
	var kind = "chairs" if item.kind == "chair" else str(item.kind)
	held[owner] = {"kind": kind, "owner": owner_of(item), "returning": true}
	return true

func return_item(spot: Vector3) -> bool:
	refresh_opened()
	if not available() or not held.has(actor()):
		return false
	var carry = held[actor()]
	# If the owner left the room, another car can take abandoned equipment home.
	var cars = poses()
	var owner = str(carry.owner) if cars.has(carry.owner) else actor()
	# Validate the carried item's destination directly. Nearby trunks can overlap;
	# selecting the first car at this point may select the carrier's car instead.
	if not cars.has(owner) or point(cars[owner]).distance_to(spot) >= 0.6 or not opened.get(owner, false) or not near(owner):
		game.toast("Подойди к багажнику машины владельца и верни коробку через F.")
		return false
	if game.room.submit("return_gear", {"pos": game.room.a(spot), "yaw": 0.0}):
		return true
	held.erase(actor())
	game.toast("Коробка снова в багажнике.")
	return true

func pending_returns() -> int:
	var count = 0
	for carry in held.values():
		count += int(carry.returning)
	return count

func offers(items: Array, interaction) -> void:
	refresh_opened()
	var cars = poses()
	for owner in cars:
		var spot = point(cars[owner])
		var holding = held.get(game.chair_owner(), {})
		var destination = str(holding.get("owner", "")) if cars.has(str(holding.get("owner", ""))) else game.chair_owner()
		if not holding.is_empty() and destination == owner and opened.get(owner, false):
			var profile = Props.trunk_profile(int(cars[owner].variant))
			interaction.offer(items, spot, maxf(0.9, profile.half), 3.3, "return_gear", "Вернуть коробку в багажник владельца", spot)
		if owner != game.chair_owner() or not opened.get(owner, false) or not holding.is_empty() or game.packing.active():
			continue
		var p = Props.trunk_profile(int(cars[owner].variant))
		var candidates: Array = []
		for i in range(KINDS.size()):
			if not stored(KINDS[i], owner):
				continue
			var box_point: Vector3 = cars[owner].pos + Props.cargo_point(p, i).rotated(Vector3.UP, cars[owner].heading)
			interaction.offer(candidates, box_point, 0.42, 3.3, "take_gear", "Взять " + ["стол", "стул", "мангал", "дрова", "казан", "лопату"][i], KINDS[i])

		# Overlapping forgiving hit zones choose the box nearest the crosshair.
		if not candidates.is_empty():
			candidates.sort_custom(func(a, b): return a.aim_error < b.aim_error)
			items.append(candidates[0])

# A departed carrier's box is considered loaded into their departed car.
# Installed items stay in the camp and can still be collected by friends.
func release_departed() -> void:
	if not game.room.connected or not game.room.is_host:
		return
	for departed in held.keys():
		if departed != game.chair_owner() and not game.room.peers.has(departed):
			held.erase(departed)

func update(delta: float) -> void:
	refresh_opened()
	var owner = game.chair_owner()
	release_departed()
	Props.update_player_trunk(game.car, bool(opened.get(owner, false)), boxes(owner), delta)
	var carry = held.get(owner, {})
	var kind = str(carry.get("kind", ""))
	if kind != hand_kind:
		if shovel_swing != null: shovel_swing.kill()
		if is_instance_valid(hand_box):
			hand_box.queue_free()
		hand_box = null
		hand_kind = kind
		if kind != "":
			hand_box = Props.gear_box(game.camera, kind, SHOVEL_POSITION if kind == "shovel" else Vector3(0, -0.65, -0.9))
			if kind == "shovel": hand_box.rotation = SHOVEL_ROTATION
	if hand_box != null:
		hand_box.visible = not game.in_car and game.placement_preview == null and not game.dead and not game.finished

func snapshot() -> Dictionary:
	refresh_opened()
	return {"opened": opened.duplicate(), "held": held.duplicate(true), "table_owner": str(game.camp.get_meta("gear_owner", game.chair_owner())) if game.camp != null else "", "grill_owner": str(game.grill.get_meta("gear_owner", game.chair_owner())) if game.grill != null else ""}

func apply_snapshot(data: Dictionary) -> void:
	opened = data.get("opened", {}).duplicate()
	held = data.get("held", {}).duplicate(true)
	if game.camp != null:
		game.camp.set_meta("gear_owner", str(data.get("table_owner", game.chair_owner())))
	if game.grill != null:
		game.grill.set_meta("gear_owner", str(data.get("grill_owner", game.chair_owner())))

