extends RefCounted
const Movable = preload("res://scripts/core/prop_registry.gd")
const Props = preload("res://scripts/core/props.gd")
const Records = preload("res://scripts/stages/stage_records.gd")
const MeshMerge = preload("res://scripts/core/mesh_merge.gd")
# Static scenery of «Поречье»: log izbas with carved window surrounds along
# the village street, a wooden tent-roofed church with a bell tower, a crane
# well, a hayloft barn, a plank-and-log bridge over the frozen stream, fences,
# haystacks in the fields and the birch-and-spruce trees that frame them.
# Positions are deterministic: every room member builds the same village.
const SNOW = Color("eef2f2")
const LOG_WALL = Color("8a6a46")
const LOG_DARK = Color("6b4f34")
const ROOF_WOOD = Color("4c5248")
const FENCE = Color("7a5c3c")

var stage
var biome
var rng = RandomNumberGenerator.new()
var counts := {}
var fence_posts: Array = []
var fence_post_colors: Array = []
var fence_rails: Array = []
var fence_rail_colors: Array = []

func build(owner_stage, owner_biome) -> void:
	stage = owner_stage
	biome = owner_biome
	rng.seed = 19022026
	var root = Node3D.new()
	root.name = "SeverScenery"
	stage.add_child(root)
	counts["houses"] = biome.HOUSES.size()
	for item in biome.HOUSES:
		_izba(root, item)
	_church(root)
	_well(root)
	_barn(root)
	_bridge(root)
	_village_sign(root)
	for item in biome.HAYSTACKS:
		_haystack(root, biome.place(item[0], item[1], item[2]))
	_roadside_posts(root)
	_birches(root)
	_spruces(root)
	_batch(root, "FencePosts", unit_cylinder(0.05, 0.05, 1.0, 5), fence_posts, fence_post_colors)
	_batch(root, "FenceRails", unit_box(), fence_rails, fence_rail_colors)
	for child in root.get_children():
		if child is Node3D and not child.has_meta("unbatched"):
			MeshMerge.bake(child)
	stage.solids.index()

# ---------------------------------------------------------------- helpers

static func beam(a: Vector3, b: Vector3, lift: float, height: float, depth: float) -> Transform3D:
	var along = b - a
	var length = maxf(along.length(), 0.01)
	var x = along / length
	var y = (Vector3.UP - x * x.dot(Vector3.UP)).normalized()
	var z = x.cross(y)
	return Transform3D(Basis(x * length, y * height, z * depth), (a + b) * 0.5 + Vector3.UP * lift)

func _anchor(root: Node3D, name: String, at: Vector3, facing: Vector3) -> Node3D:
	var node = Node3D.new()
	node.name = name
	root.add_child(node)
	node.position = at
	node.rotation.y = atan2(facing.x, facing.z)
	return node

# Levels a footprint into the micro-terrain and skirts it with a log plinth.
func _level(node: Node3D, half: Vector2, color: Color) -> void:
	var low = INF
	var high = -INF
	for corner in [Vector3(half.x, 0, half.y), Vector3(-half.x, 0, half.y), Vector3(half.x, 0, -half.y), Vector3(-half.x, 0, -half.y), Vector3.ZERO]:
		var height = stage.ground(node.position + corner.rotated(Vector3.UP, node.rotation.y))
		low = minf(low, height)
		high = maxf(high, height)
	node.position.y = lerpf(low, high, 0.52)
	var depth = node.position.y - low + 0.5
	Props.box(node, Vector3(0, 0.22 - depth * 0.5, 0), Vector3(half.x * 2.0 + 0.3, depth + 0.44, half.y * 2.0 + 0.3), color)

