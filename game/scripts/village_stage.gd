extends RefCounted
# «Виноградники · провансальская деревня». Deterministic geometry shared by
# driving, walking, camp placement and rendering, in the same shape as
# canyon.gd and finnish_forest.gd: stage.gd asks this module for the route,
# ground, grip, widths and pace, and calls build() for the scenery.
const Layout = preload("res://scripts/village_layout.gd")
const Architecture = preload("res://scripts/village_architecture.gd")
const Landscape = preload("res://scripts/village_landscape.gd")
const Batcher = preload("res://scripts/primitive_batcher.gd")
const LENGTH = 840.0
const TABLE_STEP = 0.5
const ROAD_BLEND = 11.0

var stage
var batcher = Batcher.new("VillageDetail_")
var table_xz = PackedVector2Array()
var table_y = PackedFloat32Array()
var flats: Array[Dictionary] = []
var square: Dictionary = {}
var architecture
var landscape
# Planting requests from the architecture (fig trees in gardens, cypresses).
var hints: Dictionary = {}
# Plain-data spots for the village life (chimneys, café chairs, benches, ...).
# Saved with the baked scene, so life can be rebuilt without rebuilding scenery.
var anchors: Dictionary = {}
# Counters and anchors kept for tests, life and tools.
var counts: Dictionary = {}

func _init() -> void:
	_sample_route()

# ---------------------------------------------------------------- route

# Centripetal Catmull-Rom through the authored plan, resampled by arc length.
func _sample_route() -> void:
	var dense: Array[Vector2] = []
	var points: Array = Layout.CONTROL_POINTS.duplicate()
	points.push_front(points[0] * 2.0 - points[1])
	points.append(points[-1] * 2.0 - points[-2])
	for i in range(1, points.size() - 2):
		var p0: Vector2 = points[i - 1]
		var p1: Vector2 = points[i]
		var p2: Vector2 = points[i + 1]
		var p3: Vector2 = points[i + 2]
		var t0 = 0.0
		var t1 = t0 + sqrt(p0.distance_to(p1))
		var t2 = t1 + sqrt(p1.distance_to(p2))
		var t3 = t2 + sqrt(p2.distance_to(p3))
		for k in range(48):
			var t = lerpf(t1, t2, k / 48.0)
			var a1 = p0 * ((t1 - t) / (t1 - t0)) + p1 * ((t - t0) / (t1 - t0))
			var a2 = p1 * ((t2 - t) / (t2 - t1)) + p2 * ((t - t1) / (t2 - t1))
			var a3 = p2 * ((t3 - t) / (t3 - t2)) + p3 * ((t - t2) / (t3 - t2))
			var b1 = a1 * ((t2 - t) / (t2 - t0)) + a2 * ((t - t0) / (t2 - t0))
			var b2 = a2 * ((t3 - t) / (t3 - t1)) + a3 * ((t - t1) / (t3 - t1))
			dense.append(b1 * ((t2 - t) / (t2 - t1)) + b2 * ((t - t1) / (t2 - t1)))
	dense.append(Layout.CONTROL_POINTS[-1])
	var count = int((LENGTH + 4.0) / TABLE_STEP) + 1
	table_xz.resize(count)
	var travelled = 0.0
	var index = 0
	for i in range(count):
		var target = i * TABLE_STEP
		while index < dense.size() - 2 and travelled + dense[index].distance_to(dense[index + 1]) < target:
			travelled += dense[index].distance_to(dense[index + 1])
			index += 1
		var length = maxf(dense[index].distance_to(dense[index + 1]), 0.0001)
		table_xz[i] = dense[index].lerp(dense[index + 1], clampf((target - travelled) / length, 0.0, 1.5))
	# The road follows the land, smoothed along the route so crests stay drivable.
	var raw = PackedFloat32Array()
	raw.resize(count)
	for i in range(count):
		raw[i] = landform(table_xz[i].x, table_xz[i].y)
	table_y.resize(count)
	var radius = int(14.0 / TABLE_STEP)
	for i in range(count):
		var total = 0.0
		var weight = 0.0
		for j in range(maxi(0, i - radius), mini(count, i + radius + 1)):
			var w = exp(-pow(float(j - i) * TABLE_STEP / 7.0, 2.0))
			total += raw[j] * w
			weight += w
		table_y[i] = total / weight

