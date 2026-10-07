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
	guest.room.is_host = false
	host.grill = Props.grill(host)
	host.grill.position = host.stage.clearings[0]
	host.grill_servings = 0
	host.cooking = true
	host.cook_time = 35
	for species in ["fly_agaric", "toadstool"]:
		var id = -1
		for i in range(host.stage.collectibles.size()):
			if host.stage.collectibles[i].get("species", "") == species:
				id = i
				break
		check(id >= 0, species + " grows in the forest")
		if id < 0:
			continue
		var item: Dictionary = host.stage.collectibles[id]
		var layer_name = "FlyAgaricCaps" if species == "fly_agaric" else "ToadstoolCaps"
		check(host.stage.get_node(layer_name).material_override.albedo_texture == Props.MUSHROOM_TEXTURES[species], "forest batches use the matching texture")
		host.walker = item.pos
		check(host.foraging.collect(id), species + " can be harvested")
		check(host.foraging.stock().mushroom_types == [species], "inventory preserves the mushroom species")
		for layer in item.parts:
			for index in item.parts[layer]:
				check(host.stage.collectible_parts[layer][index].hidden, "harvest hides the species cap and stem")
		host.walker = host.grill.position
		check(host.foraging.mount(-1), species + " mounts on a skewer")
		check(host.foraging.skewers["-1"][0].species == species, "cooking retains the species")
		var cap = host.grill.get_node("FoodSkewer_00/MushroomFood").find_children("MushroomCap*", "MeshInstance3D", true, false)[0]
		check(cap.material_override.albedo_texture == Props.MUSHROOM_TEXTURES[species], "grill uses the matching cap texture")
		check(not cap.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV].is_empty(), "grill cap has UV coordinates for visible texture details")
		check(not host.eat_foraged("mushroom"), "raw skewer cannot trigger an effect")
		host.elapsed += 10
		check(host.eat_foraged("mushroom"), "ready poisonous mushroom starts eating")
		check(host.food_species == species, "hand animation preserves the poisonous mushroom")
		check(not host.meat_prop.get_node("Mushroom0").get_child(1).mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV].is_empty(), "hand cap has UV coordinates")
		host._update_eating(1)
		host._cancel_eat()
		check(host.mushroom_effect.remaining == 0 and host.foraging.skewers["-1"].size() == 1, "cancelled bite neither consumes nor inverts colors")
		host.eat_foraged("mushroom")
		host._update_eating(2.7)
		check(host.mushroom_effect.remaining == 10 and host.mushroom_effect.overlay.visible, "completed bite triggers exactly ten seconds")
		check(not host.foraging.consume("mushroom", "", -1), "empty skewer cannot retrigger the effect")
		host._cancel_eat()
		guest.foraging.apply_snapshot(host.foraging.snapshot())
		check(guest.mushroom_effect.remaining == 0, "host meal never inverts a friend's screen")
		host.mushroom_effect.update(9.9)
		check(host.mushroom_effect.overlay.visible, "inversion remains visible before ten seconds")
		host.mushroom_effect.update(0.1)
		check(host.mushroom_effect.remaining < 0.0001, "inversion expires at ten seconds")
		host.mushroom_effect.update(0.001)
		check(not host.mushroom_effect.overlay.visible, "expired shader is hidden")
	# Guest consumption is authoritative; the host must not inherit its effect.
	host.foraging.skewers["-1"] = [{"ready_at": host.elapsed, "species": "fly_agaric"}]
	guest.walker = host.grill.position
	host.room._apply_command({"action": "eat_mushroom", "player": "guest", "state": guest.room.local_state(), "placement": {"source": -1}})
	check(not host.mushroom_effect.overlay.visible, "remote consumption leaves the host's colors normal")
	guest.foraging.apply_snapshot(host.foraging.snapshot())
	check(guest.mushroom_effect.remaining == 10, "guest receives their own ten second effect")
	guest.mushroom_effect.update(3)
	guest.foraging.apply_snapshot(host.foraging.snapshot())
	check(guest.mushroom_effect.remaining == 7, "repeated snapshot never restarts the timer")
	host.elapsed += 4
	guest.mushroom_effect.serial = 0
	guest.foraging.apply_snapshot(host.foraging.snapshot())
	check(guest.mushroom_effect.remaining == 6, "late snapshot starts only the remaining duration")
	guest.mushroom_effect.update(6)
	check(not guest.mushroom_effect.overlay.visible, "guest colors return to normal")
	host.foraging.skewers["-1"] = [{"ready_at": host.elapsed}]
	host.walker = host.grill.position
	check(host.foraging.consume("mushroom", "", -1) and host.mushroom_effect.remaining == 0, "legacy and edible mushrooms do not invert colors")
	for game in [host, guest]:
		await game._shutdown_audio()
		game.queue_free()
	await process_frame
	print("POISON MUSHROOM RESULT: %d failures" % failures)
	quit(1 if failures else 0)