# Gable roof; the ridge runs along local X. Returns the ridge height.
func _roof(node: Node3D, top: float, width: float, depth: float, pitch: float, color: Color) -> float:
	var span = depth * 0.5 + 0.75
	var length = width + 1.5
	var slab = span / cos(pitch)
	for sign in [-1.0, 1.0]:
		var center = Vector3(0, top + span * 0.5 * tan(pitch), sign * span * 0.5)
		var roof = Props.box(node, center, Vector3(length, 0.2, slab), color)
		roof.rotation.x = sign * pitch
		Props.box(roof, Vector3(0, 0.19, 0), Vector3(length + 0.06, 0.2, slab + 0.04), SNOW)
	return top + span * tan(pitch)

func _gables(node: Node3D, top: float, ridge: float, span: float, at: float, color: Color) -> void:
	var rise = ridge - top
	var courses = 6
	for sign in [-1.0, 1.0]:
		for i in range(courses):
			var t = (float(i) + 0.5) / courses
			var width = span * (1.0 - t) + 0.05
			Props.box(node, Vector3(sign * at, top + rise * t, 0), Vector3(0.1, rise / courses + 0.02, width), color)

func _window(node: Node3D, at: Vector3, size: Vector2, yaw: float, lit: bool) -> void:
	# A carved naличник (window surround), painted, with a small pediment.
	var frame = Props.box(node, at, Vector3(size.x + 0.22, size.y + 0.22, 0.07), Color("e8e0cc"))
	frame.rotation.y = yaw
	Props.box(frame, Vector3(0, 0, 0.025), Vector3(size.x, size.y, 0.06), Color("3a4a52") if not lit else Color("fcdf9a"))
	if lit:
		Props.unique_material(frame.get_child(0))
		frame.get_child(0).material_override.emission_enabled = true
		frame.get_child(0).material_override.emission = Color("ffb75e")
		frame.get_child(0).material_override.emission_energy_multiplier = 0.5
	var pediment = Props.box(frame, Vector3(0, size.y * 0.5 + 0.2, 0.02), Vector3(size.x + 0.4, 0.14, 0.08), Color("3f6a4a"))
	pediment.rotation.z = 0.0
	for sign in [-1.0, 1.0]:
		Props.box(frame, Vector3(sign * (size.x * 0.5 + 0.18), 0, 0.01), Vector3(0.1, size.y + 0.16, 0.05), Color("3f6a4a"))

# The carved "конёк" (ridge ornament) of a traditional izba, a stylised horse
# head looking down the street.
func _ridge_ornament(node: Node3D, at: Vector3, yaw: float) -> void:
	var ornament = Node3D.new()
	node.add_child(ornament)
	ornament.position = at
	ornament.rotation.y = yaw
	Props.box(ornament, Vector3(0, 0.05, 0), Vector3(0.12, 0.1, 0.9), LOG_DARK)
	var neck = Props.box(ornament, Vector3(0, 0.22, 0.42), Vector3(0.1, 0.34, 0.12), LOG_DARK)
	neck.rotation.x = -0.5
	Props.box(ornament, Vector3(0, 0.42, 0.58), Vector3(0.1, 0.12, 0.26), LOG_DARK)

