extends RefCounted
# Living details of the "Финский лес" stage: wind in crowns, grass and reeds,
# lily pads on the waves, ducks, birds, dragonflies, jumping fish and ants on the
# ant hills. Everything here is local scenery; gameplay state (trees, rocks,
# berries, mushrooms) stays in stage.gd and is identical for every client.
const WIND_SHADER = preload("res://shaders/forest_wind.gdshader")
const Props = preload("res://scripts/props.gd")
const ANT_COUNT = 144
const ANTS_PER_HILL = 12
const ANT_RANGE = 32.0
const LIFE_RANGE = 90.0

var stage
var root: Node3D
var rng = RandomNumberGenerator.new()
var clock = 0.0
var materials: Dictionary = {}
var reed_count = 0
var lily_count = 0
var ducks: Array[Dictionary] = []
var birds: Array[Dictionary] = []
var flies: Array[Dictionary] = []
var anthills: Array[Dictionary] = []
var ants: MultiMesh
var active_ants = 0
var fish: Node3D
var fish_jump: Dictionary = {}
var fish_timer = 3.0
var fish_jumps = 0
var swaying_nodes = 0

func wind_material(sway: float, base_y: float, span_y: float, floating: bool = false) -> ShaderMaterial:
	var key = "%.3f:%.3f:%.3f:%s" % [sway, base_y, span_y, floating]
	if materials.has(key):
		return materials[key]
	var mat = ShaderMaterial.new()
	mat.shader = WIND_SHADER
	mat.set_shader_parameter("sway_amount", sway)
	mat.set_shader_parameter("base_y", base_y)
	mat.set_shader_parameter("span_y", span_y)
	mat.set_shader_parameter("floating", floating)
	materials[key] = mat
	return mat

func build(owner_stage) -> void:
	stage = owner_stage
	rng.seed = 9102026
	root = Node3D.new()
	root.name = "ForestLife"
	stage.add_child(root)
	apply_wind()
	_build_reeds()
	_build_lily_pads()
	_build_ducks()
	_build_birds()
	_build_dragonflies()
	_build_ants()
	_build_fish()

# Crowns bend more towards their tips; trunks stay put. Grass tufts flutter.
func apply_wind() -> void:
	for node in stage.get_children():
		if not node is MultiMeshInstance3D:
			continue
		var name = str(node.name)
		var mat: ShaderMaterial = null
		if name.begins_with("ForestLayer1_"):
			mat = wind_material(0.10, -0.5, 1.0)
		elif name.begins_with("ForestLayer2_"):
			mat = wind_material(0.22, -0.5, 1.0)
		elif name.begins_with("ForestLayer3_"):
			mat = wind_material(0.36, -0.5, 1.0)
		elif name.begins_with("GrassTile"):
			mat = wind_material(0.09, 0.0, 1.0)
		if mat != null:
			node.material_override = mat
			swaying_nodes += 1

func _lake_samples(step: float) -> Array:
	var result: Array = []
	for lake in stage.finnish_forest.LAKES:
		var s: float = lake.s0 + 3.0
		while s < lake.s1 - 3.0:
			result.append({"lake": lake, "s": s})
			s += step
	return result

func _lake_point(lake: Dictionary, s: float, u: float) -> Vector3:
	var p = Vector3(stage.at(s).x + u * float(lake.side), 0.0, -s)
	p.y = stage.ground(p)
	return p

func _shore_u(lake: Dictionary, s: float) -> float:
	return stage.finnish_forest.shore_distance(lake, s)

func _clear_of_people(p: Vector3, padding: float) -> bool:
	if stage.road_distance(p) < 6.5 + padding:
		return false
	return not stage.finnish_forest.reserved(p, padding)

