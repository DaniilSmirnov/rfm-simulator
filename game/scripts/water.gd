extends RefCounted
# Lakes of the "Финский лес" stage: one analytic water surface shared by the
# lake shader, buoyancy, drag, swimming, splashes and floating scenery.
# The physical level of a lake is exact and deterministic; the small waves are a
# visual and local effect (the same formula as res://shaders/lake_waves.gdshaderinc).
const WAVE_AMPLITUDE = 0.045
const LAKE_SHADER = preload("res://shaders/lake_water.gdshader")
const GRID = 2.0
# A standing walker's feet stay this far below the surface while swimming.
const SWIM_DEPTH = 1.2
# Water this deep makes walking slow (wading) before swimming starts.
const WADE_DEPTH = 0.25
const DROPLETS = 72
const RIPPLES = 24
# Cars: buoyant body volume, cabin flooding time and water resistance.
const CAR_BODY_HEIGHT = 1.3
const BUOYANCY = 30.0
const FLOOD_SECONDS = 20.0

var stage
var surfaces: Array[MeshInstance3D] = []
var minimap_cells: PackedVector2Array = PackedVector2Array()
var droplets: Array[Dictionary] = []
var ripples: Array[Dictionary] = []
var droplet_mesh: MultiMesh
var ripple_mesh: MultiMesh
var floaters: Array[Dictionary] = []
var wake_budget: Dictionary = {}
var splash_count = 0
var rng = RandomNumberGenerator.new()
var clock_override = -1.0

static func wave(x: float, z: float, t: float) -> float:
	return WAVE_AMPLITUDE * (sin(x * 0.42 + z * 0.17 + t * 1.3) + 0.6 * sin(x * 0.19 - z * 0.37 + t * 0.9)) / 1.6

static func wave_gradient(x: float, z: float, t: float) -> Vector2:
	var a = cos(x * 0.42 + z * 0.17 + t * 1.3)
	var b = cos(x * 0.19 - z * 0.37 + t * 0.9)
	return WAVE_AMPLITUDE / 1.6 * Vector2(a * 0.42 + 0.6 * b * 0.19, a * 0.17 - 0.6 * b * 0.37)

# Shader TIME rolls over every hour by default; follow the same clock.
func now() -> float:
	if clock_override >= 0.0:
		return clock_override
	return fmod(Time.get_ticks_msec() / 1000.0, 3600.0)

# ---------------------------------------------------------------- queries

func level(pos: Vector3) -> float:
	return stage.finnish_forest.nearest_water_level(stage, pos)

# Metres of water above the lake bed; <= 0 on dry land.
func depth(pos: Vector3) -> float:
	var l = level(pos)
	return l - stage.ground(pos) if l > -999.0 else -1000.0

func surface(pos: Vector3) -> float:
	var l = level(pos)
	return l + wave(pos.x, pos.z, now()) if l > -999.0 else -1000.0

func is_water(pos: Vector3, minimum: float = 0.0) -> bool:
	return depth(pos) > minimum

func swimming(pos: Vector3) -> bool:
	return depth(pos) > SWIM_DEPTH

# Wading slows walking smoothly; swimming is half speed.
func walk_factor(pos: Vector3) -> float:
	var d = depth(pos)
	if d <= 0.0:
		return 1.0
	if d > SWIM_DEPTH:
		return 0.5
	return lerpf(1.0, 0.55, smoothstep(0.0, SWIM_DEPTH, d))

# Walking floor including floating: the body rides the waves in deep water.
func walk_floor(pos: Vector3, ground_height: float) -> float:
	var l = level(pos)
	if l <= -999.0 or l - ground_height <= SWIM_DEPTH:
		return ground_height
	return l + wave(pos.x, pos.z, now()) - SWIM_DEPTH

# ---------------------------------------------------------------- vehicles

# Called by vehicle_motion.suspension for every car (player, crews, prediction).
# Returns the upward acceleration of buoyancy and applies water resistance.
func vehicle(motion, node: Node3D, delta: float) -> float:
	var l = level(node.position)
	if l <= -999.0:
		motion.flood = maxf(0.0, motion.flood - delta / 4.0)
		motion.submerged = 0.0
		return 0.0
	var submersion = clampf((l - node.position.y) / CAR_BODY_HEIGHT, 0.0, 1.0)
	motion.submerged = submersion
	if submersion <= 0.0:
		motion.flood = maxf(0.0, motion.flood - delta / 4.0)
		return 0.0
	# Water resistance grows with immersion and speed (quadratic drag).
	var speed = motion.velocity.length()
	var resistance = (0.35 + 2.6 * submersion) * (0.25 + speed * 0.07)
	motion.velocity *= exp(-resistance * delta)
	if submersion > 0.45:
		# Water seeps in faster the deeper the body sits.
		motion.flood = minf(1.0, motion.flood + delta * submersion * 1.5 / FLOOD_SECONDS)
	else:
		motion.flood = maxf(0.0, motion.flood - delta / 4.0)
	wake(node.get_instance_id(), node.position, motion.velocity, submersion * CAR_BODY_HEIGHT, delta, 1.0)
	return BUOYANCY * submersion * (1.0 - motion.flood)

