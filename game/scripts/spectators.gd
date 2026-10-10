extends Node3D
# Fixed camps and a shared timeline make NPCs identical for late-joining clients.
const Navigation = preload("res://scripts/crowd_navigation.gd")
const Props = preload("res://scripts/props.gd")
var game: Node3D
var groups: Array[Dictionary] = []
var people: Array[Dictionary] = []
var clock = 0.0
var navigation_budget = preload("res://scripts/navigation_budget.gd").new()
var actor_targets: Dictionary = {}

func rebuild(cooperative: bool = false) -> void:
	navigation_budget = preload("res://scripts/navigation_budget.gd").new()
	for child in get_children():
		child.free()
	groups.clear()
	people.clear()
	clock = 0.0
	actor_targets.clear()
	var stage = game.stage
	for i in range(stage.clearings.size()):
		if stage.desert and i < stage.canyon.mesas.size():
			continue # Summits are reached on foot; do not spawn parked NPC cars there.
		if cooperative:
			await get_tree().process_frame
		var clearing = stage.clearings[i]
		var s = stage.road_s(clearing)
		var outward = (clearing - stage.at(s)).normalized()
		outward.y = 0
		outward = outward.normalized()
		var center = clearing + (stage.direction(s) * 7.0 if stage.provence else outward * 6.0)
		if stage.provence:
			# Keep a whole picnic group clear of both sides of every junction.
			for offset in [7.0, -7.0, 14.0, -14.0, 21.0, -21.0, 0.0]:
				var candidate = clearing + stage.direction(s) * offset
				var available = true
				for along in [-2.4, 0.0, 3.2]:
					var spot = grounded(candidate + stage.direction(s) * along)
					available = available and stage.road_distance(spot) > 6.0 and stage.solids.hit(spot, spot, 1.2, false).is_empty()
				if available:
					center = candidate
					break
		_add_group(center, s, i, 2)
	# The shoulder is already free of trees; leave the driving lane unobstructed.
	for i in range(4):
		var s = 85.0 + i * 190.0
		if stage.provence:
			continue # Village spectators use the roadside spots and the square.
		var center = stage.at(s) + stage.side(s) * (7.2 if i % 2 == 0 else -7.2)
		_add_group(center, s, i + stage.clearings.size(), 1)
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
	groups.append({"car": car, "table": table, "grill": grill, "servings": Props.FOOD_PORTIONS, "last_eat_cycle": {}})
	var group_index = groups.size() - 1
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
		people.append({"id": id * 2 + j, "group": group_index, "avatar": avatar, "arm": arm, "can": arm.get_node("BeerCan"), "food": arm.get_node("Skewer"), "action": "idle", "time": -1.0, "eat_cycle": -1, "home": avatar.position, "watch": watch_spot(s + j * 2.0, avatar.position), "helper": -1})

func activity(id: int, time: float) -> Dictionary:
	var period = 15.0 + float((id * 7) % 11)
	var shifted = maxf(0.0, time) + float((id * 13) % 19)
	var cycle = int(floor(shifted / period))
	var phase = fmod(shifted, period)
	var choice = posmod(id * 31 + cycle * 17 + game.stage.variant * 11, 5)
	var action = "beer" if choice < 2 else ("eat" if choice < 4 else "idle")
	var duration = 3.3 if action == "beer" else 3.6
	if action == "idle" or phase >= duration:
		return {"action": "idle", "time": -1.0, "cycle": cycle}
	return {"action": action, "time": phase, "cycle": cycle}

