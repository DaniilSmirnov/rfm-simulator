extends RefCounted
const Props = preload("res://scripts/props.gd")
const KINDS = ["table", "chairs", "grill"]
var game: Node3D
var opened: Dictionary = {}
var held: Dictionary = {}
var context: Dictionary = {}
var hand_box: Node3D
var hand_kind = ""

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

func owner_of(item: Dictionary) -> String:
	return str(item.get("owner", item.node.get_meta("gear_owner", game.chair_owner())))

func stored(kind: String, owner: String) -> bool:
	for item in game.packing.items():
		if (item.kind == kind or (item.kind == "chair" and kind == "chairs")) and owner_of(item) == owner:
			return false
	for carry in held.values():
		if carry.owner == owner and carry.kind == kind and carry.returning:
			return false
	return true

func boxes(owner: String) -> Array:
	return [stored("table", owner), stored("chairs", owner), stored("grill", owner)]

func target_owner(spot: Vector3) -> String:
	for owner in poses():
		if point(poses()[owner]).distance_to(spot) < 0.6:
			return str(owner)
	return ""

func toggle(spot: Vector3) -> bool:
	if not available():
		return false
	var owner = target_owner(spot)
	if owner == "" or not near(owner):
		return false
	if game.room.submit("trunk", {"pos": game.room.a(spot), "yaw": 0.0}):
		return true
	opened[owner] = not opened.get(owner, false)
	game.toast("Багажник открыт. Выбери коробку через F или Z/C/G." if opened[owner] else "Багажник закрыт.")
	return true

func take(kind: String) -> bool:
	if kind not in KINDS or not available() or game.packing.active():
		return false
	var owner = actor()
	if held.has(owner):
		return held[owner].kind == kind and not held[owner].returning
	# Moving an existing item does not produce another box or duplicate equipment.
	for item in game.packing.items():
		if (item.kind == kind or (kind == "chairs" and item.kind == "chair")) and owner_of(item) == owner and game.walker.distance_to(item.node.position) < 3.5:
			if game.room.submit("take_gear", {"resource_id": KINDS.find(kind)}):
				return true
			held[owner] = {"kind": kind, "owner": owner, "returning": false}
			return true
	if not opened.get(owner, false) or not near(owner) or not stored(kind, owner):
		game.toast("Подойди к своему багажнику и открой его через F.")
		return false
	if (kind == "table" and game.camp != null) or (kind == "grill" and game.grill != null):
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
	if (kind == "table" and game.camp != null and str(game.camp.get_meta("gear_owner", owner)) != owner) or (kind == "grill" and game.grill != null and str(game.grill.get_meta("gear_owner", owner)) != owner):
		game.toast("Общий предмет уже установлен другим игроком. Верни коробку.")
		return false
	var placed = false
	match kind:
		"table": placed = game.place_table(spot, yaw)
		"chairs": placed = game.place_chairs(spot, yaw, owner)
		"grill": placed = game.start_grill(spot, yaw)
	if placed:
		var node = game.camp if kind == "table" else (game.grill if kind == "grill" else game.personal_chairs[owner])
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
	if not available() or not held.has(actor()):
		return false
	var owner = target_owner(spot)
	var carry = held[actor()]
	# If the owner left the room, another car can take abandoned equipment home.
	var destination = carry.owner if poses().has(carry.owner) else actor()
	if owner != destination or not opened.get(owner, false) or not near(owner):
		game.toast("Открой багажник машины владельца и верни коробку через F.")
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
	var cars = poses()
	for owner in cars:
		var spot = point(cars[owner])
		var holding = held.get(game.chair_owner(), {})
		var destination = str(holding.get("owner", "")) if cars.has(str(holding.get("owner", ""))) else game.chair_owner()
		if not holding.is_empty() and destination == owner and opened.get(owner, false):
			interaction.offer(items, spot, 0.55, 3.3, "return_gear", "Вернуть коробку в багажник", spot)
		else:
			interaction.offer(items, spot, 0.36, 3.3, "trunk", "Закрыть багажник" if opened.get(owner, false) else "Открыть багажник", spot)
		if owner != game.chair_owner() or not opened.get(owner, false) or not holding.is_empty() or game.packing.active():
			continue
		var p = Props.trunk_profile(int(cars[owner].variant))
		for i in range(3):
			if not stored(KINDS[i], owner):
				continue
			var box_point: Vector3 = cars[owner].pos + Vector3((i - 1) * 0.39, p.floor + 0.18, p.rear - 0.30).rotated(Vector3.UP, cars[owner].heading)
			interaction.offer(items, box_point, 0.19, 3.3, "take_gear", "Взять " + ["стол", "стул", "мангал"][i], KINDS[i])

func update(delta: float) -> void:
	var owner = game.chair_owner()
	if game.in_car and context.is_empty():
		opened[owner] = false
	if game.room.connected and game.room.is_host:
		for departed in held.keys():
			if departed != owner and not game.room.peers.has(departed):
				held.erase(departed)
	Props.update_player_trunk(game.car, bool(opened.get(owner, false)), boxes(owner), delta)
	var carry = held.get(owner, {})
	var kind = str(carry.get("kind", ""))
	if kind != hand_kind:
		if is_instance_valid(hand_box):
			hand_box.queue_free()
		hand_box = null
		hand_kind = kind
		if kind != "":
			hand_box = Props.gear_box(game.camera, kind, Vector3(0, -0.65, -0.9))
	if hand_box != null:
		hand_box.visible = not game.in_car and game.placement_preview == null and not game.dead and not game.finished

func snapshot() -> Dictionary:
	return {"opened": opened.duplicate(), "held": held.duplicate(true), "table_owner": str(game.camp.get_meta("gear_owner", game.chair_owner())) if game.camp != null else "", "grill_owner": str(game.grill.get_meta("gear_owner", game.chair_owner())) if game.grill != null else ""}

func apply_snapshot(data: Dictionary) -> void:
	opened = data.get("opened", {}).duplicate()
	held = data.get("held", {}).duplicate(true)
	if game.camp != null:
		game.camp.set_meta("gear_owner", str(data.get("table_owner", game.chair_owner())))
	if game.grill != null:
		game.grill.set_meta("gear_owner", str(data.get("grill_owner", game.chair_owner())))
