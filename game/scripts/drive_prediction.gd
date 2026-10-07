extends RefCounted
const Motion = preload("res://scripts/vehicle_motion.gd")
const LIMIT = 96
var motion = Motion.new()
var node = Node3D.new()
var yaw = 0.0
var seq = 0
var ack = 0
var pending: Array[Dictionary] = []
var visual_offset = Vector3.ZERO
var active = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		node.free()

func reset(position: Vector3, heading: float) -> void:
	node.position = position
	yaw = heading
	motion = Motion.new()
	pending.clear()
	seq = 0
	ack = 0
	visual_offset = Vector3.ZERO
	active = true

func snapshot() -> Dictionary:
	return {"ack": ack, "pos": [node.position.x, node.position.y, node.position.z], "yaw": yaw, "velocity": [motion.velocity.x, motion.velocity.y, motion.velocity.z], "vertical": motion.vertical_speed, "initialized": motion.initialized, "grounded": motion.grounded, "pitch": motion.pitch, "roll": motion.roll, "steering": motion.handling.steering, "yaw_rate": motion.handling.yaw_rate, "longitudinal": motion.handling.longitudinal_accel}

func restore(s: Dictionary) -> void:
	node.position = Vector3(s.pos[0], s.pos[1], s.pos[2])
	yaw = s.yaw
	motion.velocity = Vector3(s.velocity[0], s.velocity[1], s.velocity[2])
	motion.vertical_speed = s.vertical
	motion.grounded = s.grounded
	motion.initialized = bool(s.get("initialized", true))
	motion.pitch = s.pitch
	motion.roll = s.roll
	motion.handling.steering = s.steering
	motion.handling.yaw_rate = s.yaw_rate
	motion.handling.longitudinal_accel = s.longitudinal
	node.rotation = Vector3(motion.pitch, yaw, motion.roll)
	ack = int(s.ack)

func step(c: Dictionary, stage, model: int) -> void:
	var dt = motion.handling.STEP
	for tick in range(int(c.ticks)):
		var previous = node.position
		var old_yaw = yaw
		yaw = motion.handling.advance(motion, yaw, c.throttle, c.steer, c.brake, stage.grip(previous), 7.0 if stage.road_distance(previous) > 4.1 else 19.0, model, dt)
		var next = previous + motion.velocity * dt
		next.x = clampf(next.x, -185, 185)
		next.z = clampf(next.z, -stage.LENGTH + 5, 10)
		var hit = stage.rock_hit(previous, next, 0.85)
		if stage.urban and hit.is_empty():
			hit = stage.city.hit(previous, next, 0.85)
		if not hit.is_empty():
			next = hit.position
			motion.rock_impulse(hit.normal, yaw)
		if stage.obstacle_hit(previous, next, 0.95, true) >= 0:
			motion.velocity *= -0.25
		else:
			node.position = next
		motion.suspension(node, stage, dt, yaw, (yaw - old_yaw) / dt * motion.velocity.length())

func predict(ticks: int, throttle: float, steer: float, brake: bool, stage, model: int) -> void:
	if ticks <= 0 or pending.size() >= LIMIT:
		return
	seq += 1
	var c = {"seq": seq, "ticks": mini(ticks, 12), "throttle": throttle, "steer": steer, "brake": brake}
	pending.append(c)
	step(c, stage, model)

func accept(commands: Array, stage, model: int) -> void:
	for c in commands:
		if int(c.seq) == ack + 1:
			step(c, stage, model)
			ack = int(c.seq)

func reconcile(s: Dictionary, stage, model: int) -> void:
	if int(s.ack) < ack:
		return
	var before = node.position + visual_offset
	restore(s)
	pending = pending.filter(func(c): return int(c.seq) > ack)
	for c in pending:
		step(c, stage, model)
	visual_offset = before - node.position
	if visual_offset.length() > 5.0:
		visual_offset = Vector3.ZERO
