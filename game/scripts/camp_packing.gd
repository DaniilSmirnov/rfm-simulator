extends RefCounted
# Shared cleanup: friends can pack any player equipment, never NPC furniture.
var game: Node3D

func active() -> bool:
	return game.course.phase == "complete" and game.course.pass_index == 2

func items() -> Array:
	var result: Array = []
	if game.camp != null:
		result.append({"node": game.camp, "kind": "table", "label": "Собрать стол", "height": 0.75, "radius": 0.85})
	if game.grill != null:
		result.append({"node": game.grill, "kind": "grill", "label": "Потушить и собрать мангал", "height": 0.9, "radius": 0.65})
	if game.camp_cooking.pot != null:
		result.append({"node": game.camp_cooking.pot, "kind": "cauldron", "label": "Собрать казан с подставкой", "height": 1.1, "radius": 0.65})
	if game.camp_cooking.fire != null:
		result.append({"node": game.camp_cooking.fire, "kind": "firewood", "label": "Потушить и собрать костёр", "height": 0.3, "radius": 0.75})
	for owner in game.personal_chairs:
		result.append({"node": game.personal_chairs[owner], "kind": "chair", "owner": owner, "label": "Собрать стул", "height": 0.65, "radius": 0.5})
	for owner in game.personal_flags:
		for node in game.personal_flags[owner]:
			result.append({"node": node, "kind": "flag", "owner": owner, "label": "Собрать флаг", "height": 1.5, "radius": 0.6})
	return result

func remaining() -> int:
	return items().size() + game.cargo.pending_returns()

func remove(item: Dictionary) -> void:
	match item.kind:
		"table":
			game.camp = null
		"grill":
			game.grill = null
			game.cooking = false
			game.cook_time = 0
			game.grill_servings = 0
			game.smoke = null
			game.fire_audio.stop()
			game.foraging.skewers.erase("-1")
		"cauldron":
			game.camp_cooking.remove_pot()
			return
		"firewood":
			game.camp_cooking.remove_fire()
			return
		"chair":
			if item.owner == game.chair_owner() and game.seated:
				game.stand_up()
			game.personal_chairs.erase(item.owner)
			game.has_chairs = not game.personal_chairs.is_empty()
		"flag":
			game.personal_flags[item.owner].erase(item.node)
			if game.personal_flags[item.owner].is_empty():
				game.personal_flags.erase(item.owner)
	item.node.queue_free()

func pack(spot: Vector3, remote: bool = false) -> bool:
	if not active() or not game.playing or game.paused or game.dead or game.finished or game.actor_in_car() or game.actor_beers() >= 30 or (not remote and (game.eat_time >= 0 or game.drink_time >= 0)) or game.actor_pos().distance_to(spot) > 3.5:
		return false
	for item in items():
		# The position identifies the exact item: retries cannot pack a different flag.
		var item_pos: Vector3 = item.node.global_position
		if item_pos.distance_to(spot) > 0.15:
			continue
		if item.kind == "firewood" and game.camp_cooking.pot != null:
			game.toast("Сначала собери казан и подставку.")
			return false
		if game.room.submit("pack", {"pos": spot_array(spot), "yaw": 0.0}):
			return true
		if item.kind != "flag" and not game.cargo.pick_up(item):
			return false
		remove(item)
		game.toast("Флаг собран." if item.kind == "flag" else "Предмет в руках. Верни его в открытый багажник через F.")
		return true
	return false

func spot_array(point: Vector3) -> Array:
	return [point.x, point.y, point.z]
