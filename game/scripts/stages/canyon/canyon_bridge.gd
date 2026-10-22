extends RefCounted
# The footbridge over the Charyn (canyon.gd): a glass-decked suspension bridge
# slung between two steel portals on the lips of the gorge, from the
# spectator area out on the near rim to the far table, where a footpath leads
# to a meadow with a camp of its own. From there the crowd watches the rim
# road and the bench road across the gorge, and the bench road passes ~37 m
# under the deck.
#
# The deck is a walking surface of stage.solids (people only, never car
# contact), so a walker in the gorge below is never lifted onto it. Its glass
# railings are walls for the feet (fenced()), the portal legs, the backstay
# anchors and a bollard at each end are rock circles, so a car cannot follow
# a walker onto it.
const Form = preload("res://scripts/stages/canyon/canyon_form.gd")
const Records = preload("res://scripts/stages/stage_records.gd")
const MeshMerge = preload("res://scripts/core/mesh_merge.gd")

# World z the bridge crosses at, picked where both lips are clear of the
# caprock knobs and the near end lands beside the rim camp (station 410).
const Z = -338.0
# How far onto the table each end runs past its portal, and where the portal
# stands back from the lip.
const LANDING = 6.0
const PORTAL_BACK = 1.5
const HALF_WIDTH = 1.2
const RAIL = 1.1
# Portal tops over the deck, the cable's lowest point over it at mid-span,
# and the run of the backstays behind each portal.
const TOWER = 15.0
const SAG_LOW = 1.4
const BACKSTAY = 7.0
const PANEL = 2.5
# The far meadow: how far back from the far lip and downstream of the bridge.
const MEADOW_BACK = 14.0
const MEADOW_DOWNSTREAM = 28.0
const PATH_HALF = 0.75

var stage
# Deck top at the near (a) and far (b) ends, on the table.
var a := Vector3.ZERO
var b := Vector3.ZERO
# Where the two portals stand along the deck, 0..1 from a.
var near_portal := 0.0
var far_portal := 1.0
var along := Vector3.ZERO
var across := Vector3.ZERO
var meadow := Vector3.ZERO
var path: PackedVector3Array = PackedVector3Array()
var surface: Dictionary = {}

# Lays the bridge out on the land; call from configure() before the meadow
# clearing exists (it would not move the ends, but keeps them independent).
func configure(owner_stage) -> void:
	stage = owner_stage
	var axis = Form.axis_x(Z)
	var near_lip = axis + Form.rim_edge(Z, 1.0)
	var far_lip = axis - Form.rim_edge(Z, -1.0)
	var near_end = Vector3(near_lip + LANDING, 0.0, Z)
	var far_end = Vector3(far_lip - LANDING, 0.0, Z)
	# Each end stands on the table as it was (cut() is still off here).
	near_end.y = stage.base_ground(near_end) + 0.08
	far_end.y = stage.base_ground(far_end) + 0.08
	a = near_end
	b = far_end
	along = Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
	across = Vector3.UP.cross(along).normalized()
	var length = Vector2(b.x - a.x, b.z - a.z).length()
	near_portal = (LANDING - PORTAL_BACK) / length
	far_portal = 1.0 - (LANDING - PORTAL_BACK) / length
	var mid = (a + b) * 0.5
	var pose = Transform3D(Basis(across, Vector3.UP, along), Vector3(mid.x, a.y, mid.z))
	surface = {"pose": pose, "inverse": pose.affine_inverse(), "half": Vector2(HALF_WIDTH, length * 0.5), "reach": length, "rise": b.y - a.y}
	stage.solids.walk_surfaces.append(surface)
	meadow = Vector3(far_lip - MEADOW_BACK, 0.0, Z - MEADOW_DOWNSTREAM)
	meadow.y = stage.base_ground(meadow)
	# The path leaves the deck straight, then bends downstream to the meadow.
	var bend = b + along * 6.0 + Vector3(0.0, 0.0, -5.0)
	var points = [b, b + along * 2.5, bend, bend.lerp(meadow, 0.5) + along * 2.0, meadow + (b - meadow).normalized() * 5.0]
	path = PackedVector3Array()
	for i in range(points.size() - 1):
		var count = maxi(1, ceili(Vector2(points[i + 1].x - points[i].x, points[i + 1].z - points[i].z).length()))
		for step in range(count):
			path.append(points[i].lerp(points[i + 1], float(step) / count))
	path.append(points[-1])

