extends RefCounted
# Plov as it looks in a camp kazan: a golden rice dome stained by the zirvak
# oil, carrot julienne, browned lamb, chickpeas, whole garlic heads and the
# steam holes poked into the rice. Grains, cumin, barberries and holes live in
# one procedural texture so the detail costs no extra draw calls.
const Props = preload("res://scripts/core/props.gd")
const RADIUS = 0.47
const EDGE = 0.10
const DOME = 0.15
const RAW = Color("f4ecd6")
const READY = Color("ecb466")
const HOLES = [Vector2(0.20, 0.08), Vector2(-0.12, 0.19), Vector2(-0.22, -0.06), Vector2(0.03, -0.24), Vector2(0.24, -0.15), Vector2(0.08, 0.30)]
static var _mesh: ArrayMesh
static var _texture: ImageTexture

static func height(radius: float) -> float:
	var t = clampf(radius / RADIUS, 0, 1)
	return EDGE + DOME * pow(1.0 - t * t, 0.75)

static func surface(rice: Node3D) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	node.mesh = _dome()
	var m = StandardMaterial3D.new()
	m.albedo_texture = _rice_texture()
	m.albedo_color = READY
	# Oil-coated rice catches a soft highlight, unlike the matte props around it.
	m.roughness = 0.55
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	node.material_override = m
	rice.add_child(node)
	return node

static func dress(portion: Node3D, i: int) -> void:
	# Portion 0 sits at the crown and is eaten last, so its garlic head stays to the end.
	var angle = i * 2.4
	var radius = 0.0 if i == 0 else 0.11 + (i % 3) * 0.105
	portion.position = Vector3(cos(angle) * radius, height(radius) - 0.012, sin(angle) * radius)
	var tilt = -Vector3(cos(angle), 0, sin(angle)) * radius * 0.6
	portion.rotation = Vector3(tilt.z, 0, -tilt.x)
	if i in [0, 4, 7]:
		var bulb = Props.faceted(portion, Vector3(0, 0.035, 0), Vector3(0.105, 0.085, 0.105), Color("d8bf92"), 8, 4)
		bulb.rotation.y = i
		Props.faceted(portion, Vector3(0, 0.07, 0), Vector3(0.07, 0.03, 0.07), Color("c9a46c"), 8, 3)
		Props.box(portion, Vector3(0, 0.085, 0), Vector3(0.012, 0.03, 0.012), Color("8d6a3f"))
		if i == 0:
			return
	var meat = Props.faceted(portion, Vector3(0.03, 0.018, -0.02), Vector3(0.095, 0.065, 0.08), Color("6c381f") if i % 2 == 0 else Color("7d4527"), 6, 3)
	meat.rotation = Vector3(0.3, i * 1.3, 0.2)
	Props.faceted(meat, Vector3(0.0, 0.02, 0.03), Vector3(0.05, 0.02, 0.03), Color("d9bf8e"), 5, 3)
	for j in range(3):
		var strip = Props.box(portion, Vector3(-0.045 + j * 0.035, 0.016, 0.04 - j * 0.025), Vector3(0.09, 0.016, 0.018), Color("e06a24") if (i + j) % 3 else Color("eea43a"))
		strip.rotation = Vector3(0, i * 0.9 + j * 1.1, 0.12)
	for j in range(2):
		Props.faceted(portion, Vector3(-0.05 + j * 0.09, 0.01, -0.045 + j * 0.02), Vector3.ONE * 0.03, Color("d9b067"), 6, 3)

static func _dome() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SIDES = 24
	# Skirt down to the kazan bottom, then rings up to the crown.
	var profile: Array[Vector2] = [Vector2(0.36, -0.13), Vector2(0.43, -0.02), Vector2(RADIUS, EDGE)]
	for k in range(1, 7):
		var r = RADIUS * (1.0 - k / 6.0)
		profile.append(Vector2(r, height(r)))
	for k in range(profile.size() - 1):
		for s in range(SIDES):
			var quad = []
			for corner in [[k, s], [k + 1, s], [k + 1, s + 1], [k, s + 1]]:
				var a = corner[1] * TAU / SIDES
				var p = profile[corner[0]]
				# A little lumpiness so the dome is not a perfect lathe shape.
				var lump = 0.0 if p.x < 0.01 or p.y < EDGE else sin(a * 5 + p.x * 23) * 0.007 + sin(a * 3 - p.x * 31) * 0.005
				quad.append(Vector3(cos(a) * p.x, p.y + lump, sin(a) * p.x))
			# The skirt widens and the dome narrows, so their windings are opposite.
			for index in ([0, 1, 2, 0, 2, 3] if profile[k + 1].x > profile[k].x else [0, 2, 1, 0, 3, 2]):
				var v: Vector3 = quad[index]
				st.set_uv(Vector2(v.x, v.z) / (RADIUS * 2) + Vector2(0.5, 0.5))
				st.add_vertex(v)
	st.index()
	st.generate_normals()
	_mesh = st.commit()
	return _mesh

