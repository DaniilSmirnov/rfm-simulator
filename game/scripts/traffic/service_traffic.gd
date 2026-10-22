extends RefCounted
# Service vehicles yield to people and retain a swept safety stop even when a
# pedestrian steps into the route after the look-ahead plan was calculated.
const Motion = preload("res://scripts/cars/vehicle_motion.gd")
const PERSON_CLEARANCE = 2.2
const CAR_CLEARANCE = 3.1
# Right of way: an ambulance held this long (s) by anything drives on in
# priority mode for PRIORITY_DISTANCE metres: it keeps away from people, goes
# round cars where the verge allows and otherwise passes through cars, rocks
# and street furniture at walking pace. Nothing but people can stop it.
const PRIORITY_AFTER = 2.5
const PRIORITY_DISTANCE = 30.0
const PRIORITY_SPEED = 5.0
# A police car first asks everybody to clear the road (the blocked notice),
# then takes the same right of way.
const POLICE_PRIORITY_AFTER = 20.0
# Held this long (s), a service vehicle passes players standing in its way
# for PRIORITY_DISTANCE metres: a player who walked away from the keyboard on
# the road cannot hold the course. Other people still hold it.
const PLAYER_PATIENCE = 45.0
const HOLD_DISTANCE = 1.5

static func applies(racer: Dictionary) -> bool:
	return racer.get("role", "racer") in ["ambulance", "opening_police", "closing_police"]

# `racer` passing players (see PLAYER_PATIENCE) leaves standing players out.
static func people(game, racer: Dictionary = {}) -> Array:
	var result: Array = []
	var skip_players = passing_players(racer)
	# Keep injury avatars discoverable for animation, but block service traffic
	# only with standing people and the actual displaced body positions.
	for person in game.injuries.people():
		if skip_players and str(person.key).begins_with("player:"):
			continue
		# Somebody riding on a car is not in the road.
		if not game.injuries.is_down(str(person.key)) and not person.get("riding", false):
			result.append(person)
	# Injured people can be displaced from their ordinary walking positions.
	for key in game.injuries.records:
		var record: Dictionary = game.injuries.records[key]
		if record.has("pos") and str(record.get("phase", "")) != "limp":
			result.append({"key": str(key), "pos": record.pos})
	return result

# A point beyond either end of the road (a player's car in the service park)
# projects onto the end station, as if it stood on the road there. It is in
# the way only when it is level with that end, not some way past it.
static func past_road_end(game, pos: Vector3, progress: float) -> bool:
	if progress > 0.5 and progress < game.stage.length - 0.5:
		return false
	return absf((pos - game.race_at(progress)).dot(game.race_direction(progress))) > 3.0

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
	for person in people(game, racer):
		if approaching_hit(start, end, person.pos, PERSON_CLEARANCE):
			return true
	if priority(racer):
		return false
	for car in cars(game, racer):
		if approaching_hit(start, end, car, CAR_CLEARANCE):
			return true
	return not game.stage.rock_hit(start, end, 1.1).is_empty() or game.stage.obstacle_hit(start, end, 1.1, true) >= 0 or not game.stage.solids.hit(start, end, 1.1).is_empty()

# Water off the carriageway. A ford floods the road itself, so only water
# deeper than on the road centre at that station counts: a van may cross the
# ford on any line but never leaves the road into a lake.
static func flooded(game, point: Vector3, progress: float) -> bool:
	if game.stage.water == null:
		return false
	return game.stage.water.depth(point) > maxf(0.2, game.stage.water.depth(game.race_at(progress)) + 0.2)

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
	return float(racer.get("priority_until", -1.0)) > float(racer.get("s", 0.0))

static func passing_players(racer: Dictionary) -> bool:
	return float(racer.get("players_until", -1.0)) > float(racer.get("s", 0.0))

