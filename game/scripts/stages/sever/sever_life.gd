extends RefCounted
# Living details of «Поречье»: villagers bundled in fur hats and felt boots
# walking the street with a bucket or a bundle of firewood, a dog trotting
# the yards, hens pecking by the barn, crows on the fence posts and over the
# fields, wood smoke from every chimney and a light, steady snowfall around
# the player. All of it is local scenery; gameplay state (snow, trees,
# collisions) stays in stage.gd and is identical for every client.
const Props = preload("res://scripts/core/props.gd")
const CharacterRig = preload("res://scripts/people/character_rig.gd")
const LIFE_RANGE = 130.0

var stage
var biome
var root: Node3D
var rng = RandomNumberGenerator.new()
var clock = 0.0
var walkers: Array[Dictionary] = []
var smoke: Array[CPUParticles3D] = []
var snowfall: CPUParticles3D
var dog: Dictionary = {}
var hens: Array[Dictionary] = []
var crows: Array[Dictionary] = []

func build(owner_stage, owner_biome) -> void:
	stage = owner_stage
	biome = owner_biome
	rng.seed = 21022026
	root = Node3D.new()
	root.name = "SeverLife"
	stage.add_child(root)
	_build_snowfall()
	for chimney in biome.chimneys:
		smoke.append(_smoke(chimney, Color(0.8, 0.8, 0.82, 0.55), 0.85, 0.95))
	_build_walkers()
	_build_dog()
	_build_hens()
	_build_crows()

static var _soft_disc: GradientTexture2D

static func soft_disc() -> GradientTexture2D:
	if _soft_disc == null:
		var fade = Gradient.new()
		fade.set_color(0, Color(1, 1, 1, 1))
		fade.set_color(1, Color(1, 1, 1, 0))
		fade.add_point(0.45, Color(1, 1, 1, 0.75))
		_soft_disc = GradientTexture2D.new()
		_soft_disc.gradient = fade
		_soft_disc.fill = GradientTexture2D.FILL_RADIAL
		_soft_disc.fill_from = Vector2(0.5, 0.5)
		_soft_disc.fill_to = Vector2(1.0, 0.5)
		_soft_disc.width = 64
		_soft_disc.height = 64
	return _soft_disc

static func _particle_material(color: Color, unshaded: bool) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.albedo_texture = soft_disc()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat

func _build_snowfall() -> void:
	snowfall = CPUParticles3D.new()
	snowfall.name = "Snowfall"
	var quad = QuadMesh.new()
	quad.size = Vector2(0.055, 0.055)
	quad.material = _particle_material(Color(1, 1, 1, 0.9), true)
	snowfall.mesh = quad
	snowfall.amount = 360
	snowfall.lifetime = 9.0
	snowfall.preprocess = 9.0
	snowfall.local_coords = false
	snowfall.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	snowfall.emission_box_extents = Vector3(26, 1, 26)
	snowfall.direction = Vector3(0.2, -1, 0.15)
	snowfall.spread = 16.0
	snowfall.gravity = Vector3(0.18, -0.4, 0.12)
	snowfall.initial_velocity_min = 0.45
	snowfall.initial_velocity_max = 1.0
	snowfall.scale_amount_min = 0.6
	snowfall.scale_amount_max = 1.4
	snowfall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	snowfall.position = stage.at(20.0) + Vector3.UP * 12.0
	root.add_child(snowfall)

func _smoke(at: Vector3, color: Color, size: float, rise: float) -> CPUParticles3D:
	var puff = CPUParticles3D.new()
	puff.name = "Smoke"
	var quad = QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = _particle_material(Color.WHITE, false)
	puff.mesh = quad
	puff.amount = 20
	puff.lifetime = 6.0
	puff.preprocess = 6.0
	puff.local_coords = false
	puff.direction = Vector3.UP
	puff.spread = 12.0
	puff.gravity = Vector3(0.3, 0.1, 0.12)
	puff.initial_velocity_min = 0.5 * rise
	puff.initial_velocity_max = 0.9 * rise
	puff.scale_amount_min = 0.8
	puff.scale_amount_max = 1.3
	var growth = Curve.new()
	growth.add_point(Vector2(0, 0.5))
	growth.add_point(Vector2(1, 2.4))
	puff.scale_amount_curve = growth
	var fade = Gradient.new()
	fade.set_color(0, color)
	fade.set_color(1, Color(color.r, color.g, color.b, 0.0))
	puff.color_ramp = fade
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	puff.position = at
	root.add_child(puff)
	return puff

# ---------------------------------------------------------------- villagers

