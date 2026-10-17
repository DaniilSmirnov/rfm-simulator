extends RefCounted
# Living details of «Чарынский каньон» (canyon.gd): herds of bactrian camels
# grazing the feather grass above the gorge that amble away from people,
# steppe eagles turning on the updraught over the walls, smoke drifting from
# the yurt camp and the dust the player kicks up. Local scenery only:
# gameplay state stays in stage.gd and is the same for every client.
const Props = preload("res://scripts/core/props.gd")
const CamelModel = preload("res://scripts/stages/canyon/camel_model.gd")
const Form = preload("res://scripts/stages/canyon/canyon_form.gd")
const LIFE_RANGE = 140.0
const SHY_DISTANCE = 17.0
# Station, side and distance of each camel herd, all of them out on the
# steppe table where the grazing is, never down in the gorge.
const HERDS = [[36.0, -1.0, 56.0], [112.0, -1.0, 46.0], [168.0, -1.0, 62.0], [214.0, -1.0, 44.0]]
# World z of the thermals the eagles turn in, over the gorge.
const THERMALS = [-180.0, -330.0, -470.0, -620.0]

var stage
var biome
var root: Node3D
var rng = RandomNumberGenerator.new()
var clock = 0.0
var camels: Array[Dictionary] = []
var eagles: Array[Dictionary] = []
var dust: CPUParticles3D
var dust_focus := Vector3.ZERO
var dust_seen := false

func build(owner_stage, owner_biome) -> void:
	stage = owner_stage
	biome = owner_biome
	rng.seed = 16102026
	root = Node3D.new()
	root.name = "CanyonLife"
	stage.add_child(root)
	_build_camels()
	_build_eagles()
	_build_smoke()
	_build_dust()

func _build_camels() -> void:
	for herd in HERDS:
		var s: float = herd[0]
		var home = stage.at(s) + stage.side(s) * float(herd[1]) * float(herd[2])
		# Graze on open steppe, away from the road, the camps and the rocks.
		for step in range(4):
			if biome.scenery.open_ground(home, 20.0, 9.0) and biome.scenery.on_steppe(home):
				break
			home += stage.side(s) * float(herd[1]) * 13.0
		home.y = stage.ground(home)
		for i in range(rng.randi_range(3, 5)):
			var camel = CamelModel.build(i == 0)
			root.add_child(camel)
			var p = home + Vector3(rng.randf_range(-9, 9), 0, rng.randf_range(-9, 9))
			if not biome.scenery.on_steppe(p):
				p = home
			p.y = stage.ground(p)
			camel.position = p
			var heading = rng.randf() * TAU
			camel.rotation.y = heading
			camels.append({"node": camel, "home": home, "target": p, "heading": heading, "wait": rng.randf_range(0.0, 8.0), "phase": 0.0, "speed": 0.0, "shy": false})

func _build_eagles() -> void:
	for z in THERMALS:
		var center = Vector3(Form.axis_x(z), 0.0, z)
		center.y = Form.rim_level(center) + rng.randf_range(6.0, 26.0)
		for i in range(2):
			var bird = Node3D.new()
			bird.name = "SteppeEagle"
			Props.faceted(bird, Vector3.ZERO, Vector3(0.22, 0.2, 0.78), Color("5a4634"), 6, 3)
			Props.faceted(bird, Vector3(0, 0.03, -0.45), Vector3(0.16, 0.14, 0.22), Color("8a7352"), 5, 3)
			Props.box(bird, Vector3(0, 0, 0.5), Vector3(0.3, 0.03, 0.34), Color("4a3a2b"))
			for side in [-1.0, 1.0]:
				var wing = Props.box(bird, Vector3(side * 0.62, 0.04, 0.02), Vector3(1.15, 0.04, 0.42), Color("53402f"))
				wing.rotation.z = side * 0.14
			root.add_child(bird)
			eagles.append({"node": bird, "center": center, "radius": rng.randf_range(16.0, 34.0), "phase": rng.randf() * TAU, "speed": rng.randf_range(0.12, 0.2) * (1.0 if i == 0 else -1.0), "rise": rng.randf_range(-3.0, 3.0)})

