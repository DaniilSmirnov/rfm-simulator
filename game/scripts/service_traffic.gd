extends RefCounted
# Service vehicles yield to people and retain a swept safety stop even when a
# pedestrian steps into the route after the look-ahead plan was calculated.
const Motion = preload("res://scripts/vehicle_motion.gd")
const PERSON_CLEARANCE = 2.2
const CAR_CLEARANCE = 3.1
# Right of way: an ambulance held this long (s) by anything drives on in
# priority mode for PRIORITY_DISTANCE metres: it keeps away from people, goes
# round cars where the verge allows and otherwise passes through cars, rocks
# and street furniture at walking pace. Nothing but people can stop it.
const PRIORITY_AFTER = 2.5
const PRIORITY_DISTANCE = 30.0
const PRIORITY_SPEED = 5.0

static func applies(racer: Dictionary) -> bool:
	return racer.get("role", "racer") in ["ambulance", "opening_police", "closing_police"]

static func people(game) -> Array:
	var result: Array = []
	# Keep injury avatars discoverable for animation, but block service traffic
	# only with standing people and the actual displaced body positions.
	for person in game.injuries.people():
		if not game.injuries.is_down(str(person.key)):
			result.append(person)
	# Injured people can be displaced from their ordinary walking positions.
	for key in game.injuries.records:
		var record: Dictionary = game.injuries.records[key]
		if record.has("pos") and str(record.get("phase", "")) != "limp":
			result.append({"key": str(key), "pos": record.pos})
	return result

static func cars(game, racer: Dictionary) -> Array:
	var result = [game.car.position]
	for peer in game.room.peers.values():
		if peer.state != null:
			result.append(game.room.v(peer.state.car))
	for group in game.spectators.groups:
		result.append(group.car.position)
	for other in game.racers:
		if other.id != racer.id:
			result.append(other.node.position)
	return result

static func approaching_hit(start: Vector3, end: Vector3, target: Vector3, radius: float) -> bool:
	# Permit separation if somebody stepped inside the safety margin.
	if start.distance_to(target) < radius and (end - start).dot(start - target) > 0.0:
		return false
	return Motion.swept_hit(start, end, target, radius)

static func blocked(game, racer: Dictionary, start: Vector3, end: Vector3) -> bool:
	for person in people(game):
		if approaching_hit(start, end, person.pos, PERSON_CLEARANCE):
			return true
	if priority(racer):
		return false
	for car in cars(game, racer):
		if approaching_hit(start, end, car, CAR_CLEARANCE):
			return true
	return not game.stage.rock_hit(start, end, 1.1).is_empty() or game.stage.obstacle_hit(start, end, 1.1, true) >= 0 or not game.stage.solids.hit(start, end, 1.1).is_empty()

static func save(racer: Dictionary) -> Dictionary:
	if not applies(racer): return {}
	return {"s": racer.s, "line": racer.line, "position": racer.node.position, "rotation": racer.node.rotation}

static func guard(game, racer: Dictionary, before: Dictionary) -> bool:
	if before.is_empty() or not blocked(game, racer, before.position, racer.node.position):
		return false
	racer.s = before.s
	racer.line = before.line
	racer.node.position = before.position
	racer.node.rotation = before.rotation
	racer.drive_speed = 0.0
	racer.motion.velocity = Vector3.ZERO
	racer.erase("lane_choice")
	return true

static func priority(racer: Dictionary) -> bool:
	return float(racer.get("priority_until", -1.0)) > float(racer.s)

# Seconds since the ambulance last moved; once held long enough it takes
# priority until it is PRIORITY_DISTANCE further on.
static func _update_hold(racer: Dictionary) -> void:
	if racer.get("role", "") != "ambulance":
		return
	if float(racer.get("drive_speed", 0.0)) >= 0.3 or not racer.has("moving_age"):
		racer.moving_age = racer.age
	if not priority(racer) and racer.age - float(racer.moving_age) >= PRIORITY_AFTER:
		racer.priority_until = float(racer.s) + PRIORITY_DISTANCE
		racer.erase("path_probes")
		racer.erase("lane_choice")

