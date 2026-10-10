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
var condition = 100.0
var impact_timer = 0.0
var context: Dictionary = {}
var events: Array[Dictionary] = []
var replaying = false
var visual_yaw = 0.0
var recovery_ack = 0

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
	condition = 100.0
	impact_timer = 0.0
	events.clear()
	visual_yaw = 0.0
	recovery_ack = 0
	context.clear()
	replaying = false

func snapshot() -> Dictionary:
	return {"recovery_ack": recovery_ack, "condition": condition, "impact_timer": impact_timer, "ack": ack, "pos": [node.position.x, node.position.y, node.position.z], "yaw": yaw, "velocity": [motion.velocity.x, motion.velocity.y, motion.velocity.z], "vertical": motion.vertical_speed, "initialized": motion.initialized, "grounded": motion.grounded, "pitch": motion.pitch, "roll": motion.roll, "steering": motion.handling.steering, "yaw_rate": motion.handling.yaw_rate, "longitudinal": motion.handling.longitudinal_accel}

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
	seq = maxi(seq, ack)
	condition = float(s.get("condition", 100.0))
	impact_timer = float(s.get("impact_timer", 0.0))
	recovery_ack = int(s.get("recovery_ack", 0))

func emit_event(event: Dictionary) -> void:
	if not replaying:
		events.append(event)

func step(c: Dictionary, stage, model: int) -> void:
	if c.get("recover", false) and not context.get("racing", false):
		recovery_ack = int(c.seq)
		node.position = stage.at(stage.road_s(node.position))
		var direction = stage.direction(stage.road_s(node.position))
		yaw = atan2(-direction.x, -direction.z)
		motion = Motion.new()
		visual_offset = Vector3.ZERO
		visual_yaw = 0.0
	var dt = motion.handling.STEP
	for tick in range(int(c.ticks)):
		if condition <= 0:
			break
		var previous = node.position
		var old_yaw = yaw
		var offroad = stage.road_distance(previous) > 4.1
		yaw = motion.handling.advance(motion, yaw, c.throttle, c.steer, c.brake, stage.grip(previous), 7.0 if offroad else 19.0, model, dt)
		var forward = Vector3(-sin(yaw), 0, -cos(yaw))
		var next = previous + motion.velocity * dt
		next.x = clampf(next.x, -185, 185)
		next.z = clampf(next.z, -stage.LENGTH + 5, 10)
		impact_timer = maxf(0, impact_timer - dt)
		var rock = stage.rock_hit(previous, next, 0.85)
		if not rock.is_empty():
			next = rock.position
			var closing = motion.rock_impulse(rock.normal, yaw)
			if closing > 1 and impact_timer <= 0:
				condition = maxf(0, condition - minf(14, closing * 0.65))
				impact_timer = 0.4
				emit_event({"kind": "impact", "speed": closing})
		var solid = stage.solids.hit(previous, next, 0.85)
		if not solid.is_empty():
			next = solid.position
			# Event kind "city" is the room protocol name for solid scenery hits.
			emit_event({"kind": "city", "hit": solid, "velocity": motion.velocity})
			var closing = motion.rock_impulse(solid.normal, yaw)
			if closing > 1 and impact_timer <= 0:
				condition = maxf(0, condition - minf(20, closing * 0.85))
				impact_timer = 0.4
				emit_event({"kind": "impact", "speed": closing})
		var tree = stage.obstacle_hit(previous, next, 0.95, true)
		var blocked = tree >= 0
		if blocked and motion.velocity.length() > 5 and not stage.fallen.has(tree):
			emit_event({"kind": "tree", "index": tree, "velocity": motion.velocity})
		for contact in context.get("contacts", []):
			var other: Vector3 = contact.position
			var radius = 1.55 if contact.get("person", false) else 2.5
			if Motion.swept_hit(previous + Vector3(0, 0.7, 0), next + Vector3(0, 0.7, 0), other + Vector3(0, 0.7, 0), radius) and next.distance_to(other) <= previous.distance_to(other):
				blocked = true
				if contact.get("person", false) and absf(motion.velocity.dot(forward)) > 5:
					emit_event({"kind": "person"})
		if blocked:
			condition = maxf(0, condition - motion.velocity.length() * 1.4)
			emit_event({"kind": "impact", "speed": motion.velocity.length()})
			motion.velocity *= -0.25
		else:
			node.position = next
		var speed = motion.velocity.dot(forward)
		motion.suspension(node, stage, dt, yaw, (yaw - old_yaw) / dt * speed)
		if offroad and absf(speed) > 5:
			condition = maxf(0, condition - dt * 0.15)

func predict(ticks: int, throttle: float, steer: float, brake: bool, stage, model: int, recover: bool = false) -> void:
	if ticks <= 0 or pending.size() >= LIMIT:
		return
	seq += 1
	var c = {"seq": seq, "ticks": mini(ticks, 12), "throttle": throttle, "steer": steer, "brake": brake, "recover": recover}
	pending.append(c)
	step(c, stage, model)

func accept(commands: Array, stage, model: int, budget: int = 1152) -> int:
	var consumed = 0
	for c in commands:
		if int(c.seq) == ack + 1:
			if consumed + int(c.ticks) > budget:
				break
			consumed += int(c.ticks)
			step(c, stage, model)
			ack = int(c.seq)

	return consumed

func reconcile(s: Dictionary, stage, model: int) -> void:
	if int(s.ack) < ack:
		return
	var recovered = int(s.get("recovery_ack", 0)) > recovery_ack
	var before = node.position + visual_offset
	var before_yaw = yaw + visual_yaw
	restore(s)
	pending = pending.filter(func(c): return int(c.seq) > ack)
	replaying = true
	for c in pending:
		step(c, stage, model)
	replaying = false
	visual_offset = before - node.position
	visual_yaw = wrapf(before_yaw - yaw, -PI, PI)
	if recovered or visual_offset.length() > 5.0 or (not pending.is_empty() and pending.back().get("recover", false)):
		visual_offset = Vector3.ZERO
		visual_yaw = 0.0
