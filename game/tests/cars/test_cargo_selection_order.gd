extends "res://tests/harness.gd"
const Props = preload("res://scripts/core/props.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	var guest = load("res://main.tscn").instantiate()
	root.add_child(game)
	root.add_child(guest)
	await process_frame
	for scene in [game, guest]:
		scene.set_process(false)
		scene.room.set_process(false)
		scene.start_game()
		scene.in_car = false
		scene.stage.trees.clear()
		scene.stage.rocks.clear()
	var origin: Vector3 = game.stage.clearings[0]
	game.car.position = origin + Vector3(0, 0, 12)
	# Exercise every visible box against its actual model transform, on flat ground and slopes.
	game.stage.has_snow = true
	for tilt in [Vector3.ZERO, Vector3(0.42, 0, -0.24), Vector3(-0.42, 0, 0.24)]:
		for variant in range(RallyProps.PLAYER_MODELS.size()):
			game.select_player_car(variant)
			game.heading = 0 if variant % 2 == 0 else PI / 2
			game.car.rotation = Vector3(tilt.x, game.heading, tilt.z)
			var pose: Dictionary = game.cargo.poses().local
			game.walker = game.cargo.point(pose)
			game.camera.position = game.car.transform * Vector3(0, 1.6, Props.trunk_profile(variant).rear + 2.2)
			for index in range(Props.CARGO_KINDS.size()):
				var target: Vector3 = game.car.transform * Props.cargo_point(Props.trunk_profile(variant), index)
				game.camera.look_at(target)
				check(game.interaction.current().get("value", "") == Props.CARGO_KINDS[index], "each cargo box is selectable on car %d, box %d" % [variant, index])
				if index >= 3:
					game.camera.look_at(target + game.car.basis * Vector3(-0.25 if index == 3 else 0.25, 0.1, 0))
					check(game.interaction.current().get("value", "") == Props.CARGO_KINDS[index], "wood and pot accept forgiving off-centre aim")
				game.interaction.activate()
				check(game.cargo.held.get("local", {}).get("kind", "") == Props.CARGO_KINDS[index] and not game.in_car, "F takes selected gear without entering car")
				game.cancel_placement()
				game.camera.look_at(game.cargo.point(pose))
				check(game.interaction.current().get("action", "") == "return_gear", "F offers return at the tilted trunk")
				game.interaction.activate()
				check(not game.cargo.held.has("local"), "F returns gear before placing anything")
	var original_stage = game.stage
	var registry = preload("res://scripts/stages/stage_registry.gd")
	for stage_index in range(registry.count()):
		var stage = preload("res://scripts/stages/stage.gd").new(stage_index)
		game.stage = stage
		var pose: Dictionary = game.cargo.poses().local
		game.walker = game.cargo.point(pose)
		game.camera.look_at(game.cargo.cargo_position(pose, 5))
		game.cargo.update(1)
		check(game.cargo.boxes("local")[5] == stage.has_snow, "shovel inventory follows stage snow support")
		check(game.car.get_node("TrunkBoxes/Box_shovel").visible == stage.has_snow, "shovel geometry follows stage snow support")
		var offers: Array = []
		game.cargo.offers(offers, game.interaction)
		check(offers.any(func(item): return item.value == "shovel") == stage.has_snow, "shovel offer follows stage snow support")
		check(game.cargo.take("shovel") == stage.has_snow, "direct shovel request follows stage snow support")
		game.cargo.held.clear()
		# The host validates the same restriction for guest commands.
		var state = game.room.local_state()
		state.pos = game.room.a(game.walker)
		game.room._apply_command({"player": "local", "action": "take_gear", "state": state, "placement": {"resource_id": 5}})
		check(game.cargo.held.has("local") == stage.has_snow, "host validates shovel request against stage")
		game.cargo.held.clear()
		game.stage = original_stage
		stage.free()
	game.stage.has_snow = false
	game.car.rotation = Vector3.ZERO
	game.heading = 0
	var pot_spot = origin + Vector3(3, 0, 0)
	var placements = [["cauldron", pot_spot], ["chairs", origin + Vector3(-3, 0, 0)], ["grill", origin + Vector3(0, 0, 3)], ["firewood", pot_spot], ["table", origin + Vector3(0, 0, -3)]]
	for entry in placements:
		game.walker = game.cargo.point(game.cargo.poses().local)
		check(game.cargo.take(entry[0]), "take independently: " + entry[0])
		game.walker = origin
		check(game.cargo.deploy(entry[0], entry[1], 0.2), "place in arbitrary order: " + entry[0])
		if entry[0] == "cauldron":
			check(game.camp_cooking.fire == null and not game.camp_cooking.start(), "pot can stand alone but cannot cook without heat")
			guest.camp_cooking.apply_snapshot(game.camp_cooking.snapshot())
			check(guest.camp_cooking.pot != null and guest.camp_cooking.fire == null, "multiplayer preserves a pot placed before firewood")
	check(game.camp_cooking.heated() and game.camp_cooking.start(), "firewood placed later heats the existing pot")
	game.camp_cooking.update(45)
	guest.camp_cooking.apply_snapshot(game.camp_cooking.snapshot())
	check(guest.camp_cooking.heated() and guest.camp_cooking.servings == 10, "multiplayer synchronizes independent fire and cooked pot")
	for scene in [game, guest]:
		await scene._shutdown_audio()
		scene.queue_free()
	await process_frame
	print("CARGO ORDER RESULT: %d failures" % failures)
	finish()
