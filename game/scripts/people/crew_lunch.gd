extends RefCounted
# A crew that went off and nobody pulled out walks over to the nearest fan
# camp and sits down to lunch with them, after Adrien Fourmaux, who hit a pole
# on Rally Croatia 2026 and spent two hours at lunch with the family whose
# holiday house was next to it.
#
# The host retires the crew: a stranded car (rally_crews.gd) that nobody,
# player or camp fan, works on for DELAY seconds, with a camp within RANGE,
# becomes "parked" and carries `lunch`, the camp's index; that goes to guests
# with the crew's snapshot (world_sync.gd). Every client then plays the same
# scene itself: the two seats of the car empty (the car swaps to its crewless
# bake), pilot and navigator in overalls climb out, walk along the shoulder to
# the camp, then over to its table, and eat there for the rest of the pass.
const Props = preload("res://scripts/core/props.gd")
const CarOccupants = preload("res://scripts/cars/car_occupants.gd")
const RallyCarModel = preload("res://scripts/cars/rally_car_model.gd")
const CharacterRig = preload("res://scripts/people/character_rig.gd")
const Navigation = preload("res://scripts/people/crowd_navigation.gd")
const Loc = preload("res://scripts/ui/loc.gd")
const DELAY = 40.0
const RANGE = 160.0
# Walking speed (m/s), the shoulder walked along (m past the road edge) and
# how far apart the two walk.
const SPEED = 1.7
const SHOULDER = 1.1
const APART = 0.9
# They stand at the far end of the table from the camp's own people, this far
# out and this far either side of its middle.
const TABLE_OUT = 1.35
const TABLE_SIDE = 0.55
# A walk to the table that cannot find a route ends there after this long.
const GIVE_UP = 30.0

# racer id -> {"racer", "people": [{"avatar", "phase", ...}], "camp"}
var crews: Dictionary = {}

func update(spectators, delta: float, guest: bool) -> void:
	var game = spectators.game
	if not guest:
		for racer in game.racers:
			_retire(spectators, racer, delta)
	for racer in game.racers:
		if int(racer.get("lunch", -1)) >= 0 and not crews.has(racer.id) and is_instance_valid(racer.node) and int(racer.lunch) < spectators.groups.size():
			_start(spectators, racer)
	for id in crews.keys():
		var crew: Dictionary = crews[id]
		if not game.racers.has(crew.racer) or int(crew.racer.get("lunch", -1)) < 0 or not is_instance_valid(crew.racer.node):
			for person in crew.people:
				if is_instance_valid(person.avatar):
					person.avatar.queue_free()
			crews.erase(id)
			continue
		for i in range(crew.people.size()):
			_walk(spectators, crew, crew.people[i], i, delta)

# Host: a stranded crew left alone long enough goes for lunch.
func _retire(spectators, racer: Dictionary, delta: float) -> void:
	var game = spectators.game
	if racer.state != "stranded" or str(racer.get("role", "racer")) != "racer" or not is_instance_valid(racer.node):
		racer.erase("lunch_wait")
		return
	var helped = racer.get("towed", false) or int(racer.get("recovery_helpers", 0)) > 0 or racer.node == game.tow_target
	for person in spectators.people:
		helped = helped or int(person.helper) == int(racer.id)
	if helped:
		racer.lunch_wait = 0.0
		return
	racer.lunch_wait = float(racer.get("lunch_wait", 0.0)) + delta
	if float(racer.lunch_wait) < DELAY:
		return
	var camp = nearest_camp(spectators, racer.node.position)
	if camp < 0:
		return
	racer.erase("lunch_wait")
	racer.state = "parked"
	racer.lunch = camp
	game.announce(Loc.t("Экипаж №%d сошёл и пошёл обедать к болельщикам.") % int(racer.node.get_meta("number", 0)))

static func nearest_camp(spectators, at: Vector3) -> int:
	var best = RANGE
	var found = -1
	for i in range(spectators.groups.size()):
		var distance = at.distance_to(spectators.groups[i].table.position)
		if distance < best:
			best = distance
			found = i
	return found

