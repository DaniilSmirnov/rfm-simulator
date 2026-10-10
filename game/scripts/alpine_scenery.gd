extends RefCounted
# Static scenery of the winter stage: everything that makes the road read as a
# Monte-Carlo col in the Alpes-Maritimes rather than a generic snowy track.
# Armco and low stone parapets above the drops, red-and-white snow poles,
# chevron boards on the lacets, kilometre stones and col signs, a rock cut with
# icicles and a frozen waterfall, the hamlet on the col and the snowy Alps all
# around. Positions are deterministic and identical on every client; barriers
# and buildings join `stage.rocks`, so cars and walkers collide with them.
const Props = preload("res://scripts/props.gd")
const Banks = preload("res://scripts/snowbanks.gd")

# Hamlet on the col. `side` follows stage.side(); `size` is width, floors, depth.
const HAMLET = [
	{"kind": "chapel", "s": 423.0, "side": -1.0, "offset": 19.5, "size": Vector3(5.4, 1.0, 8.6)},
	{"kind": "hotel", "s": 440.0, "side": 1.0, "offset": 20.5, "size": Vector3(12.0, 3.0, 8.0)},
	{"kind": "chalet", "s": 457.0, "side": -1.0, "offset": 18.5, "size": Vector3(7.6, 2.0, 6.4)},
	{"kind": "chalet", "s": 476.0, "side": 1.0, "offset": 22.0, "size": Vector3(6.6, 2.0, 5.6)},
]
const WATERFALL_STATION = 58.0
const WATERFALL_OFFSET = 15.5
const BARRIER_OFFSET = 0.5 # beyond the outer toe of the snowbank
const STONE = Color("8f887e")
const SNOW = Color("eef3f6")
const ICE = Color("d3ebf5")

static var _vertex_material: StandardMaterial3D
static var _ice_material: StandardMaterial3D
static var _glow_material: StandardMaterial3D

# ---------------------------------------------------------------- layout

static func configure(stage) -> void:
	var alpine = stage.alpine
	for item in HAMLET:
		var s = float(item.s)
		var pos: Vector3 = stage.at(s) + stage.side(s) * float(item.side) * float(item.offset)
		var size: Vector3 = item.size
		alpine.hamlet.append({"kind": item.kind, "s": s, "pos": pos, "size": size})
		alpine.reserved_spots.append({"pos": pos, "radius": maxf(size.x, size.z) * 0.62 + 2.5})
	alpine.reserved_spots.append({"pos": waterfall_position(stage), "radius": 6.0})

static func waterfall_position(stage) -> Vector3:
	var s = WATERFALL_STATION
	return stage.at(s) + stage.side(s) * stage.alpine.uphill_sign(s) * WATERFALL_OFFSET

static func bare_rock(stage, p: Vector3) -> bool:
	var distance: float = stage.road_distance(p)
	if distance < 12.0:
		return false
	var s: float = stage.road_s(p)
	return stage.alpine.rock(p, s, distance, stage.at(s).y + distance * 0.5) > 0.55

# Spectator places, camps and glades stay open: no barriers, poles or rocks.
static func keeps_clear(stage, p: Vector3, padding: float) -> bool:
	for center in stage.clearings + stage.snow_camps:
		if Vector2(p.x - center.x, p.z - center.z).length() < 9.0 + padding:
			return true
	for center in stage.snow_glades:
		if Vector2(p.x - center.x, p.z - center.z).length() < stage.GLADE_FLAT + 4.0 + padding:
			return true
	return stage.alpine.reserved(p, padding)

# +1 when the inside of the bend at `s` lies on stage.side(s).
static func inside_sign(stage, s: float) -> float:
	var chord = (stage.at(s - 8.0) + stage.at(s + 8.0)) * 0.5 - stage.at(s)
	return 1.0 if chord.dot(stage.side(s)) > 0.0 else -1.0

static func edge_point(stage, s: float, sign: float, extra: float) -> Vector3:
	var offset = stage.road_width(s) * 0.5 + Banks.ROAD_MARGIN + Banks.WIDTH + extra
	var p: Vector3 = stage.at(s) + stage.side(s) * sign * offset
	p.y = stage.ground(p)
	return p

# ---------------------------------------------------------------- helpers

static func vertex_material() -> StandardMaterial3D:
	if _vertex_material == null:
		_vertex_material = StandardMaterial3D.new()
		_vertex_material.vertex_color_use_as_albedo = true
		_vertex_material.vertex_color_is_srgb = true
		_vertex_material.roughness = 0.9
	return _vertex_material

static func ice_material() -> StandardMaterial3D:
	if _ice_material == null:
		_ice_material = StandardMaterial3D.new()
		_ice_material.albedo_color = ICE
		_ice_material.roughness = 0.12
		_ice_material.metallic_specular = 0.9
		_ice_material.vertex_color_use_as_albedo = true
		_ice_material.vertex_color_is_srgb = true
	return _ice_material

