extends RefCounted
# Everyday life of the Provençal village: people strolling on the pavements
# with baguettes and baskets, regulars on the café terrace, a game of pétanque,
# old men on a bench, pigeons that flutter up when a car passes, swallows,
# cats, laundry and tricolour flags in the breeze, chimney smoke, the fountain,
# bees over the lavender and grape pickers with a little vineyard tractor.
# All of it is local scenery: nothing here is synchronised or collides, and
# only the part near the camera is animated.
const Props = preload("res://scripts/props.gd")
const Layout = preload("res://scripts/village_layout.gd")
const LIFE_RANGE = 130.0
const BEE_COUNT = 48

var stage
var village
var root: Node3D
var rng = RandomNumberGenerator.new()
var clock = 0.0
var walkers: Array[Dictionary] = []
var sitters: Array[Dictionary] = []
var players: Array[Dictionary] = []
var pickers: Array[Dictionary] = []
var pigeons: Array[Dictionary] = []
var swallows: Array[Dictionary] = []
var cats: Array[Dictionary] = []
var laundry: Array[Dictionary] = []
var flags: Array[Node3D] = []
var smoke: Array[CPUParticles3D] = []
var boule: Dictionary = {}
var tractor: Dictionary = {}
var bees: MultiMesh
var active_bees = 0
var pigeon_alarm = 0.0

func build(owner_stage) -> void:
	stage = owner_stage
	village = stage.village
	rng.seed = 14071789
	root = Node3D.new()
	root.name = "VillageLife"
	stage.add_child(root)
	_walkers()
	_cafe_regulars()
	_petanque()
	_pickers()
	_tractor()
	_pigeons()
	_swallows()
	_cats()
	_laundry()
	_smoke()
	_fountain()
	_bees()
	for node in stage.find_children("MairieFlag", "Node3D", true, false):
		flags.append(node)

func anchors(kind: String) -> Array:
	return village.anchors.get(kind, [])

# ---------------------------------------------------------------- people

func person(variant: int, accessory: String = "") -> Node3D:
	var avatar = Props.player_avatar(variant)
	avatar.name = "Villager"
	root.add_child(avatar)
	avatar.get_node("RightArm/BeerCan").hide()
	avatar.get_node("RightArm/Skewer").hide()
	var head = avatar.get_node("Head")
	match accessory:
		"beret":
			Props.cylinder(head, Vector3(0, 0.17, 0), 0.15, 0.13, 0.05, Color("1d2226"), 10)
		"straw":
			Props.cylinder(head, Vector3(0, 0.15, 0), 0.24, 0.24, 0.02, Color("d8c27a"), 10)
			Props.cylinder(head, Vector3(0, 0.2, 0), 0.12, 0.11, 0.1, Color("d8c27a"), 10)
		"baguette":
			var bread = Props.cylinder(avatar.get_node("LeftArm"), Vector3(0, -0.3, -0.1), 0.04, 0.035, 0.7, Color("d39a4f"), 6)
			bread.rotation.x = 0.9
		"basket":
			var arm = avatar.get_node("RightArm")
			Props.cylinder(arm, Vector3(0, -0.6, 0), 0.16, 0.2, 0.18, Color("a07a44"), 8)
			Props.box(arm, Vector3(0, -0.47, 0), Vector3(0.24, 0.1, 0.12), Color("d9482f"))
	return avatar

func _legs(avatar: Node3D, swing: float) -> void:
	avatar.get_node("LeftLeg").rotation.x = swing
	avatar.get_node("RightLeg").rotation.x = -swing
	avatar.get_node("LeftArm").rotation.x = -swing * 0.6