# Deck top at a fraction t of the way from a to b.
func deck(t: float) -> Vector3:
	return a.lerp(b, t)

# (t along the deck, lateral offset) of a point; t is 0..1 between the ends.
func local(pos: Vector3) -> Vector2:
	var offset = Vector3(pos.x - a.x, 0.0, pos.z - a.z)
	var length = Vector2(b.x - a.x, b.z - a.z).length()
	return Vector2(offset.dot(along) / length, offset.dot(across))

# Highest the land may stand under and beside the deck: the bridgeheads are
# dug in so the drawn ground never shows through the glass, easing back to the
# table a few metres to either side. INF away from the bridge.
func cut(pos: Vector3) -> float:
	if a == b or pos.x > a.x + 1.0 or pos.x < b.x - 1.0 or absf(pos.z - a.z) > 12.0:
		return INF
	var p = local(pos)
	var length = Vector2(b.x - a.x, b.z - a.z).length()
	var lateral = absf(p.y) - HALF_WIDTH - 1.0
	var beyond = maxf(-p.x, p.x - 1.0) * length
	return deck(clampf(p.x, 0.0, 1.0)).y - 0.25 + maxf(0.0, lateral) * 0.35 + maxf(0.0, beyond) * 0.5

# The glass railings: a walker at deck height cannot step through them, on to
# the deck from the side or off it into the gorge. Only the last metre of each
# end is open. People far below in the gorge are not affected.
func fenced(pos: Vector3, feet_height: float) -> bool:
	if a == b:
		return false
	var p = local(pos)
	var length = Vector2(b.x - a.x, b.z - a.z).length()
	if p.x * length < 1.0 or (1.0 - p.x) * length < 1.0:
		return false
	var lateral = absf(p.y)
	if lateral < HALF_WIDTH - 0.25 or lateral > HALF_WIDTH + 1.0:
		return false
	var top = deck(clampf(p.x, 0.0, 1.0)).y
	return feet_height > top - 2.5 and feet_height < top + RAIL + 0.2

# The deck, the portals, the anchors and the path: scenery keeps off them.
func keeps_clear(p: Vector3, padding: float = 0.0) -> bool:
	if a == b:
		return false
	var q = local(p)
	var length = Vector2(b.x - a.x, b.z - a.z).length()
	if q.x * length > -BACKSTAY - 2.0 - padding and (q.x - 1.0) * length < BACKSTAY + 2.0 + padding and absf(q.y) < HALF_WIDTH + 1.8 + padding:
		return true
	return path_distance(p) < PATH_HALF + 0.6 + padding

func path_distance(p: Vector3) -> float:
	var nearest = INF
	var flat = Vector2(p.x, p.z)
	for i in range(path.size() - 1):
		var closest = Geometry2D.get_closest_point_to_segment(flat, Vector2(path[i].x, path[i].z), Vector2(path[i + 1].x, path[i + 1].z))
		nearest = minf(nearest, flat.distance_to(closest))
	return nearest

# A camp on the far side stays on its own side: across the gorge there is no
# way to the road but back over the bridge.
func far_side(p: Vector3) -> bool:
	return Vector2(p.x - meadow.x, p.z - meadow.z).length() < 30.0

# A place on the far lip, level with `home`, with the bench road in full view
# across the gorge (from the meadow itself the lip hides it).
func lookout(home: Vector3) -> Vector3:
	var p = Vector3(Form.axis_x(home.z) - Form.rim_edge(home.z, -1.0) - 3.0, 0.0, home.z)
	p.y = stage.ground(p)
	return p

# ---------------------------------------------------------------- build

