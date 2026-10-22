extends "res://tests/harness.gd"
# «Поречье»: the road crosses a stream gully on a log bridge. The opening and
# closing police drive the whole stage, so they must get across the bridge
# instead of stopping in front of it: their scenery probe reaches below the
# deck, so the log cribs under it collide only near the stream bed.
const StageRegistry = preload("res://scripts/stages/stage_registry.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	var index = -1
	for i in range(StageRegistry.count()):
		if StageRegistry.entry(i).id == "sever":
			index = i
	game.select_stage(index)
	await game.start_game()
	game.course.phase = "racing"
	game.in_car = true
	var bridge: float = game.stage.biome.BRIDGE_S
	var half: float = game.stage.road_width(bridge) * 0.5
	# The service vehicles' scenery probe swept along the deck.
	var clear = true
	for line in [-half + 1.2, 0.0, half - 1.2]:
		var s = bridge - 20.0
		while s < bridge + 20.0:
			var a = game.race_at(s) + game.race_side(s) * line
			var b = game.race_at(s + 2.0) + game.race_side(s + 2.0) * line
			a.y = game.stage.ground(a)
			b.y = game.stage.ground(b)
			clear = clear and game.stage.solids.hit(a, b, 1.1).is_empty()
			s += 2.0
	check(clear, "nothing under the deck reaches the traffic probes on the bridge")
	var pier = game.race_at(bridge) + Vector3.DOWN * (game.stage.biome.GULLY_DEPTH + 0.4) + game.race_side(bridge) * 0.5
	check(not game.stage.solids.hit(pier + game.race_direction(bridge) * 4.0, pier, 0.5).is_empty(), "the crib pier still stops a car in the stream bed")
	game.car.position = game.race_at(0.0) + Vector3(0, 0, 400)
	for role in ["opening_police", "closing_police"]:
		for old in game.racers:
			old.node.queue_free()
		game.racers.clear()
		game.spawn_course_car(role, 900)
		var police: Dictionary = game.racers[-1]
		police.s = bridge - 60.0
		police.node.position = game.race_at(police.s)
		police.node.position.y = game.stage.ground(police.node.position)
		for i in range(60 * 30):
			game.crews.update_racers_step(1.0 / 30.0)
			if float(police.s) > bridge + 40.0:
				break
		check(float(police.s) > bridge + 40.0, "%s crosses the bridge (s=%.1f, bridge at %.0f)" % [role, police.s, bridge])
	await game._shutdown_audio()
	game.free()
	print("POLICE BRIDGE RESULT: %d failures" % failures)
	finish()