func _izba(root: Node3D, item: Array) -> void:
	var s: float = item[0]
	var side: float = item[1]
	var w: float = item[3]
	var d: float = item[4]
	var floors: int = item[5]
	var pos = biome.place(s, side, item[2])
	var node = _anchor(root, "Izba_%d_%d" % [int(s), int(side)], pos, stage.at(s) - pos)
	_level(node, Vector2(w * 0.5, d * 0.5), Color("5c4832"))
	var storey = 2.5
	for floor in range(floors):
		var y = floor * storey
		var shade = Color(LOG_WALL).lightened(floor * 0.04 + rng.randf_range(-0.02, 0.02))
		Props.box(node, Vector3(0, y + storey * 0.5, 0), Vector3(w, storey, d), shade)
		for course in range(5):
			Props.box(node, Vector3(0, y + 0.24 + course * (storey / 5.0), d * 0.5 + 0.015), Vector3(w, 0.035, 0.02), LOG_DARK)
	var top = floors * storey
	var ridge = _roof(node, top, w, d, 0.56, ROOF_WOOD)
	_gables(node, top, ridge, w, d * 0.5 - 0.08, Color("9c7b52"))
	_ridge_ornament(node, Vector3(0, ridge + 0.12, d * 0.5 + 0.55), 0.0)
	var columns = maxi(2, int(w / 2.4))
	for floor in range(floors):
		var y = storey * 0.5 if floor == 0 else floor * storey + storey * 0.52
		for c in range(columns):
			var x = (float(c) - (columns - 1) * 0.5) * (w / columns)
			if floor == 0 and c == columns / 2:
				var door = Props.box(node, Vector3(x, 1.05, d * 0.5 + 0.03), Vector3(1.0, 2.1, 0.06), LOG_DARK)
				door.rotation.y = 0.0
				continue
			_window(node, Vector3(x, y, d * 0.5 + 0.05), Vector2(0.78, 0.98), 0.0, (c + floor + int(s)) % 3 != 1)
	# Chimney and the smoke sever_life.gd adds above it.
	var chimney = Vector3(w * 0.22, top + (ridge - top) * 0.6, -d * 0.12)
	Props.box(node, chimney + Vector3(0, 0.8, 0), Vector3(0.55, 1.6, 0.55), Color("8f897e"))
	Props.box(node, chimney + Vector3(0, 1.62, 0), Vector3(0.66, 0.12, 0.66), SNOW)
	biome.chimneys.append(node.position + Vector3.UP * (chimney.y + 1.7))
	_porch(node, Vector3(0, 0, d * 0.5 + 0.9), w)
	stage.solids.solid(node, Vector3(0, top * 0.5, 0), Vector3(w, maxf(top, 2.0), d), "building")
	_yard_fence(node, w, d)

func _porch(node: Node3D, at: Vector3, width: float) -> void:
	var porch = Node3D.new()
	node.add_child(porch)
	porch.position = at
	Props.box(porch, Vector3(0, 1.1, 0.5), Vector3(1.9, 2.2, 1.0), Color.TRANSPARENT).hide()
	for x in [-0.85, 0.85]:
		Props.box(porch, Vector3(x, 1.1, 0.0), Vector3(0.14, 2.2, 0.14), LOG_DARK)
	var roof = Props.box(porch, Vector3(0, 2.25, 0.0), Vector3(2.1, 0.12, 1.3), ROOF_WOOD)
	roof.rotation.x = -0.18
	Props.box(porch, Vector3(0, 0.1, 0.0), Vector3(1.9, 0.2, 1.1), Color("6b5a44"))
	for step in range(2):
		Props.box(porch, Vector3(0, -0.06 - step * 0.16, 0.55 + step * 0.3), Vector3(1.6, 0.16, 0.34), Color("6b5a44"))

# A low wattle-and-picket fence around the dooryard, with a small gate. Posts
# and rails are collected into the module's batches and collide as simple
# round posts (Records.rock), like the barriers on other stages.
func _yard_fence(house: Node3D, w: float, d: float) -> void:
	var half = Vector2(w * 0.5 + 2.6, d * 0.5 + 2.2)
	var corners = [Vector2(-half.x, half.y), Vector2(half.x, half.y), Vector2(half.x, -half.y), Vector2(-half.x, -half.y)]
	for i in range(4):
		if i == 1:
			continue # street-facing side left open for the gate below
		var a2: Vector2 = corners[i]
		var b2: Vector2 = corners[(i + 1) % 4]
		_fence_run(house.to_global(Vector3(a2.x, 0, a2.y)), house.to_global(Vector3(b2.x, 0, b2.y)))
	_fence_run(house.to_global(Vector3(half.x, 0, half.y)), house.to_global(Vector3(half.x, 0, -half.y * 0.2)), true)

