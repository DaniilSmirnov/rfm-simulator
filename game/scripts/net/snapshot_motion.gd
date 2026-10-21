extends RefCounted
# Render a short distance behind the network clock instead of chasing each
# received point. Prediction is bounded so a lost connection cannot send cars away.
#
# A `predictive` buffer (cars) is shown where the object is now instead: it
# runs ahead of the newest sample by its velocity and turn rate, and when a
# new sample moves that guess, the difference fades out over CORRECTION_TIME
# rather than jumping.
const MAX_SAMPLES = 12
const MAX_PREDICTION = 0.20
# How far ahead of the newest sample a predictive buffer goes: covers the
# server path (10 Hz, two hops) at the usual round trips; beyond it the car waits.
const MAX_LEAD = 0.35
const CORRECTION_TIME = 0.12
# A guess this far off is a teleport, not a correction.
const SNAP_DISTANCE = 6.0
const MAX_TURN = 2.5
var samples: Array[Dictionary] = []
var max_speed = 65.0
var average_interval = 0.1
var jitter = 0.0
var render_time = -INF
var predictive = false
var correction_position = Vector3.ZERO
var correction_yaw = 0.0
var _clock = -INF

# `velocity`: the object's velocity at `time` when the sender knows it (a car
# the host simulates); otherwise it is estimated from the previous sample.
func push(time: float, position: Vector3, rotation: Vector3, reset: bool = false, velocity = null) -> bool:
	var entry = {"time": time, "position": position, "rotation": rotation, "velocity": Vector3.ZERO, "turn": 0.0}
	if not samples.is_empty():
		var previous: Dictionary = samples[-1]
		if time <= previous.time:
			return false
		if reset or position.distance_to(previous.position) > 30:
			samples.clear()
			render_time = -INF
			jitter = 0.0
			_clear_correction()
		else:
			var interval = clampf(time - previous.time, 0.05, 0.5)
			jitter = lerpf(jitter, absf(interval - average_interval), 0.2)
			average_interval = lerpf(average_interval, interval, 0.2)
			var span = maxf(0.001, time - previous.time)
			entry.turn = clampf(angle_difference(previous.rotation.y, rotation.y) / span, -MAX_TURN, MAX_TURN)
			# The average velocity over the interval belongs to its middle;
			# a turning car has turned half the interval further since.
			var average: Vector3 = (position - previous.position) / span
			entry.velocity = average.rotated(Vector3.UP, entry.turn * span * 0.5) if predictive else average
	if velocity is Vector3:
		entry.velocity = velocity
	entry.velocity = entry.velocity.limit_length(max_speed)
	var before = null
	if predictive and render_time > -INF and not samples.is_empty():
		before = sample(render_time)
	samples.append(entry)
	while samples.size() > MAX_SAMPLES:
		samples.pop_front()
	if before != null:
		var after = sample(render_time)
		correction_position += before.position - after.position
		correction_yaw = wrapf(correction_yaw + angle_difference(after.rotation.y, before.rotation.y), -PI, PI)
		if correction_position.length() > SNAP_DISTANCE:
			_clear_correction()
	return true

func _clear_correction() -> void:
	correction_position = Vector3.ZERO
	correction_yaw = 0.0

# One snapshot interval plus jitter: about 100 ms for the 10 Hz server path,
# about 60 ms for the 20 Hz direct link.
func delay() -> float:
	return clampf(average_interval + jitter * 2.0, 0.06, 0.25)

func latest() -> Dictionary:
	return samples[-1] if not samples.is_empty() else {"position": Vector3.ZERO, "rotation": Vector3.ZERO}

func sample(time: float) -> Dictionary:
	if samples.size() < 2 or time <= samples[0].time:
		if samples.size() == 1 and predictive and time > samples[0].time:
			return _ahead(samples[0], minf(time - samples[0].time, MAX_LEAD))
		return samples[0] if not samples.is_empty() else latest()
	while samples.size() > 2 and samples[1].time <= time:
		samples.pop_front()
	var first: Dictionary = samples[0]
	var last: Dictionary = samples[1]
	var interval: float = maxf(0.001, last.time - first.time)
	if time <= last.time:
		var weight = clampf((time - first.time) / interval, 0, 1)
		var angles = Vector3.ZERO
		for axis in range(3):
			angles[axis] = lerp_angle(first.rotation[axis], last.rotation[axis], weight)
		return {"position": first.position.lerp(last.position, weight), "rotation": angles}
	if predictive:
		return _ahead(last, minf(time - last.time, MAX_LEAD))
	var velocity: Vector3 = (last.position - first.position) / interval
	velocity = velocity.limit_length(max_speed)
	return {"position": last.position + velocity * clampf(time - last.time, 0, MAX_PREDICTION), "rotation": last.rotation}

# Dead reckoning from one sample: constant speed along an arc of constant turn
# rate. Pitch and roll are held.
static func _ahead(from: Dictionary, lead: float) -> Dictionary:
	var velocity: Vector3 = from.velocity
	var turn: float = from.turn
	var position: Vector3 = from.position
	if absf(turn) < 0.01:
		position += velocity * lead
	else:
		var step = lead / 4.0
		for i in range(4):
			velocity = velocity.rotated(Vector3.UP, turn * step * 0.5)
			position += velocity * step
			velocity = velocity.rotated(Vector3.UP, turn * step * 0.5)
	var rotation: Vector3 = from.rotation
	rotation.y = wrapf(rotation.y + turn * lead, -PI, PI)
	return {"position": position, "rotation": rotation}

func render(time: float, frozen: bool = false) -> Dictionary:
	if frozen:
		render_time = -INF
		_clock = -INF
		_clear_correction()
		return latest()
	if not predictive:
		# Changing delay or clock calibration must never make the car drive backwards.
		render_time = maxf(render_time, time - delay())
		return sample(render_time)
	var elapsed = clampf(time - _clock, 0.0, 0.1) if _clock > -INF else 0.0
	_clock = time
	render_time = maxf(render_time, time)
	var fade = exp(-elapsed / CORRECTION_TIME)
	correction_position *= fade
	correction_yaw *= fade
	var pose = sample(render_time)
	var rotation: Vector3 = pose.rotation
	rotation.y = wrapf(rotation.y + correction_yaw, -PI, PI)
	return {"position": pose.position + correction_position, "rotation": rotation}
