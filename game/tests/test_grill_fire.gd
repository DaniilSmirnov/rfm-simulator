extends "res://tests/harness.gd"
# The grill's whole life: out of the trunk cold and bare, lit by hand, flames
# burning down to coals, skewers laid on them, the meat roasting and eaten one
# skewer at a time. The gaze decides between the food and a free slot, and a
# guest sees the same fire.
const Props = preload("res://scripts/props.gd")
const GrillModel = preload("res://scripts/grill_model.gd")

func _initialize() -> void:
	call_deferred("run")

func aim(game, target: Vector3) -> void:
	var to = target - game.walker
	game.view_yaw = atan2(-to.x, -to.z)
	game.camera.position = game.walker + Vector3(0, 1.72, 0)
	game.camera.look_at(target)
	game.view_pitch = game.camera.rotation.x

func flames_visible(grill: Node3D) -> bool:
	var fire = grill.get_node("GrillFire")
	return fire.visible and fire.get_node("Flames").visible

func run() -> void:
	var host = load("res://main.tscn").instantiate()
	var guest = load("res://main.tscn").instantiate()
	for game in [host, guest]:
		root.add_child(game)
	await process_frame
	for game in [host, guest]:
		game.set_process(false)
		game.room.set_process(false)
		await game.start_game()
		game.in_car = false
	host.room.player_id = "host"
	host.room.connected = true
	host.room.is_host = true
	guest.room.player_id = "guest"
	guest.room.connected = true
	guest.room.is_host = false
	host.walker = host.stage.clearings[0]
	host.walker.y = host.stage.ground(host.walker)
	check(host.start_grill(), "the grill comes out of the trunk")
	var grill: Node3D = host.grill
	host.walker = grill.position + Vector3(0, 0, 1.6)
	host.walker.y = host.stage.ground(host.walker)
	var fire = host.camp_grill
	check(fire.phase() == "unlit" and fire.servings == 0 and int(grill.get_meta("servings")) == 0, "a fresh grill is cold and holds no skewers")
	check(not grill.get_node("GrillFire").visible, "a cold firebox shows neither coals nor flames")
	check(not fire.can_load() and not host.eat_meat(), "nothing to lay out or eat before the fire")
	check(not host.foraging.free_skewers(-1) > 0, "mushrooms cannot go on a cold grill")
	# Lighting it: flames first, coals later.
	check(fire.light() and fire.phase() == "flaring", "F lights the grill")
	host._update_cooking(3.0)
	fire.animate(0.0)
	check(flames_visible(grill) and fire.flame_height() > 0.3, "the lit grill burns with visible flames")
	check(not fire.can_load(), "skewers wait for the flames to burn down")
	host._update_cooking(fire.COALS_SECONDS)
	fire.animate(0.0)
	check(fire.phase() == "coals" and not flames_visible(grill) and grill.get_node("GrillFire").visible, "burnt-down flames leave glowing coals")
	# Laying out the skewers and waiting for the meat.
	check(fire.load_meat() and fire.servings == Props.FOOD_PORTIONS and fire.phase() == "cooking", "F lays ten skewers on the coals")
	check(int(grill.get_meta("servings")) == Props.FOOD_PORTIONS, "the laid-out skewers are visible")
	check(not fire.load_meat() and not host.eat_meat(), "a loaded grill takes no more meat and is not ready")
	host._update_cooking(fire.MEAT_SECONDS)
	check(fire.phase() == "ready" and host.can_eat_meat(), "the meat is ready after its own wait")
	# The gaze decides: the skewers or the free end of the grate.
	host.foraging.stock().mushrooms = 1
	aim(host, grill.position + Vector3(0, 0.99, 0))
	check(host.interaction.current().get("action", "") == "meat", "looking at the skewers offers the meat")
	check(host.eat_meat() and host.commit_meat() and fire.servings == Props.FOOD_PORTIONS - 1, "one skewer leaves the grate")
	host._cancel_eat()
	aim(host, grill.to_global(Vector3(0.42, 0.99, 0)))
	check(host.interaction.current().get("action", "") == "mount", "looking at the free slot offers a mushroom")
	aim(host, grill.to_global(Vector3(0, 0.8, 0)))
	check(host.interaction.current().get("action", "") != "load_meat", "a loaded grill offers no second batch")
	check(host.foraging.mount(-1) and host.camp_grill.mushroom_count() == 1, "the free slot takes the mushroom")
	# An emptied grate goes back to bare coals and takes a new batch.
	fire.servings = 1
	check(fire.take_serving() and fire.phase() == "coals" and int(grill.get_meta("servings")) == 0, "the last skewer leaves bare coals behind")
	aim(host, grill.to_global(Vector3(0, 0.8, 0)))
	check(host.interaction.current().get("action", "") == "load_meat", "the free coals offer a new batch")
	check(fire.load_meat() and fire.servings == Props.FOOD_PORTIONS - 1, "the new batch fills the slots the mushroom left free")
	# The guest sees the fire and its meat.
	guest.room.apply_world(host.room.world_state())
	check(guest.grill != null and guest.camp_grill.lit and guest.camp_grill.coals(), "the guest sees a lit grill on burnt-down coals")
	check(guest.camp_grill.servings == fire.servings and int(guest.grill.get_meta("servings")) == fire.servings, "the guest sees the same skewers")
	# A guest asks the host to light and load its own grill.
	host.packing.remove({"kind": "grill", "node": grill})
	grill.queue_free()
	host.start_grill(host.walker + Vector3(0, 0, -2.0), 0.0, true)
	guest.walker = host.grill.position
	guest.walker.y = guest.stage.ground(guest.walker)
	host.room._apply_command({"id": "guest:1", "action": "light_grill", "state": guest.room.local_state()})
	check(host.camp_grill.lit, "a guest can light the shared grill")
	host._update_cooking(fire.COALS_SECONDS)
	host.room._apply_command({"id": "guest:2", "action": "load_meat", "state": guest.room.local_state()})
	check(host.camp_grill.servings > 0, "a guest can lay out skewers on the shared grill")
	for game in [host, guest]:
		await game._shutdown_audio()
		game.queue_free()
	await process_frame
	print("GRILL FIRE RESULT: %d checks, %d failures" % [checks, failures])
	finish()