# Seconds since the vehicle last made HOLD_DISTANCE metres of road (police
# edging sideways is still held; an ambulance rolling at all is not); once
# held long enough it takes
# priority until it is PRIORITY_DISTANCE further on. Police waiting out a red
# flag is not held, and neither is an ambulance parked at a casualty (no plan
# is made then, so the gap in planning restarts the count).
static func _update_hold(game, racer: Dictionary) -> void:
	var police = racer.get("role", "") != "ambulance"
	var gap = racer.age - float(racer.get("plan_age", racer.age))
	racer.plan_age = racer.age
	var rolling = not police and float(racer.get("drive_speed", 0.0)) >= 0.3
	if rolling or absf(float(racer.s) - float(racer.get("hold_s", -100.0))) > HOLD_DISTANCE or gap > 0.5 or gap < 0.0 or (police and game.course.red_flag):
		racer.hold_s = racer.s
		racer.moving_age = racer.age
	var held = racer.age - float(racer.moving_age)
	if not priority(racer) and held >= (POLICE_PRIORITY_AFTER if police else PRIORITY_AFTER):
		racer.priority_until = float(racer.s) + PRIORITY_DISTANCE
		racer.erase("path_probes")
		racer.erase("lane_choice")
	if not passing_players(racer) and held >= PLAYER_PATIENCE:
		racer.players_until = float(racer.s) + PRIORITY_DISTANCE
		racer.priority_until = maxf(float(racer.get("priority_until", -1.0)), float(racer.players_until))

static func pedestrian_plan(game, racer: Dictionary, plan: Dictionary) -> Dictionary:
	_update_hold(game, racer)
	if priority(racer):
		return priority_plan(game, racer, plan)
	var current: float = racer.line + racer.slide
	for person in people(game, racer):
		if racer.node.position.distance_squared_to(person.pos) > 10000.0: continue
		var station: float = game.race_station(person.pos)
		var gap: float = station - racer.s
		if gap < -3.0 or gap > 70.0: continue
		var centre: Vector3 = game.race_at(station)
		if absf(person.pos.y - centre.y) > 4.0 or past_road_end(game, person.pos, station): continue
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
		var station: float = minf(game.stage.length - 0.01, racer.s + ahead)
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
		var station: float = minf(game.stage.length - 0.01, racer.s + ahead)
		var line = lerpf(current, target_line, smoothstep(0.0, minf(14.0, distance * 0.45), ahead))
		var point: Vector3 = game.race_at(station) + game.race_side(station) * line
		point.y = game.stage.ground(point)
		if absf(line) > game.stage.road_width(station) * 0.5 + game.stage.shoulder(station) + 0.5:
			return false
		if not game.stage.rock_hit(previous, point, 1.1).is_empty() or game.stage.obstacle_hit(previous, point, 1.1, true) >= 0 or not game.stage.solids.hit(previous, point, 1.1).is_empty():
			return false
		if flooded(game, point, station):
			return false
		for person in people(game, racer):
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
	var station: float = minf(game.stage.length - 0.01, racer.s + distance)
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

# Line for a service vehicle with right of way: the nearest line to the planned one
# that keeps clear of people and water, preferring lines that also clear the
# cars. Only people can hold it; without a person-safe line it waits.
static func priority_plan(game, racer: Dictionary, plan: Dictionary) -> Dictionary:
	var current = float(racer.get("line", 0.0)) + float(racer.get("slide", 0.0))
	var station: float = game.race_station(racer.node.position)
	var road = game.stage.length - station if game.course.pass_index == 2 else station
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
	for person in people(game, racer):
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
	var standing = people(game, racer).filter(func(person): return str(person.get("key", "")) != target_key and person.pos.distance_squared_to(previous) < 3600.0)
	for i in range(1, 7):
		var ahead = distance * i / 6.0
		var progress: float = minf(game.stage.length - 0.01, racer.s + ahead)
		var line = lerpf(current, target_line, smoothstep(0.0, distance * 0.6, ahead))
		var point: Vector3 = game.race_at(progress) + game.race_side(progress) * line
		point.y = game.stage.ground(point)
		if flooded(game, point, progress):
			return false
		for person in standing:
			if approaching_hit(previous + lift, point + lift, person.pos + lift, PERSON_CLEARANCE + 0.5):
				return false
		for car in blocking_cars:
			if approaching_hit(previous + lift, point + lift, car + lift, CAR_CLEARANCE):
				return false
		previous = point
	return true
