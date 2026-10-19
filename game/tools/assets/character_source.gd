extends RefCounted

const FOOD_PORTIONS = 10
# Joint pivots below the hip and the shoulder (m), see character_rig.gd.
const KNEE = 0.33
const ELBOW = 0.22
# How much higher a "big" build's head sits: a longer torso and neck over the
# rig's usual shoulders and hips.
const TALL = 0.13
const CARGO_KINDS = ["table", "chairs", "grill", "firewood", "cauldron"]

static func material(color: Color) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.95
	return m

static func box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var n = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = size
	n.mesh = mesh
	n.material_override = material(color)
	parent.add_child(n)
	n.position = pos
	return n

static func cylinder(parent: Node3D, pos: Vector3, bottom: float, top: float, height: float, color: Color, sides: int = 7) -> MeshInstance3D:
	var n = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.bottom_radius = bottom
	mesh.top_radius = top
	mesh.height = height
	mesh.radial_segments = sides
	n.mesh = mesh
	n.material_override = material(color)
	parent.add_child(n)
	n.position = pos
	return n

const CharacterProfiles = preload("res://scripts/people/character_profiles.gd")
const SPECTATOR_MODELS = CharacterProfiles.SPECTATOR_MODELS

static func spectator_profile(variant: int, outfit: String = "") -> Dictionary:
	return CharacterProfiles.profile(variant, outfit)

# Shared smooth primitive geometry is baked into GLB, never built in gameplay.
static func rounded(parent: Node3D, pos: Vector3, size: Vector3, color: Color, _sides: int = 24, _rings: int = 8) -> MeshInstance3D:
	var sphere = SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 24
	sphere.rings = 8
	var part = MeshInstance3D.new()
	part.mesh = sphere
	part.material_override = material(color)
	parent.add_child(part)
	part.position = pos
	part.scale = size
	return part

