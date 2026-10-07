extends RefCounted
const Props = preload("res://scripts/props.gd")
const COOK_SECONDS = 45.0
var game: Node3D
var fire: Node3D
var pot: Node3D
var phase = "none"
var cook_time = 0.0
var servings = 0

func can_act() -> bool:
	return game.playing and not game.in_car and not game.paused and not game.dead and not game.finished and game.beers < 30

func deploy_fire(spot: Vector3, yaw: float) -> bool:
	if not can_act() or game.packing.active() or not game.valid_furniture_spot(spot, "firewood"):
		return false
	if fire == null:
		fire = Props.campfire(game)
	fire.position = spot
	fire.position.y = game.stage.ground(spot)
	fire.rotation.y = yaw
	game.toast("Костёр разожжён. Принеси казан из багажника.")
	return true

func place_pot(spot: Vector3) -> bool:
	if not can_act() or game.packing.active() or fire == null or spot.distance_to(fire.position) > 0.5 or game.walker.distance_to(fire.position) > 3.5:
		return false
	if pot == null:
		pot = Props.cauldron(fire)
		phase = "empty"
		cook_time = 0
		servings = 0
	game.toast("Казан на подставке. F — добавить ингредиенты и готовить плов.")
	return true

func mount() -> bool:
	if fire == null:
		return false
	if game.room.submit("cauldron", {"pos": game.room.a(fire.position), "yaw": 0.0}):
		return true
	return game.cargo.deploy("cauldron", fire.position, 0)

func start() -> bool:
	if not can_act() or not game.cargo.available() or game.packing.active() or pot == null or phase != "empty" or game.walker.distance_to(fire.position) > 3.5 or game.cargo.held.has(game.cargo.actor()):
		return false
	if game.room.submit("plov_cook"):
		return true
	phase = "cooking"
	cook_time = 0
	game.toast("Готовим плов. Осталось 45 секунд.")
	update(0)
	return true

func can_eat() -> bool:
	return can_act() and pot != null and phase == "ready" and servings > 0 and game.walker.distance_to(fire.position) <= 3.5

func consume() -> bool:
	if not can_eat() or game.cargo.held.has(game.cargo.actor()):
		return false
	servings -= 1
	if servings == 0:
		phase = "exhausted"
	game.eaten = true
	update(0)
	game.toast("Плов удался. Осталось порций: %d/10." % servings)
	return true

func update(delta: float, guest: bool = false) -> void:
	if phase == "cooking" and not guest:
		cook_time = minf(COOK_SECONDS, cook_time + delta)
		if cook_time >= COOK_SECONDS:
			phase = "ready"
			servings = Props.FOOD_PORTIONS
			game.toast("Плов готов! F — съесть порцию.")
	if fire != null:
		var flames = fire.get_node("Flames")
		for i in range(flames.get_child_count()):
			var flame = flames.get_child(i)
			flame.scale = Vector3(1 + sin(game.elapsed * 9 + i) * 0.08, 0.85 + sin(game.elapsed * 7 + i * 2) * 0.22, 1)
	if pot != null:
		Props.pose_cauldron(pot, phase, cook_time / COOK_SECONDS, servings, game.elapsed)

func offers(items: Array, interaction) -> void:
	if fire == null or game.packing.active():
		return
	var carry = game.cargo.held.get(game.chair_owner(), {})
	if not carry.is_empty():
		if carry.kind == "cauldron" and not carry.returning:
			interaction.offer(items, fire.position + Vector3(0, 0.45, 0), 0.8, 3.5, "mount_cauldron", "Поставить казан на костёр")
		return
	if pot == null:
		interaction.offer(items, fire.position + Vector3(0, 0.3, 0), 0.75, 3.5, "", "")
	elif phase == "empty":
		interaction.offer(items, fire.position + Vector3(0, 1.1, 0), 0.65, 3.5, "plov_cook", "Добавить ингредиенты и готовить плов")
	elif phase == "ready":
		interaction.offer(items, fire.position + Vector3(0, 1.1, 0), 0.65, 3.5, "plov", "Съесть плов · %d/10" % servings)
	else:
		interaction.offer(items, fire.position + Vector3(0, 1.1, 0), 0.65, 3.5, "", "")

func remove_pot() -> void:
	if pot != null:
		pot.queue_free()
	pot = null
	phase = "none"
	cook_time = 0
	servings = 0

func remove_fire() -> void:
	remove_pot()
	if fire != null:
		fire.queue_free()
	fire = null

func snapshot() -> Dictionary:
	if fire == null:
		return {}
	return {"pos": game.room.a(fire.position), "yaw": fire.rotation.y, "fire_owner": str(fire.get_meta("gear_owner", game.chair_owner())), "pot": pot != null, "pot_owner": str(pot.get_meta("gear_owner", game.chair_owner())) if pot != null else "", "phase": phase, "cook_time": cook_time, "servings": servings}

func apply_snapshot(data: Dictionary) -> void:
	if data.is_empty():
		remove_fire()
		return
	if fire == null:
		fire = Props.campfire(game)
	fire.position = game.room.v(data.pos)
	fire.rotation.y = float(data.get("yaw", 0))
	fire.set_meta("gear_owner", str(data.get("fire_owner", "")))
	if data.get("pot", false):
		if pot == null:
			pot = Props.cauldron(fire)
		pot.set_meta("gear_owner", str(data.get("pot_owner", "")))
	else:
		remove_pot()
	phase = str(data.get("phase", "none"))
	cook_time = clampf(float(data.get("cook_time", 0)), 0, COOK_SECONDS)
	servings = clampi(int(data.get("servings", 0)), 0, Props.FOOD_PORTIONS)
	update(0, true)
