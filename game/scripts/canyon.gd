extends "res://scripts/stage_biome.gd"
# «Красный каньон»: a desert stage descending into a canyon, with climbable
# terraced mesas. Deterministic geometry shared by driving, walking, camp
# placement and rendering.
const LEDGE_RISE = 0.65 # Existing jump apex is 0.84 m.
const LEDGE_WIDTH = 0.8
const TIERS = 36
const TOP_RADIUS = 9.0
const OUTER_RADIUS = TOP_RADIUS + TIERS * LEDGE_WIDTH
const SIDES = 32
const Records = preload("res://scripts/stage_records.gd")
const DetailLayer = preload("res://scripts/detail_layer.gd")
var mesas: Array[Dictionary] = []
var dust: CPUParticles3D
var dust_focus := Vector3.ZERO
var dust_seen := false

func route(s: float) -> Vector3:
	var descent = smoothstep(245.0, 415.0, s)
	var ascent = smoothstep(655.0, 815.0, s)
	var canyon = descent * (1.0 - ascent)
	var switchbacks = smoothstep(210.0, 260.0, s) * (1.0 - smoothstep(390.0, 435.0, s))
	var x = sin(s / 100.0) * 28.0 + sin(s / 43.0) * 12.0
	x += sin((s - 245.0) / 24.0) * 34.0 * switchbacks
	var y = 62.0 - canyon * 46.0 + sin(s / 52.0) * 2.5
	y += sin(s / 16.0) * 0.7 + sin(s / 7.0) * 0.18
	return Vector3(x, y, -s)

func configure() -> void:
	for index in range(4):
		var s = [100.0, 225.0, 590.0, 760.0][index]
		var center = stage.at(s) + stage.side(s) * (72.0 if index % 2 == 0 else -72.0)
		center.y = raw_ground(center)
		mesas.append({"center": center, "station": s})
		stage.clearings.append(center + Vector3(0, LEDGE_RISE * TIERS, 0))
	for s in [180.0, 450.0, 650.0]:
		var p = stage.at(s) + stage.side(s) * 15.0
		p.y = smooth_ground(p)
		stage.clearings.append(p)

func relief(s: float, lateral: float) -> float:
	var wash = smoothstep(535.0, 575.0, s) * (1.0 - smoothstep(645.0, 680.0, s))
	var bank = sin(s / 34.0) * 0.055 * lateral
	var crown = -0.035 * lateral * lateral
	var rut = -exp(-pow((absf(lateral) - 0.85) / 0.30, 2.0)) * 0.13
	var waves = sin(s * 0.36 + lateral * 0.4) * (0.07 + wash * 0.18)
	var crest = pow(maxf(0.0, cos((s - 35.0) * TAU / 83.0)), 6.0) * 0.5
	return bank + crown + rut + waves + crest

func raw_ground(pos: Vector3) -> float:
	var s: float = stage.road_s(pos)
	var p: Vector3 = stage.at(s)
	var lateral = (pos - p).dot(stage.side(s))
	var distance: float = stage.road_distance(pos)
	var canyon = smoothstep(240.0, 420.0, s) * (1.0 - smoothstep(655.0, 815.0, s))
	var erosion = sin(s * 0.045) * 3.5 + sin(s * 0.12) * 1.2
	var wall = smoothstep(21.0 + erosion, 58.0 + erosion, distance) * canyon * 48.0
	var dunes = (sin(pos.x * 0.07 + pos.z * 0.025) * 1.8 + sin(pos.z * 0.055) * 0.7) * smoothstep(7.0, 23.0, distance)
	return p.y + wall + dunes + relief(s, lateral) * (1.0 - smoothstep(3.7, 9.0, distance))

# Polygon support matches the authored ring mesh, including its corners.
func radius_at(pos: Vector3, center: Vector3) -> float:
	var offset = Vector2(pos.x - center.x, pos.z - center.z)
	var angle = atan2(offset.y, offset.x)
	var sector = TAU / SIDES
	var relative = fposmod(angle, sector) - sector * 0.5
	return offset.length() * cos(relative) / cos(sector * 0.5)

