extends "res://tests/harness.gd"
const Meals = preload("res://scripts/camp/stage_meals.gd")
const Merge = preload("res://scripts/core/mesh_merge.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var host = load("res://main.tscn").instantiate()
	var guest = load("res://main.tscn").instantiate()
	for game in [host, guest]:
		game.defer_world = true
		root.add_child(game)
		game.set_process(false)
		game.room.set_process(false)
		game.playing = true
		game.in_car = false
		game.car.position = Vector3(100, 100, 100)
		for i in range(2):
			var camp = Node3D.new()
			camp.name = "YurtCamp%d" % i
			game.stage.add_child(camp)
			camp.position = Vector3(i * 15, 100, 0)
			Meals.build(camp)
			Merge.bake(camp)
	await process_frame
	var meals = host.camp_cooking.meals
	var pots = meals.pots(host)
	check(pots.size() == 2 and meals.snapshot(host) == [10, 10], "each baked yurt camp retains an independent ten-portion meal")
	host.walker = pots[0].global_position + Vector3(0, 0, 2)
	host.camera.position = host.walker + Vector3.UP * 1.7
	host.camera.look_at(pots[0].global_position + Vector3.UP * 1.3)
	check(host.interaction.current().get("action") == "plov" and host.interaction.current().label.contains("куырдак"), "F offers kuyrdak from the pot the player looks at")
	host.interaction.activate()
	check(host.eat_kind == "kuyrdak" and host.meat_prop.get_node("PlovBowl").visible, "eating starts the bowl-and-spoon animation for kuyrdak")
	host._update_eating(2.7)
	host._update_eating(0.1)
	check(meals.snapshot(host) == [9, 10] and not pots[0].get_node("Rice/Portion_09").visible, "animation consumes exactly once and removes food from the correct pot")
	host._cancel_eat()
	host.walker += Vector3(30, 0, 0)
	check(not host.camp_cooking.consume(0) and not host.camp_cooking.consume(999), "distant or forged meal sources cannot consume inventory")
	host.walker = pots[0].global_position
	host.in_car = true
	check(not host.camp_cooking.consume(0), "eating from a car is rejected")
	host.in_car = false
	host.room.connected = true
	host.room.is_host = true
	host.room.player_id = "host"
	guest.room.connected = true
	guest.room.is_host = false
	guest.room.player_id = "guest"
	guest.walker = pots[0].global_position
	guest.camp_cooking.apply_snapshot(host.camp_cooking.snapshot())
	check(guest.camp_actions.eat_plov(0), "a guest can start eating the same shared meal")
	guest._update_eating(2.7)
	check(meals.snapshot(host) == [9, 10] and guest.camp_cooking.meals.snapshot(guest) == [9, 10] and guest.room.commands[-1].placement.source == 0, "guest sends an explicit source without speculative inventory changes")
	host.room._apply_command({"player": "guest", "action": "eat_plov", "state": guest.room.local_state(), "placement": {"source": 0}})
	check(meals.snapshot(host) == [8, 10], "the host applies a guest meal to the shared pot")
	guest.camp_cooking.apply_snapshot(host.camp_cooking.snapshot())
	check(guest.camp_cooking.meals.snapshot(guest) == [8, 10], "late snapshots synchronize both pots even without a personal campfire")
	guest._cancel_eat()
	for i in range(8):
		check(host.camp_cooking.consume(0), "remaining portions are edible")
	check(meals.snapshot(host) == [0, 10] and not pots[0].get_node("Rice").visible and not host.camp_actions.eat_plov(0), "the tenth portion empties only its pot, with no eleventh meal")
	var snapshot = host.camp_cooking.snapshot()
	guest.camp_cooking.apply_snapshot(snapshot)
	check(not guest.camp_actions.eat_plov(0), "an empty pot stays empty after synchronization")
	for game in [host, guest]:
		await game._shutdown_audio()
		game.queue_free()
	await process_frame
	print("STAGE MEALS RESULT: %d failures" % failures)
	finish()
