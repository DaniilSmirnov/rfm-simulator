extends RefCounted
# The countryside beyond the roadside crops: a patchwork of fields on a slightly
# skewed grid of farm tracks, as seen from the village hill. Each parcel is one
# crop — lavender, wheat, sunflowers, vines or an olive grove — or fallow
# garrigue with an occasional farmhouse (mas). Cypress windbreaks against the
# mistral line some parcels. Everything is batched; nothing here is collectible.
const Props = preload("res://scripts/props.gd")
const Layout = preload("res://scripts/village_layout.gd")
const DetailLayer = preload("res://scripts/detail_layer.gd")
const LAVENDER_TEXTURE = preload("res://textures/nature/lavender.svg")

const PARCEL = Vector2(30.0, 24.0)
const TRACK = 3.5
const GRID_YAW = 0.11
const BOUNDS = Rect2(-194.0, -914.0, 388.0, 988.0)
const ROAD_CLEARANCE = 9.0
# Crop mix per zone: [crop, weight]. Zones follow the route map.
const ZONES = [
	{"until": 255.0, "mix": [["lavender", 45], ["wheat", 28], ["sunflower", 12], ["fallow", 15]]},
	{"until": 545.0, "mix": [["olive", 34], ["wheat", 24], ["lavender", 20], ["fallow", 22]]},
	{"until": 2000.0, "mix": [["vines", 58], ["olive", 14], ["wheat", 12], ["fallow", 16]]},
]
const FARMHOUSES = 5

var village
var stage
var landscape
var architecture
var rng = RandomNumberGenerator.new()
var parcels: Array[Dictionary] = []
var counts: Dictionary = {}
# Olive trees for the landscape's shared olive layers.
var olives: Array = []

func _init(owner_landscape) -> void:
	landscape = owner_landscape
	village = owner_landscape.village
	stage = owner_landscape.stage
	architecture = owner_landscape.architecture
	rng.seed = 14071789

func build(cooperative: bool = false) -> void:
	_lay_out()
	await village.pause(cooperative)
	_farmhouses()
	_lavender_fields()
	await village.pause(cooperative)
	_wheat_fields()
	_sunflower_fields()
	await village.pause(cooperative)
	_vine_blocks()
	_olive_groves()
	_windbreaks()
	for parcel in parcels:
		counts[parcel.crop] = int(counts.get(parcel.crop, 0)) + 1
	village.counts["parcels"] = parcels.size()

# ---------------------------------------------------------------- layout

func _basis() -> Basis:
	return Basis(Vector3.UP, GRID_YAW)

# World point of a parcel-local offset (x across, z along the parcel).
func local(parcel: Dictionary, x: float, z: float) -> Vector3:
	return parcel.center + _basis() * Vector3(x, 0, z)

func _zone_crop(north: float) -> String:
	for zone in ZONES:
		if north < zone.until:
			var total = 0
			for item in zone.mix:
				total += int(item[1])
			var roll = rng.randi_range(1, total)
			for item in zone.mix:
				roll -= int(item[1])
				if roll <= 0:
					return item[0]
	return "fallow"

func _parcel_free(center: Vector3, half: Vector2) -> bool:
	for u in range(5):
		for v in range(5):
			var p = center + _basis() * Vector3(lerpf(-half.x, half.x, u / 4.0), 0, lerpf(-half.y, half.y, v / 4.0))
			if not BOUNDS.has_point(Vector2(p.x, p.z)):
				return false
			var nearest: Dictionary = stage.route_nearest(p)
			if nearest.distance < village.road_width(nearest.s) * 0.5 + ROAD_CLEARANCE:
				return false
			# Keep the village outskirts open: gardens, alleys and the cemetery.
			if village.in_village(nearest.s) and nearest.distance < 30.0:
				return false
			for flat in village.flats:
				if village._flat_weight(flat, p) > 0.0:
					return false
			for clearing in stage.clearings:
				if Vector2(p.x - clearing.x, p.z - clearing.z).length() < 14.0:
					return false
			if not landscape.crop_clear(p, 3.0) or not architecture.open_ground(p, 2.0):
				return false
	return true

