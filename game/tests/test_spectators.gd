extends "res://tests/harness.gd"
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	for variant in range(RallyStage.STAGES.size()):
		game.select_stage(variant)
		var crowd = game.spectators
		# Two people at every clearing camp (canyon summits are reached on foot and
		# have none) plus one at each of four roadside spots outside the village.
		var camps = game.stage.clearings.size() - (game.stage.canyon.mesas.size() if game.stage.desert else 0)
		var roadside = 0 if game.stage.provence else 4
		check(crowd.groups.size() == camps + roadside, "NPC camps populate stage %d" % variant)
		check(crowd.people.size() == camps * 2 + roadside, "NPC spectators populate stage %d" % variant)
		var clear_road = true
		var grounded = true
		for group in crowd.groups:
			clear_road = clear_road and game.stage.road_distance(group.car.position) > 4.6
			grounded = grounded and absf(group.car.position.y - game.stage.ground(group.car.position)) < 0.01
		check(clear_road and grounded, "parked NPC cars leave the road open and rest on terrain")
		var actions = {}
		var props_match = true
		for time in range(90):
			crowd.update(float(time), 0.0, false)
			for person in crowd.people:
				actions[person.action] = true
				props_match = props_match and person.can.visible == (person.action == "beer") and person.food.visible == (person.action == "eat")
		check(props_match, "NPC props match activity")
		var served = false
		for group in crowd.groups:
			served = served or int(group.servings) < 10
		check(served, "NPCs consume skewers from their own 10-stick grills")
		check(crowd.snapshot().size() == crowd.groups.size(), "NPC grill servings are snapshot-ready")
		check(actions.has("beer") and actions.has("eat") and actions.has("idle"), "NPCs alternate between watching, drinking and eating")
		var second = load("res://scripts/spectators.gd").new()
		second.game = game
		game.add_child(second)
		second.rebuild()
		crowd.update(91.5, 0.0, false)
		second.update(91.5, 0.0, false)
		var same = second.people.size() == crowd.people.size()
		for i in range(crowd.people.size()):
			same = same and second.people[i].avatar.position == crowd.people[i].avatar.position and second.people[i].action == crowd.people[i].action and second.people[i].time == crowd.people[i].time
		check(same, "late join reconstructs identical NPC positions and animation phase")
		second.free()
		check(game.personal_chairs.is_empty() and game.camp == null and not game.has_chairs, "NPC furniture never counts as a player's camp or chair")
		var previous = crowd.clock
		game.playing = true
		game.paused = true
		game._process(0.5)
		check(crowd.clock == previous, "paused game freezes NPC animations")
		game.paused = false
		game.playing = false
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	print("NPC RESULT: %d failures" % failures)
	finish()
