extends Node3D
# Deterministic course furniture: no room commands or extra network traffic.
const Props = preload("res://scripts/props.gd")
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
				if stage.urban and not stage.city.hit(point, point, clearance, false).is_empty():
					continue
				if stage.obstacle_hit(point, point, clearance) >= 0 or not stage.rock_hit(point, point, clearance, false).is_empty():
					continue
				var clear = true
				if clearance > 1.0:
					for along in [-4.6, -3.2, -1.1, 1.1, 3.2]:
						var extra = grounded(point + stage.direction(s) * along)
						clear = clear and stage.road_distance(extra) > 5.3 and stage.obstacle_hit(extra, extra, clearance) < 0 and stage.rock_hit(extra, extra, clearance, false).is_empty()
						if stage.urban:
							clear = clear and stage.city.hit(extra, extra, clearance, false).is_empty()
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
	stage.rocks.append({"pos": parent.position + local.rotated(Vector3.UP, parent.rotation.y), "radius": radius, "height": height, "official": true})

func build() -> void:
	name = "CourseOfficials"
	arch(4.0, "СТАРТ", false)
	arch(stage.LENGTH - 8.0, "ФИНИШ", true)
	station(24.0, 1.0, "Старт")
	station(stage.LENGTH - 30.0, -1.0, "Финиш")
	var positions: Array = [180.0, 420.0, 650.0] if stage.winter else [165.0, 365.0, 570.0, 730.0]
	for i in range(positions.size()):
		var spot = roadside(positions[i], 1.0 if i % 2 == 0 else -1.0, 0.6)
		if spot.is_empty():
			push_error("No safe marshal position on stage %d" % stage.variant)
			continue
		var marshal = Props.course_official("marshal", i)
		add_child(marshal)
		marshal.position = spot.pos
		var toward = stage.at(spot.s) - marshal.position
		marshal.rotation.y = atan2(-toward.x, -toward.z)
		marshals.append(marshal)
		solid(marshal, Vector3.ZERO, 0.33, 1.75)

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
		Props.box(gate, local + Vector3(0, 2.3, 0), Vector3(0.65, 4.6, 0.70), Color("e1e2df"))
		Props.box(gate, local + Vector3(0, 0.12, 0), Vector3(1.0, 0.24, 1.05), Color("353c40"))
		for row in range(8):
			for face in [-1.0, 1.0]:
				Props.box(gate, local + Vector3(0, 0.5 + row * 0.49, face * 0.361), Vector3(0.60, 0.24, 0.018), Color("272e33") if row % 2 == 0 else Color("ce4830"))
		solid(gate, local, 0.48, 4.6)
	Props.box(gate, Vector3(0, 4.5, 0), Vector3(13.1, 0.85, 0.70), Color("ce4830"))
	for face in [-1.0, 1.0]:
		var yaw = PI if face < 0 else 0.0
		Props.label_3d(gate, Vector3(0, 4.55, face * 0.37), caption, 112, 0.007, Color.WHITE, yaw)
		Props.label_3d(gate, Vector3(0, 4.25, face * 0.37), "RALLY FAN MAPS", 44, 0.004, Color("fff1dc"), yaw)
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
	arches.append(gate)

func station(s: float, sign: float, title: String) -> void:
	var spot = roadside(s, sign, 1.35)
	if spot.is_empty():
		push_error("No safe judge station on stage %d" % stage.variant)
		return
	var car = Props.judges_car()
	add_child(car)
	car.position = spot.pos
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
		if stage.urban and not stage.city.hit(official.position, official.position, 0.4, false).is_empty():
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
	Props.table(desk)
	Props.box(desk, Vector3(0, 0.91, 0), Vector3(0.35, 0.035, 0.25), Color("ece9d7"))
	Props.box(desk, Vector3(0.4, 0.96, 0), Vector3(0.17, 0.10, 0.11), Color("293339"))