# Reed beds along the near and far shores, in shallow water and wet sand.
func _build_reeds() -> void:
	var poses: Array = []
	var colors: Array = []
	for sample in _lake_samples(1.6):
		var lake: Dictionary = sample.lake
		var s: float = sample.s
		if sin(s * 0.09 + float(lake.seed)) < -0.35:
			continue # gaps between reed beds
		for shore in [_shore_u(lake, s), _shore_u(lake, s) + float(lake.width)]:
			var direction = 1.0 if shore == _shore_u(lake, s) else -1.0
			var u = shore + direction * rng.randf_range(-1.2, 2.6)
			var p = _lake_point(lake, s, u)
			var depth = stage.water.depth(p)
			if depth < -0.12 or depth > 0.65 or not _clear_of_people(p, 0.5):
				continue
			for stalk in range(5):
				var q = p + Vector3(rng.randf_range(-0.45, 0.45), 0.0, rng.randf_range(-0.45, 0.45))
				var height = rng.randf_range(1.1, 1.9)
				var base = minf(stage.ground(q), float(lake.level)) - 0.25
				poses.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(0.025, height, 0.025)), Vector3(q.x, base + height * 0.5, q.z)))
				colors.append(Color("6f7d3b").lerp(Color("a39a55"), rng.randf()))
	var mesh = CylinderMesh.new()
	mesh.height = 1.0
	mesh.bottom_radius = 1.0
	mesh.top_radius = 0.15
	mesh.radial_segments = 3
	mesh.rings = 1
	reed_count = poses.size()
	_batch("LakeReeds", mesh, poses, colors, wind_material(0.14, -0.5, 1.0), 140.0)

# Floating lily pads with a few white flowers; they bob on the wave surface.
func _build_lily_pads() -> void:
	var pads: Array = []
	var pad_colors: Array = []
	var flowers: Array = []
	var flower_colors: Array = []
	for sample in _lake_samples(3.0):
		var lake: Dictionary = sample.lake
		var s: float = sample.s
		if sin(s * 0.05 + float(lake.seed) * 2.0) < 0.15:
			continue
		var center = _lake_point(lake, s, _shore_u(lake, s) + rng.randf_range(4.0, 12.0))
		for i in range(6):
			var p = center + Vector3(rng.randf_range(-2.2, 2.2), 0.0, rng.randf_range(-2.2, 2.2))
			var depth = stage.water.depth(p)
			if depth < 0.5 or depth > 2.8:
				continue
			var size = rng.randf_range(0.22, 0.42)
			var y = float(lake.level) - 0.19
			pads.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size, 0.02, size)), Vector3(p.x, y, p.z)))
			pad_colors.append(Color("3f6a34").lerp(Color("5f8540"), rng.randf()))
			if rng.randf() < 0.18:
				flowers.append(Transform3D(Basis.from_scale(Vector3(0.11, 0.07, 0.11)), Vector3(p.x + size * 0.3, y + 0.05, p.z)))
				flower_colors.append(Color("f4f1e6"))
	var pad = CylinderMesh.new()
	pad.height = 1.0
	pad.top_radius = 1.0
	pad.bottom_radius = 1.0
	pad.radial_segments = 8
	pad.rings = 1
	lily_count = pads.size()
	_batch("LakeLilyPads", pad, pads, pad_colors, wind_material(0.0, 0.0, 1.0, true), 120.0)
	var bloom = SphereMesh.new()
	bloom.radius = 0.5
	bloom.height = 1.0
	bloom.radial_segments = 6
	bloom.rings = 2
	_batch("LakeLilyFlowers", bloom, flowers, flower_colors, wind_material(0.0, 0.0, 1.0, true), 120.0)

func _batch(name: String, mesh: Mesh, poses: Array, colors: Array, mat: Material, range_end: float) -> void:
	if poses.is_empty():
		return
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = poses.size()
	for i in range(poses.size()):
		mm.set_instance_transform(i, poses[i])
		mm.set_instance_color(i, colors[i])
	var node = MultiMeshInstance3D.new()
	node.name = name
	node.multimesh = mm
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = range_end
	node.visibility_range_end_margin = 15
	root.add_child(node)

# ---------------------------------------------------------------- animals

