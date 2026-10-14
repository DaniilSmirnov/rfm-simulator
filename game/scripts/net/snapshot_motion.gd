extends RefCounted
# Render a short distance behind the network clock instead of chasing each
# received point. Prediction is bounded so a lost connection cannot send cars away.
const MAX_SAMPLES = 12
const MAX_PREDICTION = 0.20
var samples: Array[Dictionary] = []
var max_speed = 65.0
var average_interval = 0.1
var jitter = 0.0
var render_time = -INF

func push(time: float, position: Vector3, rotation: Vector3, reset: bool = false) -> bool:
	if not samples.is_empty():
		var previous: Dictionary = samples[-1]
		if time <= previous.time:
			return false
		if reset or position.distance_to(previous.position) > 30:
			samples.clear()
			render_time = -INF
			jitter = 0.0
		else:
			var interval = clampf(time - previous.time, 0.05, 0.5)
			jitter = lerpf(jitter, absf(interval - average_interval), 0.2)
			average_interval = lerpf(average_interval, interval, 0.2)
	samples.append({"time": time, "position": position, "rotation": rotation})
	while samples.size() > MAX_SAMPLES:
		samples.pop_front()
	return true

# One snapshot interval plus jitter: about 100 ms for the 10 Hz server path,
# about 60 ms for the 20 Hz direct link.
func delay() -> float:
	return clampf(average_interval + jitter * 2.0, 0.06, 0.25)

func latest() -> Dictionary:
	return samples[-1] if not samples.is_empty() else {"position": Vector3.ZERO, "rotation": Vector3.ZERO}

func sample(time: float) -> Dictionary:
	if samples.size() < 2 or time <= samples[0].time:
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
	var velocity: Vector3 = (last.position - first.position) / interval
	velocity = velocity.limit_length(max_speed)
	return {"position": last.position + velocity * clampf(time - last.time, 0, MAX_PREDICTION), "rotation": last.rotation}

func render(time: float, frozen: bool = false) -> Dictionary:
	if frozen:
		render_time = -INF
		return latest()
	# Changing delay or clock calibration must never make the car drive backwards.
	render_time = maxf(render_time, time - delay())
	return sample(render_time)
