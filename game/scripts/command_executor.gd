extends RefCounted
const ActorContext = preload("res://scripts/actor_context.gd")
var game: Node3D

func execute(command: Dictionary, model: int) -> Dictionary:
	if game.paused:
		return outcome("deferred", "Создатель приостановил игру.")
	if not game.session.can_act():
		return outcome("rejected", "Выезд завершён.")
	var who = ActorContext.from_command(command, model)
	var placement: Dictionary = command.get("placement", {})
	var spot = Vector3(placement.pos[0], placement.pos[1], placement.pos[2]) if placement.has("pos") else Vector3.INF
	var yaw = float(placement.get("yaw", 0))
	if not who.can_act() or (spot != Vector3.INF and spot.distance_to(who.position) > 5):
		return outcome("rejected", "Подойди к предмету пешком.")
	var applied = false
	match command.action:
		"trunk": applied = spot != Vector3.INF and game.cargo.toggle(spot, who)
		"take_gear":
			var index = int(placement.get("resource_id", -1))
			if index >= 0 and index < game.cargo.KINDS.size(): applied = game.cargo.take(game.cargo.KINDS[index], who)
		"return_gear": applied = spot != Vector3.INF and game.cargo.return_item(spot, who)
		"pack": applied = spot != Vector3.INF and game.packing.pack(spot, true, who)
		"table", "chairs", "grill", "firewood", "cauldron": applied = spot != Vector3.INF and game.cargo.deploy(str(command.action), spot, yaw, who)
		"flag": applied = not game.packing.active() and game.place_flag(spot, yaw, who.owner, false, who)
		"plov_cook": applied = game.camp_cooking.start(who)
		"eat_plov": applied = game.camp_cooking.consume(who)
		"eat": applied = game.commit_meat(int(placement.get("source", -2)), who)
		"collect": applied = game.foraging.collect(int(placement.get("resource_id", -1)), who.owner, who)
		"mount_mushroom": applied = game.foraging.mount(int(placement.get("source", -2)), who.owner, who)
		"eat_mushroom": applied = game.foraging.consume("mushroom", who.owner, int(placement.get("source", -2)), who)
		"eat_berries": applied = game.foraging.consume("berries", who.owner, -2, who)
		"rally": applied = game.start_rally()
	return outcome("applied" if applied else "rejected", "" if applied else "Действие недоступно. Проверь расстояние и наличие предмета.")

func outcome(status: String, reason: String) -> Dictionary:
	return {"status": status, "reason": reason}
