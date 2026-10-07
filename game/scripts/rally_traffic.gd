extends RefCounted
# Host-side rally line selection. Guests consume the existing pose snapshots.
const CLEARANCE = 2.85
const MAX_LINE = 3.05
const BRAKE = 18.0

static func profile(id: int) -> Dictionary:
	return {"bias": sin(id * 1.91) * 0.55, "phase": fmod(id * 2.37, TAU), "pace": 0.96 + fmod(id * 0.618, 1.0) * 0.08}

static func nominal(racer: Dictionary, s: float) -> float:
	return racer.get("bias", 0.0) + sin(s / 34.0 + racer.get("phase", 0.0)) * 0.24 + sin(s / 71.0 + racer.get("phase", 0.0) * 1.7) * 0.12

static func plan(game: Node3D, racer: Dictionary) -> Dictionary:
	var stage = game.stage
	var s: float = racer.s
	var limit: float = game.race_speed(s) * racer.get("pace", 1.0)
	var current: float = racer.get("line", racer.slide)
	var base = clampf(nominal(racer, s) + racer.slide, -1.45, 1.45)
	var positions: Array[Dictionary] = [{"pos": game.car.position, "speed": 0.0}]
	for peer in game.room.peers.values():
		if peer.state != null:
			positions.append({"pos": game.room.v(peer.state.car), "speed": 0.0})
	for group in game.spectators.groups:
		positions.append({"pos": group.car.position, "speed": 0.0})
	for other in game.racers:
		if other.id == racer.id:
			continue
		var other_speed = other.get("drive_speed", game.race_speed(other.s)) if other.state == "racing" else 0.0
		positions.append({"pos": other.node.position, "speed": other_speed})
	var blockers: Array[Dictionary] = []
	var closest = INF
	for object in positions:
		var station: float = game.race_station(object.pos)
		var gap = station - s
		if gap < -6 or gap > maxf(38, limit * 2.2):
			continue
		var center = game.race_at(station)
		if absf(object.pos.y - center.y) > 4:
			continue
		var lateral: float = (object.pos - center).dot(game.race_side(station))
		if absf(lateral) > MAX_LINE + CLEARANCE:
			continue
		# A car pulling away does not require overtaking. Close cars remain
		# blockers so a leader braking in this frame cannot be rear-ended.
		if object.speed >= limit - 0.5 and gap > 12:
			continue
		blockers.append({"s": station, "gap": gap, "line": lateral, "speed": object.speed})
		if gap >= -2:
			closest = minf(closest, gap)
	if blockers.is_empty():
		return {"line": base, "speed": limit, "avoiding": false}
	var candidates = [base, -2.95, 2.95, -1.5, 1.5]
	var chosen = current
	var best = INF
	var distance = clampf(closest + 9, 12, 55) if closest != INF else 16.0
	for candidate in candidates:
		var clear = true
		for blocker in blockers:
			if absf(candidate - blocker.line) < CLEARANCE:
				clear = false
				break
		if not clear or not _clear_path(game, racer, candidate, distance):
			continue
		var cost = absf(candidate - base) * 0.5 + absf(candidate - current) * 0.25
		if racer.get("avoiding", false):
			cost += absf(candidate - racer.get("avoid_line", current)) * 0.8
		if cost < best:
			best = cost
			chosen = candidate
	var speed = limit
	var advance = INF
	# Brake until the actual lateral position clears the obstruction. Retain
	# "racing" while waiting, so towing the blocker lets the queue restart.
	for blocker in blockers:
		if blocker.gap >= 0 and (best == INF or absf(current - blocker.line) < CLEARANCE):
			var safe = sqrt(2 * BRAKE * maxf(0, blocker.gap - 8))
			speed = minf(speed, safe)
			advance = minf(advance, maxf(0, blocker.gap - 7))
	if best == INF:
		chosen = current
	return {"line": chosen, "speed": speed, "avoiding": true, "advance": advance, "can_pass": best != INF}

static func _clear_path(game, racer: Dictionary, target: float, distance: float) -> bool:
	var stage = game.stage
	var previous: Vector3 = racer.node.position
	var current: float = racer.get("line", racer.slide)
	for i in range(1, 7):
		var ahead = distance * i / 6.0
		var s: float = minf(stage.LENGTH - 0.01, racer.s + ahead)
		var line = lerpf(current, target, smoothstep(0, minf(26, distance * 0.65), ahead))
		var point = game.race_at(s) + game.race_side(s) * line
		point.y = stage.ground(point)
		if not stage.rock_hit(previous, point, 0.95).is_empty() or stage.obstacle_hit(previous, point, 0.95, true) >= 0:
			return false
		if stage.urban and not stage.city.hit(previous, point, 0.95).is_empty():
			return false
		previous = point
	return true