# Land with the mesas blended in, without their ledges: the rendered terrain.
func smooth_ground(pos: Vector3) -> float:
	var height = raw_ground(pos)
	for mesa in mesas:
		var distance = radius_at(pos, mesa.center)
		height = lerpf(mesa.center.y, height, smoothstep(OUTER_RADIUS, OUTER_RADIUS + 8.0, distance))
	return height

# Physical ground: the mesas are stepped ledges a walker must jump up.
func base_ground(pos: Vector3) -> float:
	for mesa in mesas:
		var distance = radius_at(pos, mesa.center)
		if distance < OUTER_RADIUS:
			var tier = mini(TIERS, 1 + floori((OUTER_RADIUS - distance) / LEDGE_WIDTH))
			return mesa.center.y + tier * LEDGE_RISE
	return smooth_ground(pos)

# ---------------------------------------------------------------- stage hooks

func terrain_vertex_height(x: float, z: float) -> float:
	return stage.parks.vertex(Vector3(x, 0, z), smooth_ground(Vector3(x, 0, z)) - 0.25)

func terrain_color(v: Vector3) -> Color:
	var s = stage.road_s(v)
	var strata = (sin(v.y * 0.42 + v.x * 0.015) + 1.0) * 0.5
	var base = Color("a45638").lerp(Color("e4b184"), strata)
	var wash = smoothstep(535.0, 575.0, s) * (1.0 - smoothstep(645.0, 680.0, s))
	base = base.lerp(Color("c9a56e"), wash * 0.55)
	return base.lightened(sin(v.x * 0.09 + v.z * 0.06) * 0.035)

func road_width(s: float) -> float:
	var narrow = smoothstep(230.0, 265.0, s) * (1.0 - smoothstep(405.0, 435.0, s))
	var wash = smoothstep(540.0, 565.0, s) * (1.0 - smoothstep(655.0, 680.0, s))
	return stage.WIDTH - narrow * 1.2 + wash * 1.6

func road_color(p: Vector3, s: float) -> Color:
	var wash = smoothstep(540.0, 565.0, s) * (1.0 - smoothstep(655.0, 680.0, s))
	var base = Color("d4a475").lerp(Color("b99262"), wash * 0.4)
	return base.lightened(sin(p.z * 0.25 + p.x * 0.10) * 0.03 + sin(p.x * 0.41) * 0.012)

func road_strips() -> int:
	return 8

# Loose sand off the road and in the dry riverbed.
func grip(pos: Vector3) -> float:
	var s = stage.road_s(pos)
	return 0.48 if stage.road_distance(pos) > road_width(s) * 0.5 or (s > 550.0 and s < 670.0) else 0.74

func rally_speed(s: float) -> float:
	return 17.0 if s > 240.0 and s < 420.0 else 26.0

func clearing_signs() -> bool:
	return false

# Summits are reached on foot; NPC camps and their cars stay below.
func spectator_camp(index: int, clearing: Vector3, _s: float, outward: Vector3) -> Vector3:
	return Vector3.INF if index < mesas.size() else clearing + outward * 6.0

func walk_blocked(next: Vector3, feet_height: float) -> bool:
	# Grounded walkers cannot teleport up cliffs; airborne feet must clear a lip.
	return base_ground(next) > feet_height + 0.18

func camp_allowed(spot: Vector3, _kind: String) -> bool:
	return camp_supported(spot)

func camp_supported(pos: Vector3) -> bool:
	var height = base_ground(pos)
	for offset in [Vector3(1.4, 0, 0), Vector3(-1.4, 0, 0), Vector3(0, 0, 1.4), Vector3(0, 0, -1.4), Vector3(1.4, 0, 1.4), Vector3(-1.4, 0, 1.4), Vector3(1.4, 0, -1.4), Vector3(-1.4, 0, -1.4)]:
		if absf(base_ground(pos + offset) - height) > 0.22:
			return false
	return true

func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	for point in [a, b, c]:
		st.set_color(color)
		st.add_vertex(point)