func route(s: float) -> Vector3:
	var t = clampf(s, 0.0, LENGTH + 3.0) / TABLE_STEP
	var i = mini(int(t), table_xz.size() - 2)
	var f = t - i
	var xz = table_xz[i].lerp(table_xz[i + 1], f)
	return Vector3(xz.x, lerpf(table_y[i], table_y[i + 1], f), xz.y)

# Plateau in the south, the village hill, the vineyard slope down to the valley.
func landform(x: float, z: float) -> float:
	var north = -z
	var height = 10.0 + clampf(north, 0.0, 380.0) * 0.004
	height += 2.2 * exp(-(pow(x + 32.0, 2.0) + pow(north - 410.0, 2.0)) / 7200.0)
	height -= 9.5 * smoothstep(470.0, 650.0, north)
	var calm = smoothstep(55.0, 120.0, Vector2(x + 32.0, north - 410.0).length())
	height += (sin(x * 0.035 + z * 0.021) * 0.9 + sin(z * 0.052 - x * 0.028) * 0.55 + sin(x * 0.11) * sin(z * 0.09) * 0.25) * calm
	# Hills rise towards the map edge and frame the horizon.
	height += maxf(0.0, absf(x) - 135.0) * 0.16 + maxf(0.0, north - 700.0) * 0.05
	return height

# ---------------------------------------------------------------- sections

func section(s: float) -> Dictionary:
	for item in Layout.SECTIONS:
		if s < item.to:
			return item
	return Layout.SECTIONS[-1]

func _blended(s: float, key: String) -> float:
	var total = 0.0
	var weight = 0.0
	for item in Layout.SECTIONS:
		var w = smoothstep(item.from - Layout.BLEND, item.from + Layout.BLEND, s) * (1.0 - smoothstep(item.to - Layout.BLEND, item.to + Layout.BLEND, s))
		if item.from <= 0.0 and s < Layout.BLEND:
			w = 1.0 - smoothstep(item.to - Layout.BLEND, item.to + Layout.BLEND, s)
		total += float(item[key]) * w
		weight += w
	return total / maxf(weight, 0.0001)

func surface(s: float) -> String:
	return section(s).surface

func in_village(s: float) -> bool:
	return s >= Layout.VILLAGE.x and s <= Layout.VILLAGE.y

func road_width(s: float) -> float:
	return _blended(s, "width")

func rally_speed(s: float) -> float:
	var speed = _blended(s, "speed")
	if s > Layout.HAIRPIN.x - 14.0 and s < Layout.HAIRPIN.y + 6.0:
		speed = minf(speed, Layout.HAIRPIN_SPEED)
	return speed

func roughness(s: float) -> float:
	match surface(s):
		"cobble":
			return sin(s * 3.4) * 0.012 + sin(s * 7.1) * 0.006
		"gravel":
			return sin(s * 0.55) * 0.04 + sin(s * 1.7) * 0.015
	return sin(s * 0.8) * 0.012

# Wheel ruts and a loose crown on the gravel tracks; asphalt is cambered.
func relief(s: float, lateral: float) -> float:
	match surface(s):
		"gravel":
			var rut = -exp(-pow((absf(lateral) - 0.85) / 0.26, 2.0)) * 0.07
			return rut + sin(s * 0.32 + lateral * 0.7) * 0.02 - 0.008 * lateral * lateral
		"asphalt":
			return -0.006 * lateral * lateral
	return 0.0

# Usable verge for overtaking and corner cutting. Plane trees, the village
# signs, pavements and house fronts leave no room beside the carriageway.
func shoulder(s: float) -> float:
	if s > Layout.PLANE_AVENUE.x - 6.0 and s < Layout.VILLAGE.y + 6.0:
		return 0.15
	return 1.4

func pavement(s: float) -> bool:
	if not in_village(s) or (s > 382.0 and s < 446.0):
		return false # The square side is open paving rather than a raised kerb.
	for alley in Layout.ALLEYS:
		if absf(s - alley) < 2.2:
			return false
	return true

# ---------------------------------------------------------------- terrain