func person(variant: int, accessory: String) -> Node3D:
	var avatar = Props.player_avatar(variant, stage.outfit)
	avatar.name = "Villager"
	root.add_child(avatar)
	CharacterRig.hand(avatar).get_node("BeerCan").hide()
	CharacterRig.hand(avatar).get_node("Skewer").hide()
	match accessory:
		"bucket":
			var arm = CharacterRig.hand(avatar)
			Props.cylinder(arm, Vector3(0, -0.4, 0), 0.14, 0.17, 0.22, Color("8f9497"), 8)
		"firewood":
			Props.wood_bundle(CharacterRig.hand(avatar), Vector3(0, -0.32, 0))
	return avatar

func _stroll(avatar: Node3D, gait: int, seed: float, arms: String = "", wave: float = 0.0) -> void:
	CharacterRig.pose(avatar, {"gait": gait, "time": clock, "seed": seed, "arms": arms, "wave": wave})

func _build_walkers() -> void:
	var routes = [[334.0, 556.0, 1.0], [336.0, 460.0, -1.0], [496.0, 554.0, -1.0], [360.0, 500.0, 1.0]]
	var accessories = ["bucket", "firewood", "", "bucket"]
	for i in range(routes.size()):
		var item: Array = routes[i]
		var path: Array[Vector3] = []
		var s: float = item[0]
		while s <= item[1]:
			var half = biome.road_width(s) * 0.5
			var p = stage.at(s) + stage.side(s) * item[2] * (half + 2.6)
			s += 2.0
			if biome.reserved(p, 0.6) or not stage.solids.clear(p, 0.3):
				continue
			p.y = stage.ground(p)
			path.append(p)
		if path.is_empty():
			continue
		var avatar = person(i + 1, accessories[i])
		walkers.append({"node": avatar, "path": path, "t": rng.randf() * (path.size() - 1), "direction": 1.0 if i % 2 == 0 else -1.0, "speed": rng.randf_range(0.85, 1.15)})

func _update_walkers(delta: float, focus: Vector3) -> void:
	for walker in walkers:
		var node: Node3D = walker.node
		if node.position.distance_squared_to(focus) > LIFE_RANGE * LIFE_RANGE:
			continue
		var path: Array = walker.path
		if path.size() < 2:
			continue
		var t = float(walker.t) + float(walker.direction) * float(walker.speed) * delta * 0.5
		var count = path.size()
		if t > count - 1:
			t = count - 1
			walker.direction = -1.0
		elif t < 0.0:
			t = 0.0
			walker.direction = 1.0
		walker.t = t
		var i = clampi(int(t), 0, count - 2)
		var a: Vector3 = path[i]
		var b: Vector3 = path[i + 1]
		node.position = a.lerp(b, t - i)
		var facing = (b - a) * walker.direction
		if facing.length_squared() > 0.0001:
			node.rotation.y = atan2(facing.x, facing.z)
		_stroll(node, 1, float(hash(node)) * 0.001, "", 0.0)

# ---------------------------------------------------------------- animals

func _build_dog() -> void:
	var yard = biome.place(biome.WELL.s + 8.0, 1.0, 8.0)
	var node = Node3D.new()
	node.name = "VillageDog"
	root.add_child(node)
	Props.faceted(node, Vector3(0, 0.26, 0), Vector3(0.6, 0.34, 0.26), Color("8a7256"), 8, 4)
	Props.faceted(node, Vector3(0.32, 0.4, 0), Vector3(0.26, 0.26, 0.22), Color("8a7256"), 8, 4)
	for x in [-0.2, 0.2]:
		for z in [-0.09, 0.09]:
			Props.cylinder(node, Vector3(x, 0.1, z), 0.04, 0.04, 0.2, Color("6d5a42"), 5)
	var tail = Props.cylinder(node, Vector3(-0.32, 0.36, 0), 0.03, 0.015, 0.3, Color("8a7256"), 5)
	tail.rotation.z = 0.9
	node.position = yard
	node.position.y = stage.ground(node.position)
	dog = {"node": node, "home": yard, "target": yard, "phase": 0.0, "wait": 0.0}

