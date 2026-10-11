extends RefCounted
# Service vehicles yield to people and retain a swept safety stop even when a
# pedestrian steps into the route after the look-ahead plan was calculated.
const Motion = preload("res://scripts/vehicle_motion.gd")
const PERSON_CLEARANCE = 2.2
const CAR_CLEARANCE = 3.1

static func applies(racer: Dictionary) -> bool:
	return racer.get("role", "racer") in ["ambulance", "opening_police", "closing_police"]

static func people(game) -> Array:
	var result = game.injuries.people()
	# Injured people can be displaced from their ordinary walking positions.
	for record in game.injuries.records.values():
		if record.has("pos"):
			result.append({"pos": record.pos})
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

static func pedestrian_plan(game, racer: Dictionary, plan: Dictionary) -> Dictionary:
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
		plan.speed = minf(plan.speed, sqrt(2.0 * 18.0 * maxf(0.0, gap - 5.0)))
		plan.advance = minf(float(plan.get("advance", INF)), maxf(0.0, gap - 4.0))
		plan.line = racer.line
		plan.can_pass = false
	return scenery_plan(game, racer, plan)

static func scenery_plan(game, racer: Dictionary, plan: Dictionary) -> Dictionary:
	var previous: Vector3 = racer.node.position
	for i in range(1, 13):
		var ahead = i * 5.0
		var station: float = minf(game.stage.LENGTH - 0.01, racer.s + ahead)
		var line = lerpf(float(racer.line), float(plan.line), smoothstep(0.0, 26.0, ahead))
		var point: Vector3 = game.race_at(station) + game.race_side(station) * line
		point.y = game.stage.ground(point)
		if not game.stage.rock_hit(previous, point, 1.1).is_empty() or game.stage.obstacle_hit(previous, point, 1.1, true) >= 0 or not game.stage.solids.hit(previous, point, 1.1).is_empty():
			var room = maxf(0.0, ahead - 7.0)
			plan.speed = minf(plan.speed, sqrt(2.0 * 18.0 * room))
			plan.advance = minf(float(plan.get("advance", INF)), room)
			break
		previous = point
	return plan
