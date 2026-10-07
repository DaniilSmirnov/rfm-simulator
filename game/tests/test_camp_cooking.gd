extends SceneTree
const Props = preload("res://scripts/props.gd")
var failures = 0
func check(ok: bool, title: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + title)
	if not ok:
		failures += 1

func run_command(host, guest, action: String, placement: Dictionary = {}) -> void:
	host.room._apply_command({"player": "guest", "action": action, "state": guest.room.local_state(), "placement": placement})

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var host = load("res://main.tscn").instantiate()
	var guest = load("res://main.tscn").instantiate()
	root.add_child(host)
	root.add_child(guest)
	await process_frame
	for game in [host, guest]:
		game.set_process(false)
		game.room.set_process(false)
		game.start_game()
		game.in_car = false
		game.stage.trees.clear()
		game.stage.rocks.clear()
	var origin: Vector3 = host.stage.clearings[0]
	host.walker = origin
	host.car.position = origin + Vector3(0, 0, 12)
	host.heading = 0
	check(not host.cargo.take("firewood") and not host.camp_cooking.mount(), "firewood must be taken from the trunk before lighting a fire")
	host.walker = host.cargo.point(host.cargo.poses()["local"])
	check(host.cargo.take("firewood") and not host.cargo.boxes("local")[3], "taking wood from the open trunk hides its bundle")
	host.walker = origin
	var fire_spot = origin + Vector3(3, 0, 0)
	check(host.cargo.deploy("firewood", fire_spot, 0.3), "carried wood deploys a freely positioned campfire")
	fire_spot = host.camp_cooking.fire.position
	check(host.camp_cooking.fire.has_node("Flames") and host.camp_cooking.pot == null, "campfire starts without a pot")
	check(not host.cargo.deploy("cauldron", fire_spot, 0), "a pot cannot appear without taking it from the trunk")
	host.walker = host.cargo.point(host.cargo.poses()["local"])
	host.begin_placement("cauldron")
	check(host.placement_preview != null and host.cargo.held.local.kind == "cauldron", "taking a cauldron offers free placement")
	host.cancel_placement()
	host.walker = fire_spot
	host.camera.position = fire_spot + Vector3(0, 1.7, 2)
	host.camera.look_at(fire_spot + Vector3(0, 0.45, 0))
	check(host.interaction.current().get("action", "") == "mount_cauldron", "contextual F offers mounting the carried pot on the fire")
	host.interaction.activate()
	check(host.camp_cooking.phase == "empty" and host.camp_cooking.pot.get_node("EmptyBottom").visible and not host.camp_cooking.pot.get_node("Rice").visible, "mounted pot is empty and visibly hollow")
	host.camera.look_at(fire_spot + Vector3(0, 1.1, 0))
	check(host.interaction.current().get("action", "") == "plov_cook", "F starts cooking in the empty cauldron")
	host.interaction.activate()
	var food = host.camp_cooking.pot.get_node("Rice")
	check(host.camp_cooking.phase == "cooking" and food.visible and host.camp_cooking.pot.get_node("Bubbles").visible, "cooking shows ingredients and animated bubbles")
	host.elapsed = 1
	host.camp_cooking.update(20)
	var puff = host.camp_cooking.pot.get_node("Steam").get_child(0)
	var steam_position = puff.position
	host.elapsed = 2
	host.camp_cooking.update(0)
	check(puff.position != steam_position and host.camp_cooking.servings == 0 and not host.camp_cooking.can_eat(), "steam moves during cooking and raw plov cannot be eaten")
	host.paused = true
	var before = host.camp_cooking.cook_time
	host._process(5)
	check(host.camp_cooking.cook_time == before, "pause freezes plov cooking")
	host.paused = false
	host.camp_cooking.update(25)
	check(host.camp_cooking.phase == "ready" and host.camp_cooking.servings == 10 and not host.camp_cooking.pot.get_node("Bubbles").visible, "cooking completes with exactly ten portions")
	var full_height = food.position.y
	check(host.eat_plov() and host.meat_prop.get_node("PlovBowl").visible and not host.meat_prop.get_node("SkewerStick").visible, "plov uses a bowl and spoon eating animation")
	host._update_eating(2.7)
	host._update_eating(0.1)
	check(host.camp_cooking.servings == 9 and food.position.y < full_height and not food.get_node("Portion_09").visible, "a completed meal consumes once and lowers the actual food level")
	host._cancel_eat()
	for i in range(9):
		check(host.camp_cooking.consume(), "another portion can be shared")
	check(host.camp_cooking.phase == "exhausted" and host.camp_cooking.servings == 0 and not food.visible and not host.eat_plov() and not host.camp_cooking.start(), "ten meals empty the pot without an eleventh portion or automatic refill")
	host.room.connected = true
	host.room.is_host = true
	host.room.player_id = "host"
	guest.room.connected = true
	guest.room.is_host = false
	guest.room.player_id = "guest"
	# Use a fresh empty pot to test cooking and meals requested by a guest.
	host.camp_cooking.remove_pot()
	host.camp_cooking.pot = Props.cauldron(host)
	host.camp_cooking.pot.position = fire_spot
	host.camp_cooking.phase = "empty"
	host.camp_cooking.pot.set_meta("gear_owner", "host")
	host.camp_cooking.fire.set_meta("gear_owner", "host")
	guest.walker = fire_spot
	guest.car.position = origin + Vector3(0, 0, 15)
	host.room._update_peers([{"id": "guest", "name": "Друг", "state": guest.room.local_state()}])
	run_command(host, guest, "plov_cook")
	check(host.camp_cooking.phase == "cooking", "host accepts a nearby guest's cooking request")
	host.camp_cooking.update(45)
	guest.room.apply_world(host.room.world_state())
	var old_pot = guest.camp_cooking.pot
	guest.room.apply_world(host.room.world_state())
	check(guest.camp_cooking.pot == old_pot and guest.camp_cooking.servings == 10, "late and repeated snapshots preserve ready pot without duplicates")
	guest.walker = origin + Vector3(30, 0, 0)
	run_command(host, guest, "eat_plov")
	check(host.camp_cooking.servings == 10, "host rejects eating plov remotely")
	guest.walker = fire_spot
	check(guest.eat_plov(), "guest animates their own bowl")
	host.room._update_peers([{"id": "guest", "name": "Друг", "state": guest.room.local_state()}])
	host.room.busy = true
	host.room._process(0.5)
	check(host.room.peers.guest.skewer.get_node("PlovBowl").visible and host.room.peers.guest.skewer.get_meta("food_kind") == "plov", "friends see the bowl, spoon and food animation")
	guest._update_eating(2.7)
	check(guest.camp_cooking.servings == 10 and guest.room.commands[-1].action == "eat_plov", "guest requests a meal without speculative shared inventory changes")
	run_command(host, guest, "eat_plov")
	guest.room.apply_world(host.room.world_state())
	check(host.camp_cooking.servings == 9 and guest.camp_cooking.servings == 9, "shared portions and visible food shrink in multiplayer")
	guest._cancel_eat()
	host.course.phase = "complete"
	host.course.pass_index = 2
	host.walker = fire_spot
	check(not host.packing.pack(fire_spot + Vector3(0.2, 0, 0)), "packing retries cannot select an unrelated object")
	check(host.packing.pack(fire_spot) and host.camp_cooking.pot == null and host.camp_cooking.fire != null, "cleanup takes the cauldron before the campfire")
	var trunk = host.cargo.point(host.cargo.poses()["host"])
	host.walker = trunk
	check(host.cargo.return_item(trunk), "cauldron returns to its owner's trunk")
	host.walker = fire_spot
	check(host.packing.pack(fire_spot) and host.camp_cooking.fire == null, "fire is extinguished and packed after the cauldron")
	host.walker = trunk
	check(host.cargo.return_item(trunk) and host.packing.remaining() == 0, "wood and stand are fully packed before finishing")
	guest.room.apply_world(host.room.world_state())
	check(guest.camp_cooking.fire == null and guest.camp_cooking.pot == null, "removed fire, pot, steam and food disappear from guest scene")
	for game in [host, guest]:
		await game._shutdown_audio()
		game.queue_free()
	await process_frame
	print("CAMP COOKING RESULT: %d failures" % failures)
	quit(1 if failures else 0)