func _update_dog(delta: float, focus: Vector3) -> void:
	if dog.is_empty():
		return
	var node: Node3D = dog.node
	if node.position.distance_squared_to(focus) > LIFE_RANGE * LIFE_RANGE:
		return
	dog.wait = float(dog.wait) - delta
	if dog.wait <= 0.0 or node.position.distance_to(dog.target) < 0.5:
		dog.wait = rng.randf_range(2.0, 5.0)
		dog.target = Vector3(dog.home) + Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))
	var to_target: Vector3 = dog.target - node.position
	to_target.y = 0.0
	if to_target.length() > 0.2:
		node.rotation.y = lerp_angle(node.rotation.y, atan2(to_target.x, to_target.z), 1.0 - exp(-delta * 5.0))
		node.position += Vector3(sin(node.rotation.y), 0, cos(node.rotation.y)) * minf(1.4, to_target.length()) * delta
	dog.phase = float(dog.phase) + delta * 7.0
	node.position.y = stage.ground(node.position) + absf(sin(dog.phase)) * 0.05

func _build_hens() -> void:
	var yard = biome.place(biome.BARN.s, biome.BARN.side, biome.BARN.offset + 6.5)
	for i in range(5):
		var node = Node3D.new()
		node.name = "Hen"
		root.add_child(node)
		Props.faceted(node, Vector3(0, 0.14, 0), Vector3(0.26, 0.22, 0.3), Color("eee6d2"), 7, 3)
		Props.box(node, Vector3(0, 0.16, -0.17), Vector3(0.05, 0.04, 0.06), Color("c23b2b"))
		Props.cylinder(node, Vector3(0, 0.2, -0.2), 0.0, 0.03, 0.08, Color("e8a23a"), 4)
		var home = yard + Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))
		node.position = home
		node.position.y = stage.ground(node.position)
		hens.append({"node": node, "home": home, "phase": rng.randf() * TAU, "peck": rng.randf() * TAU})

func _update_hens(delta: float, focus: Vector3) -> void:
	for hen in hens:
		var node: Node3D = hen.node
		if node.position.distance_squared_to(focus) > LIFE_RANGE * LIFE_RANGE:
			continue
		hen.peck = float(hen.peck) + delta * 3.0
		node.rotation.x = -absf(sin(hen.peck)) * 0.5

# ---------------------------------------------------------------- crows

func _build_crows() -> void:
	var homes = [[200.0, 70.0], [700.0, -70.0]]
	for home in homes:
		var s = float(home[0])
		var center: Vector3 = stage.at(s) + stage.side(s) * float(home[1])
		center.y = stage.ground(center) + 26.0
		for i in range(3):
			var bird = Node3D.new()
			bird.name = "Crow"
			Props.faceted(bird, Vector3.ZERO, Vector3(0.17, 0.15, 0.46), Color("141414"), 6, 3)
			Props.faceted(bird, Vector3(0, 0.03, -0.27), Vector3(0.12, 0.11, 0.14), Color("141414"), 6, 3)
			Props.box(bird, Vector3(0, 0, -0.36), Vector3(0.04, 0.035, 0.09), Color("2a2a2c"))
			Props.box(bird, Vector3(0, 0, 0.3), Vector3(0.2, 0.02, 0.18), Color("141414"))
			var wings: Array = []
			for side in [-1.0, 1.0]:
				var hinge = Node3D.new()
				bird.add_child(hinge)
				Props.box(hinge, Vector3(side * 0.34, 0, 0), Vector3(0.62, 0.025, 0.22), Color("1c1c1f"))
				hinge.set_meta("side", side)
				wings.append(hinge)
			root.add_child(bird)
			crows.append({"node": bird, "wings": wings, "center": center, "radius": rng.randf_range(9.0, 22.0), "phase": rng.randf() * TAU, "speed": rng.randf_range(0.17, 0.27) * (1.0 if i % 2 == 0 else -1.0), "height": rng.randf_range(-3.0, 4.0)})

func _update_crows() -> void:
	for crow in crows:
		var node: Node3D = crow.node
		var angle = clock * float(crow.speed) + float(crow.phase)
		var center: Vector3 = crow.center
		var radius = float(crow.radius)
		node.position = center + Vector3(cos(angle) * radius, float(crow.height) + sin(clock * 0.55 + float(crow.phase)) * 1.8, sin(angle) * radius)
		var heading = Vector3(-sin(angle), 0, cos(angle)) * signf(float(crow.speed))
		node.rotation = Vector3(0, atan2(-heading.x, -heading.z), -0.3 * signf(float(crow.speed)))
		var flap = sin(clock * 8.5 + float(crow.phase)) * 0.5
		for wing in crow.wings:
			wing.rotation.z = flap * float(wing.get_meta("side"))

# ---------------------------------------------------------------- update

func update(delta: float, focus: Vector3) -> void:
	clock += delta
	if snowfall != null:
		snowfall.position = focus + Vector3.UP * 12.0
	_update_walkers(delta, focus)
	_update_dog(delta, focus)
	_update_hens(delta, focus)
	_update_crows()