func _build_ducks() -> void:
	var homes = [[0, 360.0, 30.0], [0, 410.0, 22.0], [1, 590.0, 30.0], [2, 618.0, 26.0], [3, 745.0, 32.0], [3, 795.0, 24.0]]
	for home in homes:
		var lake: Dictionary = stage.finnish_forest.LAKES[home[0]]
		var center = _lake_point(lake, home[1], _shore_u(lake, home[1]) + home[2])
		if stage.water.depth(center) < 0.8:
			continue
		for i in range(3 if ducks.size() % 2 == 0 else 2):
			var duck = _duck_model(i == 0)
			root.add_child(duck)
			var p = center + Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))
			duck.position = Vector3(p.x, float(lake.level) - 0.2, p.z)
			ducks.append({"node": duck, "home": center, "level": float(lake.level), "target": center, "heading": rng.randf() * TAU, "speed": 0.0, "wait": rng.randf_range(0.0, 4.0), "ripple": rng.randf()})

func _duck_model(drake: bool) -> Node3D:
	var duck = Node3D.new()
	duck.name = "Duck"
	Props.faceted(duck, Vector3(0, 0.08, 0), Vector3(0.26, 0.16, 0.42), Color("6b5a44") if not drake else Color("8c8270"), 7, 3)
	Props.faceted(duck, Vector3(0, 0.25, -0.18), Vector3(0.13, 0.13, 0.14), Color("2f6b45") if drake else Color("6f5d47"), 6, 3)
	Props.box(duck, Vector3(0, 0.23, -0.28), Vector3(0.05, 0.03, 0.09), Color("d99a2b"))
	Props.faceted(duck, Vector3(0, 0.14, 0.2), Vector3(0.12, 0.08, 0.1), Color("4c4237"), 5, 2)
	return duck

func _build_birds() -> void:
	for flock in range(3):
		var s = 120.0 + flock * 260.0
		var center = stage.at(s) + stage.side(s) * (40.0 if flock % 2 == 0 else -45.0)
		center.y = stage.ground(center) + 24.0 + flock * 5.0
		for i in range(5):
			var bird = Node3D.new()
			bird.name = "Bird"
			Props.faceted(bird, Vector3.ZERO, Vector3(0.12, 0.1, 0.34), Color("2f2f33"), 5, 2)
			var wings: Array = []
			for side in [-1.0, 1.0]:
				var hinge = Node3D.new()
				bird.add_child(hinge)
				Props.box(hinge, Vector3(side * 0.28, 0, 0), Vector3(0.5, 0.02, 0.16), Color("3a3a40"))
				hinge.set_meta("side", side)
				wings.append(hinge)
			root.add_child(bird)
			birds.append({"node": bird, "wings": wings, "center": center, "radius": rng.randf_range(16.0, 34.0), "phase": rng.randf() * TAU, "speed": rng.randf_range(0.16, 0.24) * (1.0 if flock % 2 == 0 else -1.0), "height": rng.randf_range(-3.0, 3.0)})

func _build_dragonflies() -> void:
	for i in range(14):
		var lake: Dictionary = stage.finnish_forest.LAKES[i % stage.finnish_forest.LAKES.size()]
		var s = lerpf(float(lake.s0) + 10.0, float(lake.s1) - 10.0, rng.randf())
		var home = _lake_point(lake, s, _shore_u(lake, s) + rng.randf_range(0.5, 4.0))
		home.y = float(lake.level)
		var fly = Node3D.new()
		fly.name = "Dragonfly"
		Props.box(fly, Vector3.ZERO, Vector3(0.025, 0.025, 0.2), Color("2c6fa3"))
		for z in [-0.03, 0.03]:
			Props.box(fly, Vector3(0, 0.01, z), Vector3(0.26, 0.004, 0.035), Color("cfe3ea"))
		root.add_child(fly)
		fly.position = home + Vector3(0, 0.8, 0)
		flies.append({"node": fly, "home": home, "target": fly.position, "wait": 0.0})

