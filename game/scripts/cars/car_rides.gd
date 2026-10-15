extends RefCounted
# Riding in a friend's car and towing a broken car with your own.
#
# A passenger is `in_car` with `ride` set to the id of the car's owner: they
# move with that car and count as arrived when it reaches a service park.
# A car holds SEATS people, the driver included. A broken car (condition 0)
# no longer drives, but the outing goes on while somebody still has a working
# car: the owner rides with a friend or a friend tows the car behind theirs
# (`hitch`, T at the wheel). Only when every car in the room is broken is the
# outing over.
#
# Both choices travel in the player's state ("ride", "hitch", "broken"); the
# host moves towed cars in Recovery.update, as it does for ropes held by hand.
const Recovery = preload("res://scripts/cars/recovery.gd")
const Loc = preload("res://scripts/ui/loc.gd")
const SEATS = 5
# Metres between two cars for hooking the rope, its length, and the distance
# at which a stretched rope comes off (a car returned to the road, a host lag).
const TOW_RANGE = 8.0
const TOW_LENGTH = 5.0
const TOW_BREAK = 25.0
const TOW_TURN_RATE = 4.0

var game
var ride = "" # owner of the friend's car the local player sits in
var hitch = "" # owner of the car the local player tows
var wreck_noticed = false

func me() -> String:
	return game.room.player_id if game.room.connected else "local"

func riding() -> bool:
	return ride != ""

# Behind the wheel of their own car, not a passenger.
static func driving(state) -> bool:
	return state != null and bool(state.get("in_car", false)) and str(state.get("ride", "")) == ""

func state_of(owner: String):
	if owner == me():
		return {"in_car": game.in_car, "ride": ride, "hitch": hitch, "speed": game.speed}
	var peer = game.room.peers.get(owner)
	return peer.state if peer != null else null

func name_of(owner: String) -> String:
	return str(game.room.members.get(owner, {}).get("name", Loc.t("друг")))

# The car of a player as this client renders it.
func car_node(owner: String) -> Node3D:
	if owner == "":
		return null
	if owner.begins_with("spectator:"):
		var group_id = int(owner.trim_prefix("spectator:"))
		if group_id >= 0 and group_id < game.spectators.groups.size():
			return game.spectators.groups[group_id].car
		return null
	if owner == me():
		return game.car
	var peer = game.room.peers.get(owner)
	return peer.car if peer != null and peer.has("car") else null

func speed_of(owner: String) -> float:
	if owner.begins_with("spectator:"):
		return 0.0
	var state = state_of(owner)
	return float(state.get("speed", 0.0)) if state != null else 0.0

func broken(owner: String) -> bool:
	if owner == me():
		return game.condition <= 0
	if game.room.host_drives.has(owner):
		return game.room.host_drives[owner].condition <= 0
	var state = state_of(owner)
	return state != null and bool(state.get("broken", false))

func any_working() -> bool:
	if not broken(me()):
		return true
	for id in game.room.peers:
		if not broken(str(id)):
			return true
	return false

# Passengers of a car, sorted so every client agrees who sits where.
func riders(owner: String) -> Array:
	var result: Array = []
	if ride == owner:
		result.append(me())
	for id in game.room.peers:
		var state = game.room.peers[id].state
		if state != null and bool(state.get("in_car", false)) and str(state.get("ride", "")) == owner:
			result.append(str(id))
	result.sort()
	return result

func occupants(owner: String) -> int:
	return riders(owner).size() + (1 if driving(state_of(owner)) else 0)

# ---------------------------------------------------------------- the local player

# Where the local player sits: their own car or the friend's.
func vehicle() -> Node3D:
	var node = car_node(ride)
	return node if node != null else game.car

func seat_position() -> Vector3:
	return vehicle().position

func heading() -> float:
	return vehicle().rotation.y if riding() else game.heading

func speed() -> float:
	return speed_of(ride) if riding() else game.speed

# Where a room member sits when in a car, on any client.
func seat_of(state: Dictionary) -> Vector3:
	var owner = str(state.get("ride", ""))
	if owner != "":
		var position = Recovery.car_position(game, owner)
		if position != null:
			return position
	return game.room.v(state.car)

func offers(items: Array, interaction) -> void:
	if game.room.connected:
		for id in game.room.peers:
			var node = car_node(str(id))
			if node == null or game.room.peers[id].state == null or absf(speed_of(str(id))) > 1:
				continue
			interaction.offer(items, node.position + Vector3(0, 0.9, 0), 1.4, 4, "ride", Loc.t("Сесть к другу (%d/%d)") % [occupants(str(id)), SEATS], str(id))
	for i in range(game.spectators.groups.size()):
		var node: Node3D = game.spectators.groups[i].car
		interaction.offer(items, node.position + Vector3(0, 0.9, 0), 1.4, 4, "ride_npc", Loc.t("Сесть в машину зрителей"), "spectator:%d" % i)

func board(owner: String) -> void:
	var node = car_node(owner)
	if node == null or owner == me() or game.in_car or not game.player.can_change_seat():
		return
	if game.walker.distance_to(node.position) > 4:
		game.toast("Подойди к машине друга.")
	elif absf(speed_of(owner)) > 1:
		game.toast("Дождись, пока машина друга остановится.")
	elif occupants(owner) >= SEATS:
		game.toast(Loc.t("Мест нет: в машине максимум %d человек вместе с водителем.") % SEATS)
	else:
		ride = owner
		hitch = ""
		game.in_car = true
		game.speed = 0
		game.vehicle_motion.velocity = Vector3.ZERO
		game.view_yaw = node.rotation.y
		game.toast(Loc.t("Ты в машине: %s. F — выйти, когда машина стоит.") % name_of(owner))