func _lay_out() -> void:
	var pitch = PARCEL + Vector2(TRACK, TRACK)
	var span = int(ceil(BOUNDS.size.length() / minf(pitch.x, pitch.y) * 0.5)) + 1
	var origin = Vector3(BOUNDS.get_center().x, 0, BOUNDS.get_center().y)
	for i in range(-span, span + 1):
		for j in range(-span, span + 1):
			var center = origin + _basis() * Vector3(i * pitch.x, 0, j * pitch.y)
			if not BOUNDS.grow(-12.0).has_point(Vector2(center.x, center.z)):
				continue
			if _parcel_free(center, PARCEL * 0.5):
				_add_parcel(center, PARCEL * 0.5)
				continue
			# Near the road and the village a full parcel rarely fits: split it
			# into quarter fields so the patchwork reaches the roadside crops.
			for qx in [-1.0, 1.0]:
				for qz in [-1.0, 1.0]:
					var quarter = PARCEL * 0.25
					var middle = center + _basis() * Vector3(qx * (quarter.x + TRACK * 0.25), 0, qz * (quarter.y + TRACK * 0.25))
					var half = quarter - Vector2(TRACK, TRACK) * 0.25
					if _parcel_free(middle, half):
						_add_parcel(middle, half)

func _add_parcel(center: Vector3, half: Vector2) -> void:
	var parcel = {"center": center, "half": half, "crop": _zone_crop(-center.z), "seed": rng.randi()}
	parcels.append(parcel)
	if parcel.crop != "fallow":
		_register(parcel)

# Crop footprints keep oaks, shrubs and flowers out of the fields.
func _register(parcel: Dictionary) -> void:
	var half: Vector2 = parcel.half
	var x = -half.x
	while x <= half.x:
		var z = -half.y
		while z <= half.y:
			landscape.register_crop(local(parcel, x, z))
			z += 3.0
		x += 3.0

func _of(crop: String) -> Array:
	return parcels.filter(func(item): return item.crop == crop)

# ---------------------------------------------------------------- crops

# Rounded flowering rows, the same texture as the roadside lavender.
func _lavender_fields() -> void:
	var builders = {}
	var profile = [Vector2(-0.6, 0.02), Vector2(-0.42, 0.3), Vector2(-0.2, 0.5), Vector2(0, 0.56), Vector2(0.2, 0.5), Vector2(0.42, 0.3), Vector2(0.6, 0.02)]
	var across = _basis() * Vector3.BACK
	for parcel in _of("lavender"):
		var half: Vector2 = parcel.half
		var tint = Color("8257b8").lerp(Color("a47fd0"), float(parcel.seed % 100) / 100.0)
		var z = -half.y + 0.8
		while z < half.y:
			var previous: Array[Vector3] = []
			var x = -half.x
			while x <= half.x + 0.01:
				var p = landscape.surface(local(parcel, x, z))
				var section: Array[Vector3] = []
				for shape in profile:
					var vertex = landscape.surface(p + across * shape.x)
					vertex.y += shape.y
					section.append(vertex)
				if not previous.is_empty():
					var tile = Vector2i(floori(p.x / 64.0), floori(p.z / 64.0))
					if not builders.has(tile):
						builders[tile] = SurfaceTool.new()
						builders[tile].begin(Mesh.PRIMITIVE_TRIANGLES)
					var builder: SurfaceTool = builders[tile]
					for strip in range(profile.size() - 1):
						var colour = Color("53684a") if strip == 0 or strip == profile.size() - 2 else tint
						for vertex in [previous[strip], section[strip + 1], section[strip], previous[strip], previous[strip + 1], section[strip + 1]]:
							builder.set_color(colour)
							builder.set_uv(Vector2(vertex.x, vertex.z) * 0.85)
							builder.add_vertex(vertex)
				previous = section
				x += 2.5
			z += 2.4
	var material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.albedo_texture = LAVENDER_TEXTURE
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_commit(builders, "LavenderFields", material)

