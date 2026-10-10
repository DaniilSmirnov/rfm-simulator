extends RefCounted
# Only departed crews run this controller; route planning is limited to 5 Hz.
const Motion = preload("res://scripts/vehicle_motion.gd")

static func eligible(racer: Dictionary) -> bool:
	return racer.get("role", "racer") in ["racer", "zero"] and racer.kind != "stuck"

static func clear(game, racer: Dictionary, start: Vector3, end: Vector3) -> bool:
	var stage = game.stage
	var previous = start
	var steps = maxi(1, ceili(start.distance_to(end) / 2.0))
	for i in range(1, steps + 1):
		var point = start.lerp(end, float(i) / steps)
		point.y = stage.ground(point) + 0.06
		if absf(point.y - previous.y) > 1.4 or not stage.rock_hit(previous, point, 1.0).is_empty() or stage.obstacle_hit(previous, point, 1.0, true) >= 0:
			return false
		if not stage.solids.hit(previous, point, 1.0).is_empty():
			return false
		previous = point
	var positions = [game.car.position]
	if not game.in_car: positions.append(game.player_position())
	for peer in game.room.peers.values():
		if peer.state != null: positions.append(game.room.v(peer.state.car))
	for group in game.spectators.groups: positions.append(group.car.position)
	for other in game.racers:
		if other.id != racer.id: positions.append(other.node.position)
	for point in positions:
		if absf(point.y - start.y) < 4 and Motion.swept_hit(start, end, point, 3.0): return false
	return true

static func step(game, racer: Dictionary, dt: float) -> bool:
	var node: Node3D = racer.node
	var motion = racer.motion
	racer.rejoin_time = float(racer.get("rejoin_time", 0.0)) + dt
	if racer.rejoin_time > 25.0 or game.stage.road_distance(node.position) > 35.0:
		racer.self_rejoin = false
		return false
	if racer.node == game.tow_target or racer.get("towed", false) or int(racer.get("recovery_helpers", 0)) > 0:
		racer.self_rejoin = false
		return false
	if not motion.grounded: return false
	racer.rejoin_plan = float(racer.get("rejoin_plan", 0.0)) - dt
	if racer.rejoin_plan <= 0:
		racer.rejoin_plan = 0.2
		racer.erase("rejoin_goal")
		var station: float = clampf(game.race_station(node.position), 0, game.stage.LENGTH - 1)
		for ahead in [12.0, 6.0, 20.0, 0.0, -6.0]:
			var target: Vector3 = game.race_at(clampf(station + ahead, 0, game.stage.LENGTH - 1))
			target.y = game.stage.ground(target) + 0.06
			if clear(game, racer, node.position, target):
				racer.rejoin_goal = target
				break
	if not racer.has("rejoin_goal"): return false
	var direction: Vector3 = racer.rejoin_goal - node.position
	direction.y = 0
	var desired = atan2(-direction.x, -direction.z)
	var error = wrapf(desired - node.rotation.y, -PI, PI)
	# Reverse rather than rotate a stationary vehicle on the spot.
	var reversing = absf(error) > 1.8 and racer.rejoin_time < 3.0
	if reversing: error = wrapf(error + PI, -PI, PI)
	var forward = Vector3(-sin(node.rotation.y), 0, -cos(node.rotation.y))
	var signed_speed: float = motion.velocity.dot(forward)
	var target_speed = (-2.5 if reversing else 6.0) * clampf(1.0 - absf(error) * 0.35, 0.25, 1.0)
	var grip: float = game.stage.grip(node.position)
	var braking = absf(signed_speed) > absf(target_speed) or signed_speed * target_speed < 0
	var force = 3.0 + grip * 12.0 if braking else maxf(1.0, grip * 5.0)
	var speed = move_toward(signed_speed, target_speed, force * dt)
	var lateral: Vector3 = motion.velocity - forward * signed_speed
	motion.velocity = forward * speed + lateral.move_toward(Vector3.ZERO, grip * 8.0 * dt)
	var turn = clampf(error * 1.5, -0.8, 0.8) * clampf(absf(speed) / 2.0, 0, 1)
	node.position += motion.velocity * dt
	motion.suspension(node, game.stage, dt, node.rotation.y + turn * dt)
	var station: float = clampf(game.race_station(node.position), 0, game.stage.LENGTH - 1)
	var center: Vector3 = game.race_at(station)
	var offset: float = (node.position - center).dot(game.race_side(station))
	var road_direction: Vector3 = game.race_direction(station)
	var road_yaw = atan2(-road_direction.x, -road_direction.z)
	if absf(offset) < 1.2 and Vector2(node.position.x - center.x, node.position.z - center.z).length() < 1.3 and absf(wrapf(node.rotation.y - road_yaw, -PI, PI)) < 0.3 and speed > 0:
		racer.rejoin_residual = node.position - (center + game.race_side(station) * offset)
		racer.rejoin_residual.y = 0.0
		racer.s = station
		racer.line = offset
		racer.slide = 0.0
		racer.slide_speed = 0.0
		racer.drift_yaw = 0.0
		racer.yaw_rate = 0.0
		racer.drive_speed = speed
		racer.state = "racing"
		racer.kind = "pass"
		racer.age = 0.0
		racer.self_rejoin = false
	return true
