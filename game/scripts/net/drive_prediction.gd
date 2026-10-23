extends RefCounted
const Hitbox = preload("res://scripts/cars/car_hitbox.gd")
const PropContact = preload("res://scripts/cars/prop_contact.gd")
const Flight = preload("res://scripts/cars/helicopter_motion.gd")
const Motion = preload("res://scripts/cars/vehicle_motion.gd")
const CarRegistry = preload("res://scripts/cars/car_registry.gd")
# Commands sent per sync. The backlog itself is bounded by simulated time so
# merged commands keep about four seconds of input during a network stall.
const LIMIT = 96
const MAX_PENDING = 240
const MAX_PENDING_TICKS = 480
const MAX_TICKS = 12
const INPUT_STEP = 1.0 / 32.0
# The fixed driving tick, seconds.
const STEP = preload("res://scripts/cars/player_handling.gd").STEP
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
# When enabled, identical consecutive input that has not been sent yet is merged
# into one command instead of producing a command per rendered frame.
var coalesce = false
var sealed_seq = 0
# The predicted state after each unacknowledged command (seq -> snapshot()).
# When the host's state at an acknowledgement matches it, nothing needs replaying.
var predicted: Dictionary = {}
# Largest difference from the host that is kept instead of replayed: a few
# millimetres, below what the wire rounding and the screen can show.
const MATCH_POSITION = 0.005
const MATCH_SPEED = 0.01
const MATCH_ANGLE = 0.001

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
	sealed_seq = 0
	context.clear()
	replaying = false
	predicted = {0: snapshot()}

func snapshot() -> Dictionary:
	return {"prop_contacts": motion.prop_contacts.duplicate(), "recovery_ack": recovery_ack, "condition": condition, "impact_timer": impact_timer, "ack": ack, "pos": [node.position.x, node.position.y, node.position.z], "yaw": yaw, "velocity": [motion.velocity.x, motion.velocity.y, motion.velocity.z], "vertical": motion.vertical_speed, "initialized": motion.initialized, "grounded": motion.grounded, "pitch": motion.pitch, "roll": motion.roll, "steering": motion.handling.steering, "yaw_rate": motion.handling.yaw_rate, "longitudinal": motion.handling.longitudinal_accel}

# The snapshot as it travels: rounded to a millimetre (a hundredth of a
# milliradian for angles) and without the fields that sit at the value restore()
# assumes when they are missing.
func wire_snapshot() -> Dictionary:
	var s = snapshot()
	var wire = {"ack": s.ack, "pos": _round_vec(s.pos, 0.001), "yaw": snappedf(s.yaw, 0.0001), "velocity": _round_vec(s.velocity, 0.001), "vertical": snappedf(s.vertical, 0.001), "grounded": s.grounded,
		"pitch": snappedf(s.pitch, 0.0001), "roll": snappedf(s.roll, 0.0001), "steering": snappedf(s.steering, 0.001), "yaw_rate": snappedf(s.yaw_rate, 0.0001), "longitudinal": snappedf(s.longitudinal, 0.001)}
	if not s.initialized:
		wire.initialized = false
	if s.condition != 100.0:
		wire.condition = snappedf(s.condition, 0.01)
	if s.impact_timer != 0.0:
		wire.impact_timer = snappedf(s.impact_timer, 0.01)
	if s.recovery_ack != 0:
		wire.recovery_ack = s.recovery_ack
	if not s.prop_contacts.is_empty():
		wire.prop_contacts = s.prop_contacts
	return wire

static func _round_vec(v: Array, step: float) -> Array:
	return [snappedf(v[0], step), snappedf(v[1], step), snappedf(v[2], step)]