# Smooth capsule with rounded ends and enough geometry for the reference silhouette.
static func capsule(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var outline = []
	for i in range(24):
		var angle = TAU * i / 24.0
		outline.append(Vector2(sin(angle), -cos(angle)))
	var levels = [Vector2(-0.5, 0.15), Vector2(-0.48, 0.48), Vector2(-0.44, 0.78), Vector2(-0.35, 1), Vector2(0.35, 1), Vector2(0.44, 0.78), Vector2(0.48, 0.48), Vector2(0.5, 0.15)]
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var rings = []
	for level in levels:
		var ring = []
		for point in outline:
			ring.append(Vector3(point.x * size.x * 0.5 * level.y, level.x * size.y, point.y * size.z * 0.5 * level.y))
		rings.append(ring)
	for r in range(levels.size() - 1):
		for i in range(24):
			var j = (i + 1) % 24
			capsule_triangle(vertices, normals, rings[r][i], rings[r + 1][i], rings[r + 1][j])
			capsule_triangle(vertices, normals, rings[r][i], rings[r + 1][j], rings[r][j])
	for i in range(24):
		capsule_triangle(vertices, normals, Vector3(0, -size.y * 0.5, 0), rings[0][i], rings[0][(i + 1) % 24])
		capsule_triangle(vertices, normals, Vector3(0, size.y * 0.5, 0), rings[levels.size() - 1][i], rings[levels.size() - 1][(i + 1) % 24])
	var surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(0)
	for vertex in vertices:
		surface.add_vertex(vertex)
	surface.generate_normals()
	var mesh = surface.commit()
	var node = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material(color)
	parent.add_child(node)
	node.position = pos
	return node

static func capsule_triangle(vertices: PackedVector3Array, normals: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	# Godot front faces use clockwise winding.
	if (b - a).cross(c - a).dot(a + b + c) > 0:
		var swap = b
		b = c
		c = swap
	var normal = (c - a).cross(b - a).normalized()
	vertices.append_array(PackedVector3Array([a, b, c]))
	normals.append_array(PackedVector3Array([normal, normal, normal]))

static func player_avatar(variant: int = 0, outfit: String = "") -> Node3D:
	var profile = spectator_profile(variant, outfit)
	var winter = profile.get("outfit", "") == "winter"
	var big = profile.get("build", "") == "big"
	var skin = Color(profile.skin)
	var shirt = Color(profile.shirt)
	var trim_color = Color(profile.trim)
	var pants = Color(profile.pants)
	var hair_color = Color(profile.hair)
	var root = Node3D.new()
	root.name = "RallySpectator"
	root.set_meta("model", profile.name)
	root.set_meta("variant", posmod(variant, SPECTATOR_MODELS.size()))
	# Rounded cartoon silhouette; original skin and clothing profiles are retained.
	if winter:
		_winter_jacket(root, profile)
	elif big:
		capsule(root, Vector3(0, 1.09, 0), Vector3(0.72, 0.84, 0.44), shirt)
	else:
		capsule(root, Vector3(0, 1.03, 0), Vector3(0.58, 0.70, 0.38) if profile.get("female", false) else Vector3(0.64, 0.70, 0.40), shirt)
		for side in [-1, 1]:
			var trim = box(root, Vector3(side * 0.22, 1.30, -0.14), Vector3(0.12, 0.12, 0.15), trim_color)
			trim.rotation.z = side * 0.25
			box(root, Vector3(side * 0.27, 0.94, 0), Vector3(0.06, 0.35, 0.29), trim_color)
		# A tiny geometric palm emblem instead of a texture.
		box(root, Vector3(0, 1.10, -0.205), Vector3(0.025, 0.15, 0.012), trim_color)
		for angle in [-0.9, -0.45, 0.45, 0.9]:
			var leaf = box(root, Vector3(0, 1.19, -0.21), Vector3(0.025, 0.17, 0.013), trim_color)
			leaf.rotation.z = angle
	if profile.get("patch_vest", false):
		_patch_vest(root, profile, (0.25 if big else 0.22) if winter else (0.22 if big else 0.20), 0.39 if big else 0.34)
	rounded(root, Vector3(0, 0.69, 0), Vector3(0.58, 0.31, 0.40) if big else (Vector3(0.54, 0.30, 0.37) if winter else Vector3(0.52, 0.28, 0.35)), pants)
	if not winter and not big:
		box(root, Vector3(0, 0.77, -0.20), Vector3(0.47, 0.06, 0.03), Color("515c62"))
	for side in [-1, 1]:
		var leg = Node3D.new()
		leg.name = "LeftLeg" if side < 0 else "RightLeg"
		root.add_child(leg)
		leg.position = Vector3(side * 0.17, 0.65, 0)
		cylinder(leg, Vector3(0, -0.055, 0), 0.105, 0.115, 0.22, pants, 6)
		# Thigh and shin meet at the knee pivot; the rounded ends overlap so
		# the joint stays closed when the knee bends.
		var leg_color = pants if profile.long_pants else skin
		var leg_width = (0.20 if winter else 0.18) if profile.long_pants else 0.15
		leg_width += 0.02 if big else 0.0
		capsule(leg, Vector3(0, -0.215, 0), Vector3(leg_width, 0.25, 0.19), leg_color)
		var shin = Node3D.new()
		shin.name = "LeftShin" if side < 0 else "RightShin"
		leg.add_child(shin)
		shin.position = Vector3(0, -KNEE, 0)
		capsule(shin, Vector3(0, -0.10, 0), Vector3(leg_width * 0.96, 0.25, 0.18), leg_color)
		if winter:
			_snow_boot(shin)
		else:
			box(shin, Vector3(0, -0.26, -0.065), Vector3(0.20, 0.10, 0.32), Color("564933"))
			box(shin, Vector3(0, -0.20, -0.12), Vector3(0.20, 0.065, 0.10), Color("737b75"))
			box(shin, Vector3(0, -0.17, 0.055), Vector3(0.19, 0.11, 0.07), Color("737b75"))
		var arm = Node3D.new()
		arm.name = "LeftArm" if side < 0 else "RightArm"
		root.add_child(arm)
		arm.position = Vector3(side * 0.34, 1.29, 0)
		capsule(arm, Vector3(0, -0.09, 0), (Vector3(0.22, 0.32, 0.23) if winter else Vector3(0.19, 0.31, 0.20)) + (Vector3(0.03, 0.01, 0.03) if big else Vector3.ZERO), shirt if profile.sleeves else skin)
		# Forearm and hand turn at the elbow pivot.
		var forearm = Node3D.new()
		forearm.name = "LeftForearm" if side < 0 else "RightForearm"
		arm.add_child(forearm)
		forearm.position = Vector3(0, -ELBOW, 0)
		if winter:
			_mitten(forearm, side, profile)
			continue
		capsule(forearm, Vector3(0, -0.10, 0), Vector3(0.15, 0.32, 0.17), shirt if profile.hat == "beanie" else skin)
		capsule(forearm, Vector3(0, -0.27, -0.015), Vector3(0.15, 0.17, 0.12), skin)

		# Three readable fingers and thumb, merged into the forearm mesh on export.
		for finger in range(3):
			capsule(forearm, Vector3(-0.047 + finger * 0.047, -0.36, -0.015), Vector3(0.036, 0.10, 0.055), skin)
		var thumb = capsule(forearm, Vector3(-side * 0.086, -0.28, -0.005), Vector3(0.055, 0.11, 0.07), skin)
		thumb.rotation.z = side * 0.35

	var head = Node3D.new()
	head.name = "Head"
	root.add_child(head)
	head.position = Vector3(0, 1.62 + (TALL if big else 0.0), 0)
	capsule(head, Vector3.ZERO, Vector3(0.60, 0.84, 0.52), skin)
	for side in [-1, 1]:
		var eye = rounded(head, Vector3(side * 0.15, 0.12, -0.275), Vector3(0.28, 0.31, 0.22), Color("f5f2e7"), 10, 5)
		eye.name = "LeftEye" if side < 0 else "RightEye"
		rounded(head, Vector3(side * 0.15 + 0.014, 0.12, -0.382), Vector3(0.085, 0.095, 0.03), Color("182226"), 8, 4)
		box(head, Vector3(side * 0.15 + 0.002, 0.14, -0.401), Vector3(0.019, 0.022, 0.009), Color("ffffff"))
	var style = profile.get("hair_style", "short")
	if profile.get("female", false):
		box(head, Vector3(0, -0.16, -0.265), Vector3(0.16, 0.034, 0.016), Color("bf4f5c"))
	else:
		box(head, Vector3(0, -0.16, -0.265), Vector3(0.22, 0.018, 0.012), Color("875244"))
	var hair = rounded(head, Vector3(0, 0.38, 0.015), Vector3(0.66, 0.25, 0.54), hair_color, 10, 4)
	hair.name = "Quiff"
	_face_extras(head, profile, hair_color)
	if style == "bald":
		hair.hide()
	for i in range(3 if profile.hat == "" and style != "bald" else 0):
		var tuft = rounded(head, Vector3(-0.18 + i * 0.18, 0.465 + i * 0.01, -0.13), Vector3(0.20, 0.24, 0.32), hair_color.lightened(0.06 + i * 0.016), 7, 3)
		tuft.rotation.z = -0.25
	if profile.beard:
		rounded(head, Vector3(0, -0.235, -0.08), Vector3(0.48, 0.32, 0.44), hair_color, 8, 4)
		box(head, Vector3(0, -0.14, -0.293), Vector3(0.19, 0.06, 0.055), hair_color)
		box(head, Vector3(0, -0.19, -0.305), Vector3(0.12, 0.025, 0.02), Color("553228"))
	if winter:
		hair.hide()
		_winter_hat(root, head, profile)
	elif profile.hat != "":
		hair.hide()
		var hat_color = Color(profile.get("hat_color", "b43c32" if profile.hat == "cap" else "3f694b"))
		if profile.hat == "panama":
			rounded(head, Vector3(0, 0.41, 0), Vector3(0.64, 0.30, 0.57), hat_color, 10, 4)
			cylinder(head, Vector3(0, 0.33, 0), 0.47, 0.47, 0.03, hat_color.darkened(0.06), 12)
			cylinder(head, Vector3(0, 0.38, 0), 0.325, 0.325, 0.05, Color(profile.trim), 12)
			return root
		rounded(head, Vector3(0, 0.38, 0), Vector3(0.70, 0.32, 0.59), hat_color, 10, 4)
		if profile.hat == "cap":
			var visor = box(head, Vector3(0, 0.315, -0.37), Vector3(0.53, 0.055, 0.35), hat_color)
			visor.rotation.x = 0.13
			box(head, Vector3(0, 0.44, -0.265), Vector3(0.12, 0.09, 0.018), trim_color)
		else:
			cylinder(head, Vector3(0, 0.325, 0), 0.345, 0.345, 0.12, hat_color.lightened(0.10), 10)
			rounded(head, Vector3(0, 0.57, 0), Vector3(0.13, 0.13, 0.13), hat_color, 7, 3)
			# Folded hood and drawstrings remain below the face.
			rounded(root, Vector3(0, 1.33, 0.14), Vector3(0.53, 0.18, 0.37), shirt.lightened(0.08), 8, 4)
			for x in [-0.10, 0.10]:
				box(root, Vector3(x, 1.23, -0.215), Vector3(0.015, 0.21, 0.015), trim_color)
	return root

# ---------------------------------------------------------------- winter

# Puffer jacket a little fuller than the shirt, so the marshal's vest and the
# medic's coat still fit over it; quilted seams, a zip and a scarf.
static func _winter_jacket(root: Node3D, profile: Dictionary) -> void:
	var jacket = Color(profile.shirt)
	var big = profile.get("build", "") == "big"
	# A big build: wider, deeper and taller.
	var k = Vector3(1.12, 1.0, 1.14) if big else Vector3.ONE
	var lift = 0.06 if big else 0.0
	capsule(root, Vector3(0, 1.03 + lift, 0), Vector3(0.68, 0.74 + lift * 2.0, 0.44) * k, jacket)
	for y in [0.86, 1.02, 1.18]:
		rounded(root, Vector3(0, y + lift, 0), Vector3(0.695, 0.035, 0.455) * k, jacket.darkened(0.18), 24, 4)
	rounded(root, Vector3(0, 0.71, 0), Vector3(0.60, 0.07, 0.41) * k, jacket.darkened(0.25), 24, 4)
	box(root, Vector3(0, 1.0 + lift, -0.226 * k.z), Vector3(0.03, 0.56, 0.012), Color(profile.trim))
	var scarf = Color(profile.scarf)
	rounded(root, Vector3(0, 1.31 + (TALL if big else 0.0), -0.03), Vector3(0.64, 0.15, 0.56) * k, scarf, 24, 6)
	var tail = box(root, Vector3(0.11, 1.13 + lift, -0.285 * k.z - (0.03 if profile.get("patch_vest", false) else 0.0)), Vector3(0.11, 0.30, 0.035), scarf)
	tail.rotation.z = 0.12
	for y in [1.04, 1.10]:
		box(tail, Vector3(0, y - 1.13, -0.019), Vector3(0.112, 0.022, 0.004), scarf.lightened(0.45))

static func _snow_boot(shin: Node3D) -> void:
	var boot = Color("3c3531")
	box(shin, Vector3(0, -0.265, -0.065), Vector3(0.22, 0.11, 0.33), boot)
	cylinder(shin, Vector3(0, -0.19, 0), 0.115, 0.12, 0.16, boot, 10)
	cylinder(shin, Vector3(0, -0.10, 0), 0.125, 0.125, 0.055, Color("ebe4d6"), 10)
	box(shin, Vector3(0, -0.315, -0.065), Vector3(0.225, 0.03, 0.335), Color("201c1a"))

# Padded sleeve, a darker cuff and a mitten with a thumb.
static func _mitten(forearm: Node3D, side: int, profile: Dictionary) -> void:
	var jacket = Color(profile.shirt)
	var gloves = Color(profile.gloves)
	capsule(forearm, Vector3(0, -0.09, 0), Vector3(0.19, 0.30, 0.20), jacket)
	cylinder(forearm, Vector3(0, -0.215, -0.01), 0.098, 0.098, 0.05, jacket.darkened(0.25), 10)
	capsule(forearm, Vector3(0, -0.31, -0.015), Vector3(0.16, 0.21, 0.13), gloves)
	var thumb = capsule(forearm, Vector3(-side * 0.088, -0.28, -0.01), Vector3(0.06, 0.12, 0.075), gloves)
	thumb.rotation.z = side * 0.35

static func _winter_hat(root: Node3D, head: Node3D, profile: Dictionary) -> void:
	var hat = Color(profile.hat_color)
	var trim = Color(profile.hat_trim)
	match profile.hat:
		"ushanka":
			rounded(head, Vector3(0, 0.39, 0.0), Vector3(0.74, 0.34, 0.63), hat, 12, 5)
			# Folded-up front flap and ear flaps hanging over the ears.
			var flap = rounded(head, Vector3(0, 0.36, -0.27), Vector3(0.62, 0.20, 0.11), trim, 12, 4)
			flap.rotation.x = -0.2
			for side in [-1, 1]:
				rounded(head, Vector3(side * 0.33, 0.12, 0.03), Vector3(0.12, 0.38, 0.30), trim, 10, 4)
			rounded(head, Vector3(0, 0.30, 0.25), Vector3(0.62, 0.20, 0.12), trim, 12, 4)
		_:
			rounded(head, Vector3(0, 0.38, 0), Vector3(0.70, 0.34, 0.60), hat, 12, 5)
			cylinder(head, Vector3(0, 0.31, 0), 0.348, 0.348, 0.13, trim if profile.hat == "bobble" else hat.lightened(0.10), 12)
			if profile.hat == "bobble":
				# Knitted stripe and a pompom.
				cylinder(head, Vector3(0, 0.44, 0), 0.33, 0.30, 0.05, trim, 12)
			rounded(head, Vector3(0, 0.58, 0), Vector3(0.20, 0.19, 0.20), trim, 10, 5)
	if profile.hat == "beanie":
		# Hood folded down behind the scarf.
		rounded(root, Vector3(0, 1.34, 0.17), Vector3(0.54, 0.18, 0.36), Color(profile.shirt).lightened(0.08), 8, 4)

# Hair beyond the default quiff, glasses, a moustache and lashes (see the
# optional look keys in character_profiles.gd). Long hair and the ponytail stay
# visible under any hat.
static func _face_extras(head: Node3D, profile: Dictionary, hair_color: Color) -> void:
	match profile.get("hair_style", "short"):
		"bald":
			# A grey fringe around the back of the head.
			for side in [-1, 1]:
				rounded(head, Vector3(side * 0.275, 0.10, 0.07), Vector3(0.10, 0.22, 0.30), hair_color, 8, 4)
			rounded(head, Vector3(0, 0.10, 0.215), Vector3(0.46, 0.22, 0.12), hair_color, 8, 4)
		"ponytail":
			rounded(head, Vector3(0, 0.24, 0.30), Vector3(0.16, 0.16, 0.14), Color(profile.trim), 8, 4)
			var tail = capsule(head, Vector3(0, 0.0, 0.36), Vector3(0.17, 0.44, 0.16), hair_color)
			tail.rotation.x = 0.28
		"long":
			rounded(head, Vector3(0, 0.02, 0.15), Vector3(0.64, 0.86, 0.34), hair_color, 12, 6)
			for side in [-1, 1]:
				rounded(head, Vector3(side * 0.285, -0.02, -0.04), Vector3(0.11, 0.64, 0.30), hair_color, 8, 5)
	if profile.get("female", false):
		for side in [-1, 1]:
			for k in range(3):
				var lash = box(head, Vector3(side * (0.09 + k * 0.05), 0.27 - absf(k - 1) * 0.015, -0.33), Vector3(0.018, 0.05, 0.012), Color("1b1f22"))
				lash.rotation.z = side * (k - 1) * 0.5
	if profile.get("mustache", false):
		for side in [-1, 1]:
			var half = rounded(head, Vector3(side * 0.07, -0.115, -0.285), Vector3(0.15, 0.06, 0.06), hair_color, 8, 4)
			half.rotation.z = side * 0.25
	var glasses = str(profile.get("glasses", ""))
	if glasses != "":
		var frame = Color("1e2326")
		for side in [-1, 1]:
			var x = side * 0.15
			if glasses == "shades":
				rounded(head, Vector3(x + 0.01, 0.12, -0.405), Vector3(0.27, 0.22, 0.03), Color("15191c"), 10, 4)
			for y in [-0.025, 0.265]:
				box(head, Vector3(x, y, -0.40), Vector3(0.29, 0.022, 0.02), frame)
			for dx in [-0.145, 0.145]:
				box(head, Vector3(x + dx, 0.12, -0.40), Vector3(0.022, 0.31, 0.02), frame)
			box(head, Vector3(side * 0.30, 0.15, -0.20), Vector3(0.02, 0.022, 0.40), frame)
		box(head, Vector3(0, 0.15, -0.41), Vector3(0.05, 0.022, 0.02), frame)

# ---------------------------------------------------------------- patch vest

const PATCH_COLORS = ["c8202e", "f4f1e8", "1d3f8a", "f2c230", "1f1f22", "e46a1f", "2f8a4a", "8a2be2", "38a3d6", "d9d2c3", "b5121b", "0f5e3a"]

# The collector's open-front green vest, worn over any clothes, every season,
# with 34 sewn-on rally patches: plates like the Monte-Carlo plaque, roundels,
# shields, diamonds and striped badges. `front` is the half-depth of the body
# under it, `half` its half-width.
static func _patch_vest(root: Node3D, profile: Dictionary, front: float, half: float) -> void:
	var cloth = Color(profile.get("vest", "4d6b3c"))
	var z = front + 0.025
	var panel = 0.05
	# The vest stops at the inner edge of the arms, so the armholes sit under
	# the shoulders and the sleeves stay outside it.
	var edge = half - 0.14
	var mid = (edge + 0.03) * 0.5
	for side in [-1.0, 1.0]:
		box(root, Vector3(side * mid, 1.09, -z), Vector3(edge - 0.03, 0.60, panel), cloth)
		box(root, Vector3(side * mid, 1.42, -0.02), Vector3(edge - 0.07, 0.06, front * 2.0 + 0.08), cloth)
		box(root, Vector3(side * mid, 0.78, -z - 0.03), Vector3(edge - 0.01, 0.03, 0.012), cloth.darkened(0.3))
	box(root, Vector3(0, 1.09, z), Vector3(edge * 2.0, 0.60, panel), cloth)
	var rng = RandomNumberGenerator.new()
	rng.seed = 1969
	var spots = []
	# Front: a column of four on each panel; back: five rows of three;
	# shoulder straps: one on each side, front and back.
	for side in [-1.0, 1.0]:
		for row in range(4):
			spots.append([Vector3(side * mid, 1.31 - row * 0.155, -z - panel * 0.5), 0.12, -1.0])
		spots.append([Vector3(side * mid, 1.46, -0.12), 0.07, -1.0])
		spots.append([Vector3(side * mid, 1.46, 0.08), 0.07, 1.0])
	for row in range(5):
		for col in range(3):
			spots.append([Vector3((col - 1) * edge * 0.62, 1.33 - row * 0.12, z + panel * 0.5), 0.11, 1.0])
	for i in range(spots.size()):
		var spot = spots[i]
		# Two different colours per badge.
		var first = rng.randi() % PATCH_COLORS.size()
		var second = (first + 1 + rng.randi() % (PATCH_COLORS.size() - 1)) % PATCH_COLORS.size()
		_patch(root, spot[0], spot[1] * rng.randf_range(0.85, 1.0), ["plate", "round", "shield", "diamond", "stripes"][i % 5], Color(PATCH_COLORS[first]), Color(PATCH_COLORS[second]), spot[2])

# One sewn-on badge facing -Z (front) or +Z (back), `size` metres across.
static func _patch(root: Node3D, at: Vector3, size: float, kind: String, a: Color, b: Color, facing: float) -> void:
	var patch = Node3D.new()
	root.add_child(patch)
	patch.position = at
	if facing > 0.0:
		patch.rotation.y = PI
	var t = 0.008
	match kind:
		"plate":
			# Rally plaque: red shield with an arched top, white field, black number.
			box(patch, Vector3(0, -size * 0.08, -t), Vector3(size, size * 0.56, t), a)
			var arch = cylinder(patch, Vector3(0, size * 0.18, -t), size * 0.42, size * 0.42, t, a, 10)
			arch.rotation.x = PI / 2.0
			box(patch, Vector3(0, -size * 0.12, -t * 2.0), Vector3(size * 0.78, size * 0.22, t), b)
			box(patch, Vector3(0, size * 0.16, -t * 2.0), Vector3(size * 0.26, size * 0.22, t), Color("f4f1e8"))
			box(patch, Vector3(0, size * 0.16, -t * 3.0), Vector3(size * 0.12, size * 0.14, t), Color("1f1f22"))
		"round":
			var disc = cylinder(patch, Vector3(0, 0, -t), size * 0.5, size * 0.5, t, a, 12)
			disc.rotation.x = PI / 2.0
			var inner = cylinder(patch, Vector3(0, 0, -t * 2.0), size * 0.32, size * 0.32, t, b, 12)
			inner.rotation.x = PI / 2.0
		"shield":
			box(patch, Vector3(0, size * 0.1, -t), Vector3(size * 0.8, size * 0.6, t), a)
			var tip = box(patch, Vector3(0, -size * 0.2, -t), Vector3(size * 0.57, size * 0.57, t), a)
			tip.rotation.z = PI / 4.0
			box(patch, Vector3(0, size * 0.1, -t * 2.0), Vector3(size * 0.16, size * 0.5, t), b)
		"diamond":
			var d = box(patch, Vector3(0, 0, -t), Vector3(size * 0.7, size * 0.7, t), a)
			d.rotation.z = PI / 4.0
			var core = box(patch, Vector3(0, 0, -t * 2.0), Vector3(size * 0.36, size * 0.36, t), b)
			core.rotation.z = PI / 4.0
		_:
			box(patch, Vector3(0, 0, -t), Vector3(size, size * 0.62, t), a)
			for y in [-0.16, 0.16]:
				box(patch, Vector3(0, size * y, -t * 2.0), Vector3(size * 0.9, size * 0.1, t), b)
