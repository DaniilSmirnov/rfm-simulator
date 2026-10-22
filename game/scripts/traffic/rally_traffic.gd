extends RefCounted
# Host-side rally line selection. Guests consume the existing pose snapshots.
const Hitbox = preload("res://scripts/cars/car_hitbox.gd")
const Tracks = preload("res://scripts/traffic/rally_tracks.gd")
const ServiceTraffic = preload("res://scripts/traffic/service_traffic.gd")
const Injuries = preload("res://scripts/people/injuries.gd")
const CarRegistry = preload("res://scripts/cars/car_registry.gd")
const CLEARANCE = 2.85
const MAX_LINE = 3.05
const BRAKE = 18.0
# Crews and zero cars brake on their tyres (rally_driver.gd): plan stops
# behind a blocker at what gravel gives.
const CREW_BRAKE = 7.0
# Every car shares the top speed; bends keep the speeds tuned for 140 km/h.
const MAX_COMPETITION_SPEED = CarRegistry.TOP_SPEED
const CORNER_SPEED = 140.0 / 3.6
const MIN_CORNER_TARGET = 16.0
const CORNER_FULL_EFFECT = 0.35
const SPEED_LOOKAHEAD = [0.0, 16.0, 32.0, 48.0]
# Straights above CORNER_SPEED need a braking zone before the next bend:
# bends this far ahead (m) limit the speed through PLAN_BRAKE (m/s²).
const BRAKE_LOOKAHEAD = 150.0
const BRAKE_STEP = 10.0
const PLAN_BRAKE = 8.0
# A driver with no nerve for braking takes every bend up to this much faster
# than the safe speed; a bold one often runs wide and leaves the road.
const BEND_OVERSHOOT = 0.3
# Lateral allowance (m) when skipping far objects before projecting them.
const FAR_MARGIN = 40.0
# Travel (m) over which obstacle probes along a passing line are reused.
# A route probe is a conservative static-world check. Refreshing every couple
# of metres made each racer redo six collision sweeps for every candidate lane;
# the age limit below still picks up moved props while allowing the indexed
# stage queries to be reused across several frames.
const PROBE_REFRESH = 8.0
# Seconds a probe is kept even without travel: a car waiting behind a
# momentary obstruction must see the road clear again.
const PROBE_MAX_AGE = 0.5
# Seconds a chosen passing line is kept before candidates are re-scored.
const LANE_INTERVAL = 0.12
# Metres added each side of a service vehicle's exact footprint when probing.
const EXACT_MARGIN = 0.3

static func profile(id: int) -> Dictionary:
	return {"bias": sin(id * 1.91) * 0.55, "phase": fmod(id * 2.37, TAU), "pace": 0.96 + fmod(id * 0.618, 1.0) * 0.08}

# How much of the braking for bends and abrupt drops a driver skips, 0..1,
# fixed per driver: about 40% brake properly, 35% brake too little or too late, 25% do
# not lift at all and meet the landing and the corner after it at speed.
static func nerve(id: int) -> float:
	var h = fposmod(sin(id * 78.233 + 12.9898) * 43758.5453, 1.0)
	if h < 0.4:
		return 0.0
	if h < 0.75:
		return lerpf(0.35, 0.75, (h - 0.4) / 0.35)
	return 1.0

static func nominal(racer: Dictionary, s: float) -> float:
	return racer.get("bias", 0.0) + sin(s / 34.0 + racer.get("phase", 0.0)) * 0.24 + sin(s / 71.0 + racer.get("phase", 0.0) * 1.7) * 0.12