# Warm light behind hotel and chalet windows.
static func glow_material() -> StandardMaterial3D:
	if _glow_material == null:
		_glow_material = StandardMaterial3D.new()
		_glow_material.albedo_color = Color("ffd59a")
		_glow_material.emission_enabled = true
		_glow_material.emission = Color("ffb35a")
		_glow_material.emission_energy_multiplier = 0.75
	return _glow_material

static func unit_box() -> BoxMesh:
	var mesh = BoxMesh.new()
	mesh.size = Vector3.ONE
	return mesh

static func unit_cylinder(top: float, bottom: float, sides: int) -> CylinderMesh:
	var mesh = CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = 1.0
	mesh.radial_segments = sides
	mesh.rings = 1
	return mesh

static func batch(root: Node3D, name: String, mesh: Mesh, poses: Array, colors: Array, range_end: float = 0.0, mat: Material = null) -> MultiMeshInstance3D:
	if poses.is_empty():
		return null
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
	node.material_override = mat if mat != null else vertex_material()
	if range_end > 0.0:
		node.visibility_range_end = range_end
		node.visibility_range_end_margin = 20.0
	root.add_child(node)
	return node

# Box spanning a → b, following the slope, with the given height and depth.
static func beam(a: Vector3, b: Vector3, lift: float, height: float, depth: float) -> Transform3D:
	var along = b - a
	var length = maxf(along.length(), 0.01)
	var x = along / length
	var y = (Vector3.UP - x * x.dot(Vector3.UP)).normalized()
	var z = x.cross(y)
	return Transform3D(Basis(x * length, y * height, z * depth), (a + b) * 0.5 + Vector3.UP * lift)

static func upright(p: Vector3, size: Vector3, yaw: float = 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(size), p + Vector3.UP * size.y * 0.5)

static func facing_traffic(stage, s: float) -> float:
	var d: Vector3 = stage.direction(s)
	return atan2(-d.x, -d.z)

# ---------------------------------------------------------------- build

static func build(stage) -> void:
	var root = Node3D.new()
	root.name = "AlpineScenery"
	stage.add_child(root)
	_build_barriers(stage, root)
	_build_snow_poles(stage, root)
	_build_bend_signs(stage, root)
	_build_road_signs(stage, root)
	_build_rock_cut(stage, root)
	_build_waterfall(stage, root)
	for item in stage.alpine.hamlet:
		_build_house(stage, root, item)
	_build_fans(stage, root)

# Drops get galvanised armco; tight lacets alternate armco and stone parapets.
static func barrier_runs(stage) -> Array:
	var alpine = stage.alpine
	var runs: Array = []
	# Clear of the start and finish control posts.
	runs.append({"s0": 40.0, "s1": 110.0, "side": -alpine.uphill_sign(60.0), "kind": "armco"})
	runs.append({"s0": 722.0, "s1": 792.0, "side": -alpine.uphill_sign(780.0), "kind": "armco"})
	var index = 0
	for bend in alpine.bends:
		var s = float(bend.s)
		if float(bend.radius) > 32.0 or s < 110.0 or s > 722.0:
			continue
		runs.append({"s0": s - 11.0, "s1": s + 11.0, "side": -inside_sign(stage, s), "kind": "stone" if index % 2 == 0 else "armco"})
		index += 1
	return runs

static func _build_barriers(stage, root: Node3D) -> void:
	var rails: Array = []
	var rail_colors: Array = []
	var posts: Array = []
	var post_colors: Array = []
	var walls: Array = []
	var wall_colors: Array = []
	var caps: Array = []
	var cap_colors: Array = []
	for run in barrier_runs(stage):
		var points: Array = []
		var travelled = 0.0
		var previous = edge_point(stage, run.s0, run.side, BARRIER_OFFSET)
		var s = float(run.s0)
		points.append(previous)
		while s < float(run.s1):
			s += 0.25
			var p = edge_point(stage, s, run.side, BARRIER_OFFSET)
			travelled += Vector2(p.x - previous.x, p.z - previous.z).length()
			previous = p
			if travelled >= 2.4:
				points.append(p)
				travelled = 0.0
		for i in range(points.size()):
			var p: Vector3 = points[i]
			var open = keeps_clear(stage, p, 1.0)
			points[i] = null if open else p
		for i in range(points.size()):
			if points[i] == null:
				continue
			var p: Vector3 = points[i]
			var stone = run.kind == "stone"
			if not stone:
				posts.append(Transform3D(Basis.from_scale(Vector3(0.13, 1.15, 0.13)), p + Vector3.UP * 0.3))
				post_colors.append(Color("7c8489"))
			stage.rocks.append({"pos": p, "radius": 0.32 if stone else 0.2, "height": 0.85, "barrier": true})
			if i + 1 >= points.size() or points[i + 1] == null:
				continue
			var q: Vector3 = points[i + 1]
			if stone:
				walls.append(beam(p, q, 0.27, 0.62, 0.5))
				wall_colors.append(STONE.lightened(sin(p.x * 3.1 + p.z) * 0.06))
				caps.append(beam(p, q, 0.63, 0.13, 0.62))
			else:
				rails.append(beam(p, q, 0.62, 0.32, 0.07))
				rail_colors.append(Color("b3bbc0"))
				caps.append(beam(p, q, 0.82, 0.08, 0.2))
			cap_colors.append(SNOW)
	var box = unit_box()
	batch(root, "ArmcoRails", box, rails, rail_colors, 260.0)
	batch(root, "ArmcoPosts", box, posts, post_colors, 200.0)
	batch(root, "StoneParapets", box, walls, wall_colors, 260.0)
	batch(root, "BarrierSnow", box, caps, cap_colors, 220.0)