# Ripe wheat: a raised golden surface with tractor lines and a stubble edge.
func _wheat_fields() -> void:
	var builders = {}
	var step = 2.0
	for parcel in _of("wheat"):
		var half: Vector2 = parcel.half
		var ripe = Color("d6b35a").lerp(Color("c99d48"), float(parcel.seed % 100) / 100.0)
		var height = 0.55
		var nx = int(half.x * 2.0 / step)
		var nz = int(half.y * 2.0 / step)
		var top = func(i: int, j: int) -> Vector3:
			var p = landscape.surface(local(parcel, -half.x + i * step, -half.y + j * step))
			var edge = i == 0 or j == 0 or i == nx or j == nz
			p.y += 0.02 if edge else height + sin(p.x * 0.7 + p.z * 0.4) * 0.04
			return p
		var tile = Vector2i(floori(parcel.center.x / 64.0), floori(parcel.center.z / 64.0))
		if not builders.has(tile):
			builders[tile] = SurfaceTool.new()
			builders[tile].begin(Mesh.PRIMITIVE_TRIANGLES)
		var builder: SurfaceTool = builders[tile]
		for i in range(nx):
			for j in range(nz):
				# Lighter and darker passes of the combine across the field.
				var colour = ripe.lightened(0.06) if (j / 2) % 2 == 0 else ripe.darkened(0.03)
				var a = top.call(i, j)
				var b = top.call(i + 1, j)
				var c = top.call(i, j + 1)
				var d = top.call(i + 1, j + 1)
				for vertex in [a, c, b, b, c, d]:
					builder.set_color(colour)
					builder.add_vertex(vertex)
	var material = RallyProps.material(Color.WHITE)
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_commit(builders, "WheatFields", material)

func _commit(builders: Dictionary, name: String, material: Material) -> void:
	var tiles = builders.keys()
	tiles.sort()
	for tile in tiles:
		var builder: SurfaceTool = builders[tile]
		builder.index()
		builder.generate_normals()
		var node = MeshInstance3D.new()
		node.name = "%s_%d_%d" % [name, tile.x, tile.y]
		node.mesh = builder.commit()
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stage.add_child(node)

# Sunflowers in rows, heads turned to the morning sun.
func _sunflower_fields() -> void:
	var stems: Array = []
	var stem_colors: Array = []
	var heads: Array = []
	var head_colors: Array = []
	# Discs face east (+X) and nod slightly towards the ground.
	var east = Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.RIGHT, 0.35)
	for parcel in _of("sunflower"):
		var half: Vector2 = parcel.half
		var x = -half.x + 0.6
		while x < half.x:
			var z = -half.y + 0.6
			while z < half.y:
				var p = landscape.surface(local(parcel, x + sin(z * 3.1) * 0.12, z))
				var h = 1.35 + sin(x * 1.7 + z * 2.3) * 0.18
				stems.append(Transform3D(Basis.from_scale(Vector3(0.05, h, 0.05)), p + Vector3.UP * h * 0.5))
				stem_colors.append(Color("5d7a32"))
				heads.append(Transform3D(east.scaled(Vector3(0.42, 0.42, 0.12)), p + Vector3(0.08, h, 0)))
				head_colors.append(Color("e8b923").lerp(Color("f2cf3a"), (sin(x * 5.0 + z) + 1.0) * 0.5))
				heads.append(Transform3D(east.scaled(Vector3(0.2, 0.2, 0.08)), p + Vector3(0.13, h, 0)))
				head_colors.append(Color("4a3020"))
				z += 1.1
			x += 1.25
	counts["sunflowers"] = heads.size() / 2
	var stem_mesh = CylinderMesh.new()
	stem_mesh.top_radius = 0.5
	stem_mesh.bottom_radius = 0.5
	stem_mesh.height = 1.0
	stem_mesh.radial_segments = 4
	stem_mesh.rings = 1
	stage.detail_batch("SunflowerStems", stem_mesh, stems, stem_colors, DetailLayer.tiled(230.0))
	stage.detail_batch("SunflowerHeads", architecture._sphere(1.0, 8, 3), heads, head_colors, DetailLayer.tiled(300.0))

