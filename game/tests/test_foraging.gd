extends SceneTree
const Props = preload("res://scripts/props.gd")
var failures = 0
func check(ok: bool, title: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + title)
	if not ok:
		failures += 1
func _initialize() -> void:
	call_deferred("run")
func first_item(stage: Node3D, kind: String, skip: int = -1) -> int:
	for i in range(stage.collectibles.size()):
		if i != skip and stage.collectibles[i].kind == kind:
			return i
	return -1
func run() -> void:
	var host = load("res://main.tscn").instantiate()
	var guest = load("res://main.tscn").instantiate()
	for game in [host, guest]:
		root.add_child(game)
	await process_frame
	for game in [host, guest]:
		game.set_process(false)
		game.room.set_process(false)
		game.start_game()
		game.in_car = false
		game.room.connected = true
	host.room.is_host = true
	host.room.player_id = "host"
	guest.room.player_id = "guest"
	var mushroom = first_item(host.stage, "mushrooms")
	var berry = first_item(host.stage, "berries")
	check(mushroom >= 0 and berry >= 0, "forest exposes collectible mushrooms and berry bushes")
	if mushroom < 0 or berry < 0:
		quit(1)
		return
	host.walker = host.stage.collectibles[mushroom].pos
	check(host.foraging.collect(mushroom) and host.foraging.stock().mushrooms == 1, "picking a mushroom adds it to personal inventory")
	check(not host.foraging.collect(mushroom), "picked mushroom cannot be collected twice")
	var cap_index = host.stage.collectibles[mushroom].parts.MushroomCaps[0]
	var cap = host.stage.collectible_parts.MushroomCaps[cap_index]
	check(cap.hidden and cap.pose.basis.x.length() == 0, "picked mushroom disappears from instanced forest")
	host.walker = Vector3(1000, 0, 1000)
	check(not host.foraging.collect(berry), "remote resources cannot be picked from a distance")
	host.walker = host.stage.collectibles[berry].pos
	check(host.foraging.collect(berry) and host.foraging.stock().berries == 3, "berry bush yields three portions")
	var berry_parts_hidden = true
	for index in host.stage.collectibles[berry].parts.ForestBerries:
		var part = host.stage.collectible_parts.ForestBerries[index]
		berry_parts_hidden = berry_parts_hidden and part.hidden and part.pose.basis.x.length() == 0
	check(berry_parts_hidden, "harvested berries disappear from all affected spatial batches")
	var guest_mushroom = first_item(host.stage, "mushrooms", mushroom)
	guest.walker = guest.stage.collectibles[guest_mushroom].pos
	host.room._apply_command({"action": "collect", "player": "guest", "state": guest.room.local_state(), "placement": {"resource_id": guest_mushroom}})
	check(host.foraging.stock("guest").mushrooms == 1 and host.foraging.stock("host").mushrooms == 1, "guest harvest credits only the authenticated guest inventory")
	host.room._apply_command({"action": "collect", "player": "guest", "state": guest.room.local_state(), "placement": {"resource_id": guest_mushroom}})
	check(host.foraging.stock("guest").mushrooms == 1, "competing or repeated harvest does not duplicate resources")
	host.grill = Props.grill(host)
	host.grill.position = host.stage.clearings[0]
	host.camp = Node3D.new()
	host.add_child(host.camp)
	host.camp.position = host.grill.position + Vector3(2, 0, 0)
	host.cooking = true
	host.cook_time = 35
	host.walker = host.grill.position
	check(not host.foraging.can_mount() and not host.foraging.mount(), "full sixteen-skewer grill refuses mushrooms")
	check(host.commit_meat(-1), "eating meat releases a skewer")
	check(host.foraging.can_mount() and host.foraging.mount(), "nearby player mounts a mushroom on the free skewer")
	check(host.foraging.stock().mushrooms == 0 and host.foraging.free_skewers(-1) == 0, "mounting consumes inventory and occupies exactly one skewer")
	check(host.grill.get_node("FoodSkewer_15/MushroomFood").visible, "mounted mushroom is visible on the grill")
	check(not host.foraging.can_eat("mushroom"), "freshly mounted mushroom must cook first")
	host.elapsed += 10
	check(host.eat_foraged("mushroom"), "cooked mushroom starts its eating animation")
	host._update_eating(1.2)
	check(host.meat_prop.get_node("Mushroom0").visible and not host.meat_prop.get_node("Mushroom2").visible and not host.meat_prop.get_node("Meat0").visible, "mushroom animation shows mushroom bites rather than meat")
	var food_time = host.eat_time
	host.paused = true
	host._process(1)
	check(host.eat_time == food_time, "pause freezes mushroom eating")
	host.paused = false
	host._update_eating(3.6)
	check(host.foraging.free_skewers(-1) == 1 and host.meat_prop == null, "finished mushroom meal clears the hand and releases its skewer")
	host.walker = host.stage.collectibles[berry].pos
	check(host.eat_foraged("berries"), "berries can be eaten away from a camp")
	host._update_eating(1.2)
	check(not host.meat_prop.get_node("SkewerStick").visible and host.meat_prop.get_node("Berry0").visible and not host.meat_prop.get_node("Berry2").visible, "berry eating brings a handful to the mouth and removes bitten berries")
	host._update_eating(3.6)
	check(host.foraging.stock().berries == 2, "berry meal consumes one portion")
	host.eat_foraged("berries")
	host._update_eating(0.5)
	host._cancel_eat()
	check(host.foraging.stock().berries == 2, "interrupted eating does not consume an unfinished portion")
	guest.walker = host.grill.position
	host.room._apply_command({"action": "mount_mushroom", "player": "guest", "state": guest.room.local_state(), "placement": {"source": -1}})
	check(host.foraging.stock("guest").mushrooms == 0 and host.foraging.skewers["-1"].size() == 1, "guest can mount their own mushroom on the shared grill")
	host.elapsed += 10
	guest.room.apply_world(host.room.world_state())
	check(guest.stage.harvested.has(mushroom) and guest.stage.harvested.has(berry), "late guest sees harvested resources removed")
	check(guest.foraging.stock().mushrooms == 0 and guest.grill.get_meta("mushrooms") == 1, "guest receives personal inventory and grill mushrooms")
	guest.walker = guest.grill.position
	check(guest.eat_foraged("mushroom"), "guest can animate eating a ready shared mushroom")
	guest._update_eating(2.7)
	check(guest.room.commands[-1].action == "eat_mushroom", "guest meal submits an authoritative mushroom command")
	host.room._apply_command({"action": "eat_mushroom", "player": "guest", "state": guest.room.local_state(), "placement": {"source": -1}})
	check(host.foraging.skewers["-1"].is_empty() and host.meat_prop == null, "guest meal consumes once without animating host hands")
	guest.room.apply_world(host.room.world_state())
	check(guest.grill.get_meta("mushrooms") == 0, "mushroom removal replicates back to the guest")
	guest._cancel_eat()
	guest.eat_kind = "berries"
	guest.eat_time = 0.8
	host.room._update_peers([{"id": "guest", "name": "Друг", "slot": 1, "state": guest.room.local_state()}])
	host.room.clock = -100
	host.room._process(0.01)
	check(host.room.peers["guest"].skewer.get_meta("food_kind") == "berries" and not host.room.peers["guest"].skewer.get_node("SkewerStick").visible, "friends see the berry hand animation without a skewer")
	for game in [host, guest]:
		await game._shutdown_audio()
		game.queue_free()
	await process_frame
	print("FORAGING RESULT: %d failures" % failures)
	quit(1 if failures else 0)
