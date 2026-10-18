extends "res://tests/harness.gd"
# A loaded stage at rest costs little physics: the NPC camps' chairs, tables,
# grills and cars settle, people standing or sitting still get no pushing
# collider, and standing trunks are not re-posed every tick. Before this the
# camps never slept and the physics step alone took 50-95 ms (2-5 fps).
const PropActors = preload("res://scripts/core/prop_actors.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://scripts/core/game.gd").new()
	game.defer_world = true
	root.add_child(game)
	await process_frame
	game.select_stage(4)
	game.rng.seed = 20261008
	await game.start_game()
	game.paused = false
	for i in range(240):
		await physics_frame
	var physics_ms = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	check(physics_ms < 30.0, "a stage at rest steps its physics in %.1f ms" % physics_ms)
	var actors = game.stage.solids.prop_ground.get_node_or_null("Actors") if game.stage.solids.prop_ground != null else null
	var still = 0
	if actors != null:
		for key in actors._still:
			if int(actors._still[key]) >= PropActors.STILL_TICKS and not actors.bodies.has(key):
				still += 1
	check(actors == null or still > 0, "people who stand still near props carry no collider (%d)" % still)
	game.free()
	print("PROP SLEEP RESULT: %d checks, %d failures" % [checks, failures])
	finish()
