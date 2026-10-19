extends "res://tests/harness.gd"
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	var audio = game.soundscape
	check(audio.birds.stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "bird ambience is a sparse one shot")
	for take in range(1, audio.BIRD_TAKES + 1):
		check(load("res://audio/bird-%d.wav" % take).loop_mode == AudioStreamWAV.LOOP_DISABLED, "bird song %d is a one shot" % take)
	check(is_equal_approx(audio.birds.volume_db, -37.0), "bird ambience intensity is reduced by 80 percent")
	check(audio.cicadas.stream.loop_mode == AudioStreamWAV.LOOP_DISABLED and audio.cicadas.stream.get_length() > 1.0 and audio.cicadas.volume_db < -25.0, "cicadas are a quiet one-shot chorus")
	check(game.wind_audio.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "wind is a seamless loop")
	check(is_equal_approx(game.fire_audio.volume_db, -26.0), "cooking fire intensity is reduced by 80 percent")
	check(is_equal_approx(audio.BIRD_GAP_MIN, 20.0) and is_equal_approx(audio.BIRD_GAP_MAX, 40.0), "bird calls have long randomized gaps")
	check(is_equal_approx(audio.FIRE_GAP_MIN, 18.0) and is_equal_approx(audio.FIRE_GAP_MAX, 30.0), "fire crackle has long randomized gaps")
	check(is_equal_approx(audio.FIRE_BURST_SECONDS, 1.5), "fire crackle uses short bursts")
	for surface in ["gravel", "grass", "snow", "asphalt"]:
		for take in range(1, audio.STEP_TAKES + 1):
			var step: AudioStreamWAV = load("res://audio/step-%s-%d.wav" % [surface, take])
			check(step != null and step.loop_mode == AudioStreamWAV.LOOP_DISABLED and step.get_length() < 0.5, "footstep %s %d is a short one shot" % [surface, take])
	for sound in ["eat", "place-wood", "place-metal", "church-bell", "body-thud"]:
		check(load("res://audio/%s.wav" % sound).loop_mode == AudioStreamWAV.LOOP_DISABLED, sound + " is a one shot")
	var surface = game.stage.biome.surface_sound(game.stage.at(100.0))
	check(surface in ["gravel", "asphalt", "snow", "grass"] and ResourceLoader.exists("res://audio/step-%s-1.wav" % surface), "stage surface has footsteps (%s)" % surface)
	game.start_game()
	check(audio.active(), "audio active on start")
	game.paused = true
	check(not audio.active(), "pause suspends gameplay sound")
	game.paused = false
	game.dead = true
	check(not audio.active(), "death ends gameplay sound")
	game.dead = false
	game.playing = false
	game.start_game()
	check(audio.active(), "new outing restores gameplay audio state")
	await game._shutdown_audio()
	check(audio.shutting_down, "shutdown disables loop recovery")
	check(audio.vehicles.all_players.all(func(player): return not player.playing), "shutdown silences every car sound")
	game.queue_free()
	await process_frame
	print("SOUNDSCAPE RESULT: %d failures" % failures)
	finish()
