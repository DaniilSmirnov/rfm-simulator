extends RefCounted

const FOOD_PORTIONS = 10
# Joint pivots below the hip and the shoulder (m), see character_rig.gd.
const KNEE = 0.33
const ELBOW = 0.22
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
	else:
		capsule(root, Vector3(0, 1.03, 0), Vector3(0.64, 0.70, 0.40), shirt)
		for side in [-1, 1]:
			var trim = box(root, Vector3(side * 0.22, 1.30, -0.14), Vector3(0.12, 0.12, 0.15), trim_color)
			trim.rotation.z = side * 0.25
			box(root, Vector3(side * 0.27, 0.94, 0), Vector3(0.06, 0.35, 0.29), trim_color)
		# A tiny geometric palm emblem instead of a texture.
		box(root, Vector3(0, 1.10, -0.205), Vector3(0.025, 0.15, 0.012), trim_color)
		for angle in [-0.9, -0.45, 0.45, 0.9]:
			var leaf = box(root, Vector3(0, 1.19, -0.21), Vector3(0.025, 0.17, 0.013), trim_color)
			leaf.rotation.z = angle
	rounded(root, Vector3(0, 0.69, 0), Vector3(0.54, 0.30, 0.37) if winter else Vector3(0.52, 0.28, 0.35), pants)
	if not winter:
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
		capsule(arm, Vector3(0, -0.09, 0), Vector3(0.22, 0.32, 0.23) if winter else Vector3(0.19, 0.31, 0.20), shirt if profile.sleeves else skin)
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
	head.position = Vector3(0, 1.62, 0)
	capsule(head, Vector3.ZERO, Vector3(0.60, 0.84, 0.52), skin)
	for side in [-1, 1]:
		var eye = rounded(head, Vector3(side * 0.15, 0.12, -0.275), Vector3(0.28, 0.31, 0.22), Color("f5f2e7"), 10, 5)
		eye.name = "LeftEye" if side < 0 else "RightEye"
		rounded(head, Vector3(side * 0.15 + 0.014, 0.12, -0.382), Vector3(0.085, 0.095, 0.03), Color("182226"), 8, 4)
		box(head, Vector3(side * 0.15 + 0.002, 0.14, -0.401), Vector3(0.019, 0.022, 0.009), Color("ffffff"))
	box(head, Vector3(0, -0.16, -0.265), Vector3(0.22, 0.018, 0.012), Color("875244"))
	var hair = rounded(head, Vector3(0, 0.38, 0.015), Vector3(0.66, 0.25, 0.54), hair_color, 10, 4)
	hair.name = "Quiff"
	for i in range(3 if profile.hat == "" else 0):
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
		var hat_color = Color("b43c32") if profile.hat == "cap" else Color("3f694b")
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
	capsule(root, Vector3(0, 1.03, 0), Vector3(0.68, 0.74, 0.44), jacket)
	for y in [0.86, 1.02, 1.18]:
		rounded(root, Vector3(0, y, 0), Vector3(0.695, 0.035, 0.455), jacket.darkened(0.18), 24, 4)
	rounded(root, Vector3(0, 0.71, 0), Vector3(0.60, 0.07, 0.41), jacket.darkened(0.25), 24, 4)
	box(root, Vector3(0, 1.0, -0.226), Vector3(0.03, 0.56, 0.012), Color(profile.trim))
	var scarf = Color(profile.scarf)
	rounded(root, Vector3(0, 1.31, -0.03), Vector3(0.64, 0.15, 0.56), scarf, 24, 6)
	var tail = box(root, Vector3(0.11, 1.13, -0.285), Vector3(0.11, 0.30, 0.035), scarf)
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
