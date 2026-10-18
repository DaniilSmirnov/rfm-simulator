extends "res://tests/harness.gd"
# Entering a stage does its heavy work behind the loading screen, not during the
# camera's fly-in: the ground under every loose prop is built and the props get
# their bodies while loading, and route searches share a small time budget.
const Navigation = preload("res://scripts/people/crowd_navigation.gd")
const PropGround = preload("res://scripts/stages/prop_ground.gd")

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
	var solids = game.stage.solids
	var missing = 0
	var loose = 0
	for record in solids.movables:
		if not is_instance_valid(record.node) or record.anchored:
			continue
		loose += 1
		var center: Vector3 = (record.node.global_transform * record.box).get_center()
		if not solids.prop_ground.tiles.has(Vector2i(floori(center.x / PropGround.TILE), floori(center.z / PropGround.TILE))):
			missing += 1
	check(loose > 20 and missing == 0, "the ground under all %d loose props is built while loading" % loose)
	check(game.movable_props.records.size() >= loose, "props have their bodies before the first frame of play")
	game.paused = false
	var worst = 0
	var last = Time.get_ticks_usec()
	for i in range(90):
		await process_frame
		var now = Time.get_ticks_usec()
		worst = maxi(worst, now - last)
		last = now
	check(worst < 600000, "no frame of the fly-in stalls (%d ms)" % (worst / 1000))
	# A search past its deadline still advances one cell and then yields.
	var person: Dictionary = game.spectators.people[0]
	var start: Vector3 = person.avatar.position
	var goal = start + Vector3(25, 0, 0)
	goal.y = game.stage.ground(goal)
	var ctx = Navigation.context(game, person, start, goal, false)
	game.stage.rocks.append({"pos": start.lerp(goal, 0.5), "radius": 3.0, "height": 3.0})
	ctx = Navigation.context(game, person, start, goal, false)
	var search = Navigation.begin(game, start, goal, ctx)
	if not search.has("route"):
		check(Navigation.step(game, search, Navigation.MAX_VISITS, Time.get_ticks_usec()) == 1, "an expired frame budget allows one cell")
	# A goal inside an obstacle is given up at once instead of searched for.
	var inside = start.lerp(goal, 0.5)
	inside.y = game.stage.ground(inside)
	var blocked = Navigation.begin(game, start, inside, ctx)
	check(blocked.has("route") and blocked.route.is_empty(), "a goal inside an obstacle is not searched for")
	game.free()
	print("STAGE START RESULT: %d checks, %d failures" % [checks, failures])
	finish()