func _fence_run(a: Vector3, b: Vector3, gate_posts_only: bool = false) -> void:
	var length = a.distance_to(b)
	var posts = maxi(2, int(length / 1.8))
	for i in range(posts + 1):
		var p = a.lerp(b, float(i) / posts)
		p.y = stage.ground(p)
		fence_posts.append(Transform3D(Basis.from_scale(Vector3(0.05, 1.1, 0.05)), p + Vector3.UP * 0.55))
		fence_post_colors.append(FENCE)
		fence_posts.append(Transform3D(Basis.from_scale(Vector3(0.12, 0.08, 0.12)), p + Vector3.UP * 1.12))
		fence_post_colors.append(SNOW)
		stage.rocks.append(Records.rock(p, 0.1, 1.1, Records.BARRIER))
		if gate_posts_only or i >= posts:
			continue
		var q = a.lerp(b, float(i + 1) / posts)
		for rail in [0.35, 0.72]:
			fence_rails.append(beam(p + Vector3.UP * rail, q + Vector3.UP * rail, 0.0, 0.05, 0.05))
			fence_rail_colors.append(FENCE)

func _church(root: Node3D) -> void:
	var c = biome.CHURCH
	var pos = biome.place(c.s, c.side, c.offset)
	var node = _anchor(root, "VillageChurch", pos, stage.at(c.s) - pos)
	var w = 7.4
	var d = 9.6
	_level(node, Vector2(w * 0.5, d * 0.5), Color("6a5a48"))
	var walls = 5.2
	Props.box(node, Vector3(0, walls * 0.5, 0), Vector3(w, walls, d), Color("e4ddc8"))
	for course in range(7):
		Props.box(node, Vector3(0, 0.3 + course * (walls / 7.0), d * 0.5 + 0.02), Vector3(w, 0.05, 0.02), Color("c9bf9f"))
	# A steep tent roof (шатёр) over the nave, tapering to a drum and onion dome.
	var eaves = walls + 0.6
	var roof = Props.cylinder(node, Vector3(0, eaves + 3.0, 0), w * 0.62, 0.35, 6.0, ROOF_WOOD, 8)
	roof.rotation.y = PI * 0.0625
	var drum = Props.cylinder(node, Vector3(0, eaves + 6.4, 0), 0.9, 0.85, 1.6, Color("e4ddc8"), 10)
	var dome = Props.faceted(node, Vector3(0, eaves + 7.9, 0), Vector3(2.1, 1.7, 2.1), Color("c8ab4e"), 12, 7)
	Props.cylinder(node, Vector3(0, eaves + 8.9, 0), 0.07, 0.0, 1.0, Color("e8c968"), 8)
	Props.box(node, Vector3(0, eaves + 9.3, 0), Vector3(0.07, 0.8, 0.07), Color("e8c968"))
	Props.box(node, Vector3(0, eaves + 9.5, 0), Vector3(0.5, 0.06, 0.06), Color("e8c968"))
	# Entrance porch, facing the road.
	_porch(node, Vector3(0, 0, d * 0.5 + 1.1), w * 0.4)
	# Bell tower beside the nave: log base, open belfry, its own tent roof.
	var tower = Vector3(w * 0.5 + 2.6, 0, -d * 0.1)
	Props.box(node, tower + Vector3(0, 3.6, 0), Vector3(2.6, 7.2, 2.6), Color("8a6a46"))
	for course in range(10):
		Props.box(node, tower + Vector3(0, 0.3 + course * 0.72, 1.32), Vector3(2.6, 0.04, 0.02), LOG_DARK)
	var belfry = Node3D.new()
	node.add_child(belfry)
	belfry.position = tower + Vector3(0, 7.2, 0)
	for face in [Vector3(0, 0, 1.25), Vector3(0, 0, -1.25), Vector3(1.25, 0, 0), Vector3(-1.25, 0, 0)]:
		Props.box(belfry, face * 0.78 + Vector3(0, 1.0, 0), Vector3(1.0 if face.z != 0.0 else 0.08, 1.6, 0.08 if face.z != 0.0 else 1.0), Color("2a2622"))
	var bell_mesh = Props.cylinder(belfry, Vector3(0, 0.7, 0), 0.55, 0.2, 0.7, Color("9c7a3a"), 10)
	var tower_roof = Props.cylinder(belfry, Vector3(0, 2.6, 0), 2.1, 0.1, 2.4, ROOF_WOOD, 8)
	Props.box(belfry, Vector3(0, 4.0, 0), Vector3(0.06, 0.6, 0.06), Color("e8c968"))
	# A rounded footprint stands in for the nave and the tower for collision.
	stage.rocks.append(Records.rock(node.position, maxf(w, d) * 0.5 + 0.4, eaves + 9.5, Records.BUILDING))
	stage.rocks.append(Records.rock(node.to_global(tower), 1.8, 9.8, Records.BUILDING))