func _build_ants() -> void:
	var hills = stage.get_node_or_null("AntHills")
	if hills is MultiMeshInstance3D:
		var mm: MultiMesh = hills.multimesh
		for i in range(mm.instance_count):
			var pose: Transform3D = mm.get_instance_transform(i)
			var radius = pose.basis.x.length()
			var height = pose.basis.y.length()
			var base = hills.position + pose.origin - Vector3(0, height * 0.5, 0)
			anthills.append({"base": base, "radius": radius, "height": height, "seed": float(i) * 1.37})
	var body = BoxMesh.new()
	body.size = Vector3(0.025, 0.018, 0.06)
	ants = MultiMesh.new()
	ants.transform_format = MultiMesh.TRANSFORM_3D
	ants.mesh = body
	ants.instance_count = ANT_COUNT
	ants.visible_instance_count = 0
	var node = MultiMeshInstance3D.new()
	node.name = "AntColonies"
	node.multimesh = ants
	node.material_override = Props.material(Color("1d1611"))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(node)

func _build_fish() -> void:
	fish = Node3D.new()
	fish.name = "JumpingFish"
	Props.faceted(fish, Vector3.ZERO, Vector3(0.09, 0.12, 0.42), Color("8c9aa1"), 6, 3)
	Props.box(fish, Vector3(0, 0, 0.24), Vector3(0.02, 0.14, 0.1), Color("6f7d84"))
	fish.visible = false
	root.add_child(fish)

# ---------------------------------------------------------------- update

func update(delta: float, focus: Vector3) -> void:
	var dt = clampf(delta, 0.0, 0.1)
	clock += dt
	_update_ducks(dt, focus)
	_update_birds()
	_update_flies(dt, focus)
	_update_ants(focus)
	_update_fish(dt, focus)

func _update_ducks(dt: float, focus: Vector3) -> void:
	for duck in ducks:
		var node: Node3D = duck.node
		var offset = node.position - focus
		offset.y = 0.0
		var afraid = offset.length() < 9.0
		duck.wait = float(duck.wait) - dt
		if afraid:
			var away = node.position + offset.normalized() * 6.0
			if stage.water.depth(away) > 0.6:
				duck.target = away
		elif duck.wait <= 0.0 or node.position.distance_to(duck.target) < 0.6:
			duck.wait = rng.randf_range(3.0, 9.0)
			var candidate: Vector3 = duck.home + Vector3(rng.randf_range(-12, 12), 0, rng.randf_range(-12, 12))
			if stage.water.depth(candidate) > 0.8:
				duck.target = candidate
		var to_target: Vector3 = duck.target - node.position
		to_target.y = 0.0
		var desired = (2.2 if afraid else 0.55) if to_target.length() > 0.5 else 0.0
		duck.speed = move_toward(float(duck.speed), desired, dt * 1.5)
		if to_target.length() > 0.05:
			duck.heading = lerp_angle(float(duck.heading), atan2(-to_target.x, -to_target.z), 1.0 - exp(-dt * 2.5))
		var forward = Vector3(-sin(duck.heading), 0, -cos(duck.heading))
		var next = node.position + forward * float(duck.speed) * dt
		if stage.water.depth(next) > 0.45:
			node.position = next
		var t = stage.water.now()
		node.position.y = float(duck.level) - 0.2 + stage.water.wave(node.position.x, node.position.z, t)
		node.rotation.y = float(duck.heading)
		duck.ripple = float(duck.ripple) + dt * float(duck.speed)
		if duck.ripple > 0.9 and node.position.distance_to(focus) < LIFE_RANGE:
			duck.ripple = 0.0
			stage.water.ripple(node.position, 0.35)