# Ping-pong strolls along the village pavements.
func _walkers() -> void:
	var routes = [[296.0, 378.0, 1.0], [300.0, 352.0, -1.0], [454.0, 524.0, 1.0], [456.0, 522.0, -1.0], [318.0, 372.0, 1.0], [462.0, 516.0, -1.0], [304.0, 340.0, -1.0], [470.0, 520.0, 1.0]]
	var accessories = ["baguette", "beret", "basket", "straw", "baguette", "basket", "beret", ""]
	for i in range(routes.size()):
		var item: Array = routes[i]
		var path: Array[Vector3] = []
		var s: float = item[0]
		while s <= item[1]:
			var half = village.road_width(s) * 0.5
			var p = village.anchor(s, item[2] * (half + Layout.PAVEMENT * 0.55))
			s += 2.0
			# Villagers keep to the pavement; never step onto the racing line.
			if not village.pavement(s - 2.0) or not stage.solids.clear(p, 0.3):
				continue
			p.y = stage.ground(p)
			path.append(p)
		var avatar = person(i + 1, accessories[i])
		walkers.append({"node": avatar, "path": path, "t": rng.randf() * (path.size() - 1), "direction": 1.0 if i % 2 == 0 else -1.0, "speed": rng.randf_range(0.9, 1.25), "pause": 0.0})

func _cafe_regulars() -> void:
	var seats: Array = anchors("cafe_seats")
	for i in range(seats.size()):
		if i % 4 == 3:
			continue # leave a few chairs free
		var seat: Dictionary = seats[i]
		var avatar = person(i + 2, "beret" if i % 3 == 0 else "")
		sitters.append({"node": avatar, "pos": seat.pos, "yaw": float(seat.yaw), "phase": rng.randf() * TAU, "cup": i % 2 == 0})
		_sit(avatar, seat.pos, float(seat.yaw))
	for bench in anchors("benches").slice(0, 1):
		for k in range(2):
			var avatar = person(5 + k, "beret")
			var pos: Vector3 = bench.pos + Basis(Vector3.UP, float(bench.yaw)) * Vector3(-0.45 + k * 0.9, 0, 0.05)
			sitters.append({"node": avatar, "pos": pos, "yaw": float(bench.yaw), "phase": rng.randf() * TAU, "cup": false})
			_sit(avatar, pos, float(bench.yaw))

func _sit(avatar: Node3D, pos: Vector3, yaw: float) -> void:
	avatar.position = pos + Vector3(0, -0.36, 0)
	avatar.rotation.y = yaw
	avatar.get_node("LeftLeg").rotation.x = PI * 0.5
	avatar.get_node("RightLeg").rotation.x = PI * 0.5

func _petanque() -> void:
	if not village.anchors.has("petanque"):
		return
	var court: Vector3 = village.anchors.petanque
	var yaw = float(village.square.yaw)
	var basis = Basis(Vector3.UP, yaw)
	for i in range(4):
		var avatar = person(i, ["beret", "straw", "beret", ""][i])
		var spot = court + basis * Vector3(-0.6 + (i % 2) * 1.2, 0, 4.2 + (i / 2) * 0.7)
		avatar.position = spot
		avatar.rotation.y = yaw
		players.append({"node": avatar, "home": spot})
	var ball = Props.cylinder(root, Vector3.ZERO, 0.04, 0.04, 0.08, Color("9aa0a3"), 8)
	ball.name = "Boule"
	ball.hide()
	var jack = Props.cylinder(root, court + basis * Vector3(0.3, 0.02, -3.6), 0.016, 0.016, 0.03, Color("d9b45a"), 6)
	jack.name = "Cochonnet"
	boule = {"node": ball, "court": court, "basis": basis, "thrower": 0, "age": -1.0, "wait": 2.0, "from": Vector3.ZERO, "to": Vector3.ZERO}