func _well(root: Node3D) -> void:
	var pos = biome.place(biome.WELL.s, biome.WELL.side, biome.WELL.offset)
	var node = _anchor(root, "CraneWell", pos, stage.at(biome.WELL.s) - pos)
	_level(node, Vector2(1.0, 1.0), Color("5c4832"))
	# Square log curb around the shaft.
	for sign in [-1.0, 1.0]:
		Props.box(node, Vector3(sign * 0.55, 0.45, 0), Vector3(0.14, 0.9, 1.24), LOG_DARK)
		Props.box(node, Vector3(0, 0.45, sign * 0.55), Vector3(1.24, 0.9, 0.14), LOG_DARK)
	Props.box(node, Vector3(0, 0.05, 0), Vector3(1.0, 0.1, 1.0), Color("3a3430"))
	# The upright fork and the long pivoted crane beam ("журавль").
	var fork = Props.box(node, Vector3(-0.9, 2.3, 0), Vector3(0.22, 4.6, 0.22), Color("6b5236"))
	var beam_pivot = Node3D.new()
	node.add_child(beam_pivot)
	beam_pivot.position = Vector3(-0.9, 4.4, 0)
	beam_pivot.rotation.x = -0.22
	Props.box(beam_pivot, Vector3(0, 0, -2.6), Vector3(0.16, 0.16, 5.6), Color("6b5236"))
	Props.box(beam_pivot, Vector3(0, -0.4, -5.1), Vector3(0.4, 0.4, 0.4), Color("4a4038")) # counterweight
	var rope = Props.cylinder(beam_pivot, Vector3(0, -1.3, 2.7), 0.018, 0.018, 2.0, Color("b7a47b"), 5)
	Props.cylinder(beam_pivot, Vector3(0, -2.3, 2.7), 0.16, 0.12, 0.3, Color("8f9497"), 8)
	stage.solids.solid(node, Vector3(0, 0.45, 0), Vector3(1.4, 0.9, 1.4), "landmark")

func _barn(root: Node3D) -> void:
	var b = biome.BARN
	var pos = biome.place(b.s, b.side, b.offset)
	var node = _anchor(root, "VillageBarn", pos, stage.at(b.s) - pos)
	var w = 10.0
	var d = 7.0
	_level(node, Vector2(w * 0.5, d * 0.5), Color("5c4832"))
	var walls = 3.6
	Props.box(node, Vector3(0, walls * 0.5, 0), Vector3(w, walls, d), Color("7a6248"))
	var ridge = _roof(node, walls, w, d, 0.5, ROOF_WOOD)
	_gables(node, walls, ridge, w, d * 0.5 - 0.06, Color("9c7b52"))
	Props.box(node, Vector3(0, 1.6, d * 0.5 + 0.03), Vector3(2.4, 3.2, 0.08), Color("5a4328"))
	var loft = Props.box(node, Vector3(0, walls + (ridge - walls) * 0.4, d * 0.5 + 0.03), Vector3(1.4, 1.2, 0.07), Color("2a2420"))
	for row in range(2):
		Props.box(node, Vector3(-w * 0.5 - 0.4, 0.4 + row * 0.42, 0.0), Vector3(0.7, 0.4, d * 0.6), Color("c9a85c").lightened(row * 0.05))
	stage.solids.solid(node, Vector3(0, walls * 0.5, 0), Vector3(w, walls, d), "building")