# A thin column of smoke over the fire of the steppe yurt camp.
func _build_smoke() -> void:
	var camp = stage.get_node_or_null("SteppeYurtCamp")
	if camp == null:
		return
	var smoke = CPUParticles3D.new()
	smoke.name = "YurtSmoke"
	var quad = QuadMesh.new()
	quad.size = Vector2(0.9, 0.9)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.76, 0.72, 0.3)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = mat
	smoke.mesh = quad
	smoke.amount = 16
	smoke.lifetime = 4.5
	smoke.local_coords = false
	smoke.direction = Vector3(0.3, 1.0, 0.1)
	smoke.spread = 9.0
	smoke.gravity = Vector3(0.35, 0.3, 0.1)
	smoke.initial_velocity_min = 0.5
	smoke.initial_velocity_max = 1.1
	smoke.scale_amount_min = 1.0
	smoke.scale_amount_max = 2.6
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(smoke)
	smoke.position = camp.position + Vector3(0, 1.3, 0)

func update(delta: float, focus: Vector3) -> void:
	var dt = clampf(delta, 0.0, 0.1)
	clock += dt
	for camel in camels:
		_update_camel(camel, dt, focus)
	_update_eagles()
	_update_dust(delta, focus)

# Camels are not skittish: they lift their heads, turn and walk off.
func _update_camel(camel: Dictionary, dt: float, focus: Vector3) -> void:
	var node: Node3D = camel.node
	var offset = node.position - focus
	offset.y = 0.0
	if offset.length() > LIFE_RANGE:
		return
	camel.shy = offset.length() < SHY_DISTANCE
	camel.wait = float(camel.wait) - dt
	if camel.shy:
		camel.target = node.position + offset.normalized() * 14.0
	elif camel.wait <= 0.0 or node.position.distance_to(camel.target) < 1.0:
		camel.wait = rng.randf_range(6.0, 16.0)
		camel.target = camel.home + Vector3(rng.randf_range(-17, 17), 0, rng.randf_range(-17, 17))
	var to_target: Vector3 = camel.target - node.position
	to_target.y = 0.0
	var desired = (3.4 if camel.shy else 1.0) if to_target.length() > 1.0 else 0.0
	camel.speed = move_toward(float(camel.speed), desired, dt * 2.5)
	if to_target.length() > 0.05:
		camel.heading = lerp_angle(float(camel.heading), atan2(to_target.x, to_target.z), 1.0 - exp(-dt * 2.2))
	var walking = float(camel.speed) > 0.08
	if walking:
		node.position += Vector3(sin(camel.heading), 0, cos(camel.heading)) * float(camel.speed) * dt
		camel.phase = float(camel.phase) + dt * (0.8 + float(camel.speed) * 0.5)
	node.position.y = stage.ground(node.position)
	var pose = "Stand"
	if walking:
		pose = "StepA" if int(camel.phase) % 2 == 0 else "StepB"
	elif float(camel.wait) > 3.0:
		pose = "Graze"
	CamelModel.pose(node, pose)
	# Models face -z: turn them to the heading.
	node.rotation = Vector3(0, float(camel.heading) + PI, 0)

func _update_eagles() -> void:
	for bird in eagles:
		var node: Node3D = bird.node
		var angle = float(bird.phase) + clock * float(bird.speed)
		var center: Vector3 = bird.center
		node.position = center + Vector3(cos(angle) * float(bird.radius), float(bird.rise) + sin(clock * 0.3 + float(bird.phase)) * 2.4, sin(angle) * float(bird.radius))
		var tangent = Vector3(-sin(angle), 0, cos(angle)) * signf(float(bird.speed))
		node.rotation.y = atan2(-tangent.x, -tangent.z)
		node.rotation.z = -0.22 * signf(float(bird.speed))

func _update_dust(delta: float, focus: Vector3) -> void:
	if dust == null:
		return
	var speed := 0.0
	if dust_seen and delta > 0.0:
		speed = focus.distance_to(dust_focus) / delta
	dust_focus = focus
	dust_seen = true
	dust.position = focus + Vector3.UP * 0.35
	dust.emitting = speed > 6.0

func _build_dust() -> void:
	dust = CPUParticles3D.new()
	dust.name = "CanyonDust"
	var quad = QuadMesh.new()
	quad.size = Vector2(0.55, 0.55)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.74, 0.58, 0.4, 0.45)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	quad.material = mat
	dust.mesh = quad
	dust.amount = 36
	dust.lifetime = 1.3
	dust.explosiveness = 0.15
	dust.local_coords = false
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	dust.emission_sphere_radius = 1.1
	dust.direction = Vector3(0.2, 0.6, 0)
	dust.spread = 40.0
	dust.gravity = Vector3(0.4, 0.15, 0)
	dust.initial_velocity_min = 0.4
	dust.initial_velocity_max = 1.4
	dust.scale_amount_min = 0.8
	dust.scale_amount_max = 1.8
	dust.emitting = false
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(dust)
