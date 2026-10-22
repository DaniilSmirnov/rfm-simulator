extends SceneTree
# Frame cost of the civil helicopter over the road, low over forest and high.
# godot --headless --path game -s res://tools/profile/profile_helicopter.gd -- [stage]
func _initialize():
	call_deferred("run")

func run():
	var game = load("res://tools/profile/cpu_profile_game.gd").new()
	var args = OS.get_cmdline_user_args()
	game.defer_world = true
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.select_stage(clampi(int(args[0]), 0, RallyStage.STAGES.size() - 1) if not args.is_empty() else 0)
	game.select_player_car(11)
	game.rng.seed = 20261008
	await game.start_game()
	game.in_car = true
	Input.action_press("forward")
	var s = 240.0
	var forest = game.stage.at(s) + game.stage.side(s) * 35.0
	for spot in [["road_low", game.stage.at(s), 1.5], ["forest_low", forest, 3.0], ["forest_tree_top", forest, 14.0], ["forest_high", forest, 40.0]]:
		var place: Vector3 = spot[1]
		game.car.position = place + Vector3(0, game.stage.ground(place) - place.y + spot[2], 0)
		game.vehicle_motion.initialized = true
		game.vehicle_motion.velocity = Vector3.ZERO
		var drive = []
		var frame = []
		for i in range(240):
			game.car.position.y = maxf(game.car.position.y, game.stage.ground(game.car.position) + spot[2])
			var t = Time.get_ticks_usec()
			game.player.drive_helicopter(1.0 / 60.0)
			drive.append(Time.get_ticks_usec() - t)
			t = Time.get_ticks_usec()
			game._process(1.0 / 60.0)
			frame.append(Time.get_ticks_usec() - t)
			await process_frame
		for pair in [["drive", drive], ["frame", frame]]:
			var samples: Array = pair[1]
			samples.sort()
			var sum = 0.0
			for sample in samples: sum += sample
			print("HELI_PROFILE ", spot[0], " ", pair[0], " avg_us=", snappedf(sum / samples.size(), 0.1), " p95_us=", samples[int(samples.size() * 0.95)])
	quit()