static func pedestrian_plan(game, racer: Dictionary, plan: Dictionary) -> Dictionary:
	_update_hold(racer)
	if priority(racer):
		return priority_plan(game, racer, plan)
	var current: float = racer.line + racer.slide
	for person in people(game):
		if racer.node.position.distance_squared_to(person.pos) > 10000.0: continue
		var station: float = game.race_station(person.pos)
		var gap: float = station - racer.s
		if gap < -3.0 or gap > 70.0: continue
		var centre: Vector3 = game.race_at(station)
		if absf(person.pos.y - centre.y) > 4.0: continue
		var line: float = (person.pos - centre).dot(game.race_side(station))
		# Stop before anyone in the swept lateral corridor; do not steer around
		# a person who is crossing or lying on the carriageway.
		if line < minf(current, plan.line) - PERSON_CLEARANCE or line > maxf(current, plan.line) + PERSON_CLEARANCE: continue
		var is_assigned_casualty = racer.get("role", "") == "ambulance" and str(racer.get("target_key", "")) != "" and str(person.get("key", "")) == str(racer.get("target_key", ""))
		if racer.get("role", "") == "ambulance" and str(person.get("key", "")).begins_with("villager:"):
			var detour = _pedestrian_detour(game, racer, plan, gap)
			if detour != INF:
				plan.line = detour
				plan.speed = minf(float(plan.speed), 6.0)
				plan.can_pass = true
				plan.avoiding = true
				continue
		plan.speed = minf(plan.speed, sqrt(2.0 * 18.0 * maxf(0.0, gap - 5.0)))
		plan.advance = minf(float(plan.get("advance", INF)), maxf(0.0, gap - 4.0))
		if is_assigned_casualty:
			# The ambulance must be allowed to move onto the shoulder toward its
			# own patient; the swept service guard still prevents contact.
			plan.can_pass = true
			continue
		# A departing ambulance may move sideways into its planned clear lane
		# while forward travel stays blocked. The swept guard validates each step.
		var passing = racer.get("role", "") == "ambulance" and float(racer.get("target_s", -1.0)) < 0.0 and plan.get("can_pass", false)
		if not passing:
			plan.line = racer.line
			plan.can_pass = false
	return scenery_plan(game, racer, plan)

static func scenery_plan(game, racer: Dictionary, plan: Dictionary) -> Dictionary:
	var previous: Vector3 = racer.node.position
	var obstacle_ahead = -1.0
	for i in range(1, 13):
		var ahead = i * 5.0
		var station: float = minf(game.stage.LENGTH - 0.01, racer.s + ahead)
		var line = lerpf(float(racer.line), float(plan.line), smoothstep(0.0, 26.0, ahead))
		var point: Vector3 = game.race_at(station) + game.race_side(station) * line
		point.y = game.stage.ground(point)
		if not game.stage.rock_hit(previous, point, 1.1).is_empty() or game.stage.obstacle_hit(previous, point, 1.1, true) >= 0 or not game.stage.solids.hit(previous, point, 1.1).is_empty():
			obstacle_ahead = ahead
			break
		previous = point
	if obstacle_ahead >= 0.0 and racer.get("role", "") == "ambulance":
		var distance = clampf(obstacle_ahead + 18.0, 18.0, 75.0)
		var current = float(racer.get("line", 0.0)) + float(racer.get("slide", 0.0))
		var limit: float = game.stage.road_width(racer.s) * 0.5 + game.stage.shoulder(racer.s)
		var candidates: Array[float] = [float(plan.line)]
		for offset in [1.5, 2.5, 3.5, 4.5, 5.5]:
			candidates.append(clampf(float(plan.line) - offset, -limit + 0.7, limit - 0.7))
			candidates.append(clampf(float(plan.line) + offset, -limit + 0.7, limit - 0.7))
		var chosen = INF
		var best = INF
		for candidate in candidates:
			if absf(candidate - current) < 0.1 or not _detour_clear(game, racer, candidate, distance):
				continue
			var cost = absf(candidate - float(plan.line)) + absf(candidate - current) * 0.25
			if cost < best:
				best = cost
				chosen = candidate
		if chosen != INF:
			plan.line = chosen
			plan.speed = minf(float(plan.speed), 6.0)
			plan.can_pass = true
			plan.avoiding = true
			return plan
	var room = maxf(0.0, obstacle_ahead - 7.0)
	if obstacle_ahead >= 0.0:
		plan.speed = minf(float(plan.speed), sqrt(2.0 * 18.0 * room))
		plan.advance = minf(float(plan.get("advance", INF)), room)
	return plan

static func _detour_clear(game, racer: Dictionary, target_line: float, distance: float) -> bool:
	var start: Vector3 = racer.node.position
	var previous = start
	var current = float(racer.get("line", 0.0)) + float(racer.get("slide", 0.0))
	var target_key = str(racer.get("target_key", ""))
	for i in range(1, 7):
		var ahead = distance * i / 6.0
		var station: float = minf(game.stage.LENGTH - 0.01, racer.s + ahead)
		var line = lerpf(current, target_line, smoothstep(0.0, minf(14.0, distance * 0.45), ahead))
		var point: Vector3 = game.race_at(station) + game.race_side(station) * line
		point.y = game.stage.ground(point)
		if absf(line) > game.stage.road_width(station) * 0.5 + game.stage.shoulder(station) + 0.5:
			return false
		if not game.stage.rock_hit(previous, point, 1.1).is_empty() or game.stage.obstacle_hit(previous, point, 1.1, true) >= 0 or not game.stage.solids.hit(previous, point, 1.1).is_empty():
			return false
		if game.stage.water != null and game.stage.water.depth(point) > 0.2:
			return false
		for person in people(game):
			if str(person.get("key", "")) == target_key:
				continue
			if approaching_hit(previous + Vector3(0, 0.7, 0), point + Vector3(0, 0.7, 0), person.pos + Vector3(0, 0.7, 0), PERSON_CLEARANCE):
				return false
		for car in cars(game, racer):
			if approaching_hit(previous + Vector3(0, 0.7, 0), point + Vector3(0, 0.7, 0), car + Vector3(0, 0.7, 0), CAR_CLEARANCE):
				return false
		previous = point
	return true

