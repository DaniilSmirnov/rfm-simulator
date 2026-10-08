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
	preload("res://scripts/vehicle_simulation.gd").advance(self, c, stage, model)

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