func build(parent: Node3D) -> Node3D:
	var root = Node3D.new()
	root.name = "CharynFootbridge"
	parent.add_child(root)
	var steel = SurfaceTool.new()
	steel.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glass = SurfaceTool.new()
	glass.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stone = SurfaceTool.new()
	stone.begin(Mesh.PRIMITIVE_TRIANGLES)
	_deck(steel, glass)
	_portals(steel, stone)
	_cables(steel)
	_abutments(stone)
	_add(root, "Steel", steel, _steel_material())
	_add(root, "Glass", glass, _glass_material())
	_add(root, "Concrete", stone, _stone_material())
	var trail = _path_mesh()
	trail.name = "MeadowPath"
	root.add_child(trail)
	_meadow_flowers()
	return root

# Short grass and wild tulips, poppies and camomile round the meadow's edge,
# where the camp leaves room.
func _meadow_flowers() -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 22102026
	var poses: Array = []
	var colors: Array = []
	var blooms = [Color("d8433a"), Color("e9d24a"), Color("f2efe4"), Color("b46ad1")]
	for i in range(420):
		var angle = rng.randf() * TAU
		var distance = sqrt(rng.randf_range(49.0, 256.0))
		var p = meadow + Vector3(cos(angle), 0.0, sin(angle)) * distance
		var flower = i % 3 == 0
		var size = rng.randf_range(0.25, 0.45) if flower else rng.randf_range(0.5, 0.9)
		var tall = rng.randf_range(0.35, 0.6) if flower else rng.randf_range(0.5, 0.9)
		var tint = rng.randf()
		if path_distance(p) < PATH_HALF + 0.3:
			continue
		p.y = stage.terrain_surface_height(p)
		poses.append(Transform3D(Basis(Vector3.UP, angle * 3.0).scaled(Vector3(size, tall, size)), p))
		colors.append(blooms[i % blooms.size()].lerp(Color.WHITE, tint * 0.15) if flower else Color("6f8f3c").lerp(Color("93a24e"), tint))
	stage.detail_batch("CharynMeadow", stage.NATURE_GRASS, poses, colors)

const STEEL = Color("b9aaa2")
const STEEL_DARK = Color("6f6460")
const GLASS = Color(0.62, 0.86, 0.93, 0.32)

func _deck(steel: SurfaceTool, glass: SurfaceTool) -> void:
	var length = Vector2(b.x - a.x, b.z - a.z).length()
	var panels = maxi(2, roundi(length / PANEL))
	# Edge beams and the glass floor on top of them.
	for side in [-1.0, 1.0]:
		_beam(steel, a + across * side * (HALF_WIDTH - 0.1) - Vector3.UP * 0.2, b + across * side * (HALF_WIDTH - 0.1) - Vector3.UP * 0.2, Vector2(0.2, 0.34), STEEL)
	_slab(glass, a - Vector3.UP * 0.04, b - Vector3.UP * 0.04, HALF_WIDTH - 0.05, 0.06, Color(0.70, 0.90, 0.95, 0.55))
	for i in range(panels + 1):
		var t = float(i) / panels
		var p = deck(t)
		# Cross beams under every joint of the floor.
		_beam(steel, p - across * HALF_WIDTH - Vector3.UP * 0.25, p + across * HALF_WIDTH - Vector3.UP * 0.25, Vector2(0.14, 0.16), STEEL_DARK)
		for side in [-1.0, 1.0]:
			var edge = p + across * side * HALF_WIDTH
			# Railing posts with the glass between them and a steel handrail.
			_beam(steel, edge, edge + Vector3.UP * RAIL, Vector2(0.07, 0.07), STEEL)
			if i < panels:
				var next = deck(float(i + 1) / panels) + across * side * HALF_WIDTH
				_panel(glass, edge + Vector3.UP * 0.08, next + Vector3.UP * 0.08, RAIL - 0.16, GLASS)
				_beam(steel, edge + Vector3.UP * RAIL, next + Vector3.UP * RAIL, Vector2(0.08, 0.06), STEEL)
				# A shallow Warren truss under the span between the portals.
				if t >= near_portal - 0.001 and float(i + 1) / panels <= far_portal + 0.001:
					var low = p + across * side * (HALF_WIDTH - 0.1) - Vector3.UP * 1.3
					var low_next = next - across * side * 0.1 - Vector3.UP * 1.3
					_beam(steel, low, low_next, Vector2(0.12, 0.12), STEEL_DARK)
					_beam(steel, edge - across * side * 0.1 - Vector3.UP * 0.3, low_next, Vector2(0.08, 0.08), STEEL_DARK)
					_beam(steel, edge - across * side * 0.1 - Vector3.UP * 0.3, low, Vector2(0.08, 0.08), STEEL_DARK)

