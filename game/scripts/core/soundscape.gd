extends Node
# Sounds of the outing apart from the cars (vehicle_audio.gd): wind, birds,
# cicadas, the grill fire, footsteps on the surface underfoot, knocks, camp
# gear being set down, eating. Most files come from scripts/generate-sounds.mjs.
# Background birds and cooking fire are deliberately sparse instead of looping.
# Their gain also stays at 20% of the previous linear amplitude.
const SoundBank = preload("res://scripts/core/sound_bank.gd")
const BIRDS_VOLUME_DB = -37.0
const BIRD_TAKES = 3
const BIRD_GAP_MIN = 20.0
const BIRD_GAP_MAX = 40.0
const FIRE_BURST_SECONDS = 1.5
# Provençal summer: short cicada choruses on the vineyard stage only.
const CICADA_VOLUME_DB = -31.0
const CICADA_GAP_MIN = 6.0
const CICADA_GAP_MAX = 14.0
const CICADA_STAGE = 2
const FIRE_GAP_MIN = 18.0
const FIRE_GAP_MAX = 30.0
const STEP_TAKES = 3
# Gear put down: what it is made of.
const METAL_GEAR = ["grill", "cauldron", "light_grill"]
var game: Node
var shutting_down = false
var birds: AudioStreamPlayer
var cicadas: AudioStreamPlayer
var effects: AudioStreamPlayer
var steps: AudioStreamPlayer
var vehicles: Node
var step_clock = 0.0
var repair_clock = 0.0
var last_position = Vector3.ZERO
var last_impact = 0.0
var was_airborne = false
var eating_before = false
var effect_clock = 0.0
var bird_clock = 0.0
var fire_clock = 0.0
var fire_burst_clock = 0.0
var cicada_clock = 0.0
var ambient_random = RandomNumberGenerator.new()

func _ready() -> void:
	ambient_random.seed = 7102026
	SoundBank.warm()
	bird_clock = ambient_random.randf_range(BIRD_GAP_MIN, BIRD_GAP_MAX)
	fire_clock = ambient_random.randf_range(FIRE_GAP_MIN, FIRE_GAP_MAX)
	cicada_clock = ambient_random.randf_range(1.0, CICADA_GAP_MIN)
	game.wind_audio = SoundBank.player(game, -20.0, "forest")
	game._play_audio(game.wind_audio)
	# 20% of the previous cooking/fire linear gain (about -14 dB).
	game.fire_audio = SoundBank.spatial(game, -26.0, 10.0, 24.0, "fire")
	game.beer_audio = SoundBank.player(game, -10.0)
	cicadas = SoundBank.player(self, CICADA_VOLUME_DB, "cicadas")
	birds = SoundBank.player(self, BIRDS_VOLUME_DB, "bird-1")
	effects = SoundBank.player(self, -17.0)
	effects.max_polyphony = 4
	steps = SoundBank.player(self, -23.0)
	steps.max_polyphony = 2
	vehicles = preload("res://scripts/core/vehicle_audio.gd").new()
	vehicles.game = game
	add_child(vehicles)

func active() -> bool:
	return game.playing and not game.paused and not game.dead and not game.finished and not (game.room.is_guest() and game.room.world_paused)

func world_paused() -> bool:
	return game.paused or (game.room.is_guest() and game.room.world_paused)

func repair() -> void:
	if shutting_down:
		return
	if DisplayServer.get_name() == "headless":
		return
	# Keep the wind loop alive after a stopped session or lost playback.
	# Birds and fire are intentionally scheduled as sparse one-shots below.
	var ambience_paused = world_paused()
	SoundBank.set_paused(game.wind_audio, ambience_paused)
	if not game.wind_audio.playing:
		game.wind_audio.play()
	for node in [birds, cicadas, game.fire_audio]:
		SoundBank.set_paused(node, ambience_paused)
	if is_instance_valid(game.grill):
		game.fire_audio.global_position = game.grill.global_position

