extends "res://tests/harness.gd"
# Car sounds: the engine model (gears, revs, loop crossfade), every engine and
# tyre loop on disk, the nearest cars getting the 3D voices, sirens on course
# cars, crashes, doors and the per-stage surface under the tyres.
const VehicleAudio = preload("res://scripts/core/vehicle_audio.gd")
const SoundBank = preload("res://scripts/core/sound_bank.gd")
const CarRegistry = preload("res://scripts/cars/car_registry.gd")
const RallyCarModel = preload("res://scripts/cars/rally_car_model.gd")
const StageRegistry = preload("res://scripts/stages/stage_registry.gd")
const Stage = preload("res://scripts/stages/stage.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	engine_model()
	sound_files()
	fleet_engines()
	await cars_around()
	print("VEHICLE AUDIO RESULT: %d failures" % failures)
	finish()

func engine_model() -> void:
	var box: Dictionary = VehicleAudio.GEARBOX.rally
	var state = {}
	VehicleAudio.advance_engine(state, 0.0, 0.0, box, 0.5)
	check(absf(state.rpm - float(box.idle)) < 300.0 and state.gear == 1, "a standing car idles in first (%.0f rpm)" % state.rpm)
	var gears: Array[int] = []
	var in_range = true
	var speed = 0.0
	while speed < 40.0:
		VehicleAudio.advance_engine(state, speed, 1.0, box, 1.0 / 60.0)
		gears.append(state.gear)
		in_range = in_range and state.rpm <= float(box.redline) + 1.0 and state.rpm >= float(box.idle) - 1.0
		speed += 6.0 / 60.0
	var rising = true
	for i in range(1, gears.size()):
		rising = rising and gears[i] >= gears[i - 1]
	check(rising and gears[-1] >= 4, "full throttle shifts up through the box (top gear %d)" % gears[-1])
	check(in_range, "revs stay between idle and the redline")
	for i in range(120):
		VehicleAudio.advance_engine(state, 30.0, 0.0, box, 1.0 / 60.0)
	check(state.load < 0.05, "lifting off drops the load")
	var idle = VehicleAudio.layer_gains(900.0, 0.0)
	check(idle.low > 0.6 and idle.on < 0.01 and idle.off < 0.01, "idle plays only the low loop")
	var pulling = VehicleAudio.layer_gains(6500.0, 1.0)
	var coasting = VehicleAudio.layer_gains(6500.0, 0.0)
	check(pulling.low < 0.01 and pulling.on > 0.9 and pulling.off < 0.01, "high revs on throttle play the on loop")
	check(coasting.off > coasting.on, "high revs off throttle play the overrun loop")
	var ear = Vector3.ZERO
	check(VehicleAudio.doppler(Vector3(50, 0, 0), Vector3(-30, 0, 0), ear, Vector3.ZERO) > 1.05, "an approaching car sounds higher")
	check(VehicleAudio.doppler(Vector3(50, 0, 0), Vector3(30, 0, 0), ear, Vector3.ZERO) < 0.95, "a receding car sounds lower")

func sound_files() -> void:
	SoundBank.warm()
	check(SoundBank.streams.has("engine-v6-on") and SoundBank.streams.has("step-snow-3") and SoundBank.streams.size() >= 60, "every sound file loads while the game sets up")
	for engine in VehicleAudio.ENGINES:
		for layer in ["low", "on", "off"]:
			var stream: AudioStreamWAV = SoundBank.stream("engine-%s-%s" % [engine, layer])
			check(stream != null and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "engine %s %s loops" % [engine, layer])
	for sound in ["tyres-gravel", "tyres-asphalt", "tyres-snow", "tyres-grass", "tyres-water", "tyres-skid-asphalt", "tyres-skid-gravel", "siren-police", "siren-ambulance"]:
		var stream: AudioStreamWAV = SoundBank.stream(sound)
		check(stream != null and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, sound + " loops")
	for sound in ["engine-start", "car-door", "trunk-open", "trunk-close", "crash-light", "crash-heavy", "body-thud", "rope-hook", "backfire-1", "backfire-2", "backfire-3"]:
		var stream: AudioStreamWAV = SoundBank.stream(sound)
		check(stream != null and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, sound + " is a one shot")

func fleet_engines() -> void:
	var known = true
	for car in CarRegistry.cars + RallyCarModel.models:
		known = known and str(car.get("engine", "")) in VehicleAudio.ENGINES
	check(known, "every player and rally car names a known engine")
	check(VehicleAudio.character(Node3D.new()) == "sedan", "a car without an engine sounds like a sedan")
	for variant in RallyCarModel.models.size():
		if str(RallyCarModel.models[variant].engine) == "i5":
			var car = RallyCarModel.build(variant)
			check(VehicleAudio.character(car) == "i5", "a built rally car carries its engine")
			car.free()
			break
	var stage_sounds = true
	for index in StageRegistry.count():
		var stage = Stage.new(index)
		var surface = stage.biome.surface_sound(stage.at(200.0))
		var verge = stage.biome.surface_sound(stage.at(200.0) + stage.side(200.0) * 25.0)
		stage_sounds = stage_sounds and surface in ["gravel", "asphalt", "snow", "grass"] and verge in ["gravel", "asphalt", "snow", "grass"]
		stage.free()
	check(stage_sounds, "every stage names a tyre and footstep surface on and off the road")

func cars_around() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	await game.start_game()
	var audio = game.soundscape.vehicles
	var ear: Vector3 = game.camera.global_position
	var nodes: Array[Node3D] = []
	for i in range(5):
		var node = Node3D.new()
		node.set_meta("engine", "i5")
		game.add_child(node)
		node.global_position = ear + Vector3(20.0 + i * 20.0, 0, 0)
		nodes.append(node)
		game.racers.append({"node": node, "role": "racer", "id": 900 + i})
	var police = Node3D.new()
	game.add_child(police)
	police.global_position = ear + Vector3(0, 0, 30)
	game.racers.append({"node": police, "role": "opening_police", "id": 950})
	for frame in range(30):
		for node in nodes:
			node.global_position += Vector3(0, 0, -0.4)
		police.global_position += Vector3(0.2, 0, 0)
		audio.update(1.0 / 60.0, true, false)
	var heard: Array = audio.voices.map(func(voice): return voice.car)
	var nearest = [nodes[0].get_instance_id(), nodes[1].get_instance_id(), police.get_instance_id()]
	check(nearest.all(func(id): return id in heard), "the nearest running cars get the voices")
	check(not nodes[4].get_instance_id() in heard, "a far car waits for a free voice")
	var voice = audio.voices[heard.find(nodes[0].get_instance_id())]
	check(voice.on.stream == SoundBank.stream("engine-i5-on") or voice.low.stream == SoundBank.stream("engine-i5-low"), "a voice plays its car's engine")
	check(voice.tyre.stream == SoundBank.stream("tyres-" + game.stage.biome.surface_sound(nodes[0].global_position)), "tyres sound the stage surface")
	check(police.get_instance_id() in audio.siren_cars, "the opening police drives with its siren")
	# A car stopping dead from 24 m/s crashed.
	for frame in range(30):
		nodes[0].global_position += Vector3(0, 0, -0.4)
		audio.update(1.0 / 60.0, true, false)
	for frame in range(10):
		audio.update(1.0 / 60.0, true, false)
	check(audio.shots.any(func(shot): return shot.stream in [SoundBank.stream("crash-heavy"), SoundBank.stream("crash-light")]), "a car stopping dead sounds like a crash")
	# The driver gets out: the door.
	game.in_car = true
	audio.update(1.0 / 60.0, true, false)
	check(audio.was_driving and audio.own.rpm < 2000.0, "the own engine idles at the wheel")
	game.in_car = false
	audio.update(1.0 / 60.0, true, false)
	check(audio.shots.any(func(shot): return shot.stream == SoundBank.stream("car-door")), "getting out shuts a door")
	check(audio.all_players.size() == 5 + 1 + VehicleAudio.VOICES * 5 + 2 + 6, "pausing reaches every car sound")
	audio.update(1.0 / 60.0, false, false)
	check(audio.voices.all(func(entry): return entry.car == 0) and audio.cars.is_empty(), "ending the outing releases every voice")
	game.queue_free()
	await process_frame