func _portals(steel: SurfaceTool, stone: SurfaceTool) -> void:
	for t in [near_portal, far_portal]:
		var p = deck(t)
		var ground = stage.base_ground(p)
		for side in [-1.0, 1.0]:
			var leg = p + across * side * (HALF_WIDTH + 0.55)
			var foot = Vector3(leg.x, minf(ground, stage.base_ground(leg)) - 1.5, leg.z)
			_beam(steel, foot, leg + Vector3.UP * TOWER, Vector2(0.62, 0.62), STEEL)
			_beam(stone, foot + Vector3.UP * 0.6, Vector3(leg.x, stage.base_ground(leg) + 0.35, leg.z), Vector2(1.2, 1.2), Color("b7a894"))
			stage.rocks.append(Records.rock(Vector3(leg.x, foot.y, leg.z), 0.45, p.y + TOWER - foot.y, Records.BUILDING))
		# Cross beams at the top and under the deck tie the legs into a portal.
		for height in [TOWER - 0.4, TOWER - 3.2, -1.45]:
			_beam(steel, p - across * (HALF_WIDTH + 0.55) + Vector3.UP * height, p + across * (HALF_WIDTH + 0.55) + Vector3.UP * height, Vector2(0.45, 0.5), STEEL)
	# A bollard in the middle of each entrance: wide enough for people, not
	# for a car.
	for t in [0.0, 1.0]:
		var end = deck(t) + along * (0.5 if t == 0.0 else -0.5)
		_beam(steel, end - Vector3.UP * 0.1, end + Vector3.UP * 0.9, Vector2(0.18, 0.18), STEEL_DARK)
		stage.rocks.append(Records.rock(end - Vector3.UP * 0.1, 0.12, 1.0, Records.POST))

# Main cables hanging from the portal tops, hangers down to the deck edges and
# backstays out to an anchor block behind each portal.
func _cables(steel: SurfaceTool) -> void:
	var top_a = deck(near_portal) + Vector3.UP * (TOWER - 0.4)
	var top_b = deck(far_portal) + Vector3.UP * (TOWER - 0.4)
	for side in [-1.0, 1.0]:
		var lateral = across * side * (HALF_WIDTH + 0.12)
		var previous = top_a + lateral
		var steps = 28
		for i in range(1, steps + 1):
			var u = float(i) / steps
			var point = _cable(u, top_a, top_b) + lateral
			_beam(steel, previous, point, Vector2(0.09, 0.09), STEEL_DARK)
			previous = point
		var hangers = roundi((far_portal - near_portal) * Vector2(b.x - a.x, b.z - a.z).length() / PANEL)
		for i in range(1, hangers):
			var u = float(i) / hangers
			var top = _cable(u, top_a, top_b) + lateral
			var foot = deck(lerpf(near_portal, far_portal, u)) + lateral + Vector3.UP * RAIL
			if top.y - foot.y > 0.15:
				_beam(steel, foot, top, Vector2(0.035, 0.035), STEEL)
		for end in [[top_a, -1.0], [top_b, 1.0]]:
			var top: Vector3 = end[0] + lateral
			var anchor = top + along * float(end[1]) * BACKSTAY + across * side * 0.6
			anchor.y = stage.base_ground(anchor)
			_beam(steel, top, anchor + Vector3.UP * 0.7, Vector2(0.08, 0.08), STEEL_DARK)
			_beam(steel, anchor - Vector3.UP * 0.6, anchor + Vector3.UP * 0.8, Vector2(1.0, 1.0), Color("a99a87"))
			stage.rocks.append(Records.rock(anchor - Vector3.UP * 0.6, 0.6, 1.4, Records.BUILDING))

func _cable(u: float, top_a: Vector3, top_b: Vector3) -> Vector3:
	var straight = top_a.lerp(top_b, u)
	var low = lerpf(top_a.y, top_b.y, 0.5) - deck(0.5).y - SAG_LOW - 0.4
	return straight - Vector3.UP * low * 4.0 * u * (1.0 - u)

