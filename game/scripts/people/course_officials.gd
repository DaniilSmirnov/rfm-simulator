extends Node3D
# Fixed stations, with host-authoritative marshal movement.
const Navigation = preload("res://scripts/people/crowd_navigation.gd")
var people: Array[Dictionary] = []
var targets: Dictionary = {}
const MeshMerge = preload("res://scripts/core/mesh_merge.gd")
const Props = preload("res://scripts/core/props.gd")
const Records = preload("res://scripts/stages/stage_records.gd")
const CharacterRig = preload("res://scripts/people/character_rig.gd")
var stage: Node3D
var arches: Array[Node3D] = []
var cars: Array[Node3D] = []
var judges: Array[Node3D] = []
var marshals: Array[Node3D] = []

func grounded(point: Vector3) -> Vector3:
	point.y = stage.ground(point)
	return point

func roadside(station: float, preferred_side: float, clearance: float) -> Dictionary:
	for shift in [0.0, 8.0, -8.0, 16.0, -16.0, 24.0, -24.0, 32.0, -32.0]:
		var s = clampf(station + shift, 18.0, stage.LENGTH - 24.0)
		for sign in [preferred_side, -preferred_side]:
			for distance in [7.2, 8.0, 8.8]:
				var point = grounded(stage.at(s) + stage.side(s) * sign * distance)
				if stage.road_distance(point) < 5.3 + clearance * 0.2:
					continue
				if not stage.solids.hit(point, point, clearance, false).is_empty():
					continue
				if stage.water != null and stage.water.depth(point) > -0.3:
					continue
				if stage.obstacle_hit(point, point, clearance) >= 0 or not stage.rock_hit(point, point, clearance, false).is_empty():
					continue
				var clear = true
				if clearance > 1.0:
					for along in [-4.6, -3.2, -1.1, 1.1, 3.2]:
						var extra = grounded(point + stage.direction(s) * along)
						clear = clear and stage.road_distance(extra) > 5.3 and stage.obstacle_hit(extra, extra, clearance) < 0 and stage.rock_hit(extra, extra, clearance, false).is_empty()
						clear = clear and stage.solids.hit(extra, extra, clearance, false).is_empty()
				if clear:
					return {"pos": point, "s": s, "side": sign}
	return {}

func solid(parent: Node3D, local: Vector3, radius: float, height: float) -> void:
	var body = StaticBody3D.new()
	parent.add_child(body)
	body.position = local + Vector3(0, height * 0.5, 0)
	var collider = CollisionShape3D.new()
	var shape = CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	collider.shape = shape
	body.add_child(collider)
	var record = Records.rock(parent.position + local.rotated(Vector3.UP, parent.rotation.y), radius, height, Records.OFFICIAL)
	if parent.get_meta("role", "") in ["marshal", "judge"]:
		parent.set_meta("solid_record", record)
	if parent.get_meta("role", "") == "marshal":
		record.actor = parent
	stage.rocks.append(record)

func build() -> void:
	name = "CourseOfficials"
	# Crews wait under the arch before their start, right at the end of the road.
	arch(1.0, "Rally Fans Map", false)
	arch(stage.LENGTH - 1.0, "Rally Fans Map", true)
	station(24.0, 1.0, "Старт")
	station(stage.LENGTH - 30.0, -1.0, "Финиш")
	var positions: Array = stage.biome.marshal_stations()
	for i in range(positions.size()):
		var spot = roadside(positions[i], 1.0 if i % 2 == 0 else -1.0, 0.6)
		if spot.is_empty():
			push_error("No safe marshal position on stage %d" % stage.variant)
			continue
		var marshal = Props.course_official("marshal", i)
		red_flag(marshal)
		add_child(marshal)
		marshal.position = spot.pos
		var toward = stage.at(spot.s) - marshal.position
		marshal.rotation.y = atan2(-toward.x, -toward.z)
		marshals.append(marshal)
		solid(marshal, Vector3.ZERO, 0.33, 1.75)
		people.append({"id": i, "avatar": marshal, "home": marshal.position, "helper": -1, "action": "watch"})

# A red flag in the marshal's right hand, shown while the stage is red-flagged.
static func red_flag(marshal: Node3D) -> void:
	var flag = Node3D.new()
	flag.name = "RedFlag"
	CharacterRig.hand(marshal).add_child(flag)
	Props.box(flag, Vector3(0, -0.73, -0.05), Vector3(0.025, 0.9, 0.025), Color("d8d2c0"))
	Props.box(flag, Vector3(0, -1.00, -0.29), Vector3(0.015, 0.34, 0.46), Color("d6262b"))
	flag.hide()