# Red-and-white poles mark the road edge for the snow plough.
static func _build_snow_poles(stage, root: Node3D) -> void:
	var poses: Array = []
	var colors: Array = []
	var pole = unit_cylinder(0.5, 0.5, 6)
	for station in range(8, int(stage.LENGTH) - 8, 17):
		for sign in [-1.0, 1.0]:
			var s = float(station) + (4.0 if sign > 0 else 0.0)
			var p: Vector3 = stage.at(s) + stage.side(s) * sign * (stage.road_width(s) * 0.5 + Banks.ROAD_MARGIN + Banks.WIDTH * 0.82)
			if keeps_clear(stage, p, 0.0):
				continue
			p.y = stage.ground(p) - 0.25
			for band in range(4):
				poses.append(Transform3D(Basis.from_scale(Vector3(0.07, 0.6, 0.07)), p + Vector3.UP * (0.3 + band * 0.6)))
				colors.append(Color("d23b2a") if band % 2 == 0 else Color("f3f1ea"))
	batch(root, "SnowPoles", pole, poses, colors, 180.0)

static func _board(root: Node3D, p: Vector3, yaw: float, size: Vector2, color: Color, height: float) -> MeshInstance3D:
	Props.cylinder(root, p + Vector3.UP * height * 0.5, 0.045, 0.045, height, Color("8e969b"), 6)
	var board = Props.box(root, p + Vector3.UP * (height + size.y * 0.5 - 0.1), Vector3(size.x, size.y, 0.05), color)
	board.rotation.y = yaw
	return board

# Chevron boards on the outside of every tight bend.
static func _build_bend_signs(stage, root: Node3D) -> void:
	for bend in stage.alpine.bends:
		var s = float(bend.s)
		if float(bend.radius) > 34.0:
			continue
		var inside = inside_sign(stage, s)
		for k in [-7.0, 0.0, 7.0]:
			var station = s + k
			var p = edge_point(stage, station, -inside, 1.3)
			if keeps_clear(stage, p, 0.5):
				continue
			var board = _board(root, p, facing_traffic(stage, station), Vector2(0.95, 0.52), Color("c8352c"), 1.05)
			var arrows = ">>>" if inside > 0.0 else "<<<"
			Props.label_3d(board, Vector3(0, 0, 0.03), arrows, 110, 0.006, Color("f7f4ee"))

# Kilometre stones, the col sign and a direction board at the start.
static func _build_road_signs(stage, root: Node3D) -> void:
	for i in range(1, 5):
		var s = i * 200.0 - 6.0
		var p = edge_point(stage, s, 1.0, 0.9)
		if keeps_clear(stage, p, 0.5):
			p = edge_point(stage, s, -1.0, 0.9)
		var yaw = facing_traffic(stage, s)
		var stone = Props.box(root, p + Vector3(0, 0.25, 0), Vector3(0.44, 0.7, 0.24), Color("f1eee6"))
		stone.rotation.y = yaw
		Props.box(stone, Vector3(0, 0.39, 0), Vector3(0.46, 0.12, 0.26), Color("c43a2d"))
		Props.label_3d(stone, Vector3(0, 0.05, 0.125), "%d" % i, 64, 0.004, Color("2b2b2b"))
		stage.rocks.append({"pos": p, "radius": 0.3, "height": 0.6, "barrier": true})
	var start = edge_point(stage, 16.0, 1.0, 1.4)
	var arrow = _board(root, start, facing_traffic(stage, 16.0), Vector2(2.3, 0.95), Color("f4f2ec"), 1.6)
	Props.label_3d(arrow, Vector3(0, 0.17, 0.03), "COL DE TURINI  ↑", 64, 0.0032, Color("23272a"))
	Props.label_3d(arrow, Vector3(0, -0.17, 0.03), "MONACO  ↓", 64, 0.0032, Color("23272a"))
	var col_sign = edge_point(stage, 432.0, -1.0, 1.6)
	var board = _board(root, col_sign, facing_traffic(stage, 432.0), Vector2(2.6, 1.15), Color("6a4a2e"), 1.7)
	Props.label_3d(board, Vector3(0, 0.2, 0.03), "COL DE TURINI", 72, 0.0036, Color("f3ead7"))
	Props.label_3d(board, Vector3(0, -0.22, 0.03), "ALT. 1607 m", 64, 0.0032, Color("f3ead7"))

