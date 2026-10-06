extends SceneTree
var failures = 0
func check(ok: bool, title: String) -> void:
	if ok:
		print("PASS: " + title)
	else:
		failures += 1
		push_error(title)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	for variant in range(3):
		game.select_stage(variant)
		var crowd = game.spectators
		check(crowd.groups.size() == (4 if variant == 2 else 8), "NPC camps populate stage %d" % variant)
		check(crowd.people.size() == (8 if variant == 2 else 12), "NPC spectators populate stage %d" % variant)
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
	quit(1 if failures else 0)
