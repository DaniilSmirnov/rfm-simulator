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
	for owner in game.personal_chairs:
		result.append({"node": game.personal_chairs[owner], "kind": "chair", "owner": owner, "label": "Собрать стул", "height": 0.65, "radius": 0.5})
	for owner in game.personal_flags:
		for node in game.personal_flags[owner]:
			result.append({"node": node, "kind": "flag", "owner": owner, "label": "Собрать флаг", "height": 1.5, "radius": 0.6})
	return result

func remaining() -> int:
	return items().size()

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
	if not active() or not game.playing or game.paused or game.dead or game.finished or game.in_car or game.beers >= 30 or (not remote and (game.eat_time >= 0 or game.drink_time >= 0)) or game.walker.distance_to(spot) > 3.5:
		return false
	for item in items():
		# The position identifies the exact item: retries cannot pack a different flag.
		if item.node.position.distance_to(spot) > 0.15:
			continue
		if game.room.submit("pack", {"pos": spot_array(spot), "yaw": 0.0}):
			return true
		remove(item)
		game.toast("Предмет убран в машину. Осталось: %d." % remaining())
		return true
	return false

func spot_array(point: Vector3) -> Array:
	return [point.x, point.y, point.z]