func _pickers() -> void:
	var rows: Array = anchors("harvest")
	for i in range(mini(6, rows.size())):
		var row: Dictionary = rows[(i * 7) % rows.size()]
		var avatar = person(i + 3, "straw")
		var p: Vector3 = row.pos
		p.y = stage.terrain_surface_height(p)
		avatar.position = p
		avatar.rotation.y = float(row.yaw) + PI * 0.5
		var crate = Props.box(avatar, Vector3(0.0, 0.18, -0.55), Vector3(0.5, 0.32, 0.38), Color("b08a5a"))
		Props.box(crate, Vector3(0, 0.12, 0), Vector3(0.42, 0.08, 0.3), Color("4a2a4f"))
		pickers.append({"node": avatar, "home": p, "phase": rng.randf() * TAU})

# A narrow vineyard tractor and trailer shuttling slowly between two rows.
func _tractor() -> void:
	var rows: Array = anchors("harvest")
	if rows.size() < 2:
		return
	var node = Node3D.new()
	node.name = "VineyardTractor"
	root.add_child(node)
	var paint = Color("2f6f9e")
	Props.box(node, Vector3(0, 0.75, 0), Vector3(0.9, 0.6, 1.5), paint)
	Props.box(node, Vector3(0, 1.25, 0.35), Vector3(0.8, 0.5, 0.7), Color("3a4446"))
	Props.box(node, Vector3(0, 1.6, 0.35), Vector3(0.9, 0.06, 0.8), paint)
	for x in [-0.55, 0.55]:
		var big = Props.cylinder(node, Vector3(x, 0.5, 0.4), 0.5, 0.5, 0.25, Color("222524"), 12)
		big.rotation.z = PI / 2
		var small = Props.cylinder(node, Vector3(x, 0.32, -0.6), 0.32, 0.32, 0.2, Color("222524"), 10)
		small.rotation.z = PI / 2
	Props.box(node, Vector3(0, 0.7, 2.3), Vector3(1.1, 0.5, 1.8), Color("8a6a48"))
	Props.box(node, Vector3(0, 0.98, 2.3), Vector3(1.0, 0.1, 1.7), Color("4a2a4f"))
	var path: Array[Vector3] = []
	var s = 724.0
	while s < 804.0:
		var p = village.anchor(s, village.road_width(s) * 0.5 + 6.5 + 3.0 * 2.5)
		p.y = stage.terrain_surface_height(p)
		path.append(p)
		s += 2.0
	tractor = {"node": node, "path": path, "t": 0.0, "direction": 1.0}

# ---------------------------------------------------------------- animals

func _pigeons() -> void:
	if not village.anchors.has("fountain"):
		return
	var center: Vector3 = village.anchors.fountain
	for i in range(14):
		var bird = Node3D.new()
		bird.name = "Pigeon"
		Props.faceted(bird, Vector3(0, 0.1, 0), Vector3(0.14, 0.13, 0.26), Color("8a8f98"), 6, 3)
		Props.faceted(bird, Vector3(0, 0.2, -0.1), Vector3(0.08, 0.08, 0.08), Color("5d6a72"), 5, 2)
		Props.box(bird, Vector3(0, 0.19, -0.15), Vector3(0.02, 0.02, 0.04), Color("d9a24a"))
		var wings: Array = []
		for side in [-1.0, 1.0]:
			var hinge = Node3D.new()
			bird.add_child(hinge)
			hinge.position = Vector3(side * 0.06, 0.14, 0)
			Props.box(hinge, Vector3(side * 0.12, 0, 0), Vector3(0.24, 0.015, 0.12), Color("7d8590"))
			hinge.set_meta("side", side)
			wings.append(hinge)
		root.add_child(bird)
		var angle = rng.randf() * TAU
		var ground = center + Vector3(cos(angle), 0, sin(angle)) * rng.randf_range(3.0, 7.0)
		ground.y = float(village.square.height) + 0.03
		bird.position = ground
		pigeons.append({"node": bird, "wings": wings, "ground": ground, "target": ground, "state": "peck", "wait": rng.randf_range(0.5, 3.0), "phase": rng.randf() * TAU, "orbit": rng.randf_range(6.0, 11.0)})

