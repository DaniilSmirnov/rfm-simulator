extends "res://tests/harness.gd"
const Props = preload("res://scripts/core/props.gd")
const Loc = preload("res://scripts/ui/loc.gd")
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
	host.cooking = true
	host.camp_grill.lit = true
	host.camp_grill.fire_time = host.camp_grill.COALS_SECONDS
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
		var record: Dictionary = host.injuries.records.get("player:host", {})
		check(host.injuries.down and record.get("phase", "") == "lying" and record.get("cause", "") == "poison", species + " makes the eater collapse")
		check(host.meat_prop == null and host.eat_time < 0, "collapsing drops the meal from the hand")
		var ambulance = host.injuries._ambulance(int(record.get("ambulance", -1)))
		check(not ambulance.is_empty() and ambulance.role == "ambulance" and ambulance.target_key == "player:host", "an ambulance drives to the poisoned player")
		check(host.course.red_flag and host.injuries.red_flag(), "poisoning red-flags the stage like a casualty")
		check(host.injuries.hud_line().begins_with(Loc.t("ОТРАВЛЕНИЕ · СКОРАЯ В ПУТИ · %d М").get_slice("·", 0)), "HUD names the poisoning while the ambulance comes")
		host.injuries._stand("player:host", record)
		check(not host.injuries.down and host.injuries.limp > 0, "medics get the poisoned player up as after a hit")
		host.injuries.records.clear()
		host.injuries.limp = 0.0
		host.racers = host.racers.filter(func(racer): return racer.get("role", "") != "ambulance")
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
	check(not host.injuries.down and host.injuries.records.get("player:guest", {}).get("cause", "") == "poison", "a guest's poisoning lays the guest down, not the host")
	guest.injuries.apply_snapshot(host.injuries.snapshot())
	check(guest.injuries.down and guest.toast_label.text == Loc.t(guest.injuries.PoisonCollapse.TOAST), "the guest collapses and reads why")
	check(guest.injuries.hud_line().begins_with(Loc.t("ОТРАВЛЕНИЕ · СКОРАЯ В ПУТИ · %d М").get_slice("·", 0)), "guest HUD names the poisoning")
	host.injuries.records.clear()
	guest.injuries.apply_snapshot(host.injuries.snapshot())
	check(not guest.injuries.down, "guest stands up when the host's record clears")
	guest.injuries.limp = 0.0
	# Effects carry the host's end time; the shared clock (elapsed) is replicated.
	guest.elapsed = host.elapsed
	guest.foraging.apply_snapshot(host.foraging.snapshot())
	check(guest.mushroom_effect.movement_multiplier() == 0.5, "poison halves walking and running speed")
	check(is_equal_approx(guest.mushroom_effect.remaining, 10), "guest receives their own ten second effect")
	guest.mushroom_effect.update(3)
	guest.foraging.apply_snapshot(host.foraging.snapshot())
	check(is_equal_approx(guest.mushroom_effect.remaining, 7), "repeated snapshot never restarts the timer")
	host.elapsed += 4
	guest.elapsed = host.elapsed
	guest.mushroom_effect.serial = 0
	guest.foraging.apply_snapshot(host.foraging.snapshot())
	check(is_equal_approx(guest.mushroom_effect.remaining, 6), "late snapshot starts only the remaining duration")
	guest.mushroom_effect.update(6)
	check(not guest.mushroom_effect.overlay.visible, "guest colors return to normal")
	check(guest.mushroom_effect.movement_multiplier() == 1.0, "movement recovers when poison expires")
	host.foraging.skewers["-1"] = [{"ready_at": host.elapsed}]
	host.walker = host.grill.position
	check(host.foraging.consume("mushroom", "", -1) and host.mushroom_effect.remaining == 0, "legacy and edible mushrooms do not invert colors")
	for game in [host, guest]:
		await game._shutdown_audio()
		game.queue_free()
	await process_frame
	print("POISON MUSHROOM RESULT: %d failures" % failures)
	finish()