func update(world_time: float, delta: float, guest: bool) -> void:
	navigation_budget.advance(delta)
	if guest:
		clock += delta
		if absf(clock - world_time) > 0.35:
			clock = world_time
	else:
		clock = world_time
	for person in people:
		var previous_position: Vector3 = person.avatar.position
		var pose = activity(person.id, clock)
		var group: Dictionary = groups[int(person.group)]
		var action = pose.action
		if guest and actor_targets.has(person.id):
			var target: Dictionary = actor_targets[person.id]
			person.avatar.position = person.avatar.position.lerp(game.room.v(target.pos), 1.0 - exp(-delta * 10))
			person.avatar.rotation.y = lerp_angle(person.avatar.rotation.y, float(target.yaw), 1.0 - exp(-delta * 10))
			person.helper = int(target.get("helper", -1))
			action = str(target.action)
			if action in ["beer", "eat"]:
				target.time = minf(3.3 if action == "beer" else 3.6, float(target.time) + delta)
			pose.time = float(target.time) if action in ["beer", "eat"] else -1.0
		else:
			var racer = nearby_stranded(person)
			person.helper = -1
			if not racer.is_empty() and game.playing and not game.paused and not game.dead and not game.finished:
				person.helper = racer.id
				var road = game.Recovery.road_direction(game, racer)
				var rear: Vector3 = racer.node.position - road * 2.0 + game.stage.side(game.stage.road_s(racer.node.position)) * ((person.id % 3) - 1) * 0.35
				move_person(person, rear, delta)
				person.avatar.rotation.y = atan2(-road.x, -road.z)
				action = "push" if person.avatar.position.distance_to(rear) < 0.6 else "help"
			else:
				var destination: Vector3 = person.home if action in ["beer", "eat"] else person.watch
				move_person(person, destination, delta)
				if action in ["beer", "eat"] and person.avatar.position.distance_to(person.home) > 0.7:
					action = "return"
				elif action == "idle" and passing_car(person.avatar.position):
					action = "cheer"
				var toward: Vector3 = game.stage.at(game.stage.road_s(person.avatar.position)) - person.avatar.position
				person.avatar.rotation.y = atan2(-toward.x, -toward.z)
		if action == "eat" and int(group.servings) <= 0 and int(person.eat_cycle) != int(pose.cycle):
			action = "idle"
		person.action = action
		person.time = pose.time
		if action == "eat" and pose.time >= 1.1 and int(person.eat_cycle) != int(pose.cycle):
			person.eat_cycle = int(pose.cycle)
			if not guest and int(group.servings) > 0:
				group.servings = int(group.servings) - 1
				Props.set_grill_servings(group.grill, int(group.servings))

		person.can.visible = action == "beer"
		person.food.visible = action == "eat"
		person.arm.rotation = Vector3.ZERO
		if action == "eat":
			var lift = Props.food_lift(pose.time)
			person.arm.rotation.x = lerpf(0.25, 2.3, lift)
			person.arm.rotation.z = -0.45 * lift
			person.food.rotation.x = -lift
			Props.pose_skewer(person.food, pose.time)
		elif action == "beer":
			var lift = smoothstep(0.8, 1.25, pose.time) * (1.0 - smoothstep(2.5, 3.3, pose.time))
			person.arm.rotation.x = lerpf(0.5, 1.6, lift)
			person.can.rotation.x = 0.35 * lift
		var moving: bool = person.avatar.position.distance_to(previous_position) > 0.001
		for leg_name in ["LeftLeg", "RightLeg"]:
			person.avatar.get_node(leg_name).rotation.x = sin(clock * 8 + person.id) * 0.4 * (-1 if leg_name == "LeftLeg" else 1) if moving else 0.0
		var left_arm = person.avatar.get_node("LeftArm")
		left_arm.rotation = Vector3.ZERO
		if action == "cheer":
			person.arm.rotation = Vector3(2.5, 0, -0.5 + sin(clock * 8 + person.id) * 0.28)
			left_arm.rotation = Vector3(2.5, 0, 0.5 + sin(clock * 8 + person.id + 1) * 0.28)
		elif action == "push":
			person.arm.rotation.x = PI / 2
			left_arm.rotation.x = PI / 2
		person.avatar.get_node("Head").rotation.y = sin(clock * 0.35 + person.id) * 0.08


func nearby_table(spot: Vector3, max_distance: float = 4.5) -> int:
	var best = max_distance
	var found = -1
	for i in range(groups.size()):
		var group: Dictionary = groups[i]
		var distance = minf(spot.distance_to(group.table.position), spot.distance_to(group.grill.position))
		if distance < best:
			best = distance
			found = i
	return found