func _bridge(root: Node3D) -> void:
	var s0 = biome.BRIDGE_S - biome.BRIDGE_HALF_LENGTH
	var s1 = biome.BRIDGE_S + biome.BRIDGE_HALF_LENGTH
	var node = Node3D.new()
	node.name = "LogBridge"
	root.add_child(node)
	var width = biome.road_width(biome.BRIDGE_S)
	var rails_l: Array = []
	var rails_c: Array = []
	var posts: Array = []
	var posts_c: Array = []
	var s = s0
	while s < s1:
		var p = stage.at(s)
		p.y = stage.base_ground(p) + 0.08
		var next_s = minf(s + 2.4, s1)
		var q = stage.at(next_s)
		q.y = stage.base_ground(q) + 0.08
		for edge in [-1.0, 1.0]:
			var a = p + stage.side(s) * edge * width * 0.5
			var b = q + stage.side(next_s) * edge * width * 0.5
			rails_l.append(beam(a + Vector3.UP * 0.55, b + Vector3.UP * 0.55, 0.0, 0.14, 0.1))
			rails_c.append(LOG_DARK)
			posts.append(Transform3D(Basis.from_scale(Vector3(0.1, 0.6, 0.1)), a + Vector3.UP * 0.3))
			posts_c.append(LOG_DARK)
		var deck = beam(p, q, 0.0, 0.16, width)
		var deck_node = MeshInstance3D.new()
		deck_node.mesh = BoxMesh.new()
		deck_node.mesh.size = Vector3.ONE
		deck_node.material_override = Props.shared_material(Color("8a6e4e"))
		node.add_child(deck_node)
		deck_node.transform = deck
		s = next_s
	_batch(node, "BridgeRails", unit_box(), rails_l, rails_c)
	_batch(node, "BridgePosts", unit_box(), posts, posts_c)
	stage.solids.solid(node, (stage.at(s0) + stage.at(s1)) * 0.5 + Vector3(0, 0.6, 0), Vector3(width + 1.0, 1.2, (s1 - s0) + 1.0), "wall")
	_frozen_stream(root)

func _frozen_stream(root: Node3D) -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s = biome.BRIDGE_S
	var along = stage.direction(s)
	var across = stage.side(s)
	for i in range(-36, 36):
		var quad: Array = []
		for k in [i, i + 1]:
			var meander = sin(k * 0.17) * 2.2
			for edge in [-2.2, 2.2]:
				var p = stage.at(s) + across * k * 2.4 + along * (meander + edge)
				p.y = stage.terrain_surface_height(p) + 0.05
				quad.append(p)
		for v in [quad[0], quad[2], quad[1], quad[1], quad[2], quad[3]]:
			st.set_color(Color(0.83, 0.89, 0.91, 0.92))
			st.add_vertex(v)
	st.generate_normals()
	var ice_node = MeshInstance3D.new()
	ice_node.name = "FrozenStream"
	ice_node.mesh = st.commit()
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.1
	mat.metallic_specular = 0.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ice_node.material_override = mat
	ice_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ice_node)

func _village_sign(root: Node3D) -> void:
	var pos = biome.place(biome.SIGN_S, 1.0, 5.5)
	var node = _anchor(root, "VillageSign", pos, stage.at(biome.SIGN_S) - pos)
	for x in [-1.1, 1.1]:
		Props.cylinder(node, Vector3(x, 1.0, 0), 0.08, 0.08, 2.0, LOG_DARK, 6)
	var board = Props.box(node, Vector3(0, 1.75, 0), Vector3(2.8, 0.7, 0.1), Color("e4ddc8"))
	Props.label_3d(board, Vector3(0, 0.08, 0.06), "ПОРЕЧЬЕ", 72, 0.0055, Color("2f4a34"))
	Props.label_3d(board, Vector3(0, -0.2, 0.06), "вологодская застава", 28, 0.0035, Color("4a4238"))
	Movable.register(stage.solids, node, 18, true)

