extends RefCounted
# One gaze-selected world object; proximity alone never chooses an action.
const Props = preload("res://scripts/props.gd")
const GrillModel = preload("res://scripts/grill_model.gd")
var game: Node3D

func offer(items: Array, point: Vector3, radius: float, reach: float, action: String, label: String, value: Variant = null) -> void:
	if game.walker.distance_to(point) > reach:
		return
	var offset = point - game.camera.global_position
	var forward = -game.camera.global_basis.z
	var depth = offset.dot(forward)
	if depth <= 0 or offset.distance_to(forward * depth) > radius:
		return
	items.append({"action": action, "label": label, "value": value, "depth": depth, "aim_error": offset.distance_to(forward * depth) / depth})

func current() -> Dictionary:
	if not game.playing or game.paused or game.dead or game.finished or game.drink_time >= 0 or game.eat_time >= 0 or (game.room.is_guest() and game.room.world_paused):
		return {}
	if game.in_car:
		return {"action": "car", "label": "Выйти из машины"} if absf(game.rides.speed()) <= 1 else {}
	if game.beers >= 30 or game.injuries.down:
		return {}
	if game.seated:
		return {"action": "stand", "label": "Встать со стула"}
	if game.player.relief.active:
		return {"action": "relief_stop", "label": "Закончить"}
	var items: Array = []
	game.cargo.offers(items, self)
	if not game.cargo.at_open_trunk(game.chair_owner()):
		offer(items, game.car.position + Vector3(0, 0.9, 0), 1.4, 4, "car", "Сесть в машину")
	game.rides.offers(items, self)
	game.camp_cooking.offers(items, self)
	if game.stage.solids.bell != null:
		offer(items, game.stage.solids.bell.handle_position(), 0.35, 2.0, "church_bell", "Позвонить в колокол")
	if game.packing.active():
		for item in game.packing.items():
			if item.kind == "firewood" and game.camp_cooking.pot != null:
				continue
			if item.kind != "flag" and game.cargo.held.has(game.chair_owner()):
				continue
			offer(items, item.node.global_position + Vector3(0, item.height, 0), item.radius, 3.5, "pack", item.label, item.node.global_position)
		return select_target(items)
	if game.cargo.held.has(game.chair_owner()):
		if game.cargo.held[game.chair_owner()].kind == "shovel" and game.stage.has_snow:
			var ray = -game.camera.global_basis.z
			for distance in range(1, 81):
				var point = game.camera.global_position + ray * (distance * 0.05)
				if point.y <= game.stage.snow.visible_height(game.stage, point):
					if game.stage.snow.can_dig(game.stage, point):
						offer(items, point, 0.15, 4.0, "dig_snow", "Копать снег", point)
					break
		return select_target(items)
	var owner = game.chair_owner()
	if game.personal_chairs.has(owner):
		offer(items, game.personal_chairs[owner].position + Vector3(0, 0.65, 0), 0.5, 2.5, "sit", "Сесть на стул")
	for id in game.stage.nearby_collectibles(game.walker, 2.1):
		if game.stage.harvested.has(id):
			continue
		var item = game.stage.collectibles[id]
		var mushroom = item.kind == "mushrooms"
		offer(items, item.pos + Vector3(0, 0.15 if mushroom else 0.6, 0), 0.28 if mushroom else 0.7, 1.8 if mushroom else 2.1, "collect", "Собрать гриб" if mushroom else ("Собрать виноград" if item.get("name", "") == "виноград" else "Собрать ягоды"), id)
	var sources: Array = [-1]
	if game.spectators != null:
		for i in range(game.spectators.groups.size()):
			sources.append(i)
	for source in sources:
		var grill = game.foraging.grill_node(source)
		if grill != null:
			grill_offers(items, source, grill)
		var table = game.camp if source == -1 else game.spectators.groups[source].table
		if table != null:
			offer(items, table.position + Vector3(0, 0.75, 0), 0.85, 3, "beer" if game.beer_timer <= 0 else "", "Выпить пиво" if game.beer_timer <= 0 else "")
	game.player.relief.offers(items, self)
	return select_target(items)