func _swallows() -> void:
	var centers = [village.square.center + Vector3(0, float(village.square.height) + 16.0, 0), village.anchor(760.0, 0) + Vector3(0, village.route(760.0).y + 12.0, 0), village.anchor(120.0, 20.0) + Vector3(0, village.route(120.0).y + 14.0, 0)]
	for c in range(centers.size()):
		for i in range(5):
			var bird = Node3D.new()
			bird.name = "Swallow"
			Props.faceted(bird, Vector3.ZERO, Vector3(0.08, 0.06, 0.22), Color("1f2433"), 5, 2)
			var wings: Array = []
			for side in [-1.0, 1.0]:
				var hinge = Node3D.new()
				bird.add_child(hinge)
				Props.box(hinge, Vector3(side * 0.16, 0, 0.02), Vector3(0.3, 0.01, 0.07), Color("252a3a"))
				hinge.set_meta("side", side)
				wings.append(hinge)
			root.add_child(bird)
			swallows.append({"node": bird, "wings": wings, "center": centers[c], "radius": rng.randf_range(10.0, 26.0), "phase": rng.randf() * TAU, "speed": rng.randf_range(0.35, 0.55) * (1.0 if (c + i) % 2 else -1.0), "height": rng.randf_range(-3.0, 4.0)})

func _cats() -> void:
	var spots = [[330.0, 1.0], [478.0, -1.0], [506.0, 1.0]]
	var colours = [Color("d9883a"), Color("2b2b2e"), Color("e8e2d6")]
	for i in range(spots.size()):
		var s: float = spots[i][0]
		var p = village.anchor(s, spots[i][1] * (village.road_width(s) * 0.5 + Layout.PAVEMENT - 0.3))
		p.y = stage.ground(p)
		var cat = Node3D.new()
		cat.name = "Cat"
		Props.faceted(cat, Vector3(0, 0.16, 0), Vector3(0.16, 0.2, 0.34), colours[i], 6, 3)
		var head = Node3D.new()
		head.name = "Head"
		cat.add_child(head)
		head.position = Vector3(0, 0.32, -0.16)
		Props.faceted(head, Vector3.ZERO, Vector3(0.12, 0.11, 0.11), colours[i], 6, 3)
		for x in [-0.04, 0.04]:
			var ear = Props.cylinder(head, Vector3(x, 0.07, 0), 0.025, 0.0, 0.05, colours[i], 4)
		var tail = Node3D.new()
		tail.name = "Tail"
		cat.add_child(tail)
		tail.position = Vector3(0, 0.14, 0.16)
		var stroke = Props.cylinder(tail, Vector3(0, 0.12, 0.05), 0.02, 0.012, 0.28, colours[i], 5)
		stroke.rotation.x = 0.6
		root.add_child(cat)
		cat.position = p
		cat.rotation.y = village.yaw_at(s) + PI * 0.5 * spots[i][1]
		cats.append({"node": cat, "head": head, "tail": tail, "phase": rng.randf() * TAU})

# ---------------------------------------------------------------- props in motion

# Washing lines strung high across the narrow lane, window to window.
func _laundry() -> void:
	var colours = [Color("f2efe6"), Color("8fb3c4"), Color("d9482f"), Color("e9c43b"), Color("f4d6dc"), Color("5f8e8c")]
	for s in [318.0, 466.0, 486.0, 512.0]:
		var span = village.road_width(s) * 0.5 + Layout.PAVEMENT + 0.1
		var a = village.anchor(s, -span)
		var b = village.anchor(s, span)
		var height = village.route(s).y + 5.4
		a.y = height
		b.y = height
		var line = Props.rope(root, a, b)
		line.name = "LaundryLine"
		var count = 6
		for k in range(count):
			var t = (k + 1.0) / (count + 1.0)
			var hang = a.lerp(b, t) - Vector3.UP * (0.12 + sin(t * PI) * 0.25)
			var pivot = Node3D.new()
			pivot.name = "Laundry"
			root.add_child(pivot)
			pivot.position = hang
			# The cloth hangs in the plane of the line, facing the drivers.
			pivot.rotation.y = village.yaw_at(s)
			var size = Vector3(rng.randf_range(0.35, 0.7), rng.randf_range(0.4, 0.8), 0.02)
			Props.box(pivot, Vector3(0, -size.y * 0.5, 0), size, colours[(k + int(s)) % colours.size()])
			laundry.append({"node": pivot, "phase": rng.randf() * TAU})

