extends RefCounted
# Living details of the winter stage: light snow drifting around the player,
# wood smoke from the col hamlet, fans' red flares and national flags waving
# in the wind, and alpine choughs circling above the cliffs. All of it is local
# scenery; gameplay state (snow, banks, digging, trees) is shared elsewhere.
const Props = preload("res://scripts/props.gd")
const LIFE_RANGE = 140.0

var stage
var root: Node3D
var rng = RandomNumberGenerator.new()
var clock = 0.0
var snowfall: CPUParticles3D
var smoke: Array[CPUParticles3D] = []
var flags: Array[Dictionary] = []
var flares: Array[Dictionary] = []
var birds: Array[Dictionary] = []

func build(owner_stage) -> void:
	stage = owner_stage
	rng.seed = 27012026
	root = Node3D.new()
	root.name = "AlpineLife"
	stage.add_child(root)
	_build_snowfall()
	for chimney in stage.alpine.chimneys:
		smoke.append(_smoke(chimney, Color(0.78, 0.78, 0.8, 0.55), 0.9, 1.0))
	for spot in stage.alpine.flag_spots:
		_build_flag(spot)
	for spot in stage.alpine.flare_spots:
		_build_flare(spot)
	_build_choughs()

static var _soft_disc: GradientTexture2D

# Round, soft-edged sprite so flakes and smoke puffs are not square.
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

# Fine flakes in a box around the player; world-space, so they stay put while
# the camera moves through them.
func _build_snowfall() -> void:
	snowfall = CPUParticles3D.new()
	snowfall.name = "Snowfall"
	var quad = QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	quad.material = _particle_material(Color(1, 1, 1, 0.9), true)
	snowfall.mesh = quad
	snowfall.amount = 420
	snowfall.lifetime = 9.0
	snowfall.preprocess = 9.0
	snowfall.local_coords = false
	snowfall.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	snowfall.emission_box_extents = Vector3(26, 1, 26)
	snowfall.direction = Vector3(0.3, -1, 0.1)
	snowfall.spread = 18.0
	snowfall.gravity = Vector3(0.25, -0.45, 0.1)
	snowfall.initial_velocity_min = 0.5
	snowfall.initial_velocity_max = 1.1
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
	puff.amount = 22
	puff.lifetime = 6.0
	puff.preprocess = 6.0
	puff.local_coords = false
	puff.direction = Vector3.UP
	puff.spread = 14.0
	puff.gravity = Vector3(0.35, 0.12, 0.15)
	puff.initial_velocity_min = 0.5 * rise
	puff.initial_velocity_max = 0.9 * rise
	puff.scale_amount_min = 0.8
	puff.scale_amount_max = 1.3
	var growth = Curve.new()
	growth.add_point(Vector2(0, 0.5))
	growth.add_point(Vector2(1, 2.6))
	puff.scale_amount_curve = growth
	var fade = Gradient.new()
	fade.set_color(0, color)
	fade.set_color(1, Color(color.r, color.g, color.b, 0.0))
	puff.color_ramp = fade
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	puff.position = at
	root.add_child(puff)
	return puff

# A flag is a chain of hinged strips; each bends a little more in the wind.
func _build_flag(spot: Dictionary) -> void:
	var pole = Node3D.new()
	pole.name = "FanFlag"
	root.add_child(pole)
	pole.position = spot.pos
	pole.rotation.y = float(spot.yaw)
	Props.cylinder(pole, Vector3(0, 1.6, 0), 0.03, 0.025, 3.2, Color("cfd3d6"), 6)
	var colors: Array = spot.colors
	var strips: Array = []
	var parent: Node3D = pole
	var count = 6
	for i in range(count):
		var hinge = Node3D.new()
		hinge.position = Vector3(0.04, 2.75, 0) if i == 0 else Vector3(0.2, 0, 0)
		parent.add_child(hinge)
		if spot.vertical:
			Props.box(hinge, Vector3(0.1, 0, 0), Vector3(0.2, 0.78, 0.02), colors[mini(i * 3 / count, 2)])
		else:
			for band in range(3):
				Props.box(hinge, Vector3(0.1, 0.26 - band * 0.26, 0), Vector3(0.2, 0.26, 0.02), colors[band])
		strips.append(hinge)
		parent = hinge
	flags.append({"node": pole, "strips": strips, "phase": rng.randf() * TAU})