func restore(s: Dictionary) -> void:
	node.position = Vector3(s.pos[0], s.pos[1], s.pos[2])
	yaw = s.yaw
	motion.velocity = Vector3(s.velocity[0], s.velocity[1], s.velocity[2])
	motion.prop_contacts = s.get("prop_contacts", {}).duplicate()
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
		if CarRegistry.flies(model):
			Flight.step(self, c, stage, model, dt)
			continue
		# Same rule as player_motion.gd: a broken car only rolls to a stop.
		# Freezing it kept the crash speed forever, and nobody could get out.
		var wrecked = condition <= 0
		var previous = node.position
		var old_yaw = yaw
		var offroad = stage.road_distance(previous) > 4.1
		yaw = motion.handling.advance(motion, yaw, 0.0 if wrecked else c.throttle, 0.0 if wrecked else c.steer, wrecked or c.brake, stage.grip(previous), CarRegistry.TOP_SPEED, model, dt, {}, offroad)
		var forward = Vector3(-sin(yaw), 0, -cos(yaw))
		var next = previous + motion.velocity * dt
		next.x = clampf(next.x, -185, 185)
		next.z = clampf(next.z, stage.parks.z_limits.x, stage.parks.z_limits.y)
		impact_timer = maxf(0, impact_timer - dt)
		var car_shape = Hitbox.shape(Hitbox.player(model), yaw)
		var rock = Hitbox.rocks(stage, previous, next, car_shape)
		if not rock.is_empty():
			next = rock.position
			var closing = motion.rock_impulse(rock.normal, yaw)
			if float(rock.get("radius", 0)) >= 1.0: motion.velocity = Vector3.ZERO
			if closing > 1 and impact_timer <= 0:
				condition = maxf(0, condition - minf(14, closing * 0.65))
				impact_timer = 0.4
				emit_event({"kind": "impact", "speed": closing})
		var solid = PropContact.resolve(stage, motion, previous, next, dt, car_shape)
		next = solid.position
		for impact in solid.hits:
			# Event kind "city" is the room protocol name for solid scenery hits.
			emit_event({"kind": "city", "hit": impact.hit, "velocity": impact.velocity})
		if solid.closing > 1 and impact_timer <= 0:
			condition = maxf(0, condition - minf(20, solid.closing * 0.85))
			impact_timer = 0.4
			emit_event({"kind": "impact", "speed": solid.closing})
		var tree = Hitbox.tree(stage, previous, next, car_shape)
		var blocked = tree >= 0 or stage.biome.drive_blocked(previous, next)
		if blocked and motion.velocity.length() > 5 and not stage.fallen.has(tree):
			emit_event({"kind": "tree", "index": tree, "velocity": motion.velocity})
		for contact in context.get("contacts", []):
			var other: Vector3 = contact.position
			if Hitbox.blocked(previous, next, car_shape, contact):
				blocked = true
				if contact.get("person", false) and absf(motion.velocity.dot(forward)) > 5:
					emit_event({"kind": "person", "position": other, "velocity": motion.velocity})
		if blocked:
			# Same rule as player_motion.gd: resting against a trunk is no crash.
			var impact = motion.velocity.length()
			if impact > 1 and impact_timer <= 0:
				condition = maxf(0, condition - impact * 1.4)
				impact_timer = 0.4
				emit_event({"kind": "impact", "speed": impact})
			motion.velocity = Vector3.ZERO if tree >= 0 else motion.velocity * -0.25
		else:
			node.position = next
		var speed = motion.velocity.dot(forward)
		motion.suspension(node, stage, dt, yaw, (yaw - old_yaw) / dt * speed)
		if offroad and absf(speed) > 5:
			condition = maxf(0, condition - dt * 0.15)

func backlog_ticks() -> int:
	var total = 0
	for c in pending:
		total += int(c.get("ticks", 0))
	return total

func full() -> bool:
	return pending.size() >= MAX_PENDING or backlog_ticks() >= MAX_PENDING_TICKS

# Commands up to the current sequence are on the wire and must not change.
func seal() -> void:
	sealed_seq = seq

func outgoing() -> Array:
	return pending.slice(0, LIMIT)

static func quantize(value: float) -> float:
	return snappedf(clampf(value, -1.0, 1.0), INPUT_STEP)

