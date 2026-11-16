extends RefCounted
# Red hand flares at night, the way fans on the Col de Turini greet the Monte
# Carlo crews: one fan of each camp lights one as a crew comes by, holds it up
# and waves it while the car passes and for a few seconds after. The flame is
# a night light of its own (night_lights.gd "flare", within a small budget)
# and trails red-lit smoke. Every client decides it from the fan's replicated
# action and its own sky, so nothing extra goes over the network.
const Props = preload("res://scripts/core/props.gd")
const CharacterRig = preload("res://scripts/people/character_rig.gd")
const NightLights = preload("res://scripts/core/night_lights.gd")
# Seconds a flare keeps burning after the crew has gone.
const LINGER = 4.0
const FLAME = Color("ff3d24")
const SMOKE = Color("c98a86")

# Lights, keeps or puts out the flare of a camp fan (spectators.gd); true
# while it burns, so the fan holds it up.
static func update(person: Dictionary, lit: bool, delta: float) -> bool:
	var left = LINGER if lit else maxf(0.0, float(person.get("flare_left", 0.0)) - delta)
	person.flare_left = left
	var flare: Node3D = person.get("flare")
	if left <= 0.0:
		if flare != null and flare.visible:
			flare.hide()
			flare.get_node("Smoke").emitting = false
		return false
	if flare == null:
		flare = build()
		CharacterRig.hand(person.avatar).add_child(flare)
		person.flare = flare
	if not flare.visible:
		flare.show()
		flare.get_node("Smoke").restart()
	# The flame sputters.
	var t = Time.get_ticks_msec() / 1000.0 + float(person.get("id", 0))
	flare.get_node("Fire").scale = Vector3.ONE * (0.85 + 0.2 * sin(t * 31.0) + 0.1 * sin(t * 13.0))
	return true

# A flare held in the hand: a red tube out of the fist, the burning end above
# it (the hand is raised, so the forearm's -Y points up) and its smoke.
static func build() -> Node3D:
	var root = Node3D.new()
	root.name = "FanFlare"
	root.position = CharacterRig.grip()
	Props.cylinder(root, Vector3(0, -0.10, -0.02), 0.024, 0.024, 0.30, Color("b5281e"), 8)
	Props.cylinder(root, Vector3(0, 0.06, -0.02), 0.026, 0.026, 0.05, Color("2d2a28"), 8)
	var fire = MeshInstance3D.new()
	fire.name = "Fire"
	var ball = SphereMesh.new()
	ball.radius = 0.08
	ball.height = 0.2
	ball.radial_segments = 8
	ball.rings = 4
	fire.mesh = ball
	var glow = StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color("ffd2b8")
	fire.material_override = glow
	fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fire.position = Vector3(0, -0.28, -0.02)
	root.add_child(fire)
	var halo = MeshInstance3D.new()
	var outer = SphereMesh.new()
	outer.radius = 0.19
	outer.height = 0.38
	outer.radial_segments = 8
	outer.rings = 4
	halo.mesh = outer
	var red = StandardMaterial3D.new()
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	red.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	red.albedo_color = Color(FLAME, 0.55)
	halo.material_override = red
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fire.add_child(halo)
	NightLights.mark(fire, "flare")
	root.add_child(_smoke(fire.position))
	root.hide()
	return root

# Red-lit smoke trailing from the flame, in world space as the hand waves.
static func _smoke(at: Vector3) -> GPUParticles3D:
	var smoke = GPUParticles3D.new()
	smoke.name = "Smoke"
	smoke.position = at
	smoke.amount = 26
	smoke.lifetime = 2.6
	smoke.local_coords = false
	smoke.emitting = false
	var process = ParticleProcessMaterial.new()
	process.direction = Vector3(0, 1, 0)
	process.spread = 25
	process.initial_velocity_min = 0.5
	process.initial_velocity_max = 0.9
	process.gravity = Vector3(0.15, 0.45, 0)
	process.scale_min = 0.25
	process.scale_max = 0.7
	var grow = Curve.new()
	grow.add_point(Vector2(0, 0.3))
	grow.add_point(Vector2(1, 1.6))
	var curve = CurveTexture.new()
	curve.curve = grow
	process.scale_curve = curve
	smoke.process_material = process
	var puff = SphereMesh.new()
	puff.radius = 0.2
	puff.height = 0.4
	puff.radial_segments = 6
	puff.rings = 3
	var haze = Props.material(SMOKE)
	haze.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	haze.albedo_color.a = 0.35
	puff.material = haze
	smoke.draw_pass_1 = puff
	return smoke