func _update_birds() -> void:
	for bird in birds:
		var node: Node3D = bird.node
		var angle = float(bird.phase) + clock * float(bird.speed)
		var center: Vector3 = bird.center
		node.position = center + Vector3(cos(angle) * float(bird.radius), float(bird.height) + sin(clock * 0.6 + float(bird.phase)) * 1.5, sin(angle) * float(bird.radius))
		var tangent = Vector3(-sin(angle), 0, cos(angle)) * signf(float(bird.speed))
		node.rotation.y = atan2(-tangent.x, -tangent.z)
		node.rotation.z = -0.25 * signf(float(bird.speed))
		var flap = sin(clock * 9.0 + float(bird.phase) * 3.0)
		for wing in bird.wings:
			wing.rotation.z = float(wing.get_meta("side")) * flap * 0.55

func _update_flies(dt: float, focus: Vector3) -> void:
	for fly in flies:
		var node: Node3D = fly.node
		if node.position.distance_to(focus) > LIFE_RANGE:
			continue
		fly.wait = float(fly.wait) - dt
		if fly.wait <= 0.0:
			fly.wait = rng.randf_range(0.4, 1.6)
			fly.target = fly.home + Vector3(rng.randf_range(-3.0, 3.0), rng.randf_range(0.5, 1.3), rng.randf_range(-3.0, 3.0))
		var step: Vector3 = (fly.target - node.position)
		node.position += step * (1.0 - exp(-dt * 3.5))
		if step.length() > 0.05:
			node.rotation.y = atan2(-step.x, -step.z)

# A dozen ants circle up and down each ant hill near the camera.
func _update_ants(focus: Vector3) -> void:
	var nearby: Array = []
	for hill in anthills:
		var d = Vector2(hill.base.x - focus.x, hill.base.z - focus.z).length()
		if d < ANT_RANGE:
			nearby.append({"hill": hill, "d": d})
	nearby.sort_custom(func(a, b): return a.d < b.d)
	var index = 0
	for entry in nearby:
		var hill: Dictionary = entry.hill
		for i in range(ANTS_PER_HILL):
			if index >= ANT_COUNT:
				break
			var lap = clock * (0.35 + 0.05 * (i % 3)) + float(hill.seed) + i * 0.71
			var climb = 0.5 + 0.45 * sin(clock * 0.8 + i * 1.9 + float(hill.seed))
			var direction = 1.0 if i % 2 == 0 else -1.0
			var angle = lap * direction * TAU * 0.25 + i
			var radius = float(hill.radius) * (1.0 - climb * 0.88)
			var position: Vector3 = hill.base + Vector3(cos(angle) * radius, float(hill.height) * climb + 0.012, sin(angle) * radius)
			var tangent = Vector3(-sin(angle), 0, cos(angle)) * direction
			ants.set_instance_transform(index, Transform3D(Basis(Vector3.UP, atan2(-tangent.x, -tangent.z)), position))
			index += 1
	active_ants = index
	ants.visible_instance_count = index

func _update_fish(dt: float, focus: Vector3) -> void:
	if not fish_jump.is_empty():
		fish_jump.age = float(fish_jump.age) + dt
		var t = float(fish_jump.age) / 0.75
		var start: Vector3 = fish_jump.start
		var forward: Vector3 = fish_jump.forward
		fish.position = start + forward * t * 1.4 + Vector3(0, 4.0 * t * (1.0 - t) * 0.9, 0)
		fish.rotation = Vector3(lerpf(0.9, -0.9, t), atan2(-forward.x, -forward.z), 0)
		if t >= 1.0:
			fish.visible = false
			stage.water.splash(fish.position, 0.45)
			fish_jump = {}
		return
	fish_timer -= dt
	if fish_timer > 0.0:
		return
	fish_timer = rng.randf_range(4.0, 10.0)
	for attempt in range(8):
		var p = focus + Vector3(rng.randf_range(-45, 45), 0, rng.randf_range(-45, 45))
		if stage.water.depth(p) > 1.4:
			var level = stage.water.level(p) - 0.2
			fish_jump = {"start": Vector3(p.x, level, p.z), "forward": Vector3(cos(attempt), 0, sin(attempt)), "age": 0.0}
			fish.visible = true
			fish_jumps += 1
			stage.water.splash(Vector3(p.x, level, p.z), 0.35)
			return