func _start(spectators, racer: Dictionary) -> void:
	var game = spectators.game
	var node: Node3D = racer.node
	var variant = int(node.get_meta("variant", racer.get("variant", 0)))
	# The cabin empties: the same car baked without its two people.
	var empty = Props.rally_car(variant, int(node.get_meta("number", -1)), str(node.get_meta("sponsor", "")), false)
	var baked: MeshInstance3D = node.get_node_or_null("Baked")
	if baked != null and empty.get_node_or_null("Baked") != null:
		baked.mesh = empty.get_node("Baked").mesh
	empty.free()
	var group: Dictionary = spectators.groups[int(racer.lunch)]
	var table: Node3D = group.table
	var stage = game.stage
	var camp_s: float = stage.road_s(table.position)
	var car_s: float = stage.road_s(node.position)
	var side = 1.0 if (table.position - stage.at(camp_s)).dot(stage.side(camp_s)) >= 0.0 else -1.0
	# The far end of the table: away from where the camp's people stand.
	var right: Vector3 = table.global_basis.x
	var roadward = 1.0 if (stage.at(camp_s) - table.position).dot(right) >= 0.0 else -1.0
	var forward: Vector3 = table.global_basis.z
	var crew = {"racer": racer, "people": [], "side": side, "camp_s": camp_s}
	var p = RallyCarModel.record(variant)
	for i in range(2):
		var avatar = CarOccupants.crew_walker(p, i, variant)
		spectators.add_child(avatar)
		# Out of the pilot's door and the navigator's.
		var door = node.position + node.basis.x * (-0.9 if i == 0 else 0.9)
		avatar.position = Vector3(door.x, stage.ground(door), door.z)
		var spot: Vector3 = table.position - right * roadward * TABLE_OUT + forward * (TABLE_SIDE if i == 0 else -TABLE_SIDE)
		spot.y = stage.ground(spot)
		crew.people.append({"avatar": avatar, "phase": "out", "s": car_s + (0.0 if i == 0 else -APART), "spot": spot, "table": table.position, "helper": -1, "time": 0.0, "id": int(racer.id) * 2 + i})
	crews[racer.id] = crew

func _shoulder(stage, s: float, side: float) -> Vector3:
	var point: Vector3 = stage.at(s) + stage.side(s) * side * (stage.road_width(s) * 0.5 + SHOULDER)
	point.y = stage.ground(point)
	return point

func _walk(spectators, crew: Dictionary, person: Dictionary, index: int, delta: float) -> void:
	var stage = spectators.game.stage
	var avatar: Node3D = person.avatar
	var before = avatar.position
	person.time = float(person.time) + delta
	match person.phase:
		"out":
			var goal = _shoulder(stage, float(person.s), crew.side)
			if _step(stage, avatar, goal, delta):
				person.phase = "road"
		"road":
			var remaining = float(crew.camp_s) - float(person.s)
			person.s = float(person.s) + clampf(remaining, -SPEED * delta, SPEED * delta)
			_step(stage, avatar, _shoulder(stage, float(person.s), crew.side), delta)
			if absf(remaining) < 0.5:
				person.phase = "camp"
				person.time = 0.0
		"camp":
			Navigation.move(spectators.game, person, person.spot, delta, false)
			if Vector2(avatar.position.x - person.spot.x, avatar.position.z - person.spot.z).length() < 0.25 or float(person.time) > GIVE_UP:
				avatar.position = person.spot
				person.phase = "lunch"
				person.time = float(index) * 1.7
	var moving = avatar.position.distance_to(before) > 0.001
	if moving:
		var heading = avatar.position - before
		avatar.rotation.y = atan2(-heading.x, -heading.z)
	var pose = {"gait": 1 if moving else 0, "time": float(person.time), "seed": float(person.id)}
	var food: Node3D = avatar.get_node("RightArm/RightForearm/Skewer")
	food.visible = person.phase == "lunch"
	if person.phase == "lunch":
		var toward = person.table - avatar.position
		avatar.rotation.y = atan2(-toward.x, -toward.z)
		# A bite every few seconds, chatting in between.
		var bite = fmod(float(person.time), 6.0)
		var lift = Props.food_lift(bite) if bite < 3.6 else 0.0
		food.rotation.x = -lift
		Props.pose_skewer(food, minf(bite, 3.6))
		pose.arms = "eat"
		pose.lift = lift
		pose.look = sin(float(person.time) * 0.4 + index) * 0.25
	CharacterRig.pose(avatar, pose)

# A straight step towards `goal` on the ground; true once there.
static func _step(stage, avatar: Node3D, goal: Vector3, delta: float) -> bool:
	var offset = goal - avatar.position
	offset.y = 0.0
	if offset.length() < 0.1:
		return true
	var next = avatar.position + offset.normalized() * minf(offset.length(), SPEED * delta)
	next.y = stage.ground(next)
	avatar.position = next
	return false