func configure(owner_stage) -> void:
	stage = owner_stage
	var sq = Layout.SQUARE
	var center = anchor(sq.s, sq.lateral, sq.along)
	square = {"center": center, "yaw": yaw_at(sq.s), "half": sq.size * 0.5, "height": route(sq.s).y + Layout.KERB * 0.5}
	flats.append({"center": center, "yaw": square.yaw, "half": square.half, "height": square.height, "margin": 6.0})
	for item in Layout.FLATS:
		var p = anchor(item[0], item[1], item[2])
		flats.append({"center": p, "yaw": yaw_at(item[0]), "half": Vector2(item[3], item[4]) * 0.5, "height": landform(p.x, p.z), "margin": item[5]})
	for spot in Layout.CLEARINGS:
		var p: Vector3
		if spot is String:
			p = square.center + Basis(Vector3.UP, float(square.yaw)) * Vector3(Layout.SQUARE_CLEARING.x, 0, Layout.SQUARE_CLEARING.y)
		else:
			p = anchor(spot[0], spot[1] * spot[2])
		p.y = ground(p)
		stage.clearings.append(p)

# Point in route coordinates; y left at zero until the ground is sampled.
func anchor(s: float, lateral: float, along: float = 0.0) -> Vector3:
	var p: Vector3 = route(s) + side(s) * lateral + direction(s) * along
	return Vector3(p.x, 0.0, p.z)

func direction(s: float) -> Vector3:
	var d = route(minf(s + 1.5, LENGTH + 2.0)) - route(maxf(s - 1.5, 0.0))
	d.y = 0.0
	return d.normalized()

func side(s: float) -> Vector3:
	return direction(s).cross(Vector3.UP).normalized()

# Yaw of a node whose local -Z faces along the road.
func yaw_at(s: float) -> float:
	var d = direction(s)
	return atan2(-d.x, -d.z)

func _flat_weight(flat: Dictionary, pos: Vector3) -> float:
	var local = (Vector2(pos.x, pos.z) - Vector2(flat.center.x, flat.center.z)).rotated(float(flat.yaw))
	var outside = Vector2(maxf(absf(local.x) - flat.half.x, 0.0), maxf(absf(local.y) - flat.half.y, 0.0)).length()
	return 1.0 - smoothstep(0.0, float(flat.margin), outside)

func ground(pos: Vector3) -> float:
	var nearest: Dictionary = stage.route_nearest(pos)
	var s: float = nearest.s
	var road: Vector3 = route(s)
	var distance: float = nearest.distance
	var half = road_width(s) * 0.5
	var lateral = (pos - road).dot(side(s))
	var height = road.y + roughness(s) + relief(s, clampf(lateral, -half, half))
	var edge = half
	if pavement(s):
		edge += Layout.PAVEMENT
		if distance > half:
			height = road.y + Layout.KERB
	var land = landform(pos.x, pos.z)
	# Cuts and embankments widen with the height difference: no slope steeper
	# than about one in three between the road and the hillside.
	var span = maxf(ROAD_BLEND, absf(land - road.y) * 4.5)
	height = lerpf(height, land, smoothstep(edge + 0.6, edge + span, distance))
	var keep_road = smoothstep(half + 0.4, half + 2.0, distance)
	for flat in flats:
		var w = _flat_weight(flat, pos) * keep_road
		if w > 0.0:
			height = lerpf(height, float(flat.height), w)
	return height

func tile_step(p: Vector3) -> float:
	var nearest: Dictionary = stage.route_nearest(p)
	var edge = road_width(nearest.s) * 0.5 + (Layout.PAVEMENT if pavement(nearest.s) else 0.0)
	# Metre tiles only where kerbs and pavements need them, in the village.
	if nearest.distance < edge + 4.0 and in_village(nearest.s):
		return 1.0
	return 2.0 if nearest.distance < edge + 14.0 else 4.0

func grip(pos: Vector3) -> float:
	var nearest: Dictionary = stage.route_nearest(pos)
	var s: float = nearest.s
	if nearest.distance > road_width(s) * 0.55:
		return 0.55
	match surface(s):
		"cobble":
			return 0.84
		"gravel":
			return 0.46 if int(s / 4.0) % 15 == 7 else 0.72
	return 1.0

# Gravel is thrown only from loose tracks and the verges.
func loose(pos: Vector3) -> bool:
	var nearest: Dictionary = stage.route_nearest(pos)
	return surface(nearest.s) == "gravel" or nearest.distance > road_width(nearest.s) * 0.6