static func _pedestrian_detour(game, racer: Dictionary, plan: Dictionary, gap: float) -> float:
	var distance = clampf(gap + 14.0, 18.0, 36.0)
	var base = float(plan.line)
	var current = float(racer.get("line", 0.0)) + float(racer.get("slide", 0.0))
	var station: float = minf(game.stage.LENGTH - 0.01, racer.s + distance)
	var limit: float = game.stage.road_width(station) * 0.5 + game.stage.shoulder(station) - 0.7
	var chosen = INF
	var best = INF
	for offset in [2.8, 3.8, 4.8, 5.8]:
		for candidate in [base - offset, base + offset]:
			if absf(candidate) > limit or not _detour_clear(game, racer, candidate, distance):
				continue
			var cost = absf(candidate - base) + absf(candidate - current) * 0.25
			if cost < best:
				best = cost
				chosen = candidate
	return chosen

# ---------------------------------------------------------------- priority

# Line for an ambulance with right of way: the nearest line to the planned one
# that keeps clear of people and water, preferring lines that also clear the
# cars. Only people can hold it; without a person-safe line it waits.
static func priority_plan(game, racer: Dictionary, plan: Dictionary) -> Dictionary:
	var current = float(racer.get("line", 0.0)) + float(racer.get("slide", 0.0))
	var station: float = game.race_station(racer.node.position)
	var road = game.stage.LENGTH - station if game.course.pass_index == 2 else station
	var limit: float = game.stage.road_width(road) * 0.5 + game.stage.shoulder(road) + 1.0
	var candidates: Array[float] = [float(plan.line), current, 0.0]
	var step = -limit
	while step <= limit:
		candidates.append(step)
		step += 0.5
	var speed = minf(PRIORITY_SPEED, minf(maxf(game.race_speed(racer.s), 1.0), game.injuries.ambulance_speed(racer, racer.s)))
	for avoid_cars in [true, false]:
		var chosen = INF
		var best = INF
		for candidate in candidates:
			var cost = absf(candidate - float(plan.line)) * 0.5 + absf(candidate - current) * 0.25
			if cost < best and _priority_clear(game, racer, candidate, 24.0, avoid_cars):
				best = cost
				chosen = candidate
		if chosen != INF:
			var turning = absf(chosen - current) > 1.0
			return {"line": chosen, "speed": minf(speed, 3.0) if turning else speed, "avoiding": true, "advance": INF, "can_pass": true, "lateral_rate": 1.5}
	# No line forward keeps clear of people: stop and edge sideways to the
	# widest gap between them, so a line opens as soon as there is room.
	return {"line": _widest_gap(game, racer, candidates), "speed": 0.0, "avoiding": true, "advance": 0.0, "can_pass": true, "lateral_rate": 1.0}

static func _widest_gap(game, racer: Dictionary, candidates: Array[float]) -> float:
	var current = float(racer.get("line", 0.0)) + float(racer.get("slide", 0.0))
	var lines: Array[float] = []
	for person in people(game):
		var station: float = game.race_station(person.pos)
		if str(person.get("key", "")) == str(racer.get("target_key", "")) or station - float(racer.s) < -3.0 or station - float(racer.s) > 14.0:
			continue
		lines.append((person.pos - game.race_at(station)).dot(game.race_side(station)))
	var chosen = current
	var widest = -INF
	for candidate in candidates:
		var room = INF
		for line in lines:
			room = minf(room, absf(candidate - line))
		if room > widest + 0.01 or (is_equal_approx(room, widest) and absf(candidate - current) < absf(chosen - current)):
			widest = room
			chosen = candidate
	return chosen

static func _priority_clear(game, racer: Dictionary, target_line: float, distance: float, avoid_cars: bool) -> bool:
	var previous: Vector3 = racer.node.position
	var current = float(racer.get("line", 0.0)) + float(racer.get("slide", 0.0))
	var target_key = str(racer.get("target_key", ""))
	var lift = Vector3(0, 0.7, 0)
	var blocking_cars = cars(game, racer) if avoid_cars else []
	var standing = people(game).filter(func(person): return str(person.get("key", "")) != target_key and person.pos.distance_squared_to(previous) < 3600.0)
	for i in range(1, 7):
		var ahead = distance * i / 6.0
		var progress: float = minf(game.stage.LENGTH - 0.01, racer.s + ahead)
		var line = lerpf(current, target_line, smoothstep(0.0, distance * 0.6, ahead))
		var point: Vector3 = game.race_at(progress) + game.race_side(progress) * line
		point.y = game.stage.ground(point)
		if game.stage.water != null and game.stage.water.depth(point) > 0.2:
			return false
		for person in standing:
			if approaching_hit(previous + lift, point + lift, person.pos + lift, PERSON_CLEARANCE + 0.5):
				return false
		for car in blocking_cars:
			if approaching_hit(previous + lift, point + lift, car + lift, CAR_CLEARANCE):
				return false
		previous = point
	return true