func build_details(_cooperative: bool) -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for mesa in mesas:
		var center: Vector3 = mesa.center
		for tier in range(TIERS):
			var outer = OUTER_RADIUS - tier * LEDGE_WIDTH
			var inner = outer - LEDGE_WIDTH
			var low = center.y + tier * LEDGE_RISE
			var high = low + LEDGE_RISE
			var color = Color("9d4933").lerp(Color("d68b59"), float(tier % 5) / 4.0)
			for i in range(SIDES):
				var u = Vector3(cos(i * TAU / SIDES), 0, sin(i * TAU / SIDES))
				var v = Vector3(cos((i + 1) * TAU / SIDES), 0, sin((i + 1) * TAU / SIDES))
				var a = center + u * outer
				var b = center + v * outer
				var c = center + u * inner
				var d = center + v * inner
				a.y = high
				b.y = high
				c.y = high
				d.y = high
				_triangle(st, a, c, b, color.lightened(0.08))
				_triangle(st, b, c, d, color.lightened(0.08))
				var e = a
				var f = b
				e.y = low
				f.y = low
				_triangle(st, a, b, e, color)
				_triangle(st, b, f, e, color)
				if tier == TIERS - 1:
					_triangle(st, c, Vector3(center.x, high, center.z), d, Color("d68b59"))
	st.generate_normals()
	var node = MeshInstance3D.new()
	node.name = "CanyonClimbableMesas"
	node.mesh = st.commit()
	var mat = RallyProps.material(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = mat
	stage.add_child(node)
	# Large distant silhouettes and stone gates; keep them outside the road.
	for i in range(12):
		var s = 30.0 + i * 70.0
		var p: Vector3 = stage.at(s) + stage.side(s) * (155.0 if i % 2 == 0 else -155.0)
		p.y = smooth_ground(p)
		var height = 35.0 + (i % 4) * 9.0
		_build_butte(p, height, i)
		stage.rocks.append(Records.rock(p, 28.0, height))
	for sign in [-1.0, 1.0]:
		var p: Vector3 = stage.at(195.0) + stage.side(195.0) * sign * 15.0
		p.y = smooth_ground(p)
		RallyProps.cylinder(stage, p + Vector3.UP * 10.0, 6.0, 3.8, 20.0, Color("a85338"), 7)
		stage.rocks.append(Records.rock(p, 6.0, 20.0))
	var poses: Array = []
	var colors: Array = []
	for i in range(450):
		var p = Vector3(stage.rng.randf_range(-175, 175), 0, stage.rng.randf_range(-830, 10))
		if stage.road_distance(p) < 10.0:
			continue
		var on_mesa = false
		for mesa in mesas:
			on_mesa = on_mesa or radius_at(p, mesa.center) < OUTER_RADIUS + 2.0
		if on_mesa:
			continue
		p.y = stage.terrain_surface_height(p)
		var size = stage.rng.randf_range(0.35, 1.2)
		poses.append(Transform3D(Basis.from_scale(Vector3(size, size * 0.55, size)), p))
		colors.append(Color("8b8860"))
	stage.detail_batch("CanyonDryScrub", stage.NATURE_BUSH, poses, colors)
	_scatter_desert()
	_build_dust()

func _desert_open(p: Vector3) -> bool:
	if stage.road_distance(p) < 9.0:
		return false
	for mesa in mesas:
		if radius_at(p, mesa.center) < OUTER_RADIUS + 3.0:
			return false
	for i in range(12):
		var s = 30.0 + i * 70.0
		var butte = stage.at(s) + stage.side(s) * (155.0 if i % 2 == 0 else -155.0)
		if Vector2(p.x - butte.x, p.z - butte.z).length() < 26.0:
			return false
	return true

func _scatter_desert() -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 20261011
	var scrub_p: Array = []
	var scrub_c: Array = []
	var grass_p: Array = []
	var grass_c: Array = []
	var stone_p: Array = []
	var stone_c: Array = []
	var trunk_p: Array = []
	var trunk_c: Array = []
	var crown_p: Array = []
	var crown_c: Array = []
	var scrub_colors = [Color("6d7342"), Color("8d7c49"), Color("54633c"), Color("a08b5c")]
	for i in range(640):
		var p = Vector3(rng.randf_range(-175, 175), 0, rng.randf_range(-830, 10))
		if not _desert_open(p):
			continue
		p.y = stage.terrain_surface_height(p)
		var yaw = rng.randf() * TAU
		var kind = i % 16
		if kind < 7:
			var size = rng.randf_range(0.45, 1.55)
			var squash = rng.randf_range(0.35, 0.85)
			var wide = size * rng.randf_range(0.75, 1.15)
			var basis = Basis(Vector3.UP, yaw).scaled(Vector3(size, size * squash, wide))
			scrub_p.append(Transform3D(basis, p))
			scrub_c.append(scrub_colors[i % 4])
		elif kind < 11:
			var size = rng.randf_range(0.7, 1.6)
			var basis = Basis(Vector3.UP, yaw).scaled(Vector3(size, rng.randf_range(0.5, 1.5), size * 0.7))
			grass_p.append(Transform3D(basis, p))
			grass_c.append(Color("c2a45a").lerp(Color("8a8450"), rng.randf()))
		elif kind < 14:
			var radius = rng.randf_range(0.22, 0.85)
			stone_p.append(stage.woodland.shared_stone_pose(p, radius, yaw))
			stone_c.append(Color("a08a72").lightened(rng.randf_range(-0.06, 0.08)))
		else:
			var height = rng.randf_range(2.8, 6.2)
			var basis = Basis(Vector3.UP, yaw)
			trunk_p.append(stage.woodland.shared_tree_pose(p, height, 0, basis))
			trunk_c.append(Color("6a5140"))
			crown_p.append(stage.woodland.shared_tree_pose(p, height * 0.42, 1, basis))
			crown_c.append(Color("6e6244"))
	stage.detail_batch("CanyonSage", stage.NATURE_BUSH, scrub_p, scrub_c, DetailLayer.tiled(240.0))
	stage.detail_batch("CanyonDryGrass", stage.NATURE_GRASS, grass_p, grass_c, DetailLayer.tiled(160.0))
	stage.detail_batch("CanyonStones", stage.NATURE_STONE, stone_p, stone_c, DetailLayer.tiled(200.0))
	stage.detail_batch("CanyonSnagTrunks", stage.NATURE_TREE_MESHES[0], trunk_p, trunk_c, DetailLayer.tiled(260.0))
	stage.detail_batch("CanyonSnagCrowns", stage.NATURE_TREE_MESHES[1], crown_p, crown_c, DetailLayer.tiled(260.0))

func update_life(delta: float, focus: Vector3) -> void:
	super.update_life(delta, focus)
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
	mat.albedo_color = Color(0.72, 0.55, 0.38, 0.45)
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

func _build_butte(origin: Vector3, height: float, seed_index: int) -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sectors = 12
	var rings = 9
	for ring in range(rings):
		var low = float(ring) / rings
		var high = float(ring + 1) / rings
		var lower_radius = lerpf(23.0, 14.0, smoothstep(0.0, 0.55, low)) + sin(low * 19.0 + seed_index) * 1.3
		var upper_radius = lerpf(23.0, 14.0, smoothstep(0.0, 0.55, high)) + sin(high * 19.0 + seed_index) * 1.3
		var color = Color("9c4c32").lerp(Color("cf8652"), float(ring % 4) / 3.0)
		for sector in range(sectors):
			var angle = sector * TAU / sectors
			var next_angle = (sector + 1) * TAU / sectors
			var erosion = 1.0 + sin(angle * 3.0 + seed_index) * 0.14 + cos(angle * 5.0) * 0.06
			var next_erosion = 1.0 + sin(next_angle * 3.0 + seed_index) * 0.14 + cos(next_angle * 5.0) * 0.06
			var u = Vector3(cos(angle) * erosion, 0, sin(angle) * erosion)
			var v = Vector3(cos(next_angle) * next_erosion, 0, sin(next_angle) * next_erosion)
			var a = origin + u * lower_radius + Vector3.UP * low * height
			var b = origin + v * lower_radius + Vector3.UP * low * height
			var c = origin + u * upper_radius + Vector3.UP * high * height
			var d = origin + v * upper_radius + Vector3.UP * high * height
			_triangle(st, a, b, c, color)
			_triangle(st, b, d, c, color)
			if ring == rings - 1:
				_triangle(st, c, origin + Vector3.UP * height, d, color.lightened(0.1))
	st.generate_normals()
	var node = MeshInstance3D.new()
	node.name = "CanyonDistantButte%d" % seed_index
	node.mesh = st.commit()
	var mat = RallyProps.material(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = mat
	stage.add_child(node)
