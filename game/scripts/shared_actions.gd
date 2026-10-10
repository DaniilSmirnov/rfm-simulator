extends RefCounted
# The commands a guest can ask the host to perform (the list itself lives in
# data/net_protocol.json). The host runs each one for the guest's ActionContext.
const NetProtocol = preload("res://scripts/net_protocol.gd")
const PLACEMENT_REACH = 5.0

static func _vec(value) -> Vector3:
	return Vector3(value[0], value[1], value[2])

static func run(game: Node, context, action: String, placement: Dictionary) -> void:
	if action not in NetProtocol.actions():
		return
	var spot = _vec(placement.pos) if placement.has("pos") else Vector3.INF
	var yaw = float(placement.get("yaw", 0.0))
	# A placement must be within reach of where the guest reports standing.
	if spot != Vector3.INF and (spot.distance_to(context.pos) > PLACEMENT_REACH or context.beers >= 30):
		return
	game.acting = context
	game.cargo.context = context.cargo_context(game.car.position)
	match action:
		"trunk":
			if spot != Vector3.INF:
				game.cargo.toggle(spot)
		"dig_snow":
			if spot != Vector3.INF: game.dig_snow(spot)
		"take_gear":
			var index = int(placement.get("resource_id", -1))
			if index >= 0 and index < game.cargo.KINDS.size():
				game.cargo.take(game.cargo.KINDS[index])
		"return_gear":
			if spot != Vector3.INF:
				game.cargo.return_item(spot)
		"pack":
			if spot != Vector3.INF:
				game.packing.pack(spot, true)
		"table", "chairs", "grill", "firewood", "cauldron":
			if spot != Vector3.INF:
				game.cargo.deploy(action, spot, yaw)
		"flag":
			if not game.packing.active():
				game.place_flag(spot, yaw, context.owner)
		"plov_cook": game.camp_cooking.start()
		"eat_plov": game.camp_cooking.consume()
		"eat": game.commit_meat(int(placement.get("source", -2)))
		"church_bell":
			if game.stage.solids.bell != null:
				game.stage.solids.bell.pull(context.pos)
		"collect": game.foraging.collect(int(placement.get("resource_id", -1)), context.owner)
		"mount_mushroom": game.foraging.mount(int(placement.get("source", -2)), context.owner)
		"eat_mushroom": game.foraging.consume("mushroom", context.owner, int(placement.get("source", -2)))
		"eat_berries": game.foraging.consume("berries", context.owner)
		"rally": game.start_rally()
	game.cargo.context = {}
	game.acting = null
