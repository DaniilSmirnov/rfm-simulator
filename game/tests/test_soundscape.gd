extends SceneTree
var failures = 0
func check(value: bool, message: String) -> void:
	print(("PASS: " if value else "FAIL: ") + message)
	if not value: failures += 1
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	var audio = game.soundscape
	check(audio.birds.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "bird ambience loops")
	check(is_equal_approx(audio.birds.volume_db, -37.0), "bird ambience intensity is reduced by 80 percent")
	check(is_equal_approx(game.fire_audio.volume_db, -26.0), "cooking fire intensity is reduced by 80 percent")
	check(audio.clips.step.loop_mode == AudioStreamWAV.LOOP_DISABLED, "footsteps remain one shots")
	check(audio.clips.step.data.size() > 1000, "footstep PCM exists")
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
	game.queue_free()
	await process_frame
	print("SOUNDSCAPE RESULT: %d failures" % failures)
	quit(1 if failures else 0)
