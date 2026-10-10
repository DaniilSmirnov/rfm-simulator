extends RefCounted
# The spectators' camp: placing furniture and flags, the grill, digging snow,
# drinking beer and eating. Guest commands reach these through
# shared_actions.gd with game.acting set (see action_context.gd).
const Props = preload("res://scripts/props.gd")

var game

func valid_furniture_spot(spot: Vector3, kind: String, ignored_owner: String = "") -> bool:
	# Dug out of the snow, level on terraces, dry by the lakes: the stage decides.
	if not game.stage.biome.camp_allowed(spot, kind):
		return false
	if game.spectators != null and game.spectators.occupied(spot):
		return false
	if game.stage.road_distance(spot) < 6.0:
		return false
	if not game.stage.solids.hit(spot, spot, 0.8, false).is_empty():
		return false
	if not game.stage.rock_hit(spot, spot, 0.8, false).is_empty():
		return false
	if game.stage.obstacle_hit(spot, spot, 0.8) >= 0:
		return false
	if kind != "table" and game.camp != null and spot.distance_to(game.camp.position) < 1.5:
		return false
	if kind != "grill" and game.grill != null and spot.distance_to(game.grill.position) < 1.4:
		return false
	if kind not in ["firewood", "cauldron"] and game.camp_cooking.fire != null and spot.distance_to(game.camp_cooking.fire.position) < 1.5:
		return false
	if kind not in ["firewood", "cauldron"] and game.camp_cooking.pot != null and spot.distance_to(game.camp_cooking.pot.position) < 1.5:
		return false
	for owner in game.personal_chairs:
		if kind == "chairs" and owner == (game.chair_owner() if ignored_owner == "" else ignored_owner):
			continue
		if spot.distance_to(game.personal_chairs[owner].position) < 1.1:
			return false
	for owner in game.personal_flags:
		for flag in game.personal_flags[owner]:
			if spot.distance_to(flag.position) < 1.0:
				return false
	return true

func dig_snow(spot: Vector3) -> void:
	var owner = game.cargo.actor()
	if game.actor_in_car() or game.paused or game.dead or game.finished or not game.cargo.held.has(owner) or game.cargo.held[owner].kind != "shovel" or game.actor_pos().distance_to(spot) > 4.0: return
	var local_actor = owner == game.chair_owner()
	if local_actor and game.cargo.shovel_busy(): return
	# The room server keeps a spot only together with a yaw.
	if game.room.submit("dig_snow", {"pos": game.room.a(spot), "yaw": 0.0}):
		game.cargo.animate_shovel()
		return
	if game.stage.snow.dig(game.stage, spot):
		game.soundscape.placement()
		if local_actor: game.cargo.animate_shovel()
	elif local_actor: game.toast("Здесь уже расчищено или раскопок слишком много.")

func begin_placement(kind: String) -> void:
	if game.packing.active():
		game.toast("Выезд завершён. Соберите предметы через F.")
		return
	if game.seated:
		game.stand_up()
	if game.in_car or game.beers >= 30:
		game.toast("Для размещения выйди из машины и встань на ноги.")
		return
	if kind in game.cargo.KINDS and not game.cargo.take(kind):
		return
	cancel_placement()
	if kind == "flag" and game.flag_count() >= game.FLAGS_PER_PLAYER:
		game.toast("Можно поставить только три флага.")
		return
	game.placement_kind = kind
	game.placement_yaw = game.view_yaw
	game.placement_preview = Node3D.new()
	game.add_child(game.placement_preview)
	match kind:
		"table": Props.table(game.placement_preview)
		"chairs": Props.chair(game.placement_preview, Vector3.ZERO)
		"grill": Props.grill(game.placement_preview)
		"firewood": Props.campfire(game.placement_preview)
		"cauldron": Props.cauldron(game.placement_preview)
		"flag": Props.rally_fans_map_flag(game.placement_preview, Vector3.ZERO, 0.0, game.flag_count())
	game.placement_material = Props.material(Color("82c991"))
	for child in game.placement_preview.find_children("*", "MeshInstance3D", true, false):
		child.material_override = game.placement_material
		child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	update_placement()
	game.toast("Выбери место: WASD и обзор. Q — повернуть, F — поставить, Esc — отменить.")