func update(delta: float) -> void:
	if shutting_down:
		return
	repair_clock -= delta
	if repair_clock <= 0:
		repair_clock = 0.5
		repair()
	vehicles.update(delta, active(), world_paused())
	_update_sparse_ambience(delta)
	effect_clock = maxf(0.0, effect_clock - delta)
	if active() and game.impact_shake > last_impact + 0.12 and effect_clock <= 0:
		vehicles.impact(game.impact_shake)
		effect_clock = 0.25
	last_impact = game.impact_shake
	var eating = game.eat_time >= 0.0
	if active() and eating and not eating_before:
		_effect("eat")
	eating_before = eating
	_update_steps(delta)

func _update_steps(delta: float) -> void:
	if not active() or game.in_car or game.seated:
		step_clock = 0
		last_position = game.walker
		was_airborne = false
		return
	var airborne = game.jump_height > 0.05
	if airborne:
		was_airborne = true
		last_position = game.walker
		return
	if was_airborne:
		# Landing from a jump: both feet at once.
		was_airborne = false
		_step(-18.0)
		step_clock = 0.3
	var moved = game.walker.distance_to(last_position)
	last_position = game.walker
	if moved < 0.005:
		step_clock = 0
		return
	step_clock -= delta
	if step_clock <= 0:
		_step(-23.0)
		step_clock = 0.32 if Input.is_action_pressed("sprint") else 0.48

func _step(volume_db: float) -> void:
	var surface = game.stage.biome.surface_sound(game.walker)
	steps.stream = SoundBank.take("step-" + surface, STEP_TAKES, ambient_random)
	steps.volume_db = volume_db
	steps.pitch_scale = ambient_random.randf_range(0.92, 1.08)
	game._play_audio(steps)

func _update_sparse_ambience(delta: float) -> void:
	if world_paused():
		return

	if game.selected_stage != 1:
		bird_clock -= delta
		if bird_clock <= 0.0:
			birds.stream = SoundBank.take("bird", BIRD_TAKES, ambient_random)
			birds.pitch_scale = ambient_random.randf_range(0.94, 1.06)
			game._play_audio(birds)
			bird_clock = ambient_random.randf_range(BIRD_GAP_MIN, BIRD_GAP_MAX)
	elif birds.playing:
		birds.stop()

	if game.selected_stage == CICADA_STAGE:
		cicada_clock -= delta
		if cicada_clock <= 0.0:
			game._play_audio(cicadas)
			cicada_clock = ambient_random.randf_range(CICADA_GAP_MIN, CICADA_GAP_MAX)
	elif cicadas.playing:
		cicadas.stop()

	var fire_available = active() and is_instance_valid(game.grill)
	if not fire_available:
		fire_burst_clock = 0.0
		if game.fire_audio.playing:
			game.fire_audio.stop()
		return

	game.fire_audio.global_position = game.grill.global_position
	if fire_burst_clock > 0.0:
		fire_burst_clock = maxf(0.0, fire_burst_clock - delta)
		if fire_burst_clock <= 0.0 and game.fire_audio.playing:
			game.fire_audio.stop()
		return

	fire_clock -= delta
	if fire_clock <= 0.0:
		game._play_audio(game.fire_audio)
		fire_burst_clock = FIRE_BURST_SECONDS
		fire_clock = ambient_random.randf_range(FIRE_GAP_MIN, FIRE_GAP_MAX)

# Gear set down, the grill lit, snow dug: what it was decides the sound.
func placement(kind: String = "") -> void:
	if shutting_down:
		return
	if kind == "snow":
		_effect("step-snow-%d" % ambient_random.randi_range(1, STEP_TAKES))
	else:
		_effect("place-metal" if kind in METAL_GEAR else "place-wood")

func _effect(sound: String) -> void:
	if shutting_down:
		return
	effects.stream = SoundBank.stream(sound)
	effects.pitch_scale = ambient_random.randf_range(0.95, 1.05)
	game._play_audio(effects)

func stop_all() -> void:
	shutting_down = true
	for player in [birds, cicadas, effects, steps]:
		player.stop()
	vehicles.silence()