func terrain_color(v: Vector3) -> Color:
	var nearest: Dictionary = stage.route_nearest(v)
	var s: float = nearest.s
	var patch = (sin(v.x * 0.061) * sin(v.z * 0.043) + 1.0) * 0.5
	# Sun-dried olive grass, brown earth under lavender, red-brown under vines.
	var color = Color("5f6438").lerp(Color("7f7646"), patch)
	if s < Layout.LAVENDER.y + 10.0:
		color = color.lerp(Color("6e5c43"), 0.45)
	elif s > Layout.VINES.x - 10.0:
		color = color.lerp(Color("7d5a3c"), 0.5)
	if in_village(s) and nearest.distance < 45.0:
		color = Color("7d7458").lerp(Color("6c6a45"), patch * 0.6)
	if nearest.distance > road_width(s) * 0.5 and nearest.distance < road_width(s) * 0.5 + 2.2:
		color = color.lerp(Color("8f8164"), 0.5) # dusty verge
	return color

func road_color(p: Vector3, s: float, lateral: float) -> Color:
	var shade = sin(p.x * 0.17 + p.z * 0.11) * 0.025 + sin(p.z * 0.29 - p.x * 0.07) * 0.015
	match surface(s):
		"cobble":
			return Color("a39886").lightened(shade)
		"gravel":
			var track = exp(-pow((absf(lateral) - 0.85) / 0.3, 2.0))
			var crown = exp(-pow(lateral / 0.5, 2.0))
			return Color("8a7f6a").darkened(track * 0.18).lightened(crown * 0.05 + shade)
	# Patched asphalt with a pale worn centre, as on a departmental road.
	var patchwork = smoothstep(0.55, 0.8, sin(p.x * 0.09 + p.z * 0.05) * sin(p.z * 0.13))
	return Color("434543").lerp(Color("55554f"), patchwork * 0.6).lightened(shade)

# Cobbles are textured; the other surfaces keep vertex colours.
func road_material(kind: String) -> StandardMaterial3D:
	var mat = RallyProps.material(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if kind == "cobble":
		mat.albedo_texture = cobble_texture()
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return mat

static var _cobbles: ImageTexture

# Staggered rounded setts with darker joints; tinted by vertex colour.
static func cobble_texture() -> ImageTexture:
	if _cobbles != null:
		return _cobbles
	var size = 128
	var image = Image.create(size, size, false, Image.FORMAT_RGB8)
	var random = RandomNumberGenerator.new()
	random.seed = 1789
	var tones: Dictionary = {}
	for y in range(size):
		var row = int(y / 16)
		for x in range(size):
			var shifted = x + (8 if row % 2 else 0)
			var column = int(shifted / 16) % 8
			var key = Vector2i(column, row)
			if not tones.has(key):
				tones[key] = random.randf_range(0.82, 1.08)
			var u = float(posmod(shifted, 16)) / 16.0 - 0.5
			var v = float(y % 16) / 16.0 - 0.5
			var round = 1.0 - smoothstep(0.30, 0.48, maxf(absf(u), absf(v) * 1.05))
			var dome = 1.0 - (u * u + v * v) * 0.7
			var value = lerpf(0.42, float(tones[key]) * dome, round)
			image.set_pixel(x, y, Color(value, value * 0.97, value * 0.92))
	image.generate_mipmaps()
	_cobbles = ImageTexture.create_from_image(image)
	return _cobbles

# ---------------------------------------------------------------- scenery

func build(cooperative: bool = false) -> void:
	architecture = Architecture.new(self)
	landscape = Landscape.new(self)
	await architecture.build(cooperative)
	await landscape.build(cooperative)
	# Summary kept with the baked scene, where the generators no longer exist.
	counts.merge({"houses": architecture.house_count, "shops": architecture.shop_count,
		"lavender": landscape.lavender_count, "vines": landscape.vine_count,
		"figs": landscape.fig_count, "trees": landscape.tree_count}, true)
	batcher.flush(stage)
	stage.solids.index()

func add_anchor(kind: String, value) -> void:
	if not anchors.has(kind):
		anchors[kind] = []
	anchors[kind].append(value)

func make_life():
	var life = preload("res://scripts/village_life.gd").new()
	life.build(stage)
	return life

func landscape_hint(kind: String, p: Vector3) -> void:
	if not hints.has(kind):
		hints[kind] = []
	hints[kind].append(p)

# Coroutine-friendly pause for the cooperative (web) loader.
func pause(cooperative: bool) -> void:
	if cooperative:
		await stage.get_tree().process_frame