func update_placement() -> void:
	if game.placement_preview == null:
		return
	var spot = game.walker + Vector3(-sin(game.view_yaw), 0, -cos(game.view_yaw)) * 2.5
	if game.placement_kind == "cauldron" and game.camp_cooking.fire != null and spot.distance_to(game.camp_cooking.fire.position) < 1.5:
		spot = game.camp_cooking.fire.position
	if game.placement_kind == "firewood" and game.camp_cooking.pot != null and spot.distance_to(game.camp_cooking.pot.position) < 1.5:
		spot = game.camp_cooking.pot.position
	spot.y = game.stage.ground(spot)
	game.placement_preview.position = spot
	game.placement_preview.rotation.y = game.placement_yaw
	game.placement_valid = spot.distance_to(game.walker) <= 5.0 and valid_furniture_spot(spot, game.placement_kind)
	game.placement_material.albedo_color = Color("82c991") if game.placement_valid else Color("d75e53")

func cancel_placement() -> void:
	if is_instance_valid(game.placement_preview):
		game.placement_preview.queue_free()
	game.placement_preview = null
	game.placement_kind = ""

func confirm_placement() -> void:
	update_placement()
	if game.placement_preview == null or not game.placement_valid:
		game.toast("Здесь поставить нельзя: расчисти снег и отойди от трассы, деревьев и мебели.")
		return
	var kind = game.placement_kind
	var spot = game.placement_preview.position
	var yaw = game.placement_yaw
	if game.room.is_guest():
		game.room.submit(kind, {"pos": game.room.a(spot), "yaw": yaw})
	else:
		match kind:
			"table", "chairs", "grill", "firewood", "cauldron": game.cargo.deploy(kind, spot, yaw)
			"flag": place_flag(spot, yaw)
	game.soundscape.placement()
	cancel_placement()

func near_camp() -> bool:
	return game.camp != null and game.actor_position().distance_to(game.camp.position) < 7

func nearby_drink_source() -> bool:
	return near_camp() or (game.spectators != null and game.spectators.nearby_table(game.player_position()) >= 0)

func food_source_group() -> int:
	if not game.actor_in_car() and near_camp() and game.grill != null:
		return -1 if game.cook_time >= 35 and game.grill_servings > 0 else -2
	if not game.actor_in_car() and game.spectators != null:
		return game.spectators.nearby_grill(game.actor_position())
	return -2

func can_eat_meat() -> bool:
	return game.playing and not game.paused and not game.dead and not game.finished and not game.in_car and game.eat_time < 0 and game.drink_time < 0 and food_source_group() != -2

func place_table(spot: Vector3 = Vector3.INF, yaw: float = 0.0) -> bool:
	if game.actor_in_car():
		return false
	var moving = spot != Vector3.INF
	if game.camp != null and not moving:
		return false
	if not moving:
		spot = game.actor_pos() + Vector3(-sin(game.actor_yaw()), 0, -cos(game.actor_yaw())) * 2.5
	if not valid_furniture_spot(spot, "table"):
		return false
	if game.camp == null:
		game.camp = Node3D.new()
		game.camp.set_meta("gear_owner", game.cargo.actor())
		game.add_child(game.camp)
		Props.table(game.camp)
	game.camp.position = spot
	game.camp.position.y = game.stage.ground(spot)
	game.camp.rotation.y = yaw
	game.toast("Стол установлен.")
	return true

func place_chairs(spot: Vector3 = Vector3.INF, yaw: float = 0.0, owner: String = "") -> bool:
	if game.actor_in_car():
		return false
	if owner == "":
		owner = game.chair_owner()
	if spot == Vector3.INF:
		if game.personal_chairs.has(owner):
			return false
		spot = game.camp.position + Vector3(-1.6, 0, 0.7) if near_camp() else game.actor_pos() + Vector3(-sin(game.actor_yaw()), 0, -cos(game.actor_yaw())) * 2.5
	if not valid_furniture_spot(spot, "chairs", owner):
		return false
	apply_chair(owner, spot, yaw)
	game.toast("Твой стул установлен.")
	return true