func nearby_grill(spot: Vector3, max_distance: float = 4.5) -> int:
	var best = max_distance
	var found = -1
	for i in range(groups.size()):
		var group: Dictionary = groups[i]
		if int(group.servings) <= 0:
			continue
		var distance = minf(spot.distance_to(group.grill.position), spot.distance_to(group.table.position) + 0.7)
		if distance < best:
			best = distance
			found = i
	return found

func consume_serving(index: int) -> bool:
	if index < 0 or index >= groups.size():
		return false
	var group: Dictionary = groups[index]
	if int(group.servings) <= 0:
		return false
	group.servings = int(group.servings) - 1
	Props.set_grill_servings(group.grill, int(group.servings))
	return true

func snapshot() -> Array:
	var result: Array = []
	for group in groups:
		result.append(int(group.servings))
	return result

func apply_snapshot(remaining: Array) -> void:
	for i in range(mini(groups.size(), remaining.size())):
		var count = clampi(int(remaining[i]), 0, Props.FOOD_PORTIONS)
		groups[i].servings = count
		Props.set_grill_servings(groups[i].grill, count)

func occupied(spot: Vector3) -> bool:
	for group in groups:
		if spot.distance_to(group.car.position) < 2.3 or spot.distance_to(group.table.position) < 1.5 or spot.distance_to(group.grill.position) < 1.2:
			return true
	for person in people:
		if spot.distance_to(person.avatar.position) < 0.8:
			return true
	return false

func watch_spot(s: float, home: Vector3) -> Vector3:
	var sign = 1.0 if (home - game.stage.at(s)).dot(game.stage.side(s)) >= 0 else -1.0
	for shift in [0.0, 4.0, -4.0, 8.0, -8.0]:
		var point = grounded(game.stage.at(s + shift) + game.stage.side(s + shift) * sign * 6.4)
		if game.stage.road_distance(point) < 5.5 or game.stage.obstacle_hit(point, point, 0.4) >= 0 or not game.stage.rock_hit(point, point, 0.4, false).is_empty():
			continue
		if not game.stage.solids.hit(point, point, 0.4, false).is_empty():
			continue
		return point
	return home

func move_person(person: Dictionary, destination: Vector3, delta: float) -> void:
	Navigation.move(game, person, destination, delta, person.helper < 0)

func nearby_stranded(person: Dictionary) -> Dictionary:
	var nearest = 24.0
	var found: Dictionary = {}
	for racer in game.racers:
		if not game.can_tow_racer(racer):
			continue
		var distance: float = minf(person.home.distance_to(racer.node.position), person.avatar.position.distance_to(racer.node.position))
		if distance < nearest:
			nearest = distance
			found = racer
	return found

func passing_car(point: Vector3) -> bool:
	for racer in game.racers:
		if racer.state in ["racing", "offroad", "rock_bounce"] and racer.node.position.distance_to(point) < 42:
			return true
	return false

func push_helpers() -> Dictionary:
	var result = {}
	for person in people:
		if person.helper < 0 or person.action != "push":
			continue
		for racer in game.racers:
			if racer.id == person.helper and game.can_tow_racer(racer):
				var road = game.Recovery.road_direction(game, racer)
				result["npc_%d" % person.id] = {"pos": game.room.a(person.avatar.position), "in_car": false, "tow": false, "push": game.room.a(road), "beers": 0, "racer": racer.id}
	return result

func actor_snapshot() -> Array:
	var result: Array = []
	for person in people:
		result.append({"id": person.id, "pos": game.room.a(person.avatar.position), "yaw": person.avatar.rotation.y, "action": person.action, "time": person.time, "helper": person.helper})
	return result

func apply_actor_snapshot(poses: Array) -> void:
	var first = actor_targets.is_empty()
	actor_targets.clear()
	for pose in poses:
		actor_targets[int(pose.id)] = pose
		if first:
			for person in people:
				if person.id == int(pose.id):
					person.avatar.position = game.room.v(pose.pos)
					person.avatar.rotation.y = float(pose.yaw)