# A grill offers what the fan is looking at: the skewer rails carry the food
# (eat a serving, or put a mushroom on a free slot), the firebox below carries
# the fire (light it, lay out the meat once the coals are ready). The closest
# of those to the gaze is offered; a grill with nothing to give still occludes
# whatever stands behind it.
func grill_offers(items: Array, source: int, grill: Node3D) -> void:
	var meat = game.foraging.meat_count(source)
	var mushrooms = int(grill.get_meta("mushrooms", 0))
	var own = source == -1
	var candidates: Array = []
	if meat > 0 and (not own or game.camp_grill.ready()):
		candidates.append(_rails(grill, 0, meat, "meat", "Съесть шашлык", source))
	if mushrooms > 0 and game.foraging.ready_index(source) >= 0:
		var species = game.foraging.ready_species(source)
		var label = "Съесть мухомор" if species == "fly_agaric" else ("Съесть поганку" if species == "toadstool" else "Съесть гриб")
		candidates.append(_rails(grill, meat, mushrooms, "mushroom", label, source))
	if game.foraging.free_skewers(source) > 0 and game.foraging.stock().mushrooms > 0:
		candidates.append(_rails(grill, meat + mushrooms, Props.FOOD_PORTIONS - meat - mushrooms, "mount", "Насадить гриб", source))
	if own and game.camp_grill.can_light():
		candidates.append(_firebox(grill, "light_grill", "Разжечь мангал"))
	elif own and game.camp_grill.can_load():
		candidates.append(_firebox(grill, "load_meat", "Выложить шампуры с мясом"))
	var best: Dictionary = {}
	var best_error = INF
	for candidate in candidates:
		var error = aim_error(candidate.point, candidate.radius)
		if error < best_error:
			best_error = error
			best = candidate
	if best.is_empty():
		offer(items, grill.position + Vector3(0, 0.9, 0), 0.65, 3, "", "", source)
		return
	offer(items, best.point, best.radius, 3, best.action, best.label, best.value)

func _rails(grill: Node3D, from_index: int, count: int, action: String, label: String, source: int) -> Dictionary:
	var zone = GrillModel.slot_zone(grill, from_index, count)
	return {"point": zone.point, "radius": zone.radius, "action": action, "label": label, "value": source}

func _firebox(grill: Node3D, action: String, label: String) -> Dictionary:
	return {"point": grill.global_transform * Vector3(0, 0.8, 0), "radius": 0.2, "action": action, "label": label, "value": -1}

# How far off the gaze a point is, as a fraction of its distance; INF when the
# point is behind the camera or outside its own radius.
func aim_error(point: Vector3, radius: float) -> float:
	var offset = point - game.camera.global_position
	var forward = -game.camera.global_basis.z
	var depth = offset.dot(forward)
	if depth <= 0:
		return INF
	var miss = offset.distance_to(forward * depth)
	return miss / depth if miss <= radius else INF

func select_target(items: Array) -> Dictionary:
	if items.is_empty():
		return {}
	items.sort_custom(func(a, b): return a.depth < b.depth)
	var target: Dictionary = items[0]
	# Terrain, trees, boulders and city buildings block reaching through scenery.
	var start = game.camera.global_position
	var end = start - game.camera.global_basis.z * maxf(0, target.depth - 0.35)
	if game.stage.obstacle_hit(start, end, 0.05, true) >= 0 or not game.stage.rock_hit(start, end, 0.05).is_empty() or not game.stage.solids.hit(start, end, 0.05).is_empty():
		return {}
	for step in range(1, 9):
		var point = start.lerp(end, step / 9.0)
		if point.y < game.stage.ground(point) - 0.1:
			return {}
	return {} if target.action == "" else target

func activate() -> void:
	var target = current()
	if target.is_empty():
		return
	match target.action:
		"church_bell":
			if not game.room.submit("church_bell"):
				game.stage.solids.bell.pull(game.walker)
		"mount_cauldron": game.camp_cooking.mount()
		"mount_firewood": game.camp_cooking.light_under_pot()
		"plov_cook": game.camp_cooking.start()
		"plov": game.eat_plov()
		"trunk": game.cargo.toggle(target.value)
		"return_gear": game.cargo.return_item(target.value)
		"take_gear":
			if str(target.value) == "shovel": game.cargo.take("shovel")
			else: game.begin_placement(str(target.value))
		"dig_snow": game.dig_snow(target.value)
		"pack": game.packing.pack(target.value)
		"car": game._toggle_car()
		"ride": game.rides.board(str(target.value))
		"sit": game.sit_down()
		"stand": game.stand_up()
		"collect": game.foraging.collect(int(target.value))
		"mount": game.foraging.mount(int(target.value))
		"light_grill": game.camp_grill.light()
		"load_meat": game.camp_grill.load_meat()
		"mushroom": game.eat_foraged("mushroom", int(target.value))
		"meat": game.eat_meat(int(target.value))
		"beer": game.drink_beer()
		"relief": game.player.relief.start()
		"relief_stop": game.player.relief.stop()

