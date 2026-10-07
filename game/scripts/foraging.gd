extends RefCounted
const Props = preload("res://scripts/props.gd")
const GRILL_SECONDS = 10.0
var game: Node3D
var inventories: Dictionary = {}
var skewers: Dictionary = {}
var effects: Dictionary = {}

func owner_key(owner: String = "") -> String:
	return game.chair_owner() if owner == "" else owner

func stock(owner: String = "") -> Dictionary:
	var key = owner_key(owner)
	if not inventories.has(key):
		inventories[key] = {"mushrooms": 0, "berries": 0}
	if not inventories[key].has("mushroom_types"):
		inventories[key].mushroom_types = []
	return inventories[key]

func available() -> bool:
	return game.playing and not game.paused and not game.dead and not game.finished and not game.in_car and game.beers < 30 and game.eat_time < 0 and game.drink_time < 0

func nearest() -> int:
	return game.stage.nearest_collectible(game.walker) if available() else -1

func collect(id: int = -1, owner: String = "") -> bool:
	if not game.playing or game.in_car or game.beers >= 30 or game.paused or game.dead or game.finished:
		return false
	if id < 0:
		id = game.stage.nearest_collectible(game.walker)
	if id < 0 or id >= game.stage.collectibles.size():
		return false
	var item: Dictionary = game.stage.collectibles[id]
	if game.stage.flat(item.pos).distance_to(game.stage.flat(game.walker)) > 1.8 or absf(item.pos.y - game.walker.y) > 2.0 or game.stage.harvested.has(id):
		return false
	if owner == "" and game.room.connected and not game.room.is_host:
		return game.room.submit("collect", {"resource_id": id})
	if not game.stage.harvest(id):
		return false
	var bag = stock(owner)
	bag[item.kind] = int(bag[item.kind]) + int(item.quantity)
	if item.kind == "mushrooms":
		for i in range(int(item.quantity)):
			bag.mushroom_types.append(str(item.get("species", "edible")))
	game.toast("Собрано: " + item.get("name", "гриб" if item.kind == "mushrooms" else "ягоды"))
	return true

func grill_node(source: int) -> Node3D:
	if source == -1:
		return game.grill
	if game.spectators != null and source >= 0 and source < game.spectators.groups.size():
		return game.spectators.groups[source].grill
	return null

func nearby_source() -> int:
	var closest = 4.0
	var found = -2
	if game.grill != null:
		var distance = game.walker.distance_to(game.grill.position)
		if distance < closest:
			closest = distance
			found = -1
	if game.spectators != null:
		for i in range(game.spectators.groups.size()):
			var distance = game.walker.distance_to(game.spectators.groups[i].grill.position)
			if distance < closest:
				closest = distance
				found = i
	return found

func meat_count(source: int) -> int:
	return game.grill_servings if source == -1 else int(game.spectators.groups[source].servings)

func free_skewers(source: int) -> int:
	if grill_node(source) == null:
		return 0
	return maxi(0, Props.FOOD_PORTIONS - meat_count(source) - skewers.get(str(source), []).size())

func can_mount() -> bool:
	return available() and int(stock().mushrooms) > 0 and free_skewers(nearby_source()) > 0

func mount(source: int = -2, owner: String = "") -> bool:
	if not game.playing or game.in_car or game.beers >= 30 or game.paused or game.dead or game.finished:
		return false
	if source == -2:
		source = nearby_source()
	var node = grill_node(source)
	if node == null or game.walker.distance_to(node.position) >= 4.0 or free_skewers(source) <= 0 or int(stock(owner).mushrooms) <= 0:
		return false
	if owner == "" and game.room.connected and not game.room.is_host:
		return game.room.submit("mount_mushroom", {"source": source})
	stock(owner).mushrooms = int(stock(owner).mushrooms) - 1
	var types: Array = stock(owner).mushroom_types
	var species = str(types.pop_front()) if not types.is_empty() else "edible"
	var entries: Array = skewers.get(str(source), [])
	entries.append({"ready_at": game.elapsed + GRILL_SECONDS, "species": species})
	skewers[str(source)] = entries
	update_visuals()
	game.toast("Гриб на шампуре. Будет готов через 10 секунд.")
	return true

func ready_index(source: int) -> int:
	var entries: Array = skewers.get(str(source), [])
	for i in range(entries.size()):
		if float(entries[i].ready_at) <= game.elapsed:
			return i
	return -1

func can_eat(kind: String) -> bool:
	if not available():
		return false
	if kind == "berries":
		return int(stock().berries) > 0
	var source = nearby_source()
	return source != -2 and ready_index(source) >= 0

func ready_species(source: int) -> String:
	var index = ready_index(source)
	return str(skewers[str(source)][index].get("species", "edible")) if index >= 0 else "edible"

func consume(kind: String, owner: String = "", source: int = -2) -> bool:
	if not game.playing or game.in_car or game.beers >= 30 or game.paused or game.dead or game.finished:
		return false
	if kind == "berries":
		if int(stock(owner).berries) <= 0:
			return false
		stock(owner).berries = int(stock(owner).berries) - 1
		return true
	if kind != "mushroom":
		return false
	if source == -2:
		source = nearby_source()
	var node = grill_node(source)
	if node == null or game.walker.distance_to(node.position) >= 4.0:
		return false
	var index = ready_index(source)
	if index < 0:
		return false
	var species = ready_species(source)
	skewers[str(source)].remove_at(index)
	if species in ["fly_agaric", "toadstool"]:
		var key = owner_key(owner)
		var serial = int(effects.get(key, {}).get("serial", 0)) + 1
		effects[key] = {"serial": serial, "until": game.elapsed + 10.0}
		if key == game.chair_owner():
			game.mushroom_effect.trigger(serial)
			game.toast("Странный гриб! Цвета инвертированы на 10 секунд.")
	update_visuals()
	return true

func update_visuals() -> void:
	for key in skewers:
		var source = int(key)
		var node = grill_node(source)
		if node != null:
			node.set_meta("mushrooms", skewers[key].size())
			Props.set_grill_servings(node, meat_count(source))
			for i in range(skewers[key].size()):
				var skewer = node.get_node_or_null("FoodSkewer_%02d/MushroomFood" % (meat_count(source) + i))
				if skewer != null:
					Props.style_mushrooms(skewer, str(skewers[key][i].get("species", "edible")))

func snapshot() -> Dictionary:
	var effect_states = {}
	for key in effects:
		effect_states[key] = {"serial": effects[key].serial, "remaining": maxf(0, float(effects[key].until) - game.elapsed)}
	return {"harvested": game.stage.harvested.keys(), "inventories": inventories.duplicate(true), "skewers": skewers.duplicate(true), "effects": effect_states}

func apply_snapshot(data: Dictionary) -> void:
	game.stage.apply_harvested(data.get("harvested", []))
	inventories = data.get("inventories", {}).duplicate(true)
	skewers = data.get("skewers", {}).duplicate(true)
	effects.clear()
	for key in data.get("effects", {}):
		var state: Dictionary = data.effects[key]
		effects[key] = {"serial": int(state.get("serial", 0)), "until": game.elapsed + float(state.get("remaining", 0))}
	var effect: Dictionary = data.get("effects", {}).get(game.chair_owner(), {})
	if not effect.is_empty():
		game.mushroom_effect.trigger(int(effect.get("serial", 0)), float(effect.get("remaining", 0)))
	update_visuals()