func arch(s: float, caption: String, finish: bool) -> void:
	var gate = Node3D.new()
	gate.name = "FinishArch" if finish else "StartArch"
	add_child(gate)
	gate.position = grounded(stage.at(s))
	var heading = stage.direction(s)
	gate.rotation.y = atan2(-heading.x, -heading.z)
	gate.set_meta("station", s)
	gate.set_meta("caption", caption)
	var half_span = 6.2
	for sign in [-1.0, 1.0]:
		var local = Vector3(sign * half_span, 0, 0)
		var foot = gate.position + local.rotated(Vector3.UP, gate.rotation.y)
		local.y = stage.ground(foot) - gate.position.y
		# The pillar is shallower than the banner (0.62 vs 0.70 m), so its top
		# sits inside the banner instead of sharing its faces, and the stripes
		# stand 4 cm proud of it, their backs buried in it: no coplanar faces
		# to flicker in the depth buffer.
		Props.box(gate, local + Vector3(0, 2.3, 0), Vector3(0.65, 4.6, 0.62), Color("e1e2df"))
		Props.box(gate, local + Vector3(0, 0.12, 0), Vector3(1.0, 0.24, 1.05), Color("353c40"))
		for row in range(8):
			for face in [-1.0, 1.0]:
				Props.box(gate, local + Vector3(0, 0.5 + row * 0.49, face * 0.325), Vector3(0.60, 0.24, 0.05), Color("272e33") if row % 2 == 0 else Color("ce4830"))
		solid(gate, local, 0.48, 4.6)
	Props.box(gate, Vector3(0, 4.5, 0), Vector3(13.1, 0.85, 0.70), Color("ce4830"))
	for face in [-1.0, 1.0]:
		var yaw = PI if face < 0 else 0.0
		Props.label_3d(gate, Vector3(0, 4.55, face * 0.37), caption, 112, 0.007, Color.WHITE, yaw)
		for side in [-1.0, 1.0]:
			for x in range(5):
				for y in range(3):
					Props.box(gate, Vector3(side * (3.65 + x * 0.23), 4.28 + y * 0.23, face * 0.365), Vector3(0.23, 0.23, 0.02), Color.WHITE if (x + y) % 2 == 0 else Color("252b30"))
	var overhead = StaticBody3D.new()
	gate.add_child(overhead)
	overhead.position.y = 4.5
	var shape = CollisionShape3D.new()
	var bounds = BoxShape3D.new()
	bounds.size = Vector3(13.1, 0.85, 0.70)
	shape.shape = bounds
	overhead.add_child(shape)
	# Pillars, banner, chequers and captions: one static mesh for the gate.
	MeshMerge.bake(gate)
	arches.append(gate)

func station(s: float, sign: float, title: String) -> void:
	var spot = roadside(s, sign, 1.35)
	if spot.is_empty():
		push_error("No safe judge station on stage %d" % stage.variant)
		return
	var car = Props.judges_car()
	add_child(car)
	car.position = spot.pos
	car.position.y = stage.vehicle_ground(spot.pos)
	var forward = stage.direction(spot.s)
	car.rotation.y = atan2(-forward.x, -forward.z)
	car.set_meta("station", title)
	cars.append(car)
	for z in [-1.1, 0.0, 1.1]:
		solid(car, Vector3(0, 0, z), 0.9, 1.6)
	for i in range(2):
		# Judges work before and behind the parked car, outside the racing line.
		var official = Props.course_official("judge", i)
		add_child(official)
		official.position = grounded(car.position + forward * (-3.2 if i == 0 else 3.2))
		if not stage.solids.hit(official.position, official.position, 0.4, false).is_empty():
			official.position = grounded(car.position + stage.side(spot.s) * spot.side * 1.7 + forward * (i - 0.5))
		var toward = stage.at(spot.s) - official.position
		official.rotation.y = atan2(-toward.x, -toward.z)
		judges.append(official)
		solid(official, Vector3.ZERO, 0.33, 1.75)
	# A timing desk beside the first judge.
	var desk = Node3D.new()
	add_child(desk)
	desk.position = grounded(car.position - forward * 4.6)
	desk.rotation.y = car.rotation.y
	Props.table(desk, 0, "desk")
	# The timing clock: a dark box with a lit display facing the judges.
	Props.box(desk, Vector3(0.4, 0.94, 0), Vector3(0.17, 0.10, 0.11), Color("293339"))
	preload("res://scripts/core/prop_registry.gd").register(stage.solids, desk, 15)

