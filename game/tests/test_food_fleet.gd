extends SceneTree
const Props = preload("res://scripts/props.gd")
var checks = 0
var failures = 0
func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(title)
	else:
		print("PASS: " + title)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var names = {}
	var shapes = {}
	for i in range(9):
		var car = Props.player_car(i)
		names[car.get_meta("model")] = true
		var signature = ""
		for part in car.get_children():
			if part is MeshInstance3D:
				signature += str(part.mesh.get_aabb(), part.transform)
		shapes[signature] = true
		car.free()
	check(names.size() == 9 and shapes.size() == 9, "nine models have different names and geometry")
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
		game.walker = game.stage.clearings[0]
		game.place_table()
		game.place_chairs()
		game.start_grill()
		game.cook_time = 35
	host.room.player_id = "host"
	guest.room.player_id = "guest"
	host.room.connected = true
	host.room.is_host = true
	guest.room.connected = true
	guest.room.is_host = false
	check(guest.eat_meat(), "guest starts its own food animation")
	check(not guest.eat_meat() and not guest.drink_beer(), "food cannot overlap eating or beer")
	guest._toggle_car()
	check(not guest.in_car, "eating blocks getting into a car")
	guest._update_eating(1.2)
	check(not guest.meat_prop.get_node("Meat2").visible and guest.meat_prop.get_node("Meat1").visible, "first bite removes the top piece")
	host.room._update_peers([{"id": "guest", "name": "Друг", "slot": 7, "state": guest.room.local_state()}])
	host.room._process(0.05)
	var peer = host.room.peers.guest
	check(peer.car.get_meta("model") == "Renault Duster", "remote model comes from assigned room slot")
	check(peer.skewer.visible and not peer.can.visible and peer.arm.rotation.x > 1, "friend sees lifted skewer and animated arm")
	check(not peer.skewer.get_node("Meat2").visible, "friend sees the same eaten pieces")
	var peer_time = peer.eat_time
	host.room._update_peers([{ "id": "guest", "name": "Друг", "slot": 7, "state": guest.room.local_state() }])
	host.room._process(0.05)
	check(peer.eat_time > peer_time, "repeated snapshot does not restart the animation")
	guest.paused = true
	var time_before = guest.eat_time
	guest._process(0.3)
	check(guest.eat_time == time_before, "pause freezes eating")
	guest.paused = false
	guest._update_eating(1.5)
	check(not guest.eaten and guest.room.commands.size() == 1 and guest.room.commands[0].action == "eat", "guest sends completion after final bite")
	var host_hand = host.meat_prop
	host.room._apply_command({"id": "guest:1", "action": "eat", "state": guest.room.local_state()})
	check(host.eaten and host.meat_prop == host_hand and host.eat_time < 0, "guest meal commits without animating host's hands")
	check(host.grill_servings == 15 and int(host.grill.get_meta("servings")) == 15, "one of sixteen grill skewers disappears after a shared meal")
	guest.room.apply_world(host.room.world_state())
	check(guest.eaten, "shared meal completion reaches guest")
	guest._update_eating(1)
	guest._cancel_eat()
	guest.camp.queue_free()
	guest.camp = null
	guest.grill = null
	guest.cook_time = 0
	var npc_group = 0
	guest.walker = guest.spectators.groups[npc_group].table.position
	check(guest.nearby_drink_source() and guest.can_eat_meat(), "player can access an NPC table, beer and cooked skewers")
	var npc_before = int(guest.spectators.groups[npc_group].servings)
	check(guest.eat_meat() and guest.commit_meat(), "player eats a serving from an NPC grill")
	check(int(guest.spectators.groups[npc_group].servings) == npc_before - 1, "NPC grill stock decreases for a visiting player")
	guest._cancel_eat()
	check(guest.drink_beer(), "player can drink beer at an NPC table")
	guest._cancel_drink()
	check(guest.meat_prop == null and guest.eat_time < 0, "hand clears when animation ends")
	host.room._update_peers([{"id": "guest", "name": "Друг", "slot": 7, "state": guest.room.local_state()}])
	host.room._process(0.1)
	check(not peer.skewer.visible, "remote skewer clears when animation ends")
	guest.eaten = false
	guest.eat_meat()
	guest.die("test")
	check(guest.meat_prop == null and guest.eat_time < 0 and not guest.eaten, "death clears unfinished meal without credit")
	var old_position = host.car.position
	host.select_player_car(4)
	check(host.car.get_meta("model") == "Hyundai Solaris" and host.car.position == old_position, "local assigned model preserves car position")
	for game in [host, guest]:
		await game._shutdown_audio()
		game.queue_free()
	await process_frame
	print("FOOD/FLEET RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