static func competition_target(stage: Node3D, progress: float, pace: float = 1.0, reverse: bool = false, nerve_share: float = 0.0) -> float:
	var station = stage.length - progress if reverse else progress
	var travel_sign = -1.0 if reverse else 1.0
	# Braking envelope: arrive at every bend ahead no faster than its speed.
	var target = INF
	var ahead = 0.0
	while ahead <= BRAKE_LOOKAHEAD:
		var bend = _bend_target(stage, clampf(station + travel_sign * ahead, 0.0, stage.length - 0.01), travel_sign)
		var taken = bend * (1.0 + BEND_OVERSHOOT * nerve_share)
		target = minf(target, sqrt(taken * taken + 2.0 * PLAN_BRAKE * ahead))
		ahead += BRAKE_STEP
	# A driver short on braking carries speed through the drop zone.
	if nerve_share > 0.0 and not reverse:
		var zone: Vector2 = stage.biome.jump_zone()
		if station >= zone.x and station <= zone.y:
			target = lerpf(target, MAX_COMPETITION_SPEED, nerve_share)
	return clampf(target * pace, 0.0, MAX_COMPETITION_SPEED)

# Speed (m/s) through the station itself, from the tightest bend of the next
# 48 m; a straight gets the top speed. Cached per metre on the stage.
static func _bend_target(stage: Node3D, station: float, travel_sign: float) -> float:
	var key = "bend_targets_rev" if travel_sign < 0 else "bend_targets"
	if not stage.has_meta(key):
		var empty: Array = []
		empty.resize(int(stage.length) + 1)
		empty.fill(-1.0)
		stage.set_meta(key, empty)
	# An Array is shared by reference, so filling it in place updates the cache.
	var table: Array = stage.get_meta(key)
	var index = clampi(int(station), 0, table.size() - 1)
	if float(table[index]) >= 0.0:
		return float(table[index])
	var worst_corner = 0.0
	for lookahead in SPEED_LOOKAHEAD:
		var center = clampf(index + travel_sign * lookahead, 0.0, stage.length - 0.01)
		var before = stage.direction(maxf(0.0, center - 6.0))
		var after = stage.direction(minf(stage.length - 0.01, center + 6.0))
		worst_corner = maxf(worst_corner, acos(clampf(before.dot(after), -1.0, 1.0)))
	var corner_factor = clampf(worst_corner / CORNER_FULL_EFFECT, 0.0, 1.0)
	var geometry_target = lerpf(CORNER_SPEED, MIN_CORNER_TARGET, pow(corner_factor, 0.75))
	# Tight village junctions need a lower entry speed than flowing bends.
	geometry_target = minf(geometry_target, lerpf(MIN_CORNER_TARGET, 7.0, smoothstep(0.7, 1.3, worst_corner))) if worst_corner > 0.7 else geometry_target
	# Only a (nearly) straight road opens up to the shared top speed.
	geometry_target += (MAX_COMPETITION_SPEED - CORNER_SPEED) * pow(1.0 - clampf(corner_factor / 0.25, 0.0, 1.0), 2.0)
	table[index] = geometry_target
	return geometry_target

# After the flying finish crews slow down to roll into the service park.
const PARK_ENTRY_SPEED = 8.0
const PARK_BRAKE = 5.0

static func speed_limit(game: Node3D, racer: Dictionary, s: float) -> float:
	return minf(_speed_limit(game, racer, s), sqrt(PARK_ENTRY_SPEED * PARK_ENTRY_SPEED + 2.0 * PARK_BRAKE * maxf(0.0, game.stage.length - s)))

static func _speed_limit(game: Node3D, racer: Dictionary, s: float) -> float:
	var role = str(racer.get("role", "racer"))
	if role in ["racer", "zero"]:
		var reference = Tracks.sample(racer.get("track_parts", PackedInt32Array()), s, game.course.pass_index == 2, role == "zero")
		var target = minf(MAX_COMPETITION_SPEED, float(reference.speed) * racer.get("pace", 1.0)) if not reference.is_empty() else competition_target(game.stage, s, racer.get("pace", 1.0), game.course.pass_index == 2, float(racer.get("nerve", 0.0)))
		return recovery_speed(target, racer) if role == "racer" else target
	var cap = Injuries.ambulance_speed(racer, s) if role == "ambulance" else INF
	return minf(maxf(0.0, game.race_speed(s) * racer.get("pace", 1.0)), cap)