func predict(ticks: int, throttle: float, steer: float, brake: bool, stage, model: int, recover: bool = false, lift: float = 0.0) -> void:
	if ticks <= 0 or full():
		return
	ticks = mini(ticks, MAX_TICKS)
	lift = quantize(lift)
	if coalesce:
		throttle = quantize(throttle)
		steer = quantize(steer)
		if not recover and not pending.is_empty():
			var last: Dictionary = pending.back()
			if int(last.seq) > sealed_seq and not last.get("recover", false) and float(last.throttle) == throttle and float(last.steer) == steer and bool(last.brake) == brake and float(last.get("lift", 0)) == lift and int(last.ticks) + ticks <= MAX_TICKS:
				last.ticks = int(last.ticks) + ticks
				step({"seq": last.seq, "ticks": ticks, "throttle": throttle, "steer": steer, "brake": brake, "lift": lift}, stage, model)
				predicted[int(last.seq)] = snapshot()
				return
	seq += 1
	var c = {"seq": seq, "ticks": ticks, "throttle": throttle, "steer": steer, "brake": brake, "recover": recover, "lift": lift}
	pending.append(c)
	step(c, stage, model)
	predicted[seq] = snapshot()

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
	# The usual case: the host ran the same input to the same result. Replaying
	# every unacknowledged tick for each world packet (20 a second) cost more
	# than the driving itself, so a matching state only drops acknowledged input.
	var expected = snapshot() if pending.filter(func(c): return int(c.seq) > int(s.ack)).is_empty() else predicted.get(int(s.ack))
	if not recovered and expected != null and matches(expected, s):
		ack = int(s.ack)
		seq = maxi(seq, ack)
		pending = pending.filter(func(c): return int(c.seq) > ack)
		_forget_acknowledged()
		return
	var before = node.position + visual_offset
	var before_yaw = yaw + visual_yaw
	restore(s)
	pending = pending.filter(func(c): return int(c.seq) > ack)
	_forget_acknowledged()
	predicted[ack] = snapshot()
	replaying = true
	for c in pending:
		step(c, stage, model)
		predicted[int(c.seq)] = snapshot()
	replaying = false
	visual_offset = before - node.position
	visual_yaw = wrapf(before_yaw - yaw, -PI, PI)
	if recovered or visual_offset.length() > 5.0 or (not pending.is_empty() and pending.back().get("recover", false)):
		visual_offset = Vector3.ZERO
		visual_yaw = 0.0

func _forget_acknowledged() -> void:
	for key in predicted.keys():
		if int(key) < ack:
			predicted.erase(key)

# Whether a host snapshot (full or wire_snapshot) is the predicted state `p`,
# within the wire's rounding. Missing wire fields carry restore()'s defaults.
static func matches(p: Dictionary, s: Dictionary) -> bool:
	for key in ["pos", "velocity"]:
		var a: Array = p[key]
		var b: Array = s[key]
		var limit = MATCH_POSITION if key == "pos" else MATCH_SPEED
		for i in range(3):
			if absf(float(a[i]) - float(b[i])) > limit:
				return false
	for key in ["yaw", "pitch", "roll", "yaw_rate"]:
		if absf(angle_difference(float(p[key]), float(s[key]))) > MATCH_ANGLE:
			return false
	for key in ["vertical", "steering", "longitudinal"]:
		if absf(float(p[key]) - float(s[key])) > MATCH_SPEED:
			return false
	if bool(p.grounded) != bool(s.grounded) or bool(p.initialized) != bool(s.get("initialized", true)):
		return false
	if absf(float(p.condition) - float(s.get("condition", 100.0))) > 0.02 or absf(float(p.impact_timer) - float(s.get("impact_timer", 0.0))) > 0.02:
		return false
	if int(p.recovery_ack) != int(s.get("recovery_ack", 0)):
		return false
	var contacts: Dictionary = s.get("prop_contacts", {})
	if p.prop_contacts.size() != contacts.size():
		return false
	for key in contacts:
		if not p.prop_contacts.has(key) or absf(float(p.prop_contacts[key]) - float(contacts[key])) > 0.02:
			return false
	return true

# When a car simulated on the host from a guest's input was where it is. The
# input arrives in bursts (a packet carries a few ticks, the network adds
# jitter), so the arrival time would make the car speed up and slow down between
# snapshots. The stamp moves by the simulated ticks instead and only drifts
# slowly (2 ms a packet) towards the arrival clock, a little behind it.
const STAMP_LAG = 0.03
const STAMP_DRIFT = 0.002

static func stamp(time: float, ticks: int, clock: float) -> float:
	var target = clock - STAMP_LAG
	if ticks > 0:
		time += ticks * STEP
		time += clampf(target - time, -STAMP_DRIFT, STAMP_DRIFT)
	else:
		# Standing still: time passes, the position does not change.
		time = maxf(time + 0.001, target)
	if time > clock or time < clock - 0.25:
		time = target
	return time
