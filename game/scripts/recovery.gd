extends RefCounted
const SECONDS = 6.0
const ROPE_RANGE = 6.0
const PUSH_RANGE = 2.6

static func road_direction(game, racer: Dictionary) -> Vector3:
	var direction: Vector3 = game.stage.at(game.stage.road_s(racer.node.position)) - racer.node.position
	direction.y = 0
	if direction.length() < 0.5:
		direction = game.stage.direction(game.stage.road_s(racer.node.position))
	return direction.normalized()

static func update(game, players: Dictionary, delta: float) -> void:
	if game.paused or game.dead or game.finished:
		game._clear_recovery_ropes()
		return
	game.recovery_links.clear()
	game.recovery_helpers = 0
	game.tow_target = null
	game.tow_progress = 0
	var forces = {}
	var helpers = {}
	for id in players:
		var p: Dictionary = players[id]
		if p.get("in_car", true) or int(p.get("beers", 0)) >= 30:
			continue
		var pos = game.room.v(p.pos)
		var push = game.room.v(p.get("push", [0, 0, 0])).limit_length(1.0)
		var best = INF
		var chosen: Dictionary = {}
		var strength = 0.0
		var rope = false
		for racer in game.racers:
			if not game.can_tow_racer(racer):
				continue
			var offset: Vector3 = racer.node.position - pos
			if absf(offset.y) > 3:
				continue
			offset.y = 0
			var distance = offset.length()
			var road = road_direction(game, racer)
			var effort = 0.0
			var pulling = false
			if p.get("tow", false) and distance <= ROPE_RANGE:
				effort = maxf(0.0, (-offset.normalized()).dot(road))
				pulling = effort > 0.15
			elif distance <= PUSH_RANGE and push.dot(offset.normalized()) > 0.5:
				effort = maxf(0.0, push.dot(road))
			if effort > 0.15 and distance < best:
				best = distance
				chosen = racer
				strength = effort
				rope = pulling
		if chosen.is_empty():
			continue
		var key: int = chosen.id
		forces[key] = float(forces.get(key, 0)) + strength
		helpers[key] = int(helpers.get(key, 0)) + 1
		if rope:
			game.recovery_links.append({"player": str(id), "racer": key, "pos": p.pos})
	for racer in game.racers:
		var key: int = racer.id
		racer.recovery_helpers = int(helpers.get(key, 0))
		if not forces.has(key):
			continue
		if not racer.has("recovery_start"):
			racer.recovery_start = racer.node.position
			racer.recovery_goal = game.stage.at(game.stage.road_s(racer.node.position))
		var progress = minf(1.0, float(racer.get("recovery_progress", 0)) + maxf(0, delta) * forces[key] / SECONDS)
		var next: Vector3 = racer.recovery_start.lerp(racer.recovery_goal, progress)
		next.y = game.stage.ground(next)
		var blocked = not game.stage.rock_hit(racer.node.position, next, 0.85).is_empty() or game.stage.obstacle_hit(racer.node.position, next, 0.85, true) >= 0
		if game.stage.urban:
			blocked = blocked or not game.stage.city.hit(racer.node.position, next, 0.85).is_empty()
		if blocked:
			game.toast("Путь к дороге перекрыт. Освободи проход для экипажа.")
			continue
		racer.node.position = next
		racer.previous = next
		racer.recovery_progress = progress
		game.recovery_helpers += racer.recovery_helpers
		game.tow_target = racer.node
		game.tow_progress = progress
		if progress >= 1:
			game.recover_racer(racer)
			game.recovery_links = game.recovery_links.filter(func(link): return link.racer != key)
			game.tow_target = null
			game.tow_progress = 0
			game.toast("Вытащили! Экипаж благодарит и продолжает СУ.")
	game.draw_recovery_ropes()