func board_npc(owner: String) -> void:
	var node = car_node(owner)
	if node == null or game.in_car or not game.player.can_change_seat():
		return
	if game.walker.distance_to(node.position) > 4:
		game.toast("Подойди к машине зрителей.")
	elif absf(speed_of(owner)) > 1:
		game.toast("Дождись, пока машина остановится.")
	else:
		ride = owner
		hitch = ""
		game.in_car = true
		game.speed = 0
		game.vehicle_motion.velocity = Vector3.ZERO
		game.view_yaw = node.rotation.y
		game.toast("Ты в машине зрителей. F — выйти, когда машина остановится.")

func leave(force: bool = false) -> void:
	var node = car_node(ride)
	if not force and node != null and absf(speed_of(ride)) > 1:
		game.toast("Подожди, пока водитель остановится.")
		return
	var seat = maxi(0, riders(ride).find(me()))
	var origin: Vector3 = node.position if node != null else game.walker
	var yaw: float = node.rotation.y if node != null else game.view_yaw
	game.walker = origin + Vector3(-2.1 if seat % 2 == 0 else 2.1, 0, 0.6 * floorf(seat / 2.0)).rotated(Vector3.UP, yaw)
	game.walker.y = game.stage.walking_ground(game.walker)
	game.view_yaw = yaw
	ride = ""
	game.in_car = false
	game.speed = 0

# A passenger's frame instead of driving: sit in the friend's car.
func follow() -> void:
	var node = car_node(ride)
	if node == null:
		leave(true)
		game.toast("Друг вышел из комнаты, его машины больше нет.")
		return
	# Two friends got into the last seat at once: the later one by id gets out.
	if riders(ride).find(me()) >= SEATS - 1:
		leave(true)
		game.toast("В машине друга не хватило места.")
		return
	game.walker = node.position
	game.speed = 0

# Every frame, in the car and on foot.
func update() -> void:
	if not game.in_car:
		ride = ""
	var wrecked = game.condition <= 0
	if wrecked and not wreck_noticed and game.room.connected:
		game.toast("Машина сломана и не поедет. Садись к другу или пусть он возьмёт её на трос.")
	wreck_noticed = wrecked
	if game.in_car and not riding() and Input.is_action_just_pressed("tow"):
		toggle_hitch()
	if hitch != "" and not (game.in_car and not riding() and towable(hitch) and car_node(hitch) != null and car_node(hitch).position.distance_to(game.car.position) < TOW_BREAK):
		hitch = ""
		game.toast("Трос отцеплен.")
	if game.room.connected and game.room.is_authority() and not game.dead and not game.finished and not any_working():
		game.die("Все машины разбиты: уехать с СУ не на чем.\nСовместный выезд окончен.")

# ---------------------------------------------------------------- towing by car

# A friend's car can go on the rope when it is broken or nobody drives it.
func towable(owner: String) -> bool:
	var state = state_of(owner)
	return owner != me() and state != null and (broken(owner) or not driving(state)) and str(state.get("hitch", "")) == ""

func hitch_candidate() -> String:
	if not game.room.connected or not game.in_car or riding():
		return ""
	var best = ""
	var best_distance = TOW_RANGE
	for id in game.room.peers:
		var node = car_node(str(id))
		if node == null or not towable(str(id)):
			continue
		var distance = node.position.distance_to(game.car.position)
		if distance < best_distance:
			best = str(id)
			best_distance = distance
	return best

func toggle_hitch() -> void:
	if hitch != "":
		hitch = ""
		game.toast("Трос отцеплен.")
		return
	var owner = hitch_candidate()
	if game.condition <= 0:
		game.toast("Сломанная машина не может никого тянуть.")
	elif owner == "":
		game.toast(Loc.t("Подъедь ближе %d м к машине друга, которая не едет сама.") % int(TOW_RANGE))
	elif absf(game.speed) > 1:
		game.toast("Остановись, чтобы зацепить трос.")
	else:
		hitch = owner
		game.toast(Loc.t("Трос зацеплен: тянем машину %s. T — отцепить.") % name_of(owner))

# Host: every hooked car follows its tow car at the length of the rope.
func pull(players: Dictionary, delta: float) -> void:
	for id in players:
		var p: Dictionary = players[id]
		var owner = str(p.get("hitch", ""))
		if owner == "" or owner == str(id) or not driving(p):
			continue
		var lead = Recovery.car_position(game, str(id))
		var towed = Recovery.car_position(game, owner)
		if lead == null or towed == null:
			continue
		var offset: Vector3 = towed - lead
		offset.y = 0
		var distance = offset.length()
		if distance > TOW_BREAK or distance < 0.01:
			continue
		game.recovery_links.append({"player": str(id), "pos": game.room.a(lead), "car": owner, "hitch": true})
		if distance <= TOW_LENGTH:
			continue
		var next: Vector3 = lead + offset / distance * TOW_LENGTH
		next.y = game.stage.ground(next)
		Recovery.move_car(game, owner, next, atan2(offset.x, offset.z), delta, TOW_TURN_RATE)

func hud_state() -> Array:
	return [ride, hitch, int(absf(speed()) * 3.6), game.condition <= 0, hitch_candidate() != ""]