func apply_chair(owner: String, spot: Vector3, yaw: float) -> void:
	if not game.personal_chairs.has(owner):
		var chair = Node3D.new()
		game.add_child(chair)
		Props.chair(chair, Vector3.ZERO)
		game.personal_chairs[owner] = chair
	game.personal_chairs[owner].position = spot
	game.personal_chairs[owner].position.y = game.stage.ground(spot)
	game.personal_chairs[owner].rotation.y = yaw
	game.has_chairs = not game.personal_chairs.is_empty()

func place_flag(spot: Vector3 = Vector3.INF, yaw: float = 0.0, owner: String = "", replicated: bool = false) -> bool:
	var moving = spot != Vector3.INF
	if owner == "":
		owner = game.flag_owner()
	if not replicated and (game.actor_in_car() or not moving or game.flag_count(owner) >= game.FLAGS_PER_PLAYER):
		return false
	if not valid_furniture_spot(spot, "flag"):
		return false
	var flags: Array = game.personal_flags.get(owner, [])
	var node = Props.rally_fans_map_flag(game, spot, yaw, flags.size())
	node.position.y = game.stage.ground(spot)
	flags.append(node)
	game.personal_flags[owner] = flags
	return true

func start_grill(spot: Vector3 = Vector3.INF, yaw: float = 0.0, replicated: bool = false) -> bool:
	var moving = spot != Vector3.INF
	if not replicated and game.actor_in_car():
		return false
	if game.cooking and not moving:
		return false
	if not moving:
		spot = game.camp.position + Vector3(0.3, 0, -2.4) if game.camp != null else game.actor_pos() + Vector3(-sin(game.actor_yaw()), 0, -cos(game.actor_yaw())) * 2.5
	if not replicated and not valid_furniture_spot(spot, "grill"):
		return false
	if game.grill != null:
		game.grill.position = spot
		game.grill.position.y = game.stage.ground(spot)
		game.grill.rotation.y = yaw
		game.fire_audio.position = game.grill.position
		return true
	game.grill = Props.grill(game)
	game.grill.set_meta("gear_owner", game.cargo.actor())
	game.grill_servings = Props.FOOD_PORTIONS
	game.grill.position = spot
	game.grill.position.y = game.stage.ground(spot)
	game.grill.rotation.y = yaw
	game.cooking = true
	game.smoke = GPUParticles3D.new()
	game.grill.add_child(game.smoke)
	game.smoke.position = Vector3(0, 1.1, 0)
	game.smoke.amount = 20
	game.smoke.lifetime = 3.0
	var process = ParticleProcessMaterial.new()
	process.direction = Vector3(0.2, 1, 0)
	process.spread = 20
	process.initial_velocity_min = 0.7
	process.initial_velocity_max = 1.1
	process.gravity = Vector3(0, 0.35, 0)
	process.scale_min = 0.15
	process.scale_max = 0.4
	process.color = Color("bfc1ab")
	game.smoke.process_material = process
	var mesh = SphereMesh.new()
	mesh.radial_segments = 5
	mesh.rings = 3
	var mat = Props.material(Color("bfc1ab"))
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.2
	mesh.material = mat
	game.smoke.draw_pass_1 = mesh
	game.fire_audio.position = game.grill.global_position
	# Fire crackle is scheduled sparsely by Soundscape instead of looping continuously.
	game.toast("Угли разгорелись. Шашлык готовится 35 секунд. Следи за таймером СУ.")
	return true

func update_cooking(delta: float) -> void:
	if game.cooking and game.cook_time < 35:
		game.cook_time = minf(35, game.cook_time + delta)
		if game.cook_time >= 35:
			game.toast("Шашлык готов! Подойди к лагерю и нажми X.")

func drink_beer() -> bool:
	if game.beers >= 30:
		return false
	if game.cargo.held.has(game.chair_owner()):
		return false
	if not game.playing or game.paused or game.dead or game.finished:
		return false
	if game.in_car or not nearby_drink_source():
		game.toast("Подойди к своему или соседскому столу пешком.")
		return false
	if game.eat_time >= 0 or game.drink_time >= 0 or game.beer_timer > 0:
		game.toast("Пока хватит. Лучше посмотри ралли.")
		return false
	game.drink_time = 0.0
	game.drink_committed = false
	game.can_opened = false
	game.beer_prop = Props.beer_hand(game.avatar_variant)
	game.camera.add_child(game.beer_prop)
	update_drinking(0)
	game.show_consumption_warning("beer")
	return true

