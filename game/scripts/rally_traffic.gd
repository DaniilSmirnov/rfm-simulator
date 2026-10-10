extends RefCounted
# Host-side rally line selection. Guests consume the existing pose snapshots.
const Tracks = preload("res://scripts/rally_tracks.gd")
const CLEARANCE = 2.85
const MAX_LINE = 3.05
const BRAKE = 18.0
const MAX_COMPETITION_SPEED = 140.0 / 3.6
const MIN_CORNER_TARGET = 16.0
const CORNER_FULL_EFFECT = 0.35
const SPEED_LOOKAHEAD = [0.0, 16.0, 32.0, 48.0]
# Lateral allowance (m) when skipping far objects before projecting them.
const FAR_MARGIN = 40.0
# Travel (m) over which obstacle probes along a passing line are reused.
const PROBE_REFRESH = 2.0
# Seconds a chosen passing line is kept before candidates are re-scored.
const LANE_INTERVAL = 0.12

static func profile(id: int) -> Dictionary:
	return {"bias": sin(id * 1.91) * 0.55, "phase": fmod(id * 2.37, TAU), "pace": 0.96 + fmod(id * 0.618, 1.0) * 0.08}

static func nominal(racer: Dictionary, s: float) -> float:
	return racer.get("bias", 0.0) + sin(s / 34.0 + racer.get("phase", 0.0)) * 0.24 + sin(s / 71.0 + racer.get("phase", 0.0) * 1.7) * 0.12

static func competition_target(stage: Node3D, progress: float, pace: float = 1.0, reverse: bool = false) -> float:
	var station = stage.LENGTH - progress if reverse else progress
	var travel_sign = -1.0 if reverse else 1.0
	var worst_corner = 0.0
	for ahead in SPEED_LOOKAHEAD:
		var center = clampf(station + travel_sign * ahead, 0.0, stage.LENGTH - 0.01)
		var before = stage.direction(maxf(0.0, center - 6.0))
		var after = stage.direction(minf(stage.LENGTH - 0.01, center + 6.0))
		var angle = acos(clampf(before.dot(after), -1.0, 1.0))
		worst_corner = maxf(worst_corner, angle)
	var corner_factor = clampf(worst_corner / CORNER_FULL_EFFECT, 0.0, 1.0)
	var geometry_target = lerpf(MAX_COMPETITION_SPEED, MIN_CORNER_TARGET, pow(corner_factor, 0.75))
	# Tight village junctions need a lower entry speed than flowing bends.
	geometry_target = minf(geometry_target, lerpf(MIN_CORNER_TARGET, 7.0, smoothstep(0.7, 1.3, worst_corner))) if worst_corner > 0.7 else geometry_target
	return clampf(geometry_target * pace, 0.0, MAX_COMPETITION_SPEED)

static func speed_limit(game: Node3D, racer: Dictionary, s: float) -> float:
	var role = str(racer.get("role", "racer"))
	if role in ["racer", "zero"]:
		var reference = Tracks.sample(racer.get("track_parts", PackedInt32Array()), s, game.course.pass_index == 2, role == "zero")
		var target = minf(MAX_COMPETITION_SPEED, float(reference.speed) * racer.get("pace", 1.0)) if not reference.is_empty() else competition_target(game.stage, s, racer.get("pace", 1.0), game.course.pass_index == 2)
		return recovery_speed(target, racer) if role == "racer" else target
	return maxf(0.0, game.race_speed(s) * racer.get("pace", 1.0))

static func recovery_speed(target: float, racer: Dictionary) -> float:
	# Lift off progressively when the rear steps out, then regain pace as it settles.
	var loss = absf(float(racer.get("slide", 0.0))) * 0.22 + absf(float(racer.get("slide_speed", 0.0))) * 0.12
	return target * clampf(1.0 - loss, 0.5, 1.0)

static func line_limit(game, progress: float) -> float:
	var station: float = game.stage.LENGTH - progress if game.course.pass_index == 2 else progress
	return game.stage.road_width(station) * 0.5 + game.stage.shoulder(station)

static func corner_line(game, racer: Dictionary, base: float) -> float:
	if not racer.get("role", "racer") in ["racer", "zero"]: return base
	var before: Vector3 = game.race_direction(racer.s)
	var after: Vector3 = game.race_direction(racer.s + 10.0)
	var bend = wrapf(atan2(-after.x, -after.z) - atan2(-before.x, -before.z), -PI, PI)
	var limit = line_limit(game, racer.s)
	var cut = clampf(-bend * 9.0, -limit, limit)
	if racer.get("role", "racer") == "zero": cut *= 0.65
	# Cache obstacle probes: static shoulder checks need not run each physics step.
	if absf(cut) <= absf(base): return base
	if absf(racer.s - float(racer.get("cut_station", -100.0))) > 2.0:
		racer.cut_station = racer.s
		racer.cut_line = cut if _clear_path(game, racer, cut, 24.0) else base
	return float(racer.get("cut_line", base))