func update(game, delta: float, guest: bool) -> void:
	for person in people:
		var avatar: Node3D = person.avatar
		var flag: Node3D = CharacterRig.hand(avatar).get_node("RedFlag")
		if game.injuries.holds(avatar):
			flag.hide() # A knocked-down marshal drops the flag.
			continue
		var previous: Vector3 = avatar.position
		var facing = avatar.position - Vector3(0, 0, 1)
		if guest and targets.has(person.id):
			var pose: Dictionary = targets[person.id]
			avatar.position = avatar.position.lerp(game.room.v(pose.pos), 1 - exp(-delta * 10))
			person.helper = int(pose.get("helper", -1))
			person.action = str(pose.get("action", "watch"))
			if pose.has("yaw"):
				avatar.rotation.y = lerp_angle(avatar.rotation.y, float(pose.yaw), 1 - exp(-delta * 10))
			else:
				# A marshal watching the stage turns toward the nearest crew, so
				# the host does not send the angle.
				var look = _watch_facing(game, person) - avatar.position
				look.y = 0
				if look.length() > 0.05:
					avatar.rotation.y = lerp_angle(avatar.rotation.y, atan2(-look.x, -look.z), 1 - exp(-delta * 8))
		elif not guest:
			var racer = game.spectators.nearby_stranded(person)
			person.helper = -1
			if not racer.is_empty():
				person.helper = racer.id
				var road = game.Recovery.road_direction(game, racer)
				var rear: Vector3 = racer.node.position - road * 2.0
				Navigation.move(game, person, rear, delta, false)
				person.action = "push" if avatar.position.distance_to(rear) < 0.6 else "help"
				facing = avatar.position + road
			else:
				Navigation.move(game, person, person.home, delta)
				person.action = "flag" if game.course.red_flag else "watch"
				facing = _watch_facing(game, person)
			var direction = facing - avatar.position
			direction.y = 0
			if direction.length() > 0.05:
				avatar.rotation.y = lerp_angle(avatar.rotation.y, atan2(-direction.x, -direction.z), 1 - exp(-delta * 8))
		var moving = avatar.position.distance_to(previous) > 0.001
		# Red flag on the stage: the flag is raised high and waved side to side.
		flag.visible = person.action == "flag"
		var arms = {"flag": "flag", "push": "push"}.get(person.action, "")
		CharacterRig.pose(avatar, {"gait": 1 if moving else 0, "time": game.elapsed, "seed": float(person.id), "arms": arms, "wave": game.elapsed + person.id})
		# Keep manual swept collisions and the real static shape with the moving actor.
		var record: Dictionary = avatar.get_meta("solid_record")
		record.pos = avatar.position

func push_helpers(game) -> Dictionary:
	var result = {}
	for person in people:
		if person.action != "push" or person.helper < 0 or game.injuries.holds(person.avatar):
			continue
		for racer in game.racers:
			if racer.id == person.helper and game.can_tow_racer(racer):
				result["marshal_%d" % person.id] = {"pos": game.room.a(person.avatar.position), "in_car": false, "tow": false, "push": game.room.a(game.Recovery.road_direction(game, racer)), "beers": 0, "racer": racer.id}
	return result

# Where a marshal who is not helping looks: at the nearest crew on the stage,
# else along the road at the post.
func _watch_facing(game, person: Dictionary) -> Vector3:
	var nearest = 65.0
	var facing: Vector3 = game.stage.at(game.stage.road_s(person.home))
	for crew in game.racers:
		if crew.state not in ["racing", "offroad", "rock_bounce"]:
			continue
		var distance: float = crew.node.position.distance_to(person.avatar.position)
		if distance < nearest:
			nearest = distance
			facing = crew.node.position
	return facing

func snapshot() -> Array:
	var result: Array = []
	for person in people:
		var p: Vector3 = person.avatar.position
		# Idle values are left out; a watching marshal's angle follows from the crews.
		var entry = {"id": person.id, "pos": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]}
		if person.helper != -1:
			entry.helper = person.helper
		if person.action != "watch":
			entry.action = person.action
		if not person.action in ["watch", "flag"]:
			entry.yaw = snappedf(person.avatar.rotation.y, 0.001)
		result.append(entry)
	return result

func apply_snapshot(poses: Array) -> void:
	var first = targets.is_empty()
	targets.clear()
	for pose in poses:
		targets[int(pose.id)] = pose
		if first:
			for person in people:
				if person.id == int(pose.id):
					person.avatar.position = Vector3(pose.pos[0], pose.pos[1], pose.pos[2])
					person.avatar.rotation.y = float(pose.get("yaw", person.avatar.rotation.y))
					var record: Dictionary = person.avatar.get_meta("solid_record")
					record.pos = person.avatar.position
