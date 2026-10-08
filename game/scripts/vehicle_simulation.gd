extends RefCounted
const Motion = preload("res://scripts/vehicle_motion.gd")

static func advance(solver, c: Dictionary, stage, model: int) -> void:
	if c.get("recover", false) and not solver.context.get("racing", false):
		solver.recovery_ack = int(c.seq)
		solver.node.position = stage.at(stage.road_s(solver.node.position))
		var direction = stage.direction(stage.road_s(solver.node.position))
		solver.yaw = atan2(-direction.x, -direction.z)
		solver.motion = Motion.new()
		solver.visual_offset = Vector3.ZERO
		solver.visual_yaw = 0.0
	var dt = solver.motion.handling.STEP
	for tick in range(int(c.ticks)):
		if solver.condition <= 0:
			break
		var previous = solver.node.position
		var old_yaw = solver.yaw
		var offroad = stage.road_distance(previous) > 4.1
		solver.yaw = solver.motion.handling.advance(solver.motion, solver.yaw, c.throttle, c.steer, c.brake, stage.grip(previous), 7.0 if offroad else 19.0, model, dt)
		var forward = Vector3(-sin(solver.yaw), 0, -cos(solver.yaw))
		var next = previous + solver.motion.velocity * dt
		next.x = clampf(next.x, -185, 185)
		next.z = clampf(next.z, -stage.LENGTH + 5, 10)
		solver.impact_timer = maxf(0, solver.impact_timer - dt)
		var rock = stage.rock_hit(previous, next, 0.85)
		if not rock.is_empty():
			next = rock.position
			var closing = solver.motion.rock_impulse(rock.normal, solver.yaw)
			if closing > 1 and solver.impact_timer <= 0:
				solver.condition = maxf(0, solver.condition - minf(14, closing * 0.65))
				solver.impact_timer = 0.4
				solver.emit_event({"kind": "impact", "speed": closing})
		if stage.urban:
			var city = stage.city.hit(previous, next, 0.85)
			if not city.is_empty():
				next = city.position
				solver.emit_event({"kind": "city", "hit": city, "velocity": solver.motion.velocity})
				var closing = solver.motion.rock_impulse(city.normal, solver.yaw)
				if closing > 1 and solver.impact_timer <= 0:
					solver.condition = maxf(0, solver.condition - minf(20, closing * 0.85))
					solver.impact_timer = 0.4
					solver.emit_event({"kind": "impact", "speed": closing})
		var tree = stage.obstacle_hit(previous, next, 0.95, true)
		var blocked = tree >= 0
		if blocked and solver.motion.velocity.length() > 5 and not stage.fallen.has(tree):
			solver.emit_event({"kind": "tree", "index": tree, "velocity": solver.motion.velocity})
		for contact in solver.context.get("contacts", []):
			var other: Vector3 = contact.position
			var radius = 1.55 if contact.get("person", false) else 2.5
			if Motion.swept_hit(previous + Vector3(0, 0.7, 0), next + Vector3(0, 0.7, 0), other + Vector3(0, 0.7, 0), radius) and next.distance_to(other) <= previous.distance_to(other):
				blocked = true
				if contact.get("person", false) and absf(solver.motion.velocity.dot(forward)) > 5:
					solver.emit_event({"kind": "person"})
		if blocked:
			solver.condition = maxf(0, solver.condition - solver.motion.velocity.length() * 1.4)
			solver.emit_event({"kind": "impact", "speed": solver.motion.velocity.length()})
			solver.motion.velocity *= -0.25
		else:
			solver.node.position = next
		var speed = solver.motion.velocity.dot(forward)
		solver.motion.suspension(solver.node, stage, dt, solver.yaw, (solver.yaw - old_yaw) / dt * speed)
		if offroad and absf(speed) > 5:
			solver.condition = maxf(0, solver.condition - dt * 0.15)