static func _rice_texture() -> ImageTexture:
	if _texture != null:
		return _texture
	const SIZE = 384
	var rng = RandomNumberGenerator.new()
	rng.seed = 2207
	# Colours are tinted by the material: neutral grains read golden when ready, pale while raw.
	var image = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color("a8875e"))
	var stamps = []
	for colour in [Color("fffaee"), Color("f6ead2"), Color("eedcb8"), Color("ffffff")]:
		for step in range(8):
			stamps.append(_grain(colour, step * PI / 8))
	for i in range(14000):
		var stamp: Image = stamps[rng.randi() % stamps.size()]
		image.blend_rect(stamp, Rect2i(Vector2i.ZERO, stamp.get_size()), Vector2i(rng.randi_range(-4, SIZE - 4), rng.randi_range(-4, SIZE - 4)))
	var carrot = [_grain(Color("ff8a3a"), 0, 14, 2.2), _grain(Color("ff9e46"), PI / 3, 14, 2.2), _grain(Color("ffb84e"), -PI / 4, 12, 2.0), _grain(Color("ff7a30"), PI / 2, 14, 2.2)]
	for i in range(700):
		var stamp: Image = carrot[rng.randi() % carrot.size()]
		image.blend_rect(stamp, Rect2i(Vector2i.ZERO, stamp.get_size()), Vector2i(rng.randi_range(0, SIZE - 14), rng.randi_range(0, SIZE - 14)))
	var cumin = _grain(Color("4a3420"), PI / 5, 5, 0.9)
	for i in range(500):
		image.blend_rect(cumin, Rect2i(Vector2i.ZERO, cumin.get_size()), Vector2i(rng.randi_range(0, SIZE - 5), rng.randi_range(0, SIZE - 5)))
	for i in range(140):
		_disc(image, Vector2(rng.randf_range(4, SIZE - 4), rng.randf_range(4, SIZE - 4)), 1.6, Color("8a1a26"), Color("b8323a"))
	for hole in HOLES:
		var c = (hole / (RADIUS * 2) + Vector2(0.5, 0.5)) * SIZE
		_disc(image, c, 8.0, Color("3a2412"), Color("6e4a28"))
	image.generate_mipmaps()
	_texture = ImageTexture.create_from_image(image)
	return _texture

static func _grain(colour: Color, angle: float, length: float = 7.0, width: float = 1.6) -> Image:
	var size = int(ceil(length)) + 1
	var image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var axis = Vector2(cos(angle), sin(angle))
	var centre = Vector2(size, size) * 0.5
	for y in range(size):
		for x in range(size):
			var d = Vector2(x + 0.5, y + 0.5) - centre
			var along = d.dot(axis) / (length * 0.5)
			var across = d.dot(axis.orthogonal()) / (width * 0.5)
			var e = along * along + across * across
			if e < 1.0:
				# Lit on one flank, shaded on the other, so grains read as round.
				image.set_pixel(x, y, Color(colour.darkened(0.18 * clampf(across, 0, 1)), clampf((1.0 - e) * 3.0, 0, 1)))
	return image

static func _disc(image: Image, centre: Vector2, radius: float, inner: Color, rim: Color) -> void:
	for y in range(int(centre.y - radius - 1), int(centre.y + radius + 2)):
		for x in range(int(centre.x - radius - 1), int(centre.x + radius + 2)):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			var t = Vector2(x + 0.5, y + 0.5).distance_to(centre) / radius
			if t < 1.0:
				image.set_pixel(x, y, inner.lerp(rim, smoothstep(0.45, 1.0, t)))