func _smoke() -> void:
	var sources: Array = anchors("smoke").duplicate()
	var chimneys: Array = anchors("chimneys")
	for i in range(0, chimneys.size(), maxi(1, chimneys.size() / 5)):
		sources.append(chimneys[i])
	for p in sources.slice(0, 6):
		var particles = CPUParticles3D.new()
		particles.name = "ChimneySmoke"
		particles.amount = 14
		particles.lifetime = 5.0
		particles.preprocess = 5.0
		particles.direction = Vector3(0.25, 1, 0)
		particles.spread = 12.0
		particles.initial_velocity_min = 0.5
		particles.initial_velocity_max = 0.8
		particles.gravity = Vector3(0.12, 0.05, 0)
		particles.scale_amount_min = 0.6
		particles.scale_amount_max = 1.4
		var curve = Curve.new()
		curve.add_point(Vector2(0, 0.3))
		curve.add_point(Vector2(1, 1.6))
		particles.scale_amount_curve = curve
		var puff = SphereMesh.new()
		puff.radius = 0.35
		puff.height = 0.7
		puff.radial_segments = 6
		puff.rings = 3
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.9, 0.9, 0.88, 0.35)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		puff.material = mat
		particles.mesh = puff
		root.add_child(particles)
		particles.position = p
		smoke.append(particles)

func _fountain() -> void:
	if not village.anchors.has("fountain"):
		return
	var center: Vector3 = village.anchors.fountain
	for i in range(4):
		var angle = i * PI * 0.5
		var water = CPUParticles3D.new()
		water.name = "FountainJet"
		water.amount = 18
		water.lifetime = 0.55
		water.direction = Vector3(cos(angle), -0.2, sin(angle))
		water.spread = 4.0
		water.initial_velocity_min = 1.2
		water.initial_velocity_max = 1.4
		water.gravity = Vector3(0, -9.8, 0)
		var drop = BoxMesh.new()
		drop.size = Vector3(0.035, 0.07, 0.035)
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.75, 0.88, 0.95, 0.7)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		drop.material = mat
		water.mesh = drop
		root.add_child(water)
		water.position = center + Vector3(cos(angle) * 0.6, 1.5, sin(angle) * 0.6)

