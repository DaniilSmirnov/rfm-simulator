extends RefCounted

const FOOD_PORTIONS = 10
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

const SPECTATOR_MODELS = [
	{"name": "Шашлычник", "skin": "d9a482", "shirt": "202b31", "trim": "92985a", "pants": "394650", "hair": "71451f", "hat": "", "sleeves": false, "long_pants": false, "beard": false},
	{"name": "Болельщик", "skin": "c8906a", "shirt": "346a9c", "trim": "e2e4cc", "pants": "374f69", "hair": "332a25", "hat": "cap", "sleeves": true, "long_pants": true, "beard": false},
	{"name": "Бородатый механик", "skin": "e0b393", "shirt": "bb602d", "trim": "e9c678", "pants": "343a39", "hair": "a65d29", "hat": "", "sleeves": false, "long_pants": false, "beard": true},
	{"name": "Лесной турист", "skin": "c6a08b", "shirt": "65736d", "trim": "d9b95d", "pants": "45513b", "hair": "473329", "hat": "beanie", "sleeves": true, "long_pants": true, "beard": false},
]

static func spectator_profile(variant: int) -> Dictionary:
	return SPECTATOR_MODELS[posmod(variant, SPECTATOR_MODELS.size())]

# Separate triangle normals keep these small ellipsoids visibly faceted in WebGL.
static func faceted(parent: Node3D, pos: Vector3, size: Vector3, color: Color, sides: int = 10, rings: int = 5) -> MeshInstance3D:
	var sphere = SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = mini(sides, 6)
	sphere.rings = 2 if rings == 5 else 1
	var vertices = sphere.get_faces()
	var normals = PackedVector3Array()
	for i in range(0, vertices.size(), 3):
		for j in range(3):
			vertices[i + j] *= size
		var normal = (vertices[i + 1] - vertices[i]).cross(vertices[i + 2] - vertices[i]).normalized()
		if normal.dot(vertices[i] + vertices[i + 1] + vertices[i + 2]) < 0:
			normal = -normal
		for j in range(3):
			normals.append(normal)
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var part = MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material(color)
	parent.add_child(part)
	part.position = pos
	return part