# Trained vine rows with posts and wires; the collectible grapes stay roadside.
func _vine_blocks() -> void:
	var leaves: Array = []
	var leaf_colors: Array = []
	var posts: Array = []
	var post_colors: Array = []
	var basis = _basis()
	for parcel in _of("vines"):
		var half: Vector2 = parcel.half
		var green = Color("4f6b30").lerp(Color("7a8a3a"), float(parcel.seed % 100) / 100.0)
		var z = -half.y + 1.2
		while z < half.y:
			var x = -half.x
			while x <= half.x:
				var p = landscape.surface(local(parcel, x, z))
				if fposmod(x + half.x, 6.0) < 0.1:
					posts.append(Transform3D(basis.scaled(Vector3(0.07, 1.5, 0.07)), p + Vector3.UP * 0.7))
					post_colors.append(Color("7b6a52"))
				if x < half.x:
					var leaf = landscape.surface(local(parcel, x + 0.75, z))
					leaves.append(Transform3D((basis * Basis(Vector3.UP, PI * 0.5)).scaled(Vector3(0.6, 0.62, 1.7)), leaf + Vector3.UP * 1.05))
					leaf_colors.append(green.lightened(sin(x * 0.9 + z) * 0.05))
				x += 1.5
			z += 2.6
	counts["vine_leaves"] = leaves.size()
	stage.detail_batch("FieldVineLeaves", architecture._sphere(1.0, 6, 3), leaves, leaf_colors, DetailLayer.tiled(300.0))
	var post = CylinderMesh.new()
	post.top_radius = 0.5
	post.bottom_radius = 0.5
	post.height = 1.0
	post.radial_segments = 4
	post.rings = 1
	stage.detail_batch("FieldVinePosts", post, posts, post_colors, DetailLayer.tiled(160.0))

# Olive groves on a regular planting grid; rendered with the roadside olives.
func _olive_groves() -> void:
	for parcel in _of("olive"):
		var half: Vector2 = parcel.half
		var x = -half.x + 3.0
		while x < half.x:
			var z = -half.y + 3.0
			while z < half.y:
				var p = landscape.surface(local(parcel, x + rng.randf_range(-0.4, 0.4), z + rng.randf_range(-0.4, 0.4)))
				olives.append({"base": p - Vector3.UP * 0.05, "height": rng.randf_range(3.4, 4.8), "yaw": rng.randf() * TAU, "shade": rng.randf_range(-0.05, 0.06)})
				z += 6.0
			x += 7.0

# Cypress hedges on the north side of a third of the parcels: windbreaks.
func _windbreaks() -> void:
	var planted = 0
	for parcel in parcels:
		if parcel.crop == "fallow" or parcel.seed % 3 != 0:
			continue
		var half: Vector2 = parcel.half
		var x = -half.x
		while x <= half.x:
			village.landscape_hint("cypress", local(parcel, x, -half.y - TRACK * 0.5))
			planted += 1
			x += 3.4
	counts["windbreak_cypresses"] = planted

# A few farmhouses on the fallow parcels furthest from the road.
func _farmhouses() -> void:
	var candidates: Array = []
	for parcel in _of("fallow"):
		if parcel.half.x < PARCEL.x * 0.5:
			continue # Farmhouses need a whole parcel.
		var nearest: Dictionary = stage.route_nearest(parcel.center)
		candidates.append([float(nearest.distance), parcel])
	candidates.sort_custom(func(a, b): return a[0] > b[0])
	var built = 0
	for item in candidates:
		if built >= FARMHOUSES:
			break
		var parcel: Dictionary = item[1]
		# Never two farms side by side.
		var lonely = true
		for other in parcels:
			if other.get("farm", false) and other.center.distance_to(parcel.center) < 90.0:
				lonely = false
		if not lonely:
			continue
		parcel.farm = true
		var yaw = GRID_YAW + (PI if built % 2 else 0.0)
		var front = architecture.grounded(local(parcel, -2.0, -5.0))
		architecture.house(front, yaw, 13.0, 8.0, 2, 30 + built * 7)
		# A barn alongside and a pair of cypresses at the gate, as on every mas.
		var barn = architecture.grounded(local(parcel, 10.5, -3.5))
		architecture.house(barn, yaw, 7.0, 6.0, 1, 41 + built * 5, {}, true, false)
		for k in [-1.0, 1.0]:
			village.landscape_hint("cypress", local(parcel, -2.0 + k * 3.0, -9.5))
		built += 1
	counts["farmhouses"] = built
