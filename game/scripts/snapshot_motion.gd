extends RefCounted
# Render a short distance behind the network clock instead of chasing each
# received point. Prediction is bounded so a lost connection cannot send cars away.
const MAX_SAMPLES = 12
const MAX_PREDICTION = 0.12
var samples: Array[Dictionary] = []
var max_speed = 65.0
var average_interval = 0.1

func push(time: float, position: Vector3, rotation: Vector3, reset: bool = false) -> bool:
	if not samples.is_empty():
		var previous: Dictionary = samples[-1]
		if time <= previous.time:
			return false
		if reset or position.distance_to(previous.position) > 30:
			samples.clear()
		else:
			average_interval = lerpf(average_interval, clampf(time - previous.time, 0.05, 0.5), 0.2)
	samples.append({"time": time, "position": position, "rotation": rotation})
	while samples.size() > MAX_SAMPLES:
		samples.pop_front()
	return true

func delay() -> float:
	return clampf(average_interval * 1.35, 0.18, 0.35)

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
	return latest() if frozen else sample(time - delay())