# Rock outcrops in the cut above the corniche, hung with icicles.
static func _build_rock_cut(stage, root: Node3D) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 16072026
	var alpine = stage.alpine
	var rock_poses: Array = []
	var rock_colors: Array = []
	var cap_poses: Array = []
	var cap_colors: Array = []
	var icicles: Array = []
	var icicle_colors: Array = []
	for station in range(6, int(stage.LENGTH) - 6, 6):
		var s = float(station) + rng.randf_range(-2.0, 2.0)
		if alpine.corniche(s) < 0.6:
			continue
		var up = alpine.uphill_sign(s)
		var lateral = rng.randf_range(11.5, 17.0)
		var p: Vector3 = stage.at(s) + stage.side(s) * up * lateral
		var radius = rng.randf_range(1.2, 2.6)
		if keeps_clear(stage, p, radius) or not stage.rock_hit(p, p, radius, false).is_empty():
			continue
		var height = rng.randf_range(1.8, 4.6)
		# Bed the rock into the slope: its downhill edge sinks into the snow.
		var low = stage.ground(p)
		for k in range(8):
			low = minf(low, stage.ground(p + Vector3(cos(k * TAU / 8.0), 0, sin(k * TAU / 8.0)) * radius * 0.9))
		height += (stage.ground(p) - low) * 1.2
		var center = Vector3(p.x, low + height * 0.12, p.z)
		var yaw = rng.randf() * TAU
		rock_poses.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(radius * 2.0, height, radius * 1.7)), center))
		rock_colors.append(Color("757069").lightened(rng.randf_range(-0.08, 0.1)))
		cap_poses.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(radius * 1.5, 0.45, radius * 1.3)), center + Vector3.UP * height * 0.44))
		cap_colors.append(SNOW)
		stage.rocks.append({"pos": Vector3(p.x, low, p.z), "radius": radius * 0.85, "height": height * 0.6, "forest": true})
		# Meltwater freezes along the face that looks onto the road.
		var toward = (stage.at(s) - p)
		toward.y = 0.0
		toward = toward.normalized()
		var along = toward.cross(Vector3.UP)
		for i in range(rng.randi_range(4, 8)):
			var length = rng.randf_range(0.35, 1.25)
			var root_point = center + toward * radius * 0.8 + along * rng.randf_range(-radius * 0.6, radius * 0.6) + Vector3.UP * height * rng.randf_range(0.12, 0.24)
			icicles.append(Transform3D(Basis.from_scale(Vector3(0.13, length, 0.13)), root_point - Vector3.UP * length * 0.5))
			icicle_colors.append(Color.WHITE.lerp(ICE, rng.randf()))
	batch(root, "CutRocks", stage.NATURE_BOULDER, rock_poses, rock_colors, 320.0)
	batch(root, "CutRockSnow", stage.NATURE_STONE, cap_poses, cap_colors, 320.0)
	batch(root, "Icicles", unit_cylinder(0.5, 0.0, 5), icicles, icicle_colors, 140.0, ice_material())

# A cascade frozen solid against the rock wall above the first corniche.
static func _build_waterfall(stage, root: Node3D) -> void:
	var p = waterfall_position(stage)
	p.y = stage.ground(p)
	var toward = stage.at(WATERFALL_STATION) - p
	toward.y = 0.0
	toward = toward.normalized()
	var fall = Node3D.new()
	fall.name = "FrozenWaterfall"
	root.add_child(fall)
	fall.position = p
	fall.rotation.y = atan2(toward.x, toward.z)
	var cliff = MeshInstance3D.new()
	cliff.mesh = stage.NATURE_BOULDER
	cliff.material_override = Props.shared_material(Color("7a756f"))
	cliff.scale = Vector3(13.0, 17.0, 6.0)
	cliff.position = Vector3(0, 4.5, -2.6)
	fall.add_child(cliff)
	var ice = ice_material().duplicate()
	ice.vertex_color_use_as_albedo = false
	# Columns of ice spill over the lip and pile up into a cone at the foot.
	for column in range(3):
		var x = (column - 1) * 1.5
		var top = 11.5 - absf(column - 1) * 1.8
		for i in range(7):
			var t = float(i) / 6.0
			var part = Props.faceted(fall, Vector3(x + sin(i * 1.7 + column) * 0.3, top - t * (top - 0.8), 0.7 + t * 1.2), Vector3(1.2 + t * 1.4, top / 5.0, 0.9 + t * 0.5), ICE, 8, 4)
			part.material_override = ice
	for i in range(14):
		var x = -2.6 + i * 0.4
		var length = 0.9 + absf(sin(i * 2.3)) * 2.0
		var spike = Props.cylinder(fall, Vector3(x, 11.6 - absf(x) * 0.9 - length * 0.5, 0.45), 0.0, 0.13, length, ICE, 5)
		spike.material_override = ice
	Props.faceted(fall, Vector3(0, 0.3, 2.2), Vector3(5.2, 1.2, 3.0), SNOW, 8, 3)
	stage.rocks.append({"pos": p, "radius": 3.2, "height": 12.0, "forest": true})

