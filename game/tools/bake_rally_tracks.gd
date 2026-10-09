extends SceneTree
# Generate simplified driver/tyre reference runs once, never at game startup.
const Stage = preload("res://scripts/stage.gd")
const Handling = preload("res://scripts/rally_handling.gd")
const Tracks = preload("res://scripts/rally_tracks.gd")
const Bank = preload("res://scripts/rally_track_bank.gd")
const DT = 1.0 / 120.0
const SAMPLE_COUNT = 841
const TOP_SPEED = 140.0 / 3.6
# Pace, corner-cutting, response distance, lateral inertia, road-line bias.
const PROFILES = [Vector4(0.94, 0.5, 7.0, 0.55), Vector4(1.0, 0.9, 10.0, 0.85), Vector4(0.97, 1.1, 17.0, 0.95), Vector4(0.96, 1.5, 13.0, 0.8), Vector4(0.98, 0.7, 11.0, 1.2)]

func geometry(stage, reverse: bool) -> Array[Dictionary]:
	var frames: Array[Dictionary] = []
	for i in range(SAMPLE_COUNT):
		var station = Stage.LENGTH - i if reverse else float(i)
		var direction = Handling.direction(stage, station, reverse)
		var position = Handling.path(stage, station)
		var ahead = Handling.direction(stage, station + (-1.0 if reverse else 1.0) * 4.0, reverse)
		var distance = maxf(Handling.metric(stage, station) * 4.0, 1.0)
		var bend = wrapf(atan2(-ahead.x, -ahead.z) - atan2(-direction.x, -direction.z), -PI, PI) / distance
		frames.append({"station":station, "metric":Handling.metric(stage, station), "bend":bend, "grip":stage.grip(position), "width":stage.road_width(station), "distance":0.0})
		if i > 0:
			frames[i].distance = frames[i-1].distance + Vector2((position-Handling.path(stage, station + (1.0 if reverse else -1.0))).x, (position-Handling.path(stage, station + (1.0 if reverse else -1.0))).z).length()
	return frames

func generate(frames: Array[Dictionary], profile: int) -> PackedFloat32Array:
	var spec: Vector4 = PROFILES[profile]
	var limits = PackedFloat32Array()
	for frame in frames:
		limits.append(clampf(sqrt(frame.grip * 11.0 / maxf(absf(frame.bend), 0.001)) * spec.x, 6.0, TOP_SPEED))
	# Brake before a corner; a slower reaction varies entry speed and late apex.
	for i in range(SAMPLE_COUNT - 2, -1, -1):
		var distance: float = frames[i+1].distance - frames[i].distance
		limits[i] = minf(limits[i], sqrt(limits[i+1]*limits[i+1] + 2.0 * (13.0 - profile * 0.65) * distance))
	var rows = PackedFloat32Array()
	var progress = 0.0
	var speed = 8.0
	var line = [-0.42, 0.38, -0.2, 0.45, 0.0][profile]
	var lateral_speed = 0.0
	var slip = 0.0
	var next_sample = 0
	var previous = Vector4(line, speed, slip, frames[0].metric)
	var previous_progress = 0.0
	while next_sample < SAMPLE_COUNT:
		var frame: Dictionary = frames[mini(int(progress), SAMPLE_COUNT-1)]
		var reaction_station = spec.z / maxf(frame.metric, 0.2)
		var past: Dictionary = frames[maxi(0, int(progress - reaction_station))]
		var target = clampf(-past.bend * 22.0 * spec.y, -spec.y, spec.y)
		target += [-0.42, 0.38, -0.2, 0.45, 0.0][profile]
		# Corner load and delayed steering move the rear outward, then tyres catch it.
		var demand: float = frame.bend * speed * speed
		var acceleration = (target-line) * 4.5 - lateral_speed * 3.2 + demand * 0.18 * spec.w
		lateral_speed += acceleration * DT
		lateral_speed = clampf(lateral_speed, -2.2, 2.2)
		line += lateral_speed * DT
		var margin: float = maxf(0.55, frame.width * 0.5 - 1.0)
		line = clampf(line, -margin, margin)
		var target_slip = clampf(atan2(lateral_speed, maxf(speed, 2.0)) + demand * 0.012 * spec.w / frame.grip, -0.38, 0.38)
		slip = lerpf(slip, target_slip, 1.0 - exp(-DT * 4.0))
		speed = move_toward(speed, limits[mini(int(progress), SAMPLE_COUNT-1)] * clampf(1.0-absf(slip)*0.2, 0.8, 1.0), DT * (16.0 if speed > limits[mini(int(progress), SAMPLE_COUNT-1)] else 7.0))
		progress += speed * DT / maxf(frame.metric, 0.2)
		var value = Vector4(line, speed, slip, frame.metric)
		while next_sample <= progress and next_sample < SAMPLE_COUNT:
			var row = previous.lerp(value, clampf((next_sample - previous_progress) / maxf(progress-previous_progress, 0.00001), 0.0, 1.0))
			rows.append_array(PackedFloat32Array([row.x, row.y, row.z, row.w]))
			next_sample += 1
		previous = value
		previous_progress = progress
	return rows

func station_at_distance(frames: Array[Dictionary], distance: float) -> float:
	for i in range(1, SAMPLE_COUNT):
		if frames[i].distance >= distance:
			return lerpf(i-1, i, (distance-frames[i-1].distance) / maxf(frames[i].distance-frames[i-1].distance, 0.001))
	return Stage.LENGTH

func split_points(frames: Array[Dictionary]) -> Dictionary:
	var cuts = PackedFloat32Array()
	var blends = PackedFloat32Array()
	for quarter in range(1, 4):
		var distance: float = frames[-1].distance * quarter / 4.0
		cuts.append(station_at_distance(frames, distance))
		blends.append(station_at_distance(frames, distance - Tracks.BLEND_METRES))
		blends.append(station_at_distance(frames, distance + Tracks.BLEND_METRES))
	return {"cuts": cuts, "blends": blends}

func _initialize() -> void:
	var stage = Stage.new(2)
	var bank = Bank.new()
	bank.route_signature = Tracks.signature(stage)
	bank.labels = PackedStringArray(["Чистый", "Атакующий", "Поздний апекс", "Широкий проход", "Скользящий"])
	for reverse in [false, true]:
		var frames = geometry(stage, reverse)
		var split = split_points(frames)
		if reverse:
			bank.reverse_cuts = split.cuts
			bank.reverse_blends = split.blends
		else:
			bank.cuts = split.cuts
			bank.blends = split.blends
		for profile in range(5):
			bank.runs.append(generate(frames, profile))
	var error = ResourceSaver.save(bank, "res://data/village_rally_tracks.tres")
	stage.free()
	print("RALLY_TRACK_BAKE_RESULT: ", error, " runs=", bank.runs.size())
	quit(0 if error == OK else 1)