func update_drinking(delta: float) -> void:
	if game.drink_time < 0:
		return
	game.drink_time = minf(game.DRINK_DURATION, game.drink_time + delta)
	var rest = Vector3(0.4, -0.72, -0.7)
	var raised = Vector3(0.29, -0.18, -0.64)
	var mouth = Vector3(0.13, -0.11, -0.46)
	if game.drink_time < 0.55:
		game.beer_prop.position = rest.lerp(raised, smoothstep(0.0, 0.55, game.drink_time))
		game.beer_prop.rotation = Vector3(0.0, 0.0, -0.1)
	elif game.drink_time < 1.25:
		game.beer_prop.position = raised.lerp(mouth, smoothstep(0.8, 1.25, game.drink_time))
		game.beer_prop.rotation.x = 0.18 * smoothstep(0.8, 1.25, game.drink_time)
	elif game.drink_time < 2.5:
		var tilt = smoothstep(1.25, 1.65, game.drink_time)
		game.beer_prop.position = mouth + Vector3(0, sin(game.drink_time * 16) * 0.004, 0)
		game.beer_prop.rotation.x = 0.18 + tilt * 0.95
		game.beer_prop.rotation.z = -0.1 + sin(game.drink_time * 7) * 0.016
	else:
		var lower = smoothstep(2.5, game.DRINK_DURATION, game.drink_time)
		game.beer_prop.position = mouth.lerp(rest, lower)
		game.beer_prop.rotation.x = lerpf(1.13, 0, lower)
	if not game.can_opened and game.drink_time >= 0.65:
		game.can_opened = true
		game.beer_prop.get_node("PullTab").rotation.x = -0.7
		game.beer_prop.get_node("Opening").show()
		game.beer_audio.stream = load("res://audio/can-open.wav")
		game._play_audio(game.beer_audio)
	if not game.drink_committed and game.drink_time >= 1.8:
		game.drink_committed = true
		game.beers += 1
		if game.beers >= 3:
			game.drunk_strength = minf(1.0, game.drunk_strength + 0.45)
		game.beer_timer = 1.0
		if game.beers >= 30:
			game.sober_remaining = game.SOBER_SECONDS
			cancel_placement()
			if game.seated:
				game.stand_up()
			game.jump_height = 0
			game.jump_velocity = 0
			if game.in_car:
				game.in_car = false
				game.walker = game.car.position
				game.walker.y = game.stage.ground(game.walker)
			game.walker.y = game.stage.ground(game.walker)
			game.vehicle_motion.velocity = Vector3.ZERO
			game.speed = 0
			game.toast("Тяжёлое опьянение. Ты упал. Восстановление займёт три минуты.")
		game.beer_audio.stream = load("res://audio/beer-sip.wav")
		game._play_audio(game.beer_audio)
	if game.drink_time >= game.DRINK_DURATION:
		cancel_drink()
		if game.beers < 30:
			game.toast("Алкоголь ухудшает координацию и реакцию. Не садись за руль.")

func cancel_drink() -> void:
	game.drink_time = -1.0
	if is_instance_valid(game.beer_prop):
		game.beer_prop.queue_free()
	game.beer_prop = null
	game.camera.fov = 68
	if game.beer_audio != null:
		game.beer_audio.stop()

func eat_meat(source_group: int = -2) -> bool:
	if game.cargo.held.has(game.chair_owner()):
		return false
	if not game.playing or game.paused or game.dead or game.finished or game.eat_time >= 0 or game.drink_time >= 0:
		return false
	game.eat_source_group = food_source_group() if source_group == -2 else source_group
	if game.eat_source_group == -2:
		game.toast("Шашлык не готов или рядом нет мангала с порциями.")
		return false
	game.eat_kind = "meat"
	game.eat_time = 0
	game.eat_committed = false
	game.meat_prop = Props.meat_hand(game.avatar_variant)
	game.camera.add_child(game.meat_prop)
	update_eating(0)
	game.toast("Шампур горячий. Приятного аппетита!")
	return true