static func plan(game: Node3D, racer: Dictionary) -> Dictionary:
	var stage = game.stage
	var s: float = racer.s
	racer.track_reference = Tracks.sample(racer.get("track_parts", PackedInt32Array()), s, game.course.pass_index == 2, racer.get("role", "racer") == "zero")
	var limit: float = speed_limit(game, racer, s)
	var current: float = racer.get("line", 0.0) + racer.slide
	var base = float(racer.track_reference.line) if not racer.track_reference.is_empty() else clampf(nominal(racer, s), -1.45, 1.45)
	base = corner_line(game, racer, base)
	var positions: Array[Dictionary] = [{"pos": game.car.position, "speed": 0.0}]
	for peer in game.room.peers.values():
		if peer.state != null:
			positions.append({"pos": game.room.v(peer.state.car), "speed": 0.0})
	for group in game.spectators.groups:
		positions.append({"pos": group.car.position, "speed": 0.0})
	for other in game.racers:
		if other.id == racer.id:
			continue
		var other_speed = 0.0
		if other.state == "racing":
			other_speed = other.drive_speed if other.has("drive_speed") else speed_limit(game, other, other.s)
		positions.append({"pos": other.node.position, "speed": other_speed})
	var blockers: Array[Dictionary] = []
	var closest = INF
	# Projecting a point on the route is the costly step. The route is at least
	# as long as any chord, so an object further away than the look-ahead plus
	# a generous lateral allowance cannot pass the gap test below: skip it.
	var horizon = maxf(38, limit * 2.2) + FAR_MARGIN
	var here: Vector3 = racer.node.position
	for object in positions:
		if Vector2(object.pos.x - here.x, object.pos.z - here.z).length_squared() > horizon * horizon:
			continue
		var station: float = game.race_station(object.pos)
		var gap = station - s
		if gap < -6 or gap > maxf(38, limit * 2.2):
			continue
		var center = game.race_at(station)
		if absf(object.pos.y - center.y) > 4:
			continue
		var lateral: float = (object.pos - center).dot(game.race_side(station))
		if absf(lateral) > line_limit(game, station) + CLEARANCE:
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
	# Passing lines never leave the usable width: on open roads this keeps the
	# historic ±2.95 m, in narrow village streets it stays off the pavements.
	var reach = maxf(1.0, line_limit(game, s) - 0.8)
	var candidates = [base, -minf(2.95, reach), minf(2.95, reach), -minf(1.5, reach), minf(1.5, reach)]
	# Picking a passing line probes the road ahead for every candidate; it is
	# redone ~8 times a second or when the set of blockers changes. Braking
	# below still follows the blockers every step.
	var chosen = current
	var best = INF
	var lane: Dictionary = racer.get("lane_choice", {})
	if lane.is_empty() or racer.age < float(lane.age) or racer.age - float(lane.age) >= LANE_INTERVAL or int(lane.blockers) != blockers.size():
		var distance = clampf(closest + 9, 12, 55) if closest != INF else 16.0
		for candidate in candidates:
			var clear = true
			for blocker in blockers:
				if absf(candidate - blocker.line) < CLEARANCE:
					clear = false
					break
			if not clear or not _clear_path_cached(game, racer, candidate, distance):
				continue
			var cost = absf(candidate - base) * 0.5 + absf(candidate - current) * 0.25
			if racer.get("avoiding", false):
				cost += absf(candidate - racer.get("avoid_line", current)) * 0.8
			if cost < best:
				best = cost
				chosen = candidate
		racer.lane_choice = {"age": racer.age, "blockers": blockers.size(), "best": best, "chosen": chosen}
	else:
		best = float(lane.best)
		chosen = float(lane.chosen)
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

# Rocks, trees and walls barely change while a crew covers two metres, so
# probe results are reused over that distance, like the corner-cut probe.
static func _clear_path_cached(game, racer: Dictionary, target: float, distance: float) -> bool:
	var probes: Dictionary = racer.get("path_probes", {})
	if absf(racer.s - float(probes.get("s", -100.0))) > PROBE_REFRESH:
		probes = {"s": racer.s}
		racer.path_probes = probes
	var key = snappedf(target, 0.01)
	var cached = probes.get(key)
	if cached != null and absf(float(cached.distance) - distance) < PROBE_REFRESH * 2.0:
		return cached.clear
	var clear = _clear_path(game, racer, target, distance)
	probes[key] = {"distance": distance, "clear": clear}
	return clear

static func _clear_path(game, racer: Dictionary, target: float, distance: float) -> bool:
	var stage = game.stage
	var previous: Vector3 = racer.node.position
	var current: float = racer.get("line", 0.0) + racer.slide
	for i in range(1, 7):
		var ahead = distance * i / 6.0
		var s: float = minf(stage.LENGTH - 0.01, racer.s + ahead)
		var line = lerpf(current, target, smoothstep(0, minf(26, distance * 0.65), ahead))
		var point = game.race_at(s) + game.race_side(s) * line
		point.y = stage.ground(point)
		if not stage.rock_hit(previous, point, 0.95).is_empty() or stage.obstacle_hit(previous, point, 0.95, true) >= 0:
			return false
		if not stage.solids.hit(previous, point, 0.95).is_empty():
			return false
		previous = point
	return true