# ---------------------------------------------------------------- hamlet

static func _level(stage, node: Node3D, half: Vector2, color: Color) -> void:
	var low = INF
	var high = -INF
	for corner in [Vector3(half.x, 0, half.y), Vector3(-half.x, 0, half.y), Vector3(half.x, 0, -half.y), Vector3(-half.x, 0, -half.y), Vector3.ZERO]:
		var height = stage.ground(node.position + corner.rotated(Vector3.UP, node.rotation.y))
		low = minf(low, height)
		high = maxf(high, height)
	node.position.y = lerpf(low, high, 0.55)
	var depth = node.position.y - low + 0.6
	Props.box(node, Vector3(0, 0.25 - depth * 0.5, 0), Vector3(half.x * 2.0 + 0.3, depth + 0.5, half.y * 2.0 + 0.3), color)

# Gable roof; the ridge runs along local X unless `along_z`. Snow lies on top.
static func _roof(node: Node3D, top: float, width: float, depth: float, pitch: float, color: Color, along_z: bool = false) -> float:
	var span = (width if along_z else depth) * 0.5 + 0.7
	var length = (depth if along_z else width) + 1.4
	var slab = span / cos(pitch)
	for sign in [-1.0, 1.0]:
		var center = Vector3(0, top + span * 0.5 * tan(pitch), 0)
		var roof: MeshInstance3D
		if along_z:
			center.x = sign * span * 0.5
			roof = Props.box(node, center, Vector3(slab, 0.22, length), color)
			roof.rotation.z = -sign * pitch
		else:
			center.z = sign * span * 0.5
			roof = Props.box(node, center, Vector3(length, 0.22, slab), color)
			roof.rotation.x = sign * pitch
		Props.box(roof, Vector3(0, 0.2, 0), Vector3(slab + 0.04, 0.2, length + 0.06) if along_z else Vector3(length + 0.06, 0.2, slab + 0.04), SNOW)
	return top + span * tan(pitch)

# Fill the triangular gable ends under a roof with stepped courses.
static func _gables(node: Node3D, top: float, ridge: float, span: float, at: float, color: Color, along_z: bool) -> void:
	var rise = ridge - top
	var courses = 6
	for sign in [-1.0, 1.0]:
		for i in range(courses):
			var t = (float(i) + 0.5) / courses
			var width = span * (1.0 - t) + 0.05
			var center = Vector3(0, top + rise * t, sign * at) if along_z else Vector3(sign * at, top + rise * t, 0)
			var size = Vector3(width, rise / courses + 0.02, 0.1) if along_z else Vector3(0.1, rise / courses + 0.02, width)
			Props.box(node, center, size, color)

static func _window(node: Node3D, at: Vector3, size: Vector2, yaw: float, lit: bool, shutters: bool) -> void:
	var frame = Props.box(node, at, Vector3(size.x + 0.16, size.y + 0.16, 0.06), Color("efe8da"))
	frame.rotation.y = yaw
	var glass = Props.box(frame, Vector3(0, 0, 0.02), Vector3(size.x, size.y, 0.05), Color("2f3a42"))
	if lit:
		glass.material_override = glow_material()
	if shutters:
		for sign in [-1.0, 1.0]:
			Props.box(frame, Vector3(sign * (size.x * 0.5 + 0.32), 0, 0.01), Vector3(0.42, size.y + 0.1, 0.05), Color("4d6a3b"))

static func _local(node: Node3D, local: Vector3) -> Vector3:
	return node.position + node.basis * local

static func _build_house(stage, root: Node3D, item: Dictionary) -> void:
	var size: Vector3 = item.size
	var w = size.x
	var d = size.z
	var node = Node3D.new()
	node.name = "Col" + String(item.kind).capitalize() + "_%d" % int(item.s)
	root.add_child(node)
	node.position = item.pos
	var toward: Vector3 = stage.at(float(item.s)) - node.position
	node.rotation.y = atan2(toward.x, toward.z)
	_level(stage, node, Vector2(w * 0.5, d * 0.5), Color("6f6a64"))
	var height = 0.0
	if item.kind == "chapel":
		height = _build_chapel(node, w, d)
	else:
		height = _build_chalet(stage, node, w, d, int(size.y), item.kind == "hotel")
	# Rectangular footprints are covered by a row of overlapping circles.
	var across = node.basis.x
	var circles = maxi(1, ceili(w / d))
	for i in range(circles):
		var offset = (float(i) - (circles - 1) * 0.5) * (w / circles)
		stage.rocks.append({"pos": node.position + across * offset, "radius": minf(w / circles, d) * 0.5 + 0.35, "height": height, "building": true})

