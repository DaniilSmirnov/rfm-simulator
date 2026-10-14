extends RefCounted
# Per-world FIFO, bounded burst and simulation-time refill independent of render FPS.
const RATE = 24.0
const BURST = 2.0
var tokens = BURST
var clock = 0.0
var pending: Array = []
var last_seen: Dictionary = {}
func advance(delta: float) -> void:
	clock += maxf(delta, 0)
	tokens = minf(BURST, tokens + maxf(delta, 0) * RATE)
	for id in pending.duplicate():
		if clock - float(last_seen[id]) > 0.15:
			pending.erase(id)
			last_seen.erase(id)
func request(id: int) -> bool:
	if not last_seen.has(id):
		pending.append(id)
	last_seen[id] = clock
	if pending[0] != id or tokens < 1:
		return false
	tokens -= 1
	pending.pop_front()
	last_seen.erase(id)
	return true