# Octagonal bevelled capsule with a broad flat face and rounded ends.
static func capsule(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var outline = [Vector2(-0.7, -1), Vector2(0.7, -1), Vector2(1, -0.7), Vector2(1, 0.7), Vector2(0.7, 1), Vector2(-0.7, 1), Vector2(-1, 0.7), Vector2(-1, -0.7)]
	var levels = [Vector2(-0.5, 0.68), Vector2(-0.37, 1), Vector2(0.37, 1), Vector2(0.5, 0.68)]
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var rings = []
	for level in levels:
		var ring = []
		for point in outline:
			ring.append(Vector3(point.x * size.x * 0.5 * level.y, level.x * size.y, point.y * size.z * 0.5 * level.y))
		rings.append(ring)
	for r in range(3):
		for i in range(8):
			var j = (i + 1) % 8
			capsule_triangle(vertices, normals, rings[r][i], rings[r + 1][i], rings[r + 1][j])
			capsule_triangle(vertices, normals, rings[r][i], rings[r + 1][j], rings[r][j])
	for i in range(8):
		capsule_triangle(vertices, normals, Vector3(0, -size.y * 0.5, 0), rings[0][i], rings[0][(i + 1) % 8])
		capsule_triangle(vertices, normals, Vector3(0, size.y * 0.5, 0), rings[3][i], rings[3][(i + 1) % 8])
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
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

static func player_avatar(variant: int = 0) -> Node3D:
	var profile = spectator_profile(variant)
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
	faceted(root, Vector3(0, 0.69, 0), Vector3(0.52, 0.28, 0.35), pants)
	box(root, Vector3(0, 0.77, -0.20), Vector3(0.47, 0.06, 0.03), Color("515c62"))
	for side in [-1, 1]:
		var leg = Node3D.new()
		leg.name = "LeftLeg" if side < 0 else "RightLeg"
		root.add_child(leg)
		leg.position = Vector3(side * 0.17, 0.65, 0)
		cylinder(leg, Vector3(0, -0.055, 0), 0.105, 0.115, 0.22, pants, 6)
		capsule(leg, Vector3(0, -0.32, 0), Vector3(0.18 if profile.long_pants else 0.15, 0.43, 0.19), pants if profile.long_pants else skin)
		box(leg, Vector3(0, -0.59, -0.065), Vector3(0.20, 0.10, 0.32), Color("564933"))
		box(leg, Vector3(0, -0.53, -0.12), Vector3(0.20, 0.065, 0.10), Color("737b75"))
		box(leg, Vector3(0, -0.50, 0.055), Vector3(0.19, 0.11, 0.07), Color("737b75"))
		var arm = Node3D.new()
		arm.name = "LeftArm" if side < 0 else "RightArm"
		root.add_child(arm)
		arm.position = Vector3(side * 0.34, 1.29, 0)
		capsule(arm, Vector3(0, -0.09, 0), Vector3(0.19, 0.31, 0.20), shirt if profile.sleeves else skin)
		capsule(arm, Vector3(0, -0.32, 0), Vector3(0.15, 0.32, 0.17), shirt if profile.hat == "beanie" else skin)
		capsule(arm, Vector3(0, -0.49, -0.015), Vector3(0.15, 0.17, 0.12), skin)

		# Three readable fingers and thumb, merged into the arm mesh on export.
		for finger in range(3):
			box(arm, Vector3(-0.047 + finger * 0.047, -0.58, -0.015), Vector3(0.036, 0.09, 0.075), skin)
		var thumb = box(arm, Vector3(-side * 0.086, -0.50, -0.005), Vector3(0.055, 0.11, 0.07), skin)
		thumb.rotation.z = side * 0.35

	var head = Node3D.new()
	head.name = "Head"
	root.add_child(head)
	head.position = Vector3(0, 1.62, 0)
	capsule(head, Vector3.ZERO, Vector3(0.60, 0.84, 0.52), skin)
	for side in [-1, 1]:
		var eye = faceted(head, Vector3(side * 0.15, 0.12, -0.275), Vector3(0.28, 0.31, 0.22), Color("f5f2e7"), 10, 5)
		eye.name = "LeftEye" if side < 0 else "RightEye"
		faceted(head, Vector3(side * 0.15 + 0.014, 0.12, -0.382), Vector3(0.085, 0.095, 0.03), Color("182226"), 8, 4)
		box(head, Vector3(side * 0.15 + 0.002, 0.14, -0.401), Vector3(0.019, 0.022, 0.009), Color("ffffff"))
	box(head, Vector3(0, -0.16, -0.265), Vector3(0.22, 0.018, 0.012), Color("875244"))
	var hair = faceted(head, Vector3(0, 0.38, 0.015), Vector3(0.66, 0.25, 0.54), hair_color, 10, 4)
	hair.name = "Quiff"
	for i in range(3):
		var tuft = faceted(hair, Vector3(-0.18 + i * 0.18, 0.085 + i * 0.01, -0.13), Vector3(0.20, 0.24, 0.32), hair_color.lightened(0.06 + i * 0.016), 7, 3)
		tuft.rotation.z = -0.25
	if profile.beard:
		faceted(head, Vector3(0, -0.235, -0.08), Vector3(0.48, 0.32, 0.44), hair_color, 8, 4)
		box(head, Vector3(0, -0.14, -0.293), Vector3(0.19, 0.06, 0.055), hair_color)
		box(head, Vector3(0, -0.19, -0.305), Vector3(0.12, 0.025, 0.02), Color("553228"))
	if profile.hat != "":
		hair.hide()
		var hat_color = Color("b43c32") if profile.hat == "cap" else Color("3f694b")
		faceted(head, Vector3(0, 0.38, 0), Vector3(0.70, 0.32, 0.59), hat_color, 10, 4)
		if profile.hat == "cap":
			var visor = box(head, Vector3(0, 0.315, -0.37), Vector3(0.53, 0.055, 0.35), hat_color)
			visor.rotation.x = 0.13
			box(head, Vector3(0, 0.44, -0.265), Vector3(0.12, 0.09, 0.018), trim_color)
		else:
			cylinder(head, Vector3(0, 0.325, 0), 0.345, 0.345, 0.12, hat_color.lightened(0.10), 10)
			faceted(head, Vector3(0, 0.57, 0), Vector3(0.13, 0.13, 0.13), hat_color, 7, 3)
			# Folded hood and drawstrings remain below the face.
			faceted(root, Vector3(0, 1.33, 0.14), Vector3(0.53, 0.18, 0.37), shirt.lightened(0.08), 8, 4)
			for x in [-0.10, 0.10]:
				box(root, Vector3(x, 1.23, -0.215), Vector3(0.015, 0.21, 0.015), trim_color)
	return root