# Concrete under each landing, from the end of the deck to the portal, so the
# deck rests on something where it runs over the table.
func _abutments(stone: SurfaceTool) -> void:
	for range_t in [[0.0, near_portal], [far_portal, 1.0]]:
		var from = deck(range_t[0])
		var to = deck(range_t[1])
		var low = minf(minf(stage.base_ground(from), stage.base_ground(to)), stage.base_ground((from + to) * 0.5)) - 1.0
		var top = minf(from.y, to.y) - 0.38
		_slab(stone, Vector3(from.x, top, from.z), Vector3(to.x, top, to.z), HALF_WIDTH - 0.05, top - low, Color("b9ab98"))

# A strip of trodden earth draped over the drawn land from the far end of the
# deck to the meadow.
func _path_mesh() -> MeshInstance3D:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var earth = Color("9c7f5c")
	for i in range(path.size() - 1):
		var p0 = path[i]
		var p1 = path[i + 1]
		var dir = Vector3(p1.x - p0.x, 0.0, p1.z - p0.z).normalized()
		var side = Vector3.UP.cross(dir).normalized() * PATH_HALF
		var corners = [p0 - side, p0 + side, p1 + side, p1 - side]
		for j in range(4):
			corners[j].y = stage.terrain_surface_height(corners[j]) + 0.05
		var shade = earth.lightened(sin(float(i) * 1.7) * 0.04)
		for index in [0, 1, 2, 0, 2, 3]:
			st.set_color(shade)
			st.set_normal(Vector3.UP)
			st.add_vertex(corners[index])
	var node = MeshInstance3D.new()
	node.mesh = st.commit()
	var mat = MeshMerge.material(true, 1.0, 0.0)
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

# ---------------------------------------------------------------- geometry

func _add(root: Node3D, node_name: String, st: SurfaceTool, mat: Material) -> void:
	st.generate_normals()
	var node = MeshInstance3D.new()
	node.name = node_name
	node.mesh = st.commit()
	node.material_override = mat
	root.add_child(node)

# A box of cross-section `size` (width, height) from a to b.
func _beam(st: SurfaceTool, from: Vector3, to: Vector3, size: Vector2, color: Color) -> void:
	var dir = to - from
	if dir.length() < 0.001:
		return
	dir = dir.normalized()
	var side = (Vector3.UP if absf(dir.y) < 0.95 else along).cross(dir).normalized()
	var up = dir.cross(side).normalized()
	_box(st, from, to, side * size.x * 0.5, up * size.y * 0.5, color)

# A flat slab of half width `half` and thickness `depth` under the line a-b.
func _slab(st: SurfaceTool, from: Vector3, to: Vector3, half: float, depth: float, color: Color) -> void:
	var dir = Vector3(to.x - from.x, 0.0, to.z - from.z).normalized()
	var side = Vector3.UP.cross(dir).normalized() * half
	var down = Vector3.UP * depth * 0.5
	_box(st, from - down, to - down, side, down, color)

# A vertical pane between two posts, `height` tall.
func _panel(st: SurfaceTool, from: Vector3, to: Vector3, height: float, color: Color) -> void:
	var dir = Vector3(to.x - from.x, 0.0, to.z - from.z).normalized()
	_box(st, from + Vector3.UP * height * 0.5, to + Vector3.UP * height * 0.5, Vector3.UP.cross(dir).normalized() * 0.015, Vector3.UP * height * 0.5, color)

# Box with its two end faces centred on from and to; `side` and `up` are half
# extents.
func _box(st: SurfaceTool, from: Vector3, to: Vector3, side: Vector3, up: Vector3, color: Color) -> void:
	var c = [from - side - up, from + side - up, from + side + up, from - side + up, to - side - up, to + side - up, to + side + up, to - side + up]
	for quad in [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]:
		for index in [quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]]:
			st.set_color(color)
			st.add_vertex(c[index])

func _steel_material() -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.metallic = 0.55
	mat.roughness = 0.38
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

func _glass_material() -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.2
	mat.roughness = 0.08
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

func _stone_material() -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
