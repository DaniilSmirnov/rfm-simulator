extends Node3D
# Fixed camps and a shared timeline make NPCs identical for late-joining clients.
const Props = preload("res://scripts/props.gd")
var game: Node3D
var groups: Array[Dictionary] = []
var people: Array[Dictionary] = []
var clock = 0.0

func rebuild() -> void:
	for child in get_children():
		child.free()
	groups.clear()
	people.clear()
	clock = 0.0
	var stage = game.stage
	for i in range(stage.clearings.size()):
		var clearing = stage.clearings[i]
		var s = stage.road_s(clearing)
		var outward = (clearing - stage.at(s)).normalized()
		outward.y = 0
		outward = outward.normalized()
		var center = clearing + (stage.direction(s) * 7.0 if stage.urban else outward * 6.0)
		_add_group(center, s, i, 2)
	# The shoulder is already free of trees; leave the driving lane unobstructed.
	for i in range(4):
		var s = 85.0 + i * 190.0
		if stage.urban:
			continue # City spectators use the existing street parking areas.
		var center = stage.at(s) + stage.side(s) * (7.2 if i % 2 == 0 else -7.2)
		_add_group(center, s, i + 4, 1)
	update(clock, 0.0, false)

func grounded(pos: Vector3) -> Vector3:
	pos.y = game.stage.ground(pos)
	return pos

func _add_group(center: Vector3, s: float, id: int, count: int) -> void:
	center = grounded(center)
	var forward = game.stage.direction(s)
	var yaw = atan2(-forward.x, -forward.z)
	var car = Props.player_car((id * 3 + game.stage.variant) % Props.PLAYER_MODELS.size())
	add_child(car)
	car.position = grounded(center + forward * 3.2)
	car.rotation.y = yaw
	var table = Node3D.new()
	add_child(table)
	Props.table(table)
	table.position = center
	table.rotation.y = yaw
	var grill = Props.grill(self)
	grill.position = grounded(center - forward * 2.4)
	grill.rotation.y = yaw
	groups.append({"car": car, "table": table, "grill": grill})
	for j in range(count):
		var variant = (id + j + game.stage.variant) % Props.SPECTATOR_MODELS.size()
		var avatar = Props.player_avatar(variant)
		add_child(avatar)
		var offset = Vector3(-1.5, 0, 0.4 + j * 1.6).rotated(Vector3.UP, yaw)
		avatar.position = grounded(center + offset)
		var toward_road = game.stage.at(s) - avatar.position
		avatar.rotation.y = atan2(-toward_road.x, -toward_road.z)
		var chair = Node3D.new()
		add_child(chair)
		Props.chair(chair, Vector3.ZERO)
		chair.position = grounded(avatar.position + forward * 0.85)
		chair.rotation.y = avatar.rotation.y
		var arm = avatar.get_node("RightArm")
		people.append({"id": id * 2 + j, "avatar": avatar, "arm": arm, "can": arm.get_node("BeerCan"), "food": arm.get_node("Skewer"), "action": "idle", "time": -1.0})

func activity(id: int, time: float) -> Dictionary:
	var period = 15.0 + float((id * 7) % 11)
	var shifted = maxf(0.0, time) + float((id * 13) % 19)
	var cycle = int(floor(shifted / period))
	var phase = fmod(shifted, period)
	var choice = posmod(id * 31 + cycle * 17 + game.stage.variant * 11, 5)
	var action = "beer" if choice < 2 else ("eat" if choice < 4 else "idle")
	var duration = 3.3 if action == "beer" else 3.6
	if action == "idle" or phase >= duration:
		return {"action": "idle", "time": -1.0}
	return {"action": action, "time": phase}

func update(world_time: float, delta: float, guest: bool) -> void:
	if guest:
		clock += delta
		if absf(clock - world_time) > 0.35:
			clock = world_time
	else:
		clock = world_time
	for person in people:
		var pose = activity(person.id, clock)
		person.action = pose.action
		person.time = pose.time
		person.can.visible = pose.action == "beer"
		person.food.visible = pose.action == "eat"
		person.arm.rotation = Vector3.ZERO
		if pose.action == "eat":
			var lift = Props.food_lift(pose.time)
			person.arm.rotation.x = lerpf(0.25, 2.3, lift)
			person.arm.rotation.z = -0.45 * lift
			person.food.rotation.x = -lift
			Props.pose_skewer(person.food, pose.time)
		elif pose.action == "beer":
			var lift = smoothstep(0.8, 1.25, pose.time) * (1.0 - smoothstep(2.5, 3.3, pose.time))
			person.arm.rotation.x = lerpf(0.5, 1.6, lift)
			person.can.rotation.x = 0.35 * lift
		person.avatar.get_node("Head").rotation.y = sin(clock * 0.35 + person.id) * 0.08

func occupied(spot: Vector3) -> bool:
	for group in groups:
		if spot.distance_to(group.car.position) < 2.3 or spot.distance_to(group.table.position) < 1.5 or spot.distance_to(group.grill.position) < 1.2:
			return true
	for person in people:
		if spot.distance_to(person.avatar.position) < 0.8:
			return true
	return false