func eat_plov() -> bool:
	if game.cargo.held.has(game.chair_owner()) or not game.camp_cooking.can_eat() or game.eat_time >= 0 or game.drink_time >= 0:
		return false
	game.eat_kind = "plov"
	game.eat_time = 0
	game.eat_committed = false
	game.meat_prop = Props.meat_hand(game.avatar_variant, "plov")
	game.camera.add_child(game.meat_prop)
	update_eating(0)
	game.toast("Едим плов из миски. Приятного аппетита!")
	return true

func eat_foraged(kind: String, source: int = -2) -> bool:
	if game.cargo.held.has(game.chair_owner()):
		return false
	if source == -2 and not game.foraging.can_eat(kind):
		return false
	game.eat_kind = kind
	game.forage_source = (game.foraging.nearby_source() if source == -2 else source) if kind == "mushroom" else -2
	if kind == "mushroom" and (game.foraging.grill_node(game.forage_source) == null or game.player_position().distance_to(game.foraging.grill_node(game.forage_source).position) > 4 or game.foraging.ready_index(game.forage_source) < 0):
		return false
	game.food_species = game.foraging.ready_species(game.forage_source) if kind == "mushroom" else "edible"
	game.eat_time = 0
	game.eat_committed = false
	game.meat_prop = Props.meat_hand(game.avatar_variant, kind)
	Props.style_mushrooms(game.meat_prop, game.food_species)
	game.camera.add_child(game.meat_prop)
	update_eating(0)
	if kind == "mushroom":
		game.show_consumption_warning("mushroom")
	else:
		game.toast("Едим ягоды.")
	return true

func commit_meat(source_group: int = -2) -> bool:
	if game.actor_in_car():
		return false
	var source = source_group
	if source == -2:
		source = game.eat_source_group if game.eat_source_group != -2 else food_source_group()
	if source == -1:
		if game.grill == null or (not near_camp() and game.actor_position().distance_to(game.grill.position) > 4) or game.cook_time < 35 or game.grill_servings <= 0:
			return false
		game.grill_servings -= 1
		Props.set_grill_servings(game.grill, game.grill_servings)
	elif game.spectators == null or source < 0 or source >= game.spectators.groups.size() or game.actor_position().distance_to(game.spectators.groups[source].grill.position) > 4 or not game.spectators.consume_serving(source):
		return false
	game.eaten = true
	game.toast("Шашлык удался. Осталось %d шампуров." % game.grill_servings if source == -1 else "У NPC нашлась порция шашлыка. Приятного аппетита!")
	game.eat_source_group = -2
	return true

func update_eating(delta: float) -> void:
	if game.eat_time < 0:
		return
	game.eat_time = minf(game.EAT_DURATION, game.eat_time + delta)
	var lift = Props.food_lift(game.eat_time)
	game.meat_prop.position = Vector3(0.34, -0.72, -0.70).lerp(Vector3(0.10, -0.43, -0.39), lift)
	game.meat_prop.rotation = Vector3(-0.18 * lift, 0.15, -0.25 + lift * 0.17)
	Props.pose_food(game.meat_prop, game.eat_time, game.eat_kind)
	if not game.eat_committed and game.eat_time >= 2.6:
		game.eat_committed = true
		if game.room.is_authority():
			if game.eat_kind == "meat":
				commit_meat()
			elif game.eat_kind == "plov":
				game.camp_cooking.consume()
			else:
				game.foraging.consume(game.eat_kind, "", game.forage_source)
		else:
			game.room.submit(game.EAT_ACTIONS[game.eat_kind], {"source": game.eat_source_group if game.eat_kind == "meat" else game.forage_source})
	if game.eat_time >= game.EAT_DURATION:
		cancel_eat()

func cancel_eat() -> void:
	game.eat_time = -1
	game.eat_kind = "meat"
	game.forage_source = -2
	game.eat_source_group = -2
	if is_instance_valid(game.meat_prop):
		game.meat_prop.queue_free()
	game.meat_prop = null