static func _build_chalet(stage, node: Node3D, w: float, d: float, floors: int, hotel: bool) -> float:
	var ground_floor = 3.0
	var storey = 2.6
	Props.box(node, Vector3(0, ground_floor * 0.5, 0), Vector3(w, ground_floor, d), Color("a69d90"))
	for floor in range(1, floors):
		var y = ground_floor + (floor - 0.5) * storey
		Props.box(node, Vector3(0, y, 0), Vector3(w, storey, d), Color("8a5a35").lightened(floor * 0.03))
		# Plank lines.
		for line in range(3):
			Props.box(node, Vector3(0, y - storey * 0.5 + 0.5 + line * 0.75, d * 0.5 + 0.015), Vector3(w, 0.05, 0.02), Color("6b4428"))
	var top = ground_floor + (floors - 1) * storey
	var ridge = _roof(node, top, w, d, 0.5, Color("4b3a2d"))
	_gables(node, top, ridge, d, w * 0.5 - 0.06, Color("7d5131"), false)
	var columns = maxi(2, int(w / 2.3))
	for floor in range(floors):
		var y = ground_floor * 0.55 if floor == 0 else ground_floor + (floor - 0.45) * storey
		for c in range(columns):
			var x = (float(c) - (columns - 1) * 0.5) * (w / columns)
			if floor == 0 and c == columns / 2:
				Props.box(node, Vector3(x, 1.1, d * 0.5 + 0.03), Vector3(1.2, 2.2, 0.06), Color("5a3a24"))
				continue
			_window(node, Vector3(x, y, d * 0.5 + 0.04), Vector2(0.85, 1.05), 0.0, (c + floor) % 3 != 1, floor > 0)
		for sign in [-1.0, 1.0]:
			_window(node, Vector3(sign * (w * 0.5 + 0.04), y, 0.0), Vector2(0.8, 1.0), sign * PI * 0.5, floor > 0 and (floor + int(sign)) % 2 == 0, false)
	# Wooden balconies along the upper floors, snow on the hand rail.
	for floor in range(1, floors):
		var y = ground_floor + (floor - 1) * storey
		Props.box(node, Vector3(0, y + 0.06, d * 0.5 + 0.6), Vector3(w - 0.6, 0.14, 1.2), Color("74492b"))
		Props.box(node, Vector3(0, y + 0.55, d * 0.5 + 1.17), Vector3(w - 0.6, 0.9, 0.07), Color("6a4227"))
		Props.box(node, Vector3(0, y + 1.04, d * 0.5 + 1.17), Vector3(w - 0.5, 0.1, 0.16), SNOW)
	if hotel:
		var board = Props.box(node, Vector3(0, ground_floor + 0.05, d * 0.5 + 1.25), Vector3(4.6, 0.62, 0.08), Color("3a2b20"))
		Props.label_3d(board, Vector3(0, 0, 0.05), "HÔTEL DU COL", 96, 0.006, Color("f2e3bf"))
	# Chimney with a snow cap; alpine_life.gd adds the smoke.
	var chimney = Vector3(w * 0.24, top + (ridge - top) * 0.55, -d * 0.18)
	Props.box(node, chimney + Vector3(0, 0.9, 0), Vector3(0.7, 1.9, 0.7), STONE)
	Props.box(node, chimney + Vector3(0, 1.9, 0), Vector3(0.82, 0.14, 0.82), SNOW)
	stage.alpine.chimneys.append(_local(node, chimney + Vector3(0, 2.0, 0)))
	# Firewood under the eaves, a classic of mountain houses.
	for row in range(3):
		Props.box(node, Vector3(-w * 0.5 - 0.5, 0.3 + row * 0.38, 0.0), Vector3(0.7, 0.36, d * 0.7), Color("7a5636").lightened(row * 0.04))
	return ridge

