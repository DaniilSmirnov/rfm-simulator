extends RefCounted
# Fixed-tick flight shared by local play, prediction and host authority.
# A released height control hovers; W/S translate, A/D yaw, Space/Shift lift.
const Hitbox = preload("res://scripts/cars/car_hitbox.gd")
const TOP_SPEED = 24.0
const CLIMB_SPEED = 5.0
const CEILING = 90.0

static func floor_at(stage, point: Vector3, yaw: float) -> float:
	var surface: Callable = stage.vehicle_ground if stage.has_method("vehicle_ground") else stage.ground
	var height: float = surface.call(point)
	for x in [-1.2, 1.2]:
		for z in [-2.1, 2.1]:
			var foot = point + Vector3(x, 0, z).rotated(Vector3.UP, yaw)
			height = maxf(height, surface.call(foot))
	return height + 0.06

static func step(solver, command: Dictionary, stage, model: int, dt: float) -> void:
	var motion = solver.motion
	var node: Node3D = solver.node
	var start = node.position
	var floor_height = floor_at(stage, start, solver.yaw)
	if not motion.initialized:
		node.position.y = maxf(start.y, floor_height)
		start = node.position
		motion.initialized = true
	var wrecked: bool = solver.condition <= 0
	var old_yaw: float = solver.yaw
	solver.yaw = wrapf(solver.yaw - (0.0 if wrecked else float(command.steer)) * 0.85 * dt, -PI, PI)
	var lift = -0.6 if wrecked else clampf(float(command.get("lift", 0)), -1, 1)
	motion.vertical_speed = move_toward(motion.vertical_speed, lift * CLIMB_SPEED, dt * 8.0)
	var forward = Vector3(-sin(solver.yaw), 0, -cos(solver.yaw))
	var flying = start.y > floor_height + 0.15 or lift > 0
	var target = forward * float(command.throttle) * TOP_SPEED if flying and not wrecked else Vector3.ZERO
	motion.velocity = motion.velocity.move_toward(target, dt * 6.0)
	motion.velocity.y = motion.vertical_speed
	var next = start + motion.velocity * dt
	next.x = clampf(next.x, -185, 185)
	next.z = clampf(next.z, stage.parks.z_limits.x, stage.parks.z_limits.y)
	next.y = minf(next.y, CEILING + floor_height)
	# Terrain sweeps include skid corners; narrow crests cannot be crossed below ground.
	var samples = maxi(1, int(ceil(start.distance_to(next) / 0.1)))
	for i in range(1, samples + 1):
		var probe = start.lerp(next, float(i) / samples)
		var support = floor_at(stage, probe, solver.yaw)
		if probe.y < support:
			if support > start.y + 0.25:
				next = start
				motion.velocity = Vector3.ZERO
			else:
				next.y = maxf(next.y, support)
			motion.vertical_speed = 0
			break
	var shape = Hitbox.shape(Hitbox.player(model), solver.yaw)
	var blocked = false
	# Yaw in place also sweeps the duct tips conservatively. Test the full
	# proposed box even with zero translation, including overhead scenery.
	var rock = Hitbox.rocks(stage, start, next, shape)
	blocked = not rock.is_empty() or Hitbox.tree(stage, start, next, shape) >= 0
	var solid = Hitbox.solids(stage.solids, start, next, shape, [])
	blocked = blocked or not solid.is_empty()
	for contact in solver.context.get("contacts", []):
		blocked = blocked or Hitbox.blocked(start, next, shape, contact)
	solver.impact_timer = maxf(0, solver.impact_timer - dt)
	if blocked:
		solver.yaw = old_yaw
		if solver.impact_timer <= 0 and motion.velocity.length() > 1:
			solver.condition = maxf(0, solver.condition - minf(18, motion.velocity.length()))
			solver.emit_event({"kind": "impact", "speed": motion.velocity.length()})
			solver.impact_timer = 0.4
		motion.velocity = Vector3.ZERO
		motion.vertical_speed = 0
	else:
		node.position = next
	motion.grounded = node.position.y <= floor_at(stage, node.position, solver.yaw) + 0.09
	motion.pitch = 0
	motion.roll = 0
	node.rotation = Vector3(0, solver.yaw, 0)