func _haystack(root: Node3D, pos: Vector3) -> void:
	pos.y = stage.ground(pos)
	var node = Node3D.new()
	node.name = "Haystack"
	root.add_child(node)
	node.position = pos
	var height = rng.randf_range(2.0, 2.7)
	var radius = height * 0.62
	Props.faceted(node, Vector3(0, height * 0.42, 0), Vector3(radius * 2.0, height * 0.82, radius * 2.0), Color("c9a85c"), 10, 6)
	Props.cylinder(node, Vector3(0, height * 0.92, 0), 0.1, 0.0, height * 0.22, Color("b79450"), 8)
	Props.faceted(node, Vector3(radius * 0.4, height * 0.08, 0), Vector3(radius * 0.7, height * 0.18, radius * 0.7), SNOW, 8, 4)
	stage.rocks.append(Records.rock(pos, radius * 0.85, height))

# Simple wooden snow stakes mark the road edge where the fields are open.
func _roadside_posts(root: Node3D) -> void:
	var poses: Array = []
	var colors: Array = []
	for station in range(10, int(biome.LENGTH) - 10, 22):
		if biome.in_village(float(station)) or absf(float(station) - biome.BRIDGE_S) < 20.0:
			continue
		for side in [-1.0, 1.0]:
			var s = float(station)
			var half = biome.road_width(s) * 0.5
			var p = stage.at(s) + stage.side(s) * side * (half + 1.3)
			if biome.reserved(p, 1.0):
				continue
			p.y = stage.ground(p) - 0.15
			poses.append(Transform3D(Basis.from_scale(Vector3(0.05, 1.2, 0.05)), p + Vector3.UP * 0.6))
			colors.append(Color("5c4c38"))
	_batch(root, "SnowStakes", unit_box(), poses, colors)

# ---------------------------------------------------------------- batching

static func unit_box() -> BoxMesh:
	var mesh = BoxMesh.new()
	mesh.size = Vector3.ONE
	return mesh

static func unit_cylinder(top: float, bottom: float, height: float, sides: int) -> CylinderMesh:
	var mesh = CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = sides
	return mesh

static var _vertex_material: StandardMaterial3D

static func _batch(root: Node3D, name: String, mesh: Mesh, poses: Array, colors: Array) -> void:
	if poses.is_empty():
		return
	if _vertex_material == null:
		_vertex_material = StandardMaterial3D.new()
		_vertex_material.vertex_color_use_as_albedo = true
		_vertex_material.roughness = 0.9
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
	node.material_override = _vertex_material
	node.set_meta("unbatched", true)
	root.add_child(node)

# ---------------------------------------------------------------- trees

func _birches(root: Node3D) -> void:
	var trunk = CylinderMesh.new()
	trunk.top_radius = 0.09
	trunk.bottom_radius = 0.16
	trunk.height = 1.0
	trunk.radial_segments = 6
	var crown = SphereMesh.new()
	crown.radial_segments = 7
	crown.rings = 4
	var trees: Array = []
	for grove in _birch_centers():
		for k in range(rng.randi_range(4, 9)):
			var p = grove + Vector3(rng.randf_range(-7, 7), 0, rng.randf_range(-7, 7))
			if stage.road_distance(p) < 10.5 or biome.reserved(p, 1.5):
				continue
			p.y = stage.terrain_surface_height(p) - 0.05
			trees.append({"base": p, "height": rng.randf_range(7.0, 13.0), "yaw": rng.randf() * TAU, "shade": rng.randf_range(-0.05, 0.06)})
	stage.woodland.tree_layers("NorthBirch", trees, [
		{"mesh": trunk, "scale": Vector3(0.055, 0.7, 0.055), "y": 0.35, "color": "e8e4da"},
		{"mesh": crown, "scale": Vector3(0.17, 0.2, 0.17), "y": 0.74, "dx": 0.08, "color": "453b2e"},
		{"mesh": crown, "scale": Vector3(0.14, 0.11, 0.14), "y": 0.92, "dx": -0.04, "color": "eef1ee"},
	])
	counts["birches"] = trees.size()