func _bees() -> void:
	var body = BoxMesh.new()
	body.size = Vector3(0.05, 0.04, 0.07)
	bees = MultiMesh.new()
	bees.transform_format = MultiMesh.TRANSFORM_3D
	bees.use_colors = true
	bees.mesh = body
	bees.instance_count = BEE_COUNT
	bees.visible_instance_count = 0
	for i in range(BEE_COUNT):
		bees.set_instance_color(i, Color("e8b62c") if i % 4 else Color("f4f1e6"))
	var node = MultiMeshInstance3D.new()
	node.name = "LavenderBees"
	node.multimesh = bees
	var mat = Props.material(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(node)

# ---------------------------------------------------------------- update

func update(delta: float, focus: Vector3) -> void:
	var dt = clampf(delta, 0.0, 0.1)
	clock += dt
	_update_walkers(dt, focus)
	_update_sitters(focus)
	_update_petanque(dt, focus)
	_update_pickers(focus)
	_update_tractor(dt, focus)
	_update_pigeons(dt, focus)
	_update_swallows()
	_update_cats(focus)
	_update_breeze(focus)
	_update_bees(focus)

func near(p: Vector3, focus: Vector3, range_value: float = LIFE_RANGE) -> bool:
	return Vector2(p.x - focus.x, p.z - focus.z).length() < range_value

func _path_point(path: Array, t: float) -> Vector3:
	var i = clampi(int(t), 0, path.size() - 2)
	return path[i].lerp(path[i + 1], t - i)

# Positions of the rally and course cars currently on the stage.
func _cars() -> Array:
	var result: Array = []
	var game = stage.get_parent()
	if game == null or not "racers" in game:
		return result
	for racer in game.racers:
		if racer.get("node") is Node3D:
			result.append(racer.node.position)
	return result

func _car_near(p: Vector3, cars: Array, reach: float) -> Vector3:
	for car in cars:
		if Vector2(car.x - p.x, car.z - p.z).length() < reach:
			return car
	return Vector3.INF

func _update_walkers(dt: float, focus: Vector3) -> void:
	var cars = _cars()
	for walker in walkers:
		var node: Node3D = walker.node
		var path: Array = walker.path
		if path.size() < 2 or not near(node.position, focus):
			continue
		# A rally car is coming: stop on the pavement, face it and wave.
		var car = _car_near(node.position, cars, 38.0)
		if car != Vector3.INF:
			var look = car - node.position
			node.rotation.y = lerp_angle(node.rotation.y, atan2(-look.x, -look.z), 1.0 - exp(-dt * 6.0))
			_legs(node, 0.0)
			var wave = sin(clock * 9.0 + float(walker.speed) * 7.0) * 0.3
			node.get_node("RightArm").rotation = Vector3(2.6, 0, -0.4 + wave)
			continue
		node.get_node("RightArm").rotation = Vector3.ZERO
		if walker.pause > 0.0:
			walker.pause -= dt
			_legs(node, 0.0)
			continue
		var step = float(walker.speed) * dt / 2.0
		walker.t = float(walker.t) + step * float(walker.direction)
		if walker.t >= path.size() - 1.0 or walker.t <= 0.0:
			walker.t = clampf(walker.t, 0.0, path.size() - 1.0)
			walker.direction = -float(walker.direction)
			walker.pause = rng.randf_range(2.0, 6.0) # a chat on the doorstep
		var p = _path_point(path, walker.t)
		var ahead = _path_point(path, clampf(walker.t + 0.2 * float(walker.direction), 0.0, path.size() - 1.0))
		node.position = p
		var d = ahead - p
		if d.length_squared() > 0.0001:
			node.rotation.y = atan2(-d.x, -d.z)
		_legs(node, sin(clock * 7.0 + float(walker.speed) * 10.0) * 0.45)

func _update_sitters(focus: Vector3) -> void:
	for sitter in sitters:
		var node: Node3D = sitter.node
		if not near(node.position, focus, 80.0):
			continue
		var arm = node.get_node("RightArm")
		var sip = smoothstep(0.75, 0.95, sin(clock * 0.5 + float(sitter.phase)))
		arm.rotation.x = lerpf(0.5, 1.9, sip) if sitter.cup else 0.4 + sin(clock * 0.8 + float(sitter.phase)) * 0.25
		node.get_node("Head").rotation.y = sin(clock * 0.3 + float(sitter.phase)) * 0.35

func _update_petanque(dt: float, focus: Vector3) -> void:
	if boule.is_empty() or not near(boule.court, focus, 90.0):
		return
	var ball: Node3D = boule.node
	var thrower: Dictionary = players[int(boule.thrower)]
	var arm = thrower.node.get_node("RightArm")
	if float(boule.age) < 0.0:
		boule.wait = float(boule.wait) - dt
		arm.rotation.x = -0.5 * smoothstep(1.0, 0.0, float(boule.wait)) if float(boule.wait) < 1.0 else 0.0
		if float(boule.wait) <= 0.0:
			boule.age = 0.0
			boule.from = thrower.node.position + Vector3(0, 0.6, 0) + boule.basis * Vector3(0, 0, -0.3)
			boule.to = boule.court + boule.basis * Vector3(rng.randf_range(-0.8, 0.8), 0.05, -3.6 + rng.randf_range(-0.5, 0.5))
			ball.show()
		return
	boule.age = float(boule.age) + dt
	var t = clampf(float(boule.age) / 1.4, 0.0, 1.0)
	arm.rotation.x = lerpf(1.6, 0.0, smoothstep(0.0, 0.3, t))
	var p: Vector3 = boule.from.lerp(boule.to, t)
	p.y += sin(t * PI) * 1.6 * (1.0 - t * 0.4)
	ball.position = p
	if float(boule.age) > 3.5:
		ball.hide()
		boule.age = -1.0
		boule.wait = rng.randf_range(3.0, 6.0)
		boule.thrower = (int(boule.thrower) + 1) % players.size()
	for player in players:
		player.node.get_node("Head").rotation.y = sin(clock * 0.4 + float(player.home.x)) * 0.2

func _update_pickers(focus: Vector3) -> void:
	for picker in pickers:
		var node: Node3D = picker.node
		if not near(node.position, focus, 100.0):
			continue
		# Bend to the bunches, straighten, reach again.
		var bend = (sin(clock * 0.9 + float(picker.phase)) + 1.0) * 0.5
		node.rotation.x = 0.0
		node.get_node("Head").rotation.x = bend * 0.5
		node.get_node("RightArm").rotation.x = lerpf(0.3, 1.4, bend)
		node.get_node("LeftArm").rotation.x = lerpf(0.2, 1.1, 1.0 - bend)

func _update_tractor(dt: float, focus: Vector3) -> void:
	if tractor.is_empty() or not near(tractor.node.position, focus, 160.0):
		return
	var path: Array = tractor.path
	tractor.t = float(tractor.t) + float(tractor.direction) * dt * 1.4 / 2.0
	if tractor.t >= path.size() - 1.0 or tractor.t <= 0.0:
		tractor.t = clampf(tractor.t, 0.0, path.size() - 1.0)
		tractor.direction = -float(tractor.direction)
	var p = _path_point(path, tractor.t)
	var ahead = _path_point(path, clampf(tractor.t + 0.3 * float(tractor.direction), 0.0, path.size() - 1.0))
	var node: Node3D = tractor.node
	node.position = p
	var d = ahead - p
	if d.length_squared() > 0.0001:
		node.rotation.y = atan2(-d.x, -d.z)

# Pigeons peck around the fountain and take off when a car or the player
# comes close, circle the square and land again.
func _update_pigeons(dt: float, focus: Vector3) -> void:
	if pigeons.is_empty():
		return
	var center: Vector3 = village.anchors.fountain
	pigeon_alarm = maxf(0.0, pigeon_alarm - dt)
	var game = stage.get_parent()
	if near(center, focus, 9.0):
		pigeon_alarm = 7.0
	if game != null and "racers" in game:
		for racer in game.racers:
			if racer.node.position.distance_to(center) < 22.0:
				pigeon_alarm = 8.0
	if not near(center, focus, 120.0):
		return
	for bird in pigeons:
		var node: Node3D = bird.node
		if pigeon_alarm > 0.0 and bird.state != "fly":
			bird.state = "fly"
		elif pigeon_alarm <= 0.0 and bird.state == "fly":
			bird.state = "land"
		match bird.state:
			"fly":
				var angle = float(bird.phase) + clock * 0.9
				var target = center + Vector3(cos(angle) * float(bird.orbit), 7.0 + sin(clock + float(bird.phase)) * 1.5, sin(angle) * float(bird.orbit))
				target.y += float(village.square.height)
				node.position = node.position.lerp(target, 1.0 - exp(-dt * 2.2))
				var tangent = Vector3(-sin(angle), 0, cos(angle))
				node.rotation.y = atan2(-tangent.x, -tangent.z)
				_flap(bird.wings, sin(clock * 22.0 + float(bird.phase)) * 0.9)
			"land":
				node.position = node.position.lerp(bird.ground, 1.0 - exp(-dt * 1.6))
				_flap(bird.wings, sin(clock * 18.0 + float(bird.phase)) * 0.6)
				if node.position.distance_to(bird.ground) < 0.08:
					node.position = bird.ground
					bird.state = "peck"
			_:
				_flap(bird.wings, 0.0)
				bird.wait = float(bird.wait) - dt
				if float(bird.wait) <= 0.0:
					bird.wait = rng.randf_range(1.0, 4.0)
					var step = Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
					var next: Vector3 = bird.ground + step
					if next.distance_to(center) > 2.6 and next.distance_to(center) < 8.0:
						bird.ground = next
				node.position = node.position.lerp(bird.ground, 1.0 - exp(-dt * 3.0))
				node.rotation.x = maxf(0.0, sin(clock * 6.0 + float(bird.phase))) * 0.5

func _flap(wings: Array, amount: float) -> void:
	for wing in wings:
		wing.rotation.z = float(wing.get_meta("side")) * amount

func _update_swallows() -> void:
	for bird in swallows:
		var node: Node3D = bird.node
		var angle = float(bird.phase) + clock * float(bird.speed)
		var center: Vector3 = bird.center
		var radius = float(bird.radius) * (1.0 + 0.25 * sin(clock * 0.7 + float(bird.phase)))
		node.position = center + Vector3(cos(angle) * radius, float(bird.height) + sin(clock * 1.3 + float(bird.phase)) * 2.0, sin(angle) * radius)
		var tangent = Vector3(-sin(angle), 0, cos(angle)) * signf(float(bird.speed))
		node.rotation.y = atan2(-tangent.x, -tangent.z)
		node.rotation.z = -0.5 * signf(float(bird.speed))
		_flap(bird.wings, sin(clock * 14.0 + float(bird.phase) * 3.0) * 0.6)

func _update_cats(focus: Vector3) -> void:
	for cat in cats:
		var node: Node3D = cat.node
		if not near(node.position, focus, 60.0):
			continue
		cat.tail.rotation.z = sin(clock * 1.6 + float(cat.phase)) * 0.5
		var look = node.position.direction_to(focus)
		var watching = node.position.distance_to(focus) < 8.0
		var yaw = atan2(-look.x, -look.z) - node.rotation.y if watching else sin(clock * 0.25 + float(cat.phase)) * 0.6
		cat.head.rotation.y = lerp_angle(cat.head.rotation.y, clampf(wrapf(yaw, -PI, PI), -1.1, 1.1), 0.08)

func _update_breeze(focus: Vector3) -> void:
	for item in laundry:
		var node: Node3D = item.node
		if near(node.position, focus, 90.0):
			node.rotation.x = sin(clock * 2.3 + float(item.phase)) * 0.22 + 0.1
	for flag in flags:
		flag.rotation.y = sin(clock * 1.7 + flag.position.x) * 0.25
		flag.rotation.z = sin(clock * 3.1) * 0.05

# Bees buzz over the lavender bands close to the camera.
func _update_bees(focus: Vector3) -> void:
	var spots: Array = anchors("lavender")
	var index = 0
	for spot in spots:
		if index >= BEE_COUNT:
			break
		if not near(spot, focus, 22.0):
			continue
		for k in range(4):
			if index >= BEE_COUNT:
				break
			var phase = float(index) * 1.7
			var offset = Vector3(sin(clock * 1.9 + phase) * 0.9, 0.75 + sin(clock * 5.3 + phase) * 0.15, cos(clock * 1.4 + phase * 1.3) * 0.9)
			var heading = Vector3(cos(clock * 1.9 + phase), 0, -sin(clock * 1.4 + phase * 1.3))
			bees.set_instance_transform(index, Transform3D(Basis(Vector3.UP, atan2(-heading.x, -heading.z)), spot + offset))
			index += 1
	active_bees = index
	bees.visible_instance_count = index
