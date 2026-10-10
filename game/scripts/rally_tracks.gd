extends RefCounted
# Shared, immutable bank; only the four selected run IDs live on each vehicle.
const BANK = preload("res://data/village_rally_tracks.tres")
const Handling = preload("res://scripts/rally_handling.gd")
const COUNT = 5
const PARTS = 4
const STRIDE = 4
const BLEND_METRES = 22.0

static func signature(stage) -> String:
	return var_to_bytes(stage.points).hex_encode().sha256_text()

static func available(stage) -> bool:
	if not stage.biome.uses_baked_tracks() or BANK.runs.size() != COUNT * 2:
		return false
	if not stage.has_meta("rally_tracks_valid"):
		stage.set_meta("rally_tracks_valid", BANK.schema == 1 and BANK.route_signature == signature(stage))
	return stage.get_meta("rally_tracks_valid")

static func choose(stage, rng: RandomNumberGenerator, role: String) -> PackedInt32Array:
	if role not in ["racer", "zero"] or not available(stage):
		return PackedInt32Array()
	var selected = PackedInt32Array()
	for part in range(PARTS):
		selected.append(rng.randi_range(0, COUNT - 1))
	return selected

static func _row(run: int, progress: float, reverse: bool) -> Vector4:
	var values: PackedFloat32Array = BANK.runs[run + (COUNT if reverse else 0)]
	var t = clampf(progress / BANK.sample_step, 0.0, values.size() / STRIDE - 1.0)
	var low = int(t)
	var high = mini(low + 1, values.size() / STRIDE - 1)
	var a = Vector4(values[low*STRIDE], values[low*STRIDE+1], values[low*STRIDE+2], values[low*STRIDE+3])
	var b = Vector4(values[high*STRIDE], values[high*STRIDE+1], values[high*STRIDE+2], values[high*STRIDE+3])
	return a.lerp(b, t - low)

static func sample(selection: PackedInt32Array, progress: float, reverse: bool = false, zero: bool = false) -> Dictionary:
	if selection.size() != PARTS:
		return {}
	var cuts: PackedFloat32Array = BANK.reverse_cuts if reverse else BANK.cuts
	var part = 0
	while part < PARTS - 1 and progress >= cuts[part]:
		part += 1
	var value = _row(selection[part], progress, reverse)
	var blends: PackedFloat32Array = BANK.reverse_blends if reverse else BANK.blends
	for seam in range(PARTS - 1):
		# Bounds are baked in physical metres, including clustered junctions.
		var start: float = blends[seam*2]
		var end: float = blends[seam*2+1]
		if progress < start or progress > end:
			continue
		var t = clampf((progress-start) / (end-start), 0.0, 1.0)
		# Quintic easing has zero first/second derivative at either edge.
		var weight = t*t*t*(t*(t*6.0-15.0)+10.0)
		value = _row(selection[seam], progress, reverse).lerp(_row(selection[seam+1], progress, reverse), weight)
		break
	return {"line": value.x * (0.45 if zero else 1.0), "speed": value.y * (0.84 if zero else 1.0), "yaw": value.z * (0.35 if zero else 1.0), "metric": maxf(value.w, 0.2)}