const SLIDE_SLACK = 0.6
const SLIDE_RATE_SLACK = 0.8

static func recovery_speed(target: float, racer: Dictionary) -> float:
	# Lift off progressively when the car runs wide of its line, then regain
	# pace as it settles. A crew on the tyre model always sits a little off
	# its line, so the first SLIDE_SLACK metres and m/s cost nothing.
	var loss = maxf(0.0, absf(float(racer.get("slide", 0.0))) - SLIDE_SLACK) * 0.22 + maxf(0.0, absf(float(racer.get("slide_speed", 0.0))) - SLIDE_RATE_SLACK) * 0.12
	return target * clampf(1.0 - loss, 0.5, 1.0)

static func line_limit(game, progress: float) -> float:
	var station: float = game.stage.length - progress if game.course.pass_index == 2 else progress
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
	if absf(racer.s - float(racer.get("cut_station", -100.0))) > 2.0 or racer.age - float(racer.get("cut_age", -INF)) > PROBE_MAX_AGE:
		racer.cut_age = racer.age
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
	# Authored parked cars have solid bodies too; the full bumper can reach
	# them while the old centre circle was still clear. Plan around them.
	var parked: Dictionary = stage.get_meta("traffic_parked_solids", {})
	if parked.get("count", -1) != stage.solids.obstacles.size():
		parked = {"count": stage.solids.obstacles.size(), "objects": stage.solids.obstacles.filter(func(object): return object.kind == "parked_car")}
		stage.set_meta("traffic_parked_solids", parked)
	for object in parked.objects:
		if is_instance_valid(object.body):
			positions.append({"pos": stage.solids.relative_pose(object.body).origin, "speed": 0.0})
	# Once treatment is complete, an ambulance must safely pass people
	# still standing near the scene instead of remaining red-flagged forever.
	if racer.get("role", "") == "ambulance" and float(racer.get("target_s", -1.0)) < 0.0:
		for person in ServiceTraffic.people(game, racer):
			positions.append({"pos": person.pos, "speed": 0.0})
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
	var clearance = ServiceTraffic.CAR_CLEARANCE + 0.3 if ServiceTraffic.applies(racer) else CLEARANCE
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
		var offset: Vector3 = object.pos - center
		var lateral: float = offset.dot(game.race_side(station))
		if absf(lateral) > line_limit(game, station) + CLEARANCE:
			continue
		# Behind the start or past the finish the projection clamps to the
		# route's end: a car further along the park's aisle is not on the road.
		if Vector2(offset.x, offset.z).length_squared() > lateral * lateral + 9.0:
			continue
		# Clear of both the line the crew holds and the one it means to drive
		# (a spectator's car on the verge, a car in the park beside the start):
		# no reason to leave the racing line and look for a way round.
		if lateral < minf(current, base) - clearance or lateral > maxf(current, base) + clearance:
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
	# Holding the present line is a candidate too: a parked car on the pavement
	# can be too close to the planned line yet clear of the one driven now, and
	# with no other line open in a narrow street the crew would stop beside it.
	var candidates = [base, clampf(current, -reach, reach), -minf(2.95, reach), minf(2.95, reach), -minf(1.5, reach), minf(1.5, reach)]
	# Police and ambulance also try the lines that just clear each blocker:
	# beside a car parked before a narrow bridge, a fixed passing line can be
	# too far out for the bridge and the racing line too close to the car.
	if ServiceTraffic.applies(racer):
		for blocker in blockers:
			for side in [-1.0, 1.0]:
				var edge = float(blocker.line) + side * (clearance + 0.05)
				if absf(edge) <= reach:
					candidates.append(edge)
	if racer.get("role", "") == "ambulance":
		reach += 2.0 # Search the verge too; terrain/solid probes must approve it.
		for edge in [reach, maxf(0.0, reach - 0.75), maxf(0.0, reach - 1.5)]:
			candidates.append(-edge)
			candidates.append(edge)
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
				if absf(candidate - blocker.line) < clearance:
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
	var speed = minf(limit, 6.0) if racer.get("role", "") == "ambulance" and absf(chosen) > 2.95 else limit
	var advance = INF
	# Brake until the actual lateral position clears the obstruction. Retain
	# "racing" while waiting, so towing the blocker lets the queue restart.
	for blocker in blockers:
		if blocker.gap >= 0 and (best == INF or absf(current - blocker.line) < clearance):
			var safe = sqrt(2 * (CREW_BRAKE if racer.get("role", "racer") in ["racer", "zero"] else BRAKE) * maxf(0, blocker.gap - 8))
			speed = minf(speed, safe)
			advance = minf(advance, maxf(0, blocker.gap - 7))
	if best == INF:
		chosen = current
	return {"line": chosen, "speed": speed, "avoiding": true, "advance": advance, "can_pass": best != INF}