# ---------------------------------------------------------------- effects

# Spray proportional to speed and immersion; `key` keeps each mover's budget.
func wake(key: int, pos: Vector3, velocity: Vector3, water_depth: float, delta: float, size: float) -> void:
	if surfaces.is_empty() or water_depth <= 0.02:
		return
	var horizontal = Vector2(velocity.x, velocity.z).length()
	if horizontal < 0.6:
		return
	if wake_budget.size() > 64:
		wake_budget.clear()
	var budget = float(wake_budget.get(key, 0.0)) + delta * horizontal * (0.8 + water_depth * 2.0) * size
	while budget >= 1.0:
		budget -= 1.0
		var at = pos
		at.y = level(pos)
		splash(at + Vector3(rng.randf_range(-0.9, 0.9), 0, rng.randf_range(-0.9, 0.9)) * size, clampf(horizontal / 10.0, 0.25, 1.4) * size, velocity * 0.25)
	wake_budget[key] = budget

func splash(pos: Vector3, strength: float = 1.0, carry: Vector3 = Vector3.ZERO) -> void:
	splash_count += 1
	var count = clampi(int(4 + strength * 7), 3, 14)
	for i in range(count):
		var angle = rng.randf() * TAU
		var spread = rng.randf_range(0.6, 2.4) * strength
		var velocity = Vector3(cos(angle) * spread, rng.randf_range(2.0, 4.6) * strength, sin(angle) * spread) + carry
		if droplets.size() >= DROPLETS:
			droplets.pop_front()
		droplets.append({"pos": pos + Vector3(0, 0.05, 0), "velocity": velocity, "level": pos.y, "size": rng.randf_range(0.05, 0.11) * (0.7 + strength * 0.4)})
	ripple(pos, 0.6 + strength * 1.4)

func ripple(pos: Vector3, size: float = 1.0) -> void:
	if ripples.size() >= RIPPLES:
		ripples.pop_front()
	ripples.append({"pos": Vector3(pos.x, level(pos), pos.z), "age": 0.0, "life": 1.6 + size * 0.5, "size": size})

# Floating scenery (boats, lily pads, logs): heave, pitch and roll follow the
# local wave slope with a little damping so they bob rather than snap.
func add_floater(node: Node3D, offset: float, length: float = 1.0) -> void:
	floaters.append({"node": node, "offset": offset, "length": length, "heave": 0.0, "velocity": 0.0})
	node.position.y = level(node.position) + wave(node.position.x, node.position.z, now()) + offset

func _float(f: Dictionary, delta: float) -> void:
	var node: Node3D = f.node
	if not is_instance_valid(node):
		return
	var t = now()
	var target = level(node.position) + wave(node.position.x, node.position.z, t) + float(f.offset)
	# Critically damped spring towards the wave height (buoyancy + water drag).
	var stiffness = 26.0
	var damping = 2.0 * sqrt(stiffness)
	var displacement = node.position.y - target
	f.velocity = float(f.velocity) + (-stiffness * displacement - damping * float(f.velocity)) * delta
	node.position.y += float(f.velocity) * delta
	var gradient = wave_gradient(node.position.x, node.position.z, t) * float(f.length) * 4.0
	node.rotation.x = lerpf(node.rotation.x, -gradient.y, 1.0 - exp(-delta * 4.0))
	node.rotation.z = lerpf(node.rotation.z, gradient.x, 1.0 - exp(-delta * 4.0))

func update(delta: float) -> void:
	var dt = clampf(delta, 0.0, 0.1)
	for f in floaters:
		_float(f, dt)
	for drop in droplets.duplicate():
		drop.velocity.y -= 9.8 * dt
		drop.pos += drop.velocity * dt
		if drop.pos.y < drop.level and drop.velocity.y < 0.0:
			droplets.erase(drop)
	for ring in ripples.duplicate():
		ring.age += dt
		if ring.age >= ring.life:
			ripples.erase(ring)
	_render()