static func _build_chapel(node: Node3D, w: float, d: float) -> float:
	var walls = 4.2
	Props.box(node, Vector3(0, walls * 0.5, 0), Vector3(w, walls, d), Color("ebe5d9"))
	var ridge = _roof(node, walls, w, d, 0.72, Color("4a4f56"), true)
	# Gable end facing the road, with door and a round window.
	_gables(node, walls, ridge, w, d * 0.5 - 0.06, Color("ebe5d9"), true)
	Props.box(node, Vector3(0, 1.2, d * 0.5 + 0.03), Vector3(1.3, 2.4, 0.08), Color("5b3a25"))
	var rose = Props.cylinder(node, Vector3(0, 3.4, d * 0.5 + 0.03), 0.42, 0.42, 0.06, Color("3b4f6b"), 10)
	rose.rotation.x = PI * 0.5
	for sign in [-1.0, 1.0]:
		Props.box(node, Vector3(sign * (w * 0.5 + 0.03), 2.4, 0.0), Vector3(0.06, 1.4, 0.6), Color("3b4f6b"))
	# Bell tower behind the nave, stone base and slate spire.
	var tower = Vector3(w * 0.5 - 0.9, 0, -d * 0.5 + 0.9)
	Props.box(node, tower + Vector3(0, 4.6, 0), Vector3(1.9, 9.2, 1.9), Color("e4ded1"))
	for face in [Vector3(0, 0, 0.96), Vector3(0, 0, -0.96), Vector3(0.96, 0, 0), Vector3(-0.96, 0, 0)]:
		Props.box(node, tower + face + Vector3(0, 8.0, 0), Vector3(0.7 if face.z != 0.0 else 0.06, 1.2, 0.06 if face.z != 0.0 else 0.7), Color("2a2a2c"))
	var spire = Props.cylinder(node, tower + Vector3(0, 10.4, 0), 1.45, 0.02, 2.4, Color("4a4f56"), 4)
	spire.rotation.y = PI * 0.25
	var spire_snow = Props.cylinder(node, tower + Vector3(0, 10.1, 0), 1.2, 0.35, 1.0, SNOW, 4)
	spire_snow.rotation.y = PI * 0.25
	Props.box(node, tower + Vector3(0, 12.0, 0), Vector3(0.08, 0.9, 0.08), Color("2f2b26"))
	Props.box(node, tower + Vector3(0, 12.15, 0), Vector3(0.45, 0.08, 0.08), Color("2f2b26"))
	return 11.0

# ---------------------------------------------------------------- spectators

# Snowmen by the clearings; spots for waving flags and red flares.
static func _build_fans(stage, root: Node3D) -> void:
	var alpine = stage.alpine
	var palettes = [
		[Color("1f4fa0"), Color("f4f4f0"), Color("d02c2c"), true],
		[Color("d02c2c"), Color("f4f4f0"), Color("d02c2c"), false],
		[Color("2b8a3e"), Color("f4f4f0"), Color("d02c2c"), true],
		[Color("1d1d1d"), Color("e8c22c"), Color("d02c2c"), true],
		[Color("2f6db5"), Color("1d1d1d"), Color("f4f4f0"), false],
	]
	for i in range(stage.clearings.size()):
		var clearing: Vector3 = stage.clearings[i]
		var s: float = stage.road_s(clearing)
		var along: Vector3 = stage.direction(s)
		along.y = 0.0
		along = along.normalized()
		var snowman = clearing + along * (5.2 if i % 2 == 0 else -5.2)
		snowman.y = stage.ground(snowman)
		_snowman(root, snowman, atan2(-along.x, -along.z) + (0.6 if i % 2 == 0 else -0.6), i)
		var flag = clearing - along * (4.0 if i % 2 == 0 else -4.0)
		flag.y = stage.ground(flag)
		var palette: Array = palettes[i % palettes.size()]
		alpine.flag_spots.append({"pos": flag, "colors": [palette[0], palette[1], palette[2]], "vertical": palette[3], "yaw": atan2(along.x, along.z)})
		if i % 2 == 1:
			var flare = clearing + (stage.at(s) - clearing).normalized() * 3.5
			flare.y = stage.ground(flare)
			alpine.flare_spots.append(flare)
	# Flags on the col, by the hotel terrace and the chapel.
	for item in alpine.hamlet:
		if item.kind == "chalet":
			continue
		var s = float(item.s)
		var toward: Vector3 = stage.at(s) - item.pos
		toward.y = 0.0
		var spot: Vector3 = item.pos + toward.normalized() * (float(item.size.z) * 0.5 + 3.2) + toward.normalized().cross(Vector3.UP) * 3.0
		spot.y = stage.ground(spot)
		var palette: Array = palettes[(alpine.flag_spots.size() + 1) % palettes.size()]
		alpine.flag_spots.append({"pos": spot, "colors": [palette[0], palette[1], palette[2]], "vertical": palette[3], "yaw": atan2(toward.x, toward.z) + PI * 0.5})
	var terrace: Dictionary = alpine.hamlet[1]
	var flare_spot: Vector3 = terrace.pos + (stage.at(float(terrace.s)) - terrace.pos).normalized() * 9.0
	flare_spot.y = stage.ground(flare_spot)
	alpine.flare_spots.append(flare_spot)