func _build_flare(at: Vector3) -> void:
	var flare = Node3D.new()
	flare.name = "FanFlare"
	root.add_child(flare)
	flare.position = at
	var stick = Props.cylinder(flare, Vector3(0, 1.3, 0), 0.025, 0.03, 0.32, Color("d23b2a"), 6)
	var glow = StandardMaterial3D.new()
	glow.albedo_color = Color("ff5a3c")
	glow.emission_enabled = true
	glow.emission = Color("ff3b1f")
	glow.emission_energy_multiplier = 3.0
	stick.material_override = glow
	# A fan holds it up on a short pole stuck in the snow.
	Props.cylinder(flare, Vector3(0, 0.6, 0), 0.02, 0.02, 1.2, Color("5c4a3a"), 5)
	var light = OmniLight3D.new()
	light.light_color = Color("ff4a2a")
	light.light_energy = 1.6
	light.omni_range = 7.5
	light.position = Vector3(0, 1.6, 0)
	flare.add_child(light)
	var plume = _smoke(at + Vector3(0, 1.5, 0), Color(0.93, 0.32, 0.27, 0.6), 1.1, 1.6)
	plume.amount = 30
	flares.append({"node": flare, "light": light, "phase": rng.randf() * TAU})

func _build_choughs() -> void:
	var homes = [[60.0, 34.0], [300.0, -40.0], [448.0, 46.0], [760.0, 38.0]]
	for home in homes:
		var s = float(home[0])
		var center: Vector3 = stage.at(s) + stage.side(s) * float(home[1])
		center.y = stage.ground(center) + 18.0
		for i in range(5):
			var bird = Node3D.new()
			bird.name = "Chough"
			Props.faceted(bird, Vector3.ZERO, Vector3(0.13, 0.11, 0.36), Color("18181b"), 5, 2)
			Props.box(bird, Vector3(0, 0, -0.21), Vector3(0.04, 0.03, 0.08), Color("e8c43a"))
			var wings: Array = []
			for side in [-1.0, 1.0]:
				var hinge = Node3D.new()
				bird.add_child(hinge)
				Props.box(hinge, Vector3(side * 0.3, 0, 0), Vector3(0.54, 0.02, 0.17), Color("222226"))
				hinge.set_meta("side", side)
				wings.append(hinge)
			root.add_child(bird)
			birds.append({"node": bird, "wings": wings, "center": center, "radius": rng.randf_range(10.0, 26.0), "phase": rng.randf() * TAU, "speed": rng.randf_range(0.18, 0.3) * (1.0 if i % 2 == 0 else -1.0), "height": rng.randf_range(-4.0, 5.0)})

func update(delta: float, focus: Vector3) -> void:
	clock += delta
	if snowfall != null:
		snowfall.position = focus + Vector3.UP * 12.0
	var gust = 0.7 + 0.3 * sin(clock * 0.37) + 0.15 * sin(clock * 1.3)
	for flag in flags:
		var node: Node3D = flag.node
		if node.position.distance_squared_to(focus) > LIFE_RANGE * LIFE_RANGE:
			continue
		var strips: Array = flag.strips
		for i in range(strips.size()):
			var hinge: Node3D = strips[i]
			hinge.rotation.y = sin(clock * 3.4 - i * 0.9 + float(flag.phase)) * (0.12 + 0.05 * i) * gust
			hinge.rotation.z = -0.06 * (1.0 - gust) * (i + 1) * 0.3
	for flare in flares:
		var light: OmniLight3D = flare.light
		light.light_energy = 1.3 + 0.45 * sin(clock * 23.0 + float(flare.phase)) + 0.25 * sin(clock * 37.0)
	for bird in birds:
		var node: Node3D = bird.node
		var angle = clock * float(bird.speed) + float(bird.phase)
		var center: Vector3 = bird.center
		var radius = float(bird.radius)
		node.position = center + Vector3(cos(angle) * radius, float(bird.height) + sin(clock * 0.6 + float(bird.phase)) * 2.0, sin(angle) * radius)
		var heading = Vector3(-sin(angle), 0, cos(angle)) * signf(float(bird.speed))
		node.rotation = Vector3(0, atan2(-heading.x, -heading.z), -0.35 * signf(float(bird.speed)))
		if node.position.distance_squared_to(focus) < LIFE_RANGE * LIFE_RANGE:
			var flap = sin(clock * 9.0 + float(bird.phase)) * 0.55
			for wing in bird.wings:
				wing.rotation.z = flap * float(wing.get_meta("side"))