func _render() -> void:
	if droplet_mesh == null:
		return
	droplet_mesh.visible_instance_count = droplets.size()
	for i in range(droplets.size()):
		var drop: Dictionary = droplets[i]
		droplet_mesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * float(drop.size)), drop.pos))
	ripple_mesh.visible_instance_count = ripples.size()
	for i in range(ripples.size()):
		var ring: Dictionary = ripples[i]
		var t = ring.age / ring.life
		var radius = lerpf(0.25, 1.6, sqrt(t)) * float(ring.size)
		ripple_mesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(radius, 0.05, radius)), ring.pos + Vector3(0, 0.03, 0)))
		ripple_mesh.set_instance_color(i, Color(0.92, 0.97, 1.0, 0.55 * (1.0 - t)))

# ---------------------------------------------------------------- build

func build(owner_stage) -> void:
	stage = owner_stage
	rng.seed = 5402026
	for body in stage.finnish_forest.BODIES:
		_build_surface(body)
	_build_effects()

func world_point(s: float, lat: float) -> Vector3:
	return Vector3(stage.at(s).x + lat, 0.0, -s)

func _build_surface(body: Dictionary) -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var visible_level: float = body.level - 0.2 # rendered terrain sits 0.25 m below ground()
	var rows = int((body.s1 - body.s0) / GRID)
	var columns = int((body.lat1 - body.lat0) / GRID)
	var depths: Dictionary = {}
	for row in range(rows + 1):
		for column in range(columns + 1):
			var p = world_point(body.s0 + row * GRID, body.lat0 + column * GRID)
			depths[Vector2i(row, column)] = body.level - stage.ground(p)
	var quads = 0
	for row in range(rows):
		for column in range(columns):
			var corners = [Vector2i(row, column), Vector2i(row + 1, column), Vector2i(row, column + 1), Vector2i(row + 1, column + 1)]
			var deepest = -INF
			for c in corners:
				deepest = maxf(deepest, depths[c])
			if deepest < -0.35:
				continue
			quads += 1
			var points: Array[Vector3] = []
			var colors: Array[Color] = []
			for c in corners:
				var p = world_point(body.s0 + c.x * GRID, body.lat0 + c.y * GRID)
				p.y = visible_level
				points.append(p)
				colors.append(_tint(depths[c]))
			for i in [0, 2, 1, 1, 2, 3]:
				st.set_normal(Vector3.UP)
				st.set_color(colors[i])
				st.add_vertex(points[i])
			if (row + column) % 3 == 0 and deepest > 0.3:
				var center = (points[0] + points[3]) * 0.5
				minimap_cells.append(Vector2(center.x, center.z))
	if quads == 0:
		return
	var node = MeshInstance3D.new()
	node.name = "LakeSurface_%s" % body.name
	node.mesh = st.commit()
	var mat = ShaderMaterial.new()
	mat.shader = LAKE_SHADER
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.set_meta("level", body.level)
	stage.add_child(node)
	surfaces.append(node)

func _tint(water_depth: float) -> Color:
	var t = smoothstep(0.0, 3.0, water_depth)
	var color = Color("6d8a74").lerp(Color("1f3a45"), t)
	color.a = lerpf(0.12, 0.9, smoothstep(-0.1, 2.2, water_depth))
	return color

func _build_effects() -> void:
	var drop_material = StandardMaterial3D.new()
	drop_material.albedo_color = Color(0.86, 0.93, 0.97, 0.8)
	drop_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop_material.roughness = 0.1
	var sphere = SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 6
	sphere.rings = 3
	droplet_mesh = MultiMesh.new()
	droplet_mesh.transform_format = MultiMesh.TRANSFORM_3D
	droplet_mesh.mesh = sphere
	droplet_mesh.instance_count = DROPLETS
	droplet_mesh.visible_instance_count = 0
	var drops = MultiMeshInstance3D.new()
	drops.name = "LakeSplashDroplets"
	drops.multimesh = droplet_mesh
	drops.material_override = drop_material
	drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(drops)
	var ring_material = StandardMaterial3D.new()
	ring_material.vertex_color_use_as_albedo = true
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var ring = TorusMesh.new()
	ring.inner_radius = 0.9
	ring.outer_radius = 1.0
	ring.rings = 18
	ring.ring_segments = 3
	ripple_mesh = MultiMesh.new()
	ripple_mesh.transform_format = MultiMesh.TRANSFORM_3D
	ripple_mesh.use_colors = true
	ripple_mesh.mesh = ring
	ripple_mesh.instance_count = RIPPLES
	ripple_mesh.visible_instance_count = 0
	var rings = MultiMeshInstance3D.new()
	rings.name = "LakeRipples"
	rings.multimesh = ripple_mesh
	rings.material_override = ring_material
	rings.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(rings)