# Rocks, trees and walls barely change while a crew covers two metres, so
# probe results are reused over that distance, like the corner-cut probe.
static func _clear_path_cached(game, racer: Dictionary, target: float, distance: float) -> bool:
	var probes: Dictionary = racer.get("path_probes", {})
	if absf(racer.s - float(probes.get("s", -100.0))) > PROBE_REFRESH or absf(float(racer.line) - float(probes.get("line", INF))) > 0.2 or racer.age - float(probes.get("age", -INF)) > PROBE_MAX_AGE:
		probes = {"s": racer.s, "line": racer.line, "age": racer.age}
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
	var box = Hitbox.bounds(racer.node)
	# Route planning only needs a conservative clearance envelope. The full
	# oriented-box SAT is still used when a car moves, but probing six segments
	# for every passing candidate with it made the 120 Hz traffic update scale
	# poorly with the number of racers. A circumscribed footprint keeps the
	# route safe while reusing the stage's indexed, scalar collision queries.
	var route_radius = maxf(box.size.x, box.size.z) * 0.5 + 0.15
	for i in range(1, 7):
		var ahead = distance * i / 6.0
		var s: float = minf(stage.length - 0.01, racer.s + ahead)
		var line = lerpf(current, target, smoothstep(0, minf(26, distance * 0.65), ahead))
		var point = game.race_at(s) + game.race_side(s) * line
		point.y = stage.ground(point)
		if racer.get("role", "") == "ambulance":
			if absf(line) > line_limit(game, s) + 1.2: return false
			if absf(point.y - previous.y) > maxf(0.5, point.distance_to(previous) * 0.45): return false
			if ServiceTraffic.flooded(game, point, s): return false
		var route_blocked = not stage.rock_hit(previous, point, route_radius).is_empty() or stage.obstacle_hit(previous, point, route_radius, true) >= 0
		# Police and ambulance passes use the exact footprint: the wider scalar
		# envelope would reject a valid verge gap beside a stopped car, or a
		# line round a car parked just before the narrow Поречье bridge.
		# The probe is a little wider than the car: a car still turning onto
		# the line sweeps wider than one already holding it.
		var exact = ServiceTraffic.applies(racer)
		if exact:
			var direction: Vector3 = point - previous
			var shape = Hitbox.shape(AABB(box.position - Vector3(EXACT_MARGIN, 0, 0), box.size + Vector3(EXACT_MARGIN * 2.0, 0, 0)), atan2(-direction.x, -direction.z))
			route_blocked = not Hitbox.rocks(stage, previous, point, shape).is_empty() or Hitbox.tree(stage, previous, point, shape) >= 0 or not Hitbox.solids(stage.solids, previous, point, shape, []).is_empty()
		if route_blocked:
			return false
		if not exact and not stage.solids.hit(previous, point, route_radius).is_empty():
			return false
		previous = point
	return true
