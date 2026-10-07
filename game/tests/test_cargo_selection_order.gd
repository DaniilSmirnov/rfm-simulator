extends SceneTree
const Props = preload("res://scripts/props.gd")
var failures = 0
func check(ok: bool, title: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + title)
	if not ok:
		failures += 1
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
	for variant in range(10):
		game.selected_car = variant
		game.heading = 0 if variant % 2 == 0 else PI / 2
		var pose: Dictionary = game.cargo.poses().local
		game.walker = game.cargo.point(pose)
		game.camera.position = pose.pos + Vector3(0, 1.6, Props.trunk_profile(variant).rear + 2.2).rotated(Vector3.UP, game.heading)
		for index in range(5):
			var target: Vector3 = pose.pos + Props.cargo_point(Props.trunk_profile(variant), index).rotated(Vector3.UP, game.heading)
			game.camera.look_at(target)
			check(game.interaction.current().get("value", "") == Props.CARGO_KINDS[index], "each cargo box is selectable on car %d, box %d" % [variant, index])
			if index >= 3:
				game.camera.look_at(target + Vector3(-0.25 if index == 3 else 0.25, 0.1, 0).rotated(Vector3.UP, game.heading))
				check(game.interaction.current().get("value", "") == Props.CARGO_KINDS[index], "wood and pot accept forgiving off-centre aim")
			game.interaction.activate()
			check(game.cargo.held.get("local", {}).get("kind", "") == Props.CARGO_KINDS[index] and not game.in_car, "F takes selected gear without entering car")
			game.cancel_placement()
			check(game.cargo.return_item(game.cargo.point(pose)), "gear can be returned before placing anything")
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
	quit(1 if failures else 0)