static func _snowman(root: Node3D, p: Vector3, yaw: float, index: int) -> void:
	var man = Node3D.new()
	man.name = "Snowman"
	root.add_child(man)
	man.position = p
	man.rotation.y = yaw
	Props.faceted(man, Vector3(0, 0.38, 0), Vector3(0.9, 0.8, 0.9), SNOW, 10, 6)
	Props.faceted(man, Vector3(0, 0.98, 0), Vector3(0.64, 0.6, 0.64), SNOW, 10, 6)
	Props.faceted(man, Vector3(0, 1.45, 0), Vector3(0.44, 0.42, 0.44), SNOW, 10, 6)
	var nose = Props.cylinder(man, Vector3(0, 1.46, 0.3), 0.045, 0.0, 0.22, Color("e0782a"), 6)
	nose.rotation.x = PI * 0.5
	for x in [-0.08, 0.08]:
		Props.box(man, Vector3(x, 1.53, 0.2), Vector3(0.04, 0.04, 0.03), Color("1f1f1f"))
	for y in [0.92, 1.05, 1.18]:
		Props.box(man, Vector3(0, y, 0.31), Vector3(0.05, 0.05, 0.03), Color("1f1f1f"))
	var scarf = [Color("c8352c"), Color("2d5fa8"), Color("e2b52b")][index % 3]
	Props.cylinder(man, Vector3(0, 1.25, 0), 0.25, 0.25, 0.1, scarf, 10)
	var tail = Props.box(man, Vector3(0.12, 1.05, 0.26), Vector3(0.1, 0.35, 0.05), scarf)
	tail.rotation.z = 0.25
	for sign in [-1.0, 1.0]:
		var arm = Props.cylinder(man, Vector3(sign * 0.45, 1.1, 0), 0.02, 0.02, 0.6, Color("5a4230"), 4)
		arm.rotation.z = sign * -1.0
	# Rally fan's cap, of course.
	Props.cylinder(man, Vector3(0, 1.66, 0), 0.19, 0.19, 0.08, Color("ce4830"), 10)
	Props.box(man, Vector3(0, 1.63, 0.18), Vector3(0.26, 0.02, 0.16), Color("ce4830"))

# ---------------------------------------------------------------- distant Alps

static func build_peaks(stage) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 1607
	var surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var anchors: Array = []
	for i in range(30):
		var z = lerpf(140.0, -1010.0, float(i) / 29.0) + rng.randf_range(-20.0, 20.0)
		var side = -1.0 if i % 2 == 0 else 1.0
		anchors.append(Vector3(side * rng.randf_range(250.0, 330.0), rng.randf_range(0.0, 20.0), z))
		if i % 3 == 0:
			anchors.append(Vector3(side * rng.randf_range(390.0, 470.0), rng.randf_range(10.0, 30.0), z + rng.randf_range(-40.0, 40.0)))
	for z in [260.0, -1130.0]:
		for x in [-160.0, 20.0, 190.0]:
			anchors.append(Vector3(x + rng.randf_range(-40.0, 40.0), rng.randf_range(0.0, 20.0), z + rng.randf_range(-30.0, 30.0)))
	for base in anchors:
		_peak(surface, rng, base, rng.randf_range(110.0, 175.0), rng.randf_range(150.0, 300.0))
	surface.generate_normals()
	var node = MeshInstance3D.new()
	node.name = "DistantAlps"
	node.mesh = surface.commit()
	node.material_override = vertex_material()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(node)

# A jagged peak: three jittered rings narrowing to an off-centre summit.
# Rock shows on the lower flanks and on steep ribs; snow covers the rest.
static func _peak(surface: SurfaceTool, rng: RandomNumberGenerator, base: Vector3, radius: float, height: float) -> void:
	var sides = 9
	var rings: Array = []
	var levels = [[0.0, 1.0], [0.38, 0.62], [0.72, 0.3]]
	for level in levels:
		var ring: Array = []
		for k in range(sides):
			var angle = TAU * k / sides + rng.randf_range(-0.18, 0.18)
			var r = radius * float(level[1]) * rng.randf_range(0.78, 1.15)
			ring.append(base + Vector3(cos(angle) * r, height * float(level[0]) + rng.randf_range(-6.0, 6.0) * float(level[0]), sin(angle) * r))
		rings.append(ring)
	var summit = base + Vector3(rng.randf_range(-0.12, 0.12) * radius, height, rng.randf_range(-0.12, 0.12) * radius)
	var snowline = base.y + height * rng.randf_range(0.28, 0.45)
	for level in range(rings.size()):
		for k in range(sides):
			var a: Vector3 = rings[level][k]
			var b: Vector3 = rings[level][(k + 1) % sides]
			var rib = k % 3 == 0
			if level + 1 < rings.size():
				var c: Vector3 = rings[level + 1][k]
				var d: Vector3 = rings[level + 1][(k + 1) % sides]
				for v in [a, c, b, b, c, d]:
					surface.set_color(_peak_color(v, snowline, rib))
					surface.add_vertex(v)
			else:
				for v in [a, summit, b]:
					surface.set_color(_peak_color(v, snowline, rib))
					surface.add_vertex(v)

static func _peak_color(v: Vector3, snowline: float, rib: bool) -> Color:
	var rock = Color("646a73").lerp(Color("7b8088"), (sin(v.x * 0.05 + v.z * 0.03) + 1.0) * 0.5)
	var snow = Color("f0f4f8")
	var line = snowline + (18.0 if rib else 0.0) + sin(v.x * 0.07) * 8.0
	return rock.lerp(snow, smoothstep(line - 10.0, line + 14.0, v.y))