func _birch_centers() -> Array:
	var centers: Array = []
	for i in range(10):
		var s = 150.0 + i * 9.0
		centers.append(stage.at(s) + stage.side(s) * (36.0 if i % 2 == 0 else -40.0))
	for i in range(6):
		var s = 300.0 + i * 5.0
		centers.append(stage.at(s) + stage.side(s) * (20.0 if i % 2 == 0 else -22.0))
	for i in range(8):
		var s = 630.0 + i * 9.0
		centers.append(stage.at(s) + stage.side(s) * (30.0 if i % 2 == 0 else -34.0))
	return centers

func _spruces(root: Node3D) -> void:
	var trunk = CylinderMesh.new()
	trunk.top_radius = 0.1
	trunk.bottom_radius = 0.17
	trunk.height = 1.0
	trunk.radial_segments = 6
	var lower = CylinderMesh.new()
	lower.top_radius = 0.0
	lower.bottom_radius = 1.0
	lower.height = 1.0
	lower.radial_segments = 7
	var upper = CylinderMesh.new()
	upper.top_radius = 0.0
	upper.bottom_radius = 0.7
	upper.height = 1.0
	upper.radial_segments = 7
	var cap = CylinderMesh.new()
	cap.top_radius = 0.0
	cap.bottom_radius = 0.22
	cap.height = 1.0
	cap.radial_segments = 6
	var trees: Array = []
	for grove in _birch_centers():
		for k in range(rng.randi_range(2, 5)):
			var p = grove + Vector3(rng.randf_range(-9, 9), 0, rng.randf_range(-9, 9))
			if stage.road_distance(p) < 12.0 or biome.reserved(p, 1.5):
				continue
			p.y = stage.terrain_surface_height(p) - 0.05
			trees.append({"base": p, "height": rng.randf_range(8.0, 16.0), "yaw": rng.randf() * TAU, "shade": rng.randf_range(-0.05, 0.05)})
	stage.woodland.tree_layers("NorthSpruce", trees, [
		{"mesh": trunk, "scale": Vector3(0.05, 0.42, 0.05), "y": 0.21, "color": "4a3a28"},
		{"mesh": lower, "scale": Vector3(0.24, 0.62, 0.24), "y": 0.5, "color": "23402c"},
		{"mesh": upper, "scale": Vector3(0.17, 0.46, 0.17), "y": 0.78, "color": "1d3826"},
		{"mesh": cap, "scale": Vector3(0.1, 0.18, 0.1), "y": 0.95, "color": "eef2ee"},
	])
	counts["spruces"] = trees.size()

# ---------------------------------------------------------------- horizon

# A low, hazy taiga line melting into the fog at the edge of the open fields;
# flat country, not peaks.
static func build_treeline(stage) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 1902
	var root = Node3D.new()
	root.name = "DistantTreeline"
	stage.add_child(root)
	for i in range(34):
		var z = lerpf(100.0, -980.0, float(i) / 33.0) + rng.randf_range(-25.0, 25.0)
		var side = -1.0 if i % 2 == 0 else 1.0
		var p = Vector3(side * rng.randf_range(170.0, 230.0), 0, z)
		var height = rng.randf_range(10.0, 20.0)
		Props.faceted(root, p + Vector3.UP * height * 0.5, Vector3(rng.randf_range(18.0, 30.0), height, 14.0), Color("27362c").lightened(rng.randf_range(-0.03, 0.05)), 7, 3)
