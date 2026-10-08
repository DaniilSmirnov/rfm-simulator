extends RefCounted
# One gaze-selected world object; proximity alone never chooses an action.
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
	if not game.playing or game.paused or game.dead or game.finished or game.drink_time >= 0 or game.eat_time >= 0 or (game.room.connected and not game.room.is_host and game.room.world_paused):
		return {}
	if game.in_car:
		return {"action": "car", "label": "Выйти из машины"} if absf(game.speed) <= 1 else {}
	if game.beers >= 30:
		return {}
	if game.seated:
		return {"action": "stand", "label": "Встать со стула"}
	var items: Array = []
	game.cargo.offers(items, self)
	if not game.cargo.at_open_trunk(game.chair_owner()):
		offer(items, game.car.position + Vector3(0, 0.9, 0), 1.4, 4, "car", "Сесть в машину")
	game.camp_cooking.offers(items, self)
	if game.stage.urban and game.stage.city.bell != null:
		offer(items, game.stage.city.bell.handle_position(), 0.35, 2.0, "church_bell", "Позвонить в колокол")
	if game.packing.active():
		for item in game.packing.items():
			if item.kind == "firewood" and game.camp_cooking.pot != null:
				continue
			if item.kind != "flag" and game.cargo.held.has(game.chair_owner()):
				continue
			offer(items, item.node.global_position + Vector3(0, item.height, 0), item.radius, 3.5, "pack", item.label, item.node.global_position)
		return select_target(items)
	if game.cargo.held.has(game.chair_owner()):
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
			var action = ""
			var label = ""
			if game.foraging.ready_index(source) >= 0:
				action = "mushroom"
				var species = game.foraging.ready_species(source)
				label = "Съесть мухомор" if species == "fly_agaric" else ("Съесть поганку" if species == "toadstool" else "Съесть гриб")
			elif game.foraging.stock().mushrooms > 0 and game.foraging.free_skewers(source) > 0:
				action = "mount"
				label = "Насадить гриб"
			elif game.foraging.meat_count(source) > 0 and (source >= 0 or game.cook_time >= 35):
				action = "meat"
				label = "Съесть шашлык"
			# Even an unavailable grill occludes another interactable behind it.
			offer(items, grill.position + Vector3(0, 0.9, 0), 0.65, 3, action, label, source)
		var table = game.camp if source == -1 else game.spectators.groups[source].table
		if table != null:
			offer(items, table.position + Vector3(0, 0.75, 0), 0.85, 3, "beer" if game.beer_timer <= 0 else "", "Выпить пиво" if game.beer_timer <= 0 else "")
	return select_target(items)

func select_target(items: Array) -> Dictionary:
	if items.is_empty():
		return {}
	items.sort_custom(func(a, b): return a.depth < b.depth)
	var target: Dictionary = items[0]
	# Terrain, trees, boulders and city buildings block reaching through scenery.
	var start = game.camera.global_position
	var end = start - game.camera.global_basis.z * maxf(0, target.depth - 0.35)
	if game.stage.obstacle_hit(start, end, 0.05, true) >= 0 or not game.stage.rock_hit(start, end, 0.05).is_empty() or (game.stage.urban and not game.stage.city.hit(start, end, 0.05).is_empty()):
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
				game.stage.city.bell.pull(game.walker)
		"mount_cauldron": game.camp_cooking.mount()
		"mount_firewood": game.camp_cooking.light_under_pot()
		"plov_cook": game.camp_cooking.start()
		"plov": game.eat_plov()
		"trunk": game.cargo.toggle(target.value)
		"return_gear": game.cargo.return_item(target.value)
		"take_gear": game.begin_placement(str(target.value))
		"pack": game.packing.pack(target.value)
		"car": game._toggle_car()
		"sit": game.sit_down()
		"stand": game.stand_up()
		"collect": game.foraging.collect(int(target.value))
		"mount": game.foraging.mount(int(target.value))
		"mushroom": game.eat_foraged("mushroom", int(target.value))
		"meat": game.eat_meat(int(target.value))
		"beer": game.drink_beer()

