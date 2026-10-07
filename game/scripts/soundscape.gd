extends Node
# Short deterministic PCM effects are shared by all players; no per-frame synthesis.
# Background birds and cooking fire run at 20% of their previous linear gain.
const BIRDS_VOLUME_DB = -37.0
var game: Node
var shutting_down = false
var birds: AudioStreamPlayer
var effects: AudioStreamPlayer
var steps: AudioStreamPlayer
var step_clock = 0.0
var repair_clock = 0.0
var last_position = Vector3.ZERO
var last_impact = 0.0
var eating_before = false
var effect_clock = 0.0
var clips: Dictionary = {}

func tone(kind: String, seconds: float) -> AudioStreamWAV:
	var rate = 22050
	var count = int(seconds * rate)
	var bytes = PackedByteArray()
	bytes.resize(count * 2)
	var random = RandomNumberGenerator.new()
	random.seed = 7102026
	for i in range(count):
		var t = float(i) / rate
		var value = 0.0
		if kind == "birds":
			var phase = fmod(t, 2.0)
			if phase < 0.30:
				value = sin(TAU * (1800 * phase + 1500 * phase * phase)) * sin(PI * phase / 0.30) * 0.18
		else:
			var envelope = exp(-t * (22.0 if kind == "step" else 9.0))
			value = (random.randf_range(-1, 1) * 0.5 + sin(TAU * t * (110 if kind in ["step", "impact"] else 340)) * 0.25) * envelope
		bytes.encode_s16(i * 2, int(clampf(value, -1, 1) * 32767))
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	if kind == "birds":
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = count
	return stream

func _ready() -> void:
	clips.step = tone("step", 0.18)
	clips.place = tone("place", 0.4)
	clips.impact = tone("impact", 0.3)
	clips.eat = tone("eat", 0.22)
	birds = AudioStreamPlayer.new()
	birds.stream = tone("birds", 8.0)
	birds.volume_db = BIRDS_VOLUME_DB
	add_child(birds)
	effects = AudioStreamPlayer.new()
	effects.stream = clips.place
	effects.volume_db = -17
	effects.max_polyphony = 4
	add_child(effects)
	steps = AudioStreamPlayer.new()
	steps.stream = clips.step
	steps.volume_db = -23
	add_child(steps)

func active() -> bool:
	return game.playing and not game.paused and not game.dead and not game.finished and not (game.room.connected and not game.room.is_host and game.room.world_paused)

func repair() -> void:
	if shutting_down:
		return
	if DisplayServer.get_name() == "headless":
		return
	# Keep loops alive after a stopped session or lost playback, never one-shots.
	var running = active()
	for player in [game.engine_audio, game.wind_audio, game.fire_audio, birds]:
		var wanted = running if player == game.engine_audio else true
		if player == game.fire_audio:
			wanted = running and is_instance_valid(game.grill)
		elif player == birds:
			wanted = game.selected_stage != 1
		player.stream_paused = game.paused or (game.room.connected and not game.room.is_host and game.room.world_paused)
		if wanted and not player.playing:
			player.play()
		elif not wanted and player.playing:
			player.stop()
	game.rally_audio.stream_paused = not running
	if is_instance_valid(game.grill):
		game.fire_audio.global_position = game.grill.global_position

func update(delta: float) -> void:
	if shutting_down:
		return
	repair_clock -= delta
	if repair_clock <= 0:
		repair_clock = 0.5
		repair()
	effect_clock = maxf(0.0, effect_clock - delta)
	if active() and game.impact_shake > last_impact + 0.12 and effect_clock <= 0:
		effect("impact")
		effect_clock = 0.25
	last_impact = game.impact_shake
	var eating = game.eat_time >= 0.0
	if active() and eating and not eating_before:
		effect("eat")
	eating_before = eating
	if not active() or game.in_car or game.seated or game.jump_height > 0.05:
		step_clock = 0
		last_position = game.walker
		return
	var moved = game.walker.distance_to(last_position)
	last_position = game.walker
	if moved < 0.005:
		step_clock = 0
		return
	step_clock -= delta
	if step_clock <= 0:
		game._play_audio(steps)
		step_clock = 0.32 if Input.is_action_pressed("sprint") else 0.48

func placement() -> void:
	if shutting_down:
		return
	effect("place")

func effect(kind: String) -> void:
	if shutting_down:
		return
	effects.stream = clips[kind]
	game._play_audio(effects)
