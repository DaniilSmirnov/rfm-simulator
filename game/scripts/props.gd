extends RefCounted
class_name RallyProps
const CampingHatchbackAsset = preload("res://scripts/camping_hatchback_asset.gd")
const FOOD_PORTIONS = 10
const CARGO_KINDS = ["table", "chairs", "grill", "firewood", "cauldron"]
const MUSHROOM_TEXTURES = {
	"fly_agaric": preload("res://textures/mushrooms/fly_agaric.svg"),
	"toadstool": preload("res://textures/mushrooms/toadstool.svg"),
}

static func mushroom_material(species: String) -> StandardMaterial3D:
	var mat = material(Color.WHITE if MUSHROOM_TEXTURES.has(species) else Color("916137"))
	if MUSHROOM_TEXTURES.has(species):
		mat.albedo_texture = MUSHROOM_TEXTURES[species]
	return mat

static func texture_mushroom_cap(cap: MeshInstance3D, species: String) -> void:
	# Legacy faceted meshes (including character GLBs) have no UV channel.
	# Substitute a UV sphere while preserving each cap's dimensions and pose.
	if cap.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV] == null or cap.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV].is_empty():
		var size = cap.mesh.get_aabb().size
		var sphere = SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = 1.0
		sphere.radial_segments = 16
		sphere.rings = 8
		cap.mesh = sphere
		cap.scale *= size
	cap.material_override = mushroom_material(species)

static func style_mushrooms(node: Node3D, species: String) -> void:
	if node.get_meta("mushroom_species", "") == species:
		return
	node.set_meta("mushroom_species", species)
	for cap in node.find_children("MushroomCap*", "MeshInstance3D", true, false):
		texture_mushroom_cap(cap, species)
	# Character GLBs were exported before caps had explicit node names.
	for i in range(3):
		var mushroom = node.get_node_or_null("Mushroom%d" % i)
		if mushroom != null and mushroom.get_child_count() >= 2 and mushroom.get_child(1) is MeshInstance3D:
			texture_mushroom_cap(mushroom.get_child(1), species)

static func material(color: Color) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.95
	return m

# Exact resource keys and hard limits prevent random geometry/colours growing the cache.
const RESOURCE_CACHE_LIMIT = 256
static var _materials: Dictionary = {}
static var _boxes: Dictionary = {}
static var _cylinders: Dictionary = {}
static var _faceted: Dictionary = {}

static func shared_material(color: Color) -> StandardMaterial3D:
	if _materials.has(color):
		return _materials[color]
	var result = material(color)
	if _materials.size() < RESOURCE_CACHE_LIMIT:
		_materials[color] = result
	return result

static func unique_material(node: MeshInstance3D) -> void:
	# Copy before an object's colour, glow or shading changes independently.
	node.material_override = node.material_override.duplicate()

static func resource_cache_sizes() -> Dictionary:
	return {"materials": _materials.size(), "boxes": _boxes.size(), "cylinders": _cylinders.size(), "faceted": _faceted.size()}

static func box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var n = MeshInstance3D.new()
	var mesh: BoxMesh = _boxes.get(size)
	if mesh == null:
		mesh = BoxMesh.new()
		mesh.size = size
		if _boxes.size() < RESOURCE_CACHE_LIMIT:
			_boxes[size] = mesh
	n.mesh = mesh
	n.material_override = shared_material(color)
	parent.add_child(n)
	n.position = pos
	return n

static func cylinder(parent: Node3D, pos: Vector3, bottom: float, top: float, height: float, color: Color, sides: int = 7) -> MeshInstance3D:
	var n = MeshInstance3D.new()
	var key = Vector4(bottom, top, height, sides)
	var mesh: CylinderMesh = _cylinders.get(key)
	if mesh == null:
		mesh = CylinderMesh.new()
		mesh.bottom_radius = bottom
		mesh.top_radius = top
		mesh.height = height
		mesh.radial_segments = sides
		if _cylinders.size() < RESOURCE_CACHE_LIMIT:
			_cylinders[key] = mesh
	n.mesh = mesh
	n.material_override = shared_material(color)
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
	var key = [size, sides, rings]
	var mesh: ArrayMesh = _faceted.get(key)
	if mesh == null:
		var sphere = SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = 1.0
		sphere.radial_segments = sides
		sphere.rings = rings
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
		mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		if _faceted.size() < RESOURCE_CACHE_LIMIT:
			_faceted[key] = mesh
	var part = MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = shared_material(color)
	parent.add_child(part)
	part.position = pos
	return part

const AVATAR_SCENES = [
	preload("res://models/characters/spectator_0.glb"),
	preload("res://models/characters/spectator_1.glb"),
	preload("res://models/characters/spectator_2.glb"),
	preload("res://models/characters/spectator_3.glb"),
]

static func player_avatar(variant: int = 0) -> Node3D:
	var index = posmod(variant, AVATAR_SCENES.size())
	var root = AVATAR_SCENES[index].instantiate() as Node3D
	root.name = "RallySpectator"
	root.set_meta("model", spectator_profile(index).name)
	root.set_meta("variant", index)
	var arm = root.get_node("RightArm")
	var can = cylinder(arm, Vector3(0, -0.52, -0.085), 0.075, 0.075, 0.23, Color("daa44f"), 8)
	can.name = "BeerCan"
	cylinder(can, Vector3(0, 0.119, 0), 0.071, 0.071, 0.008, Color("c4cac5"), 8)
	can.hide()
	var food = skewer()
	arm.add_child(food)
	food.position = Vector3(0, -0.5, -0.09)
	food.hide()
	return root


# Roll wheel and hub meshes according to signed longitudinal travel.
# Cache references once per car; skip teleports to prevent large visual jumps.
static func animate_wheels(car_root: Node3D) -> void:
	if car_root == null:
		return
	var current_position = car_root.global_position
	if not car_root.has_meta("wheel_previous_position"):
		car_root.set_meta("wheel_previous_position", current_position)
		return
	var previous: Vector3 = car_root.get_meta("wheel_previous_position")
	car_root.set_meta("wheel_previous_position", current_position)
	var travelled = current_position - previous
	if travelled.length_squared() < 0.000001 or travelled.length_squared() > 64.0:
		return
	var signed_distance = travelled.dot(-car_root.global_basis.z.normalized())
	if absf(signed_distance) < 0.0001:
		return
	if not car_root.has_meta("wheel_parts"):
		var wheels: Array = []
		var pending: Array[Node] = [car_root]
		while not pending.is_empty():
			var current: Node = pending.pop_back()
			for child in current.get_children():
				pending.append(child)
				if child is Node3D and child.has_meta("rolling_wheel_radius"):
					wheels.append(child)
		car_root.set_meta("wheel_parts", wheels)
	var parts: Array = car_root.get_meta("wheel_parts")
	for wheel in parts:
		if not is_instance_valid(wheel):
			continue
		var radius = wheel.get_meta("rolling_wheel_radius")
		if radius is String:
			radius = 0.4
		wheel.rotate_object_local(wheel.get_meta("rolling_wheel_axis", Vector3.UP), signed_distance / maxf(float(radius), 0.1))

static func car(color: Color, rally: bool = false, variant: int = 0) -> Node3D:
	if rally:
		return rally_car(variant)
	var root = Node3D.new()
	box(root, Vector3(0, 0.68, 0), Vector3(1.85, 0.65, 3.8), color)
	box(root, Vector3(0, 1.22, 0.25), Vector3(1.58, 0.6, 1.9), Color("344a4f"))
	box(root, Vector3(0, 1.56, 0.3), Vector3(1.7, 0.12, 2), color)
	box(root, Vector3(0, 0.85, -1.05), Vector3(1.8, 0.15, 1.5), color)
	box(root, Vector3(0, 0.48, -1.96), Vector3(1.85, 0.18, 0.1), Color("383a35"))
	box(root, Vector3(0, 0.5, 1.96), Vector3(1.85, 0.17, 0.1), Color("383a35"))
	for x in [-0.65, 0.65]:
		box(root, Vector3(x, 0.79, -1.92), Vector3(0.4, 0.23, 0.08), Color("f6e4ac"))
		box(root, Vector3(x, 0.79, 1.92), Vector3(0.35, 0.16, 0.08), Color("b95234"))
	for x in [-0.95, 0.95]:
		for z in [-1.22, 1.25]:
			var wheel = cylinder(root, Vector3(x, 0.39, z), 0.4, 0.4, 0.28, Color("222b2a"), 10)
			wheel.rotation.z = PI / 2
			wheel.set_meta("rolling_wheel_radius", 0.4)
			var hub = cylinder(root, Vector3(x * 1.15, 0.39, z), 0.22, 0.22, 0.03, Color("ddd7c3"), 8)
			hub.rotation.z = PI / 2
			hub.set_meta("rolling_wheel_radius", "inherit")
	if rally:
		box(root, Vector3(0, 1.3, 1.65), Vector3(2, 0.1, 0.42), Color("273230"))
		box(root, Vector3(0, 0.86, -0.7), Vector3(0.65, 0.1, 2), Color("f2e8d0"))
		for x in [-0.936, 0.936]:
			box(root, Vector3(x, 0.81, 0.15), Vector3(0.03, 0.32, 0.55), Color("f2e8d0"))
	return root

# Player fleet. Shapes are stylized original meshes, with recognizable proportions.
const PLAYER_MODELS = [
	{"name": "Компактный седан", "color": "111a2b", "length": 4.26, "width": 1.70, "height": 1.50, "rear": 0.95, "glass": 0.36, "lights": "wide", "grille": 0.65},
	{"name": "Городской седан", "color": "a8bdc2", "length": 4.41, "width": 1.77, "height": 1.49, "rear": 1.05, "glass": 0.48, "lights": "slim", "grille": 0.94},
	{"name": "Лесной внедорожник", "color": "627746", "length": 3.74, "width": 1.68, "height": 1.74, "rear": 1.50, "glass": 0.14, "lights": "round", "grille": 0.86},
	{"name": "Классический седан", "color": "e6dfc7", "length": 4.12, "width": 1.64, "height": 1.45, "rear": 0.95, "glass": 0.19, "lights": "square", "grille": 0.55},
	{"name": "Лёгкий седан", "color": "8dabb9", "length": 4.37, "width": 1.72, "height": 1.46, "rear": 1.00, "glass": 0.52, "lights": "wide", "grille": 0.80},
	{"name": "Дорожный седан", "color": "a74d43", "length": 4.40, "width": 1.74, "height": 1.47, "rear": 0.93, "glass": 0.43, "lights": "slim", "grille": 0.56},
	{"name": "Семейный седан", "color": "c6c9b9", "length": 4.35, "width": 1.73, "height": 1.53, "rear": 0.87, "glass": 0.27, "lights": "square", "grille": 0.90},
	{"name": "Туристический кроссовер", "color": "a58058", "length": 4.34, "width": 1.82, "height": 1.70, "rear": 1.63, "glass": 0.28, "lights": "square", "grille": 1.05},
	{"name": "Походный хэтчбек", "color": "283f87", "length": 4.17, "width": 1.68, "height": 1.47, "rear": 0.98, "glass": 0.30, "lights": "square", "grille": 0.75},
	{"name": "Спортивный седан", "color": "c92530", "length": 4.68, "width": 1.88, "height": 1.46, "rear": 1.00, "glass": 0.40, "lights": "slim", "grille": 0.80},
]

# A closed faceted shell with bevelled cross-sections. Each model has its own
# bonnet, roof, windscreen, rear deck and wheelbase instead of stacked boxes.
static func car_shell(parent: Node3D, sections: Array, color: Color) -> MeshInstance3D:
	var rows = []
	for section in sections:
		var z: float = section.x
		var w: float = section.y
		var bottom: float = section.z
		var top: float = section.w
		rows.append([Vector3(-w * 0.88, bottom, z), Vector3(-w, bottom + 0.08, z), Vector3(-w, top - 0.06, z), Vector3(-w * 0.88, top, z), Vector3(w * 0.88, top, z), Vector3(w, top - 0.06, z), Vector3(w, bottom + 0.08, z), Vector3(w * 0.88, bottom, z)])
	var vertices = PackedVector3Array()
	for i in range(rows.size() - 1):
		for j in range(8):
			var k = (j + 1) % 8
			vertices.append_array(PackedVector3Array([rows[i][j], rows[i][k], rows[i + 1][j], rows[i][k], rows[i + 1][k], rows[i + 1][j]]))
	for index in [0, rows.size() - 1]:
		for j in range(1, 7):
			vertices.append_array(PackedVector3Array([rows[index][0], rows[index][j], rows[index][j + 1]]))
	var normals = PackedVector3Array()
	var middle = Vector3(0, (sections[0].z + sections[0].w) / 2, (sections[0].x + sections[-1].x) / 2)
	for i in range(0, vertices.size(), 3):
		var normal = (vertices[i + 1] - vertices[i]).cross(vertices[i + 2] - vertices[i]).normalized()
		if normal.dot((vertices[i] + vertices[i + 1] + vertices[i + 2]) / 3 - middle) < 0:
			normal = -normal
		for j in range(3):
			normals.append(normal)
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material(color)
	node.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	parent.add_child(node)
	return node

static func car_beam(parent: Node3D, a: Vector3, b: Vector3, width: float, color: Color) -> void:
	var beam = box(parent, (a + b) / 2, Vector3(width, a.distance_to(b), width), color)
	beam.quaternion = Quaternion(Vector3.UP, (b - a).normalized())

static func quad_panel(parent: Node3D, points: PackedVector3Array, color: Color) -> MeshInstance3D:
	var vertices = PackedVector3Array([points[0], points[1], points[2], points[0], points[2], points[3]])
	var normal = (vertices[1] - vertices[0]).cross(vertices[2] - vertices[0]).normalized()
	var normals = PackedVector3Array()
	for i in range(vertices.size()):
		normals.append(normal)
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var panel = MeshInstance3D.new()
	panel.mesh = mesh
	panel.material_override = material(color)
	panel.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	parent.add_child(panel)
	return panel

static func player_car_camping_hatchback() -> Node3D:
	var imported = CampingHatchbackAsset.build()
	if imported != null:
		return add_player_trunk(imported, 8)
	var root = Node3D.new()
	root.name = "PlayerCar_8"
	root.set_meta("model", "Походный хэтчбек")
	root.set_meta("variant", 8)
	root.set_meta("roof_cargo", "inflatable_boat")
	var paint = Color("283f87")
	var trim = Color("202b31")
	var glass = Color("253d49")
	# Low, long hatchback profile: flat bonnet, rising windscreen, short roof and sharply
	# raked rear hatch glass. The cabin is deliberately not a tall box.
	var body = car_shell(root, [
		Vector4(-2.08, 0.73, 0.40, 0.79),
		Vector4(-1.68, 0.84, 0.39, 0.94),
		Vector4(-1.02, 0.84, 0.39, 1.00),
		Vector4(0.26, 0.84, 0.39, 1.00),
		Vector4(1.30, 0.80, 0.39, 0.88),
		Vector4(2.08, 0.70, 0.40, 0.80)
	], paint)
	body.name = "BodyShellHatchback"
	# Roof cap and angular window belt, following the real sloped glasshouse.
	var roof = car_shell(root, [
		Vector4(-0.72, 0.67, 1.34, 1.47),
		Vector4(-0.55, 0.69, 1.39, 1.49),
		Vector4(0.24, 0.68, 1.39, 1.49),
		Vector4(0.38, 0.65, 1.32, 1.44)
	], paint)
	roof.name = "RoofHatchback"
	for side in [-1.0, 1.0]:
		var x = side * 0.705
		# Separate front/rear door glass and small rear quarter glass, with body-color pillars.
		quad_panel(root, PackedVector3Array([
			Vector3(x, 1.29, -0.60), Vector3(x, 1.29, -0.03),
			Vector3(side * 0.67, 1.40, -0.14), Vector3(side * 0.67, 1.40, -0.47)
		]), glass)
		quad_panel(root, PackedVector3Array([
			Vector3(x, 1.29, 0.06), Vector3(x, 1.28, 0.48),
			Vector3(side * 0.66, 1.39, 0.30), Vector3(side * 0.67, 1.40, 0.06)
		]), glass)
		quad_panel(root, PackedVector3Array([
			Vector3(x, 1.25, 0.54), Vector3(side * 0.62, 1.14, 0.99),
			Vector3(side * 0.65, 1.33, 0.56), Vector3(side * 0.66, 1.38, 0.40)
		]), glass)
		# A-, B-, C-pillars trace the rising belt and the steep rear hatch rake.
		car_beam(root, Vector3(side * 0.76, 1.00, -0.96), Vector3(side * 0.68, 1.43, -0.61), 0.075, paint)
		car_beam(root, Vector3(side * 0.71, 1.28, -0.03), Vector3(side * 0.67, 1.42, -0.03), 0.055, paint)
		car_beam(root, Vector3(side * 0.69, 1.40, 0.48), Vector3(side * 0.61, 1.18, 1.08), 0.08, paint)
		car_beam(root, Vector3(side * 0.61, 1.18, 1.08), Vector3(side * 0.56, 0.91, 1.48), 0.08, paint)
		box(root, Vector3(side * 0.86, 1.03, -0.08), Vector3(0.045, 0.07, 1.55), trim)
		box(root, Vector3(side * 0.91, 1.10, -0.94), Vector3(0.22, 0.13, 0.18), trim)
		box(root, Vector3(side * 0.86, 0.78, -0.92), Vector3(0.045, 0.035, 0.16), Color("aeb9ba"))
		for z in [-1.33, 1.34]:
			var wheel = cylinder(root, Vector3(side * 0.87, 0.39, z), 0.39, 0.39, 0.28, Color("171c1e"), 12)
			wheel.rotation.z = PI / 2
			wheel.set_meta("rolling_wheel_radius", 0.39)
			var hub = cylinder(root, Vector3(side * 1.03, 0.39, z), 0.22, 0.22, 0.035, Color("323b40"), 8)
			hub.rotation.z = PI / 2
			hub.set_meta("rolling_wheel_radius", "inherit")
	# Large slanted windscreen; the rear glass is a long fastback panel into the hatch.
	quad_panel(root, PackedVector3Array([
		Vector3(-0.66, 1.40, -0.62), Vector3(0.66, 1.40, -0.62),
		Vector3(0.77, 1.02, -1.00), Vector3(-0.77, 1.02, -1.00)
	]), glass)
	quad_panel(root, PackedVector3Array([
		Vector3(-0.65, 1.40, 0.35), Vector3(0.65, 1.40, 0.35),
		Vector3(0.68, 0.91, 1.52), Vector3(-0.68, 0.91, 1.52)
	]), glass)
	# Front fascia: broad trapezoid lamp housings, narrow grille and integrated bumper.
	box(root, Vector3(0, 0.48, -2.10), Vector3(1.58, 0.16, 0.12), trim)
	box(root, Vector3(0, 0.72, -2.115), Vector3(0.70, 0.16, 0.035), Color("17252b"))
	for side in [-1.0, 1.0]:
		quad_panel(root, PackedVector3Array([
			Vector3(side * 0.31, 0.72, -2.135), Vector3(side * 0.78, 0.73, -2.135),
			Vector3(side * 0.78, 0.91, -2.12), Vector3(side * 0.35, 0.88, -2.12)
		]), Color("e8e5d2"))
		box(root, Vector3(side * 0.53, 0.95, -1.89), Vector3(0.15, 0.035, 0.32), paint)
	# Rear hatch has the characteristic broad red light panel, segmented at the centre.
	box(root, Vector3(0, 0.62, 2.105), Vector3(1.48, 0.24, 0.055), Color("242b2e"))
	for side in [-1.0, 1.0]:
		box(root, Vector3(side * 0.50, 0.65, 2.14), Vector3(0.47, 0.17, 0.035), Color("ad3b37"))
		box(root, Vector3(side * 0.50, 0.76, 2.14), Vector3(0.47, 0.035, 0.035), Color("d1d0bd"))
	box(root, Vector3(0, 0.65, 2.14), Vector3(0.38, 0.14, 0.035), Color("353a3b"))
	box(root, Vector3(0, 0.45, 2.10), Vector3(1.55, 0.15, 0.12), trim)
	# Door seams and handles emphasize the five-door body rather than a generic shell.
	for side in [-1.0, 1.0]:
		for z in [-0.03, 0.53]:
			box(root, Vector3(side * 0.847, 0.96, z), Vector3(0.018, 0.025, 0.13), Color("aeb9ba"))
	# Roof rack, visible above the roofline and below the inflatable boat.
	for z in [-0.62, 0.62]:
		box(root, Vector3(0, 1.56, z), Vector3(1.32, 0.07, 0.12), trim)
	# Inflatable boat hull, dark inner well and yellow tie-down straps.
	faceted(root, Vector3(0, 1.93, 0), Vector3(0.72, 0.30, 1.70), Color("747d7e"), 10, 5)
	faceted(root, Vector3(0, 2.06, 0), Vector3(0.47, 0.12, 1.38), Color("354448"), 10, 4)
	for z in [-0.62, 0.62]:
		box(root, Vector3(0, 1.91, z), Vector3(1.48, 0.045, 0.10), Color("e0b83f"))
		box(root, Vector3(0, 1.83, z), Vector3(0.055, 0.38, 0.055), Color("202a2d"))
	return add_player_trunk(root, 8)
static func player_car_sport_sedan() -> Node3D:
	var root = Node3D.new()
	root.name = "PlayerCar_9"
	root.set_meta("model", "Спортивный седан")
	root.set_meta("variant", 9)
	var paint = Color("c92530")
	var black = Color("171d23")
	var glass = Color("263c4a")
	var silver = Color("929ca3")
	# Wide four-door sedan: long bonnet, rearward cabin and separate short boot.
	var body = car_shell(root, [
		Vector4(-2.34, 0.84, 0.34, 0.79),
		Vector4(-1.91, 0.93, 0.33, 0.91),
		Vector4(-1.42, 0.98, 0.33, 0.96),
		Vector4(-0.98, 0.93, 0.33, 1.00),
		Vector4(0.66, 0.93, 0.33, 0.99),
		Vector4(1.39, 1.00, 0.33, 1.00),
		Vector4(1.84, 0.96, 0.34, 0.99),
		Vector4(2.34, 0.86, 0.36, 0.88)
	], paint)
	body.name = "BodyShellSportSedan"
	body.material_override.roughness = 0.38
	var cabin = car_shell(root, [
		Vector4(-0.99, 0.78, 0.98, 1.04),
		Vector4(-0.43, 0.71, 0.98, 1.40),
		Vector4(0.57, 0.70, 0.98, 1.41),
		Vector4(1.20, 0.77, 0.98, 1.06)
	], glass)
	cabin.name = "GlassCabinSportSedan"
	var roof = car_shell(root, [
		Vector4(-0.45, 0.72, 1.39, 1.44),
		Vector4(-0.15, 0.73, 1.41, 1.46),
		Vector4(0.57, 0.71, 1.40, 1.45)
	], black)
	roof.name = "CarbonRoofSport"
	var bonnet = car_shell(root, [
		Vector4(-1.91, 0.26, 0.89, 0.94),
		Vector4(-1.40, 0.31, 0.93, 1.01),
		Vector4(-1.03, 0.27, 0.96, 1.03)
	], paint)
	bonnet.name = "BonnetPowerDome"
	for side in [-1.0, 1.0]:
		car_beam(root, Vector3(side * 0.79, 1.01, -1.00), Vector3(side * 0.72, 1.42, -0.44), 0.065, paint)
		car_beam(root, Vector3(side * 0.78, 1.01, 0.14), Vector3(side * 0.71, 1.42, 0.14), 0.055, black)
		car_beam(root, Vector3(side * 0.71, 1.43, 0.58), Vector3(side * 0.80, 1.02, 1.23), 0.085, paint)
		# Two door handles, seams and an angular rear quarter window on each side.
		for z in [-0.03, 0.89]:
			box(root, Vector3(side * 0.935, 0.90, z), Vector3(0.025, 0.035, 0.16), paint.lightened(0.12))
		for z in [-0.92, 0.18, 1.05]:
			car_beam(root, Vector3(side * 0.936, 0.45, z), Vector3(side * 0.937, 0.94, z), 0.012, paint.darkened(0.32))
		box(root, Vector3(side * 0.95, 0.36, 0.10), Vector3(0.12, 0.10, 2.80), paint.darkened(0.18)).name = "SideSkirt_%s" % side
		box(root, Vector3(side * 0.951, 0.81, -1.00), Vector3(0.02, 0.12, 0.28), black)
		box(root, Vector3(side * 1.00, 1.12, -0.86), Vector3(0.25, 0.13, 0.22), black)
		car_beam(root, Vector3(side * 0.81, 1.09, -0.76), Vector3(side * 0.98, 1.12, -0.86), 0.05, paint)
		for wheel_index in range(2):
			var z = -1.42 if wheel_index == 0 else 1.39
			var wheel = cylinder(root, Vector3(side * 0.94, 0.36, z), 0.36, 0.36, 0.26, black, 16)
			wheel.rotation.z = PI / 2
			wheel.set_meta("rolling_wheel_radius", 0.36)
			wheel.name = "SportWheel_%s_%d" % [side, wheel_index]
			var rim = cylinder(root, Vector3(side * 1.077, 0.36, z), 0.27, 0.27, 0.018, Color("252a30"), 16)
			rim.rotation.z = PI / 2
			# Ten split spokes and a plain metal centre cap.
			for spoke in range(10):
				var angle = spoke * TAU / 10.0
				car_beam(root, Vector3(side * 1.094, 0.36 + sin(angle) * 0.06, z + cos(angle) * 0.06), Vector3(side * 1.094, 0.36 + sin(angle + 0.10) * 0.25, z + cos(angle + 0.10) * 0.25), 0.025, silver)
			var cap = cylinder(root, Vector3(side * 1.106, 0.36, z), 0.055, 0.055, 0.025, silver, 8)
			cap.rotation.z = PI / 2
			# Faceted painted lips outline the widened arches.
			for segment in range(10):
				var start = segment * PI / 10.0
				var finish = (segment + 1) * PI / 10.0
				car_beam(root, Vector3(side * 1.01, 0.36 + sin(start) * 0.40, z + cos(start) * 0.40), Vector3(side * 1.01, 0.36 + sin(finish) * 0.40, z + cos(finish) * 0.40), 0.065, paint)
	# One unbranded grille and simple rectangular lamps.
	box(root, Vector3(0, 0.82, -2.379), Vector3(0.78, 0.18, 0.025), black).name = "SportGrille"
	for slat in range(3):
		box(root, Vector3(0, 0.76 + slat * 0.06, -2.397), Vector3(0.73, 0.018, 0.013), Color("515960"))
	for side in [-1.0, 1.0]:
		quad_panel(root, PackedVector3Array([
			Vector3(side * 0.42, 0.73, -2.37), Vector3(side * 0.86, 0.78, -2.29),
			Vector3(side * 0.84, 0.94, -2.27), Vector3(side * 0.42, 0.92, -2.37)
		]), black).name = "HeadlightSport_%s" % side
		for eye in range(2):
			var x = side * (0.51 + eye * 0.20)
			var z = -2.39 + eye * 0.043
			box(root, Vector3(x, 0.81, z), Vector3(0.115, 0.025, 0.02), Color("edf4ff"))
			for edge in [-1.0, 1.0]:
				var led = box(root, Vector3(x + edge * 0.06, 0.846, z), Vector3(0.022, 0.07, 0.02), Color("edf4ff"))
				led.rotation.z = edge * 0.24
		box(root, Vector3(side * 0.66, 0.52, -2.34), Vector3(0.39, 0.23, 0.07), black)
		box(root, Vector3(side * 0.66, 0.51, -2.384), Vector3(0.33, 0.027, 0.015), Color("424b50"))
	box(root, Vector3(0, 0.44, -2.37), Vector3(0.81, 0.17, 0.055), black).name = "SportLowerIntake"
	box(root, Vector3(0, 0.33, -2.38), Vector3(1.79, 0.065, 0.17), black)
	box(root, Vector3(0, 0.62, -2.39), Vector3(0.43, 0.11, 0.025), Color("e4e4dd"))
	# L-shaped rear lamps, boot lip, black diffuser and four exhaust tips.
	box(root, Vector3(0, 1.015, 2.03), Vector3(1.67, 0.045, 0.12), black).name = "SportBootLip"
	box(root, Vector3(0, 0.40, 2.35), Vector3(1.66, 0.18, 0.075), black).name = "SportRearDiffuser"
	for side in [-1.0, 1.0]:
		box(root, Vector3(side * 0.62, 0.84, 2.354), Vector3(0.47, 0.17, 0.04), Color("721c27")).name = "TaillightSport_%s" % side
		box(root, Vector3(side * 0.62, 0.89, 2.38), Vector3(0.43, 0.028, 0.018), Color("eb4544"))
		box(root, Vector3(side * 0.82, 0.84, 2.38), Vector3(0.028, 0.10, 0.018), Color("eb4544"))
		for tip in range(2):
			var pipe = cylinder(root, Vector3(side * (0.52 + tip * 0.16), 0.36, 2.42), 0.065, 0.065, 0.18, silver, 10)
			pipe.rotation.x = PI / 2
			pipe.name = "SportExhaust_%s_%d" % [side, tip]
			var opening = cylinder(root, Vector3(side * (0.52 + tip * 0.16), 0.36, 2.515), 0.047, 0.047, 0.012, black, 10)
			opening.rotation.x = PI / 2
	box(root, Vector3(0, 0.71, 2.385), Vector3(0.43, 0.13, 0.025), Color("e4e4dd"))
	return add_player_trunk(root, 9)

static func player_car(variant: int = 0) -> Node3D:
	variant = posmod(variant, PLAYER_MODELS.size())
	if variant == 0:
		return load("res://scripts/granta_model.gd").build()
	if variant == 8:
		return player_car_camping_hatchback()
	if variant == 9:
		return player_car_sport_sedan()
	var p: Dictionary = PLAYER_MODELS[variant]
	var shapes = [
		[-0.87, -0.40, 0.57, 1.07, 0.72, 0.77], # Compact sedan: compact cabin, high boot.
		[-1.02, -0.37, 0.68, 1.25, 0.77, 0.80], # City sedan: long, low wedge.
		[-0.72, -0.59, 1.28, 1.52, 0.63, 0.56], # Off-road vehicle: upright three-door wagon.
		[-0.77, -0.61, 0.65, 0.88, 0.68, 0.66], # Classic sedan: rectangular cabin and flat bonnet.
		[-0.98, -0.32, 0.64, 1.27, 0.78, 0.77], # Light sedan: arched roof and swept rear glass.
		[-0.94, -0.40, 0.70, 1.22, 0.79, 0.78], # Road sedan: longer bonnet, low rear deck.
		[-0.79, -0.49, 0.65, 1.03, 0.70, 0.66], # Family sedan: tall, upright sedan.
		[-0.91, -0.56, 1.29, 1.66, 0.75, 0.65], # Touring crossover: broad five-door SUV.
		[-0.96, -0.43, 0.60, 1.08, 0.68, 0.70], # hatchback: low hatchback nose and steep rear glass.
	]
	var shape: Array = shapes[variant]
	var root = Node3D.new()
	root.name = "PlayerCar_%d" % variant
	root.set_meta("model", p.name)
	root.set_meta("variant", variant)
	var paint = Color(p.color)
	var suv = variant in [2, 7]
	var base = 0.81 if suv else 0.67
	var radius = 0.43 if suv else 0.36
	var front: float = -p.length / 2
	var rear: float = p.length / 2
	var half: float = p.width / 2
	var bonnet = base + (0.34 if variant in [2, 3, 6, 8] else 0.27)
	var body = car_shell(root, [Vector4(front, half * 0.90, base - 0.24, bonnet - 0.13), Vector4(front + 0.38, half, base - 0.26, bonnet - 0.03), Vector4(shape[0], half, base - 0.26, bonnet), Vector4(shape[3], half, base - 0.26, bonnet - 0.02), Vector4(rear, half * 0.93, base - 0.22, bonnet - 0.06)], paint)
	body.name = "BodyShell"
	var floor_height = bonnet - 0.02
	var glass_half = half * 0.86
	var cabin = car_shell(root, [Vector4(shape[0], glass_half, floor_height - 0.06, floor_height + 0.13), Vector4(shape[1], glass_half * 0.94, floor_height, p.height - 0.06), Vector4(shape[2], glass_half * 0.93, floor_height, p.height - 0.06), Vector4(shape[3], glass_half, floor_height - 0.06, floor_height + 0.13)], Color("304a55"))
	cabin.name = "GlassCabin"
	car_shell(root, [Vector4(shape[1] - 0.03, glass_half * 0.94, p.height - 0.07, p.height + 0.02), Vector4(shape[2] + 0.03, glass_half * 0.93, p.height - 0.07, p.height + 0.02)], paint)
	for side in [-1, 1]:
		var x: float = side * glass_half
		car_beam(root, Vector3(x, floor_height + 0.04, shape[0]), Vector3(x * 0.94, p.height - 0.04, shape[1]), 0.065, paint)
		car_beam(root, Vector3(x * 0.93, p.height - 0.04, shape[2]), Vector3(x, floor_height + 0.04, shape[3]), 0.08, paint)
		var pillar_z: float = 0.32 if variant == 2 else 0.1
		car_beam(root, Vector3(x, floor_height, pillar_z), Vector3(x * 0.94, p.height - 0.05, pillar_z), 0.07, paint)
		box(root, Vector3(side * half * 1.08, bonnet + 0.12, shape[0] + 0.04), Vector3(0.21, 0.13, 0.21), Color("28343a"))
		for z in [front + shape[4], rear - shape[5]]:
			var wheel = cylinder(root, Vector3(side * half * 1.01, radius, z), radius, radius, 0.26, Color("202827"), 12)
			wheel.rotation.z = PI / 2
			wheel.set_meta("rolling_wheel_radius", radius)
			var hub = cylinder(root, Vector3(side * half * 1.17, radius, z), radius * 0.60, radius * 0.60, 0.035, Color("b8c0bf"), 8)
			hub.rotation.z = PI / 2
			hub.set_meta("rolling_wheel_radius", "inherit")
			cylinder(hub, Vector3(0, 0.024, 0), radius * 0.19, radius * 0.19, 0.025, Color("515b5e"), 8)
			if suv:
				box(root, Vector3(side * half, base + 0.02, z), Vector3(0.11, 0.13, 1.00), Color("35413d"))
		box(root, Vector3(side * half * 1.005, base + 0.19, 0.19), Vector3(0.02, 0.035, 0.15), Color("c5cbc7"))
		if variant != 2:
			box(root, Vector3(side * half * 1.005, base + 0.19, 0.89), Vector3(0.02, 0.035, 0.15), Color("c5cbc7"))
		var light_x: float = side * half * 0.65
		if p.lights == "round":
			var light = cylinder(root, Vector3(light_x, bonnet - 0.18, front - 0.025), 0.15, 0.15, 0.055, Color("eee8b4"), 10)
			light.rotation.x = PI / 2
		else:
			var lamp = box(root, Vector3(light_x, bonnet - 0.14, front - 0.028), Vector3(0.48 if p.lights == "wide" else 0.38, 0.10 if p.lights == "slim" else 0.21, 0.055), Color("eee8b4"))
			lamp.rotation.z = side * (0.16 if variant in [0, 1, 4, 5] else 0.0)
		box(root, Vector3(light_x, bonnet - 0.13, rear + 0.025), Vector3(0.33, 0.30 if suv else 0.17, 0.055), Color("ab3631"))
	var trim = Color("c6ccc8") if variant in [2, 3] else Color("303d41")
	for z in [front - 0.045, rear + 0.045]:
		box(root, Vector3(0, base - 0.19, z), Vector3(p.width * 0.97, 0.15, 0.11), trim)
		box(root, Vector3(0, base - 0.13, z + (-0.07 if z < 0 else 0.07)), Vector3(0.38, 0.10, 0.02), Color("e8e5d0"))
	box(root, Vector3(0, bonnet - 0.15, front - 0.06), Vector3(p.grille, 0.24, 0.03), Color("1f2e33"))
	if variant in [0, 1, 4, 5]:
		box(root, Vector3(0, base - 0.07, front - 0.075), Vector3(1.08 if variant == 4 else 0.91, 0.17, 0.02), Color("1d2b31"))
	if variant == 3:
		box(root, Vector3(0, bonnet - 0.13, front - 0.08), Vector3(0.62, 0.35, 0.025), Color("bdc6c3"))
		for x in [-0.22, -0.11, 0, 0.11, 0.22]:
			box(root, Vector3(x, bonnet - 0.13, front - 0.10), Vector3(0.055, 0.27, 0.02), Color("293a3c"))
	elif variant in [6, 7]:
		for x in [-0.35, 0.35]:
			box(root, Vector3(x, bonnet - 0.1, front - 0.081), Vector3(0.46, 0.025, 0.02), Color("c2cac5"))
	elif variant == 5:
		for x in [-0.27, 0.27]:
			box(root, Vector3(x, bonnet - 0.13, front - 0.084), Vector3(0.40, 0.035, 0.018), Color("b8c5c7"))
	if variant == 2:
		var spare = cylinder(root, Vector3(0, base + 0.22, rear + 0.18), 0.38, 0.38, 0.22, Color("25332b"), 10)
		spare.rotation.x = PI / 2
	if suv:
		for side in [-1, 1]:
			box(root, Vector3(side * 0.57, p.height + 0.08, 0.48), Vector3(0.06, 0.07, 1.65), Color("38413a"))
	if variant == 8:
		# Real-world hatchback details: hatch spoiler, black steel wheels and a roof rack.
		box(root, Vector3(0, p.height + 0.08, 0.72), Vector3(1.18, 0.08, 0.16), Color("1d2b35"))
		for z in [-0.62, 0.62]:
			box(root, Vector3(0, p.height + 0.11, z), Vector3(1.35, 0.08, 0.12), Color("252e30"))
		# Inflatable boat strapped across the roof, with a recessed dark interior.
		faceted(root, Vector3(0, p.height + 0.48, 0), Vector3(0.72, 0.30, 1.72), Color("747d7e"), 10, 5)
		faceted(root, Vector3(0, p.height + 0.60, 0), Vector3(0.48, 0.12, 1.40), Color("354448"), 10, 4)
		for z in [-0.62, 0.62]:
			box(root, Vector3(0, p.height + 0.46, z), Vector3(1.48, 0.045, 0.10), Color("e0b83f"))
			box(root, Vector3(0, p.height + 0.36, z), Vector3(0.055, 0.36, 0.055), Color("202a2d"))
		root.set_meta("roof_cargo", "inflatable_boat")
	return add_player_trunk(root, variant)

static func skewer() -> Node3D:
	var root = Node3D.new()
	root.name = "Skewer"
	box(root, Vector3(0, 0.08, 0), Vector3(0.022, 0.68, 0.022), Color("b6b8ad")).name = "SkewerStick"
	box(root, Vector3(0, -0.29, 0), Vector3(0.05, 0.14, 0.04), Color("725135")).name = "SkewerHandle"
	for i in range(3):
		var meat = box(root, Vector3(0, i * 0.11 + 0.06, 0), Vector3(0.12, 0.09, 0.10), Color("9e5130").lightened(i * 0.035))
		meat.name = "Meat%d" % i
		meat.rotation.y = i * 0.5
		box(meat, Vector3(0, 0.02, 0.051), Vector3(0.10, 0.016, 0.007), Color("563b27"))
	for i in range(3):
		var mushroom = Node3D.new()
		mushroom.name = "Mushroom%d" % i
		root.add_child(mushroom)
		cylinder(mushroom, Vector3(0, i * 0.13 + 0.03, 0), 0.025, 0.02, 0.07, Color("dbcc9b"), 5)
		faceted(mushroom, Vector3(0, i * 0.13 + 0.08, 0), Vector3(0.16, 0.08, 0.14), Color("916137"), 12, 6).name = "MushroomCap"
		mushroom.hide()
		var berry = faceted(root, Vector3((i - 1) * 0.055, 0.06 + i * 0.025, -0.03), Vector3.ONE * 0.09, Color("b83d39"), 6, 3)
		berry.name = "Berry%d" % i
		berry.hide()
	var bowl = Node3D.new()
	bowl.name = "PlovBowl"
	root.add_child(bowl)
	cylinder(bowl, Vector3(0, 0.02, 0), 0.10, 0.14, 0.07, Color("c9d3ca"), 10)
	for i in range(3):
		faceted(bowl, Vector3((i - 1) * 0.045, 0.07, 0), Vector3(0.08, 0.045, 0.08), Color("e5c16b"), 6, 3).name = "RicePiece%d" % i
	var spoon = Node3D.new()
	spoon.name = "Spoon"
	bowl.add_child(spoon)
	box(spoon, Vector3(0.07, 0.12, 0), Vector3(0.014, 0.20, 0.014), Color("bcc5c8"))
	faceted(spoon, Vector3(0.07, 0.23, 0), Vector3(0.05, 0.075, 0.022), Color("cbd4d6"), 6, 3)
	bowl.hide()
	return root

static func meat_hand(variant: int = 0, kind: String = "meat") -> Node3D:
	var profile = spectator_profile(variant)
	var skin = Color(profile.skin)
	var forearm = Color(profile.shirt) if profile.hat == "beanie" else skin
	var root = skewer()
	pose_food(root, 0.0, kind)
	var sleeve = faceted(root, Vector3(0.07, -0.48, 0.08), Vector3(0.17, 0.35, 0.19), forearm, 8, 4)
	sleeve.rotation.z = -0.18
	box(root, Vector3(0, -0.24, 0.04), Vector3(0.13, 0.14, 0.12), skin)
	for child in root.get_children():
		if child is GeometryInstance3D:
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root

static func pose_food(node: Node3D, time: float, kind: String = "meat") -> void:
	node.set_meta("food_kind", kind)
	node.get_node("PlovBowl").visible = kind == "plov"
	node.get_node("PlovBowl/Spoon").rotation.x = sin(maxf(0, time) * 8) * 0.25
	node.get_node("SkewerStick").visible = kind in ["meat", "mushroom"]
	node.get_node("SkewerHandle").visible = kind in ["meat", "mushroom"]
	for i in range(3):
		var remains = (2 - i) >= food_bites(time)
		node.get_node("Meat%d" % i).visible = kind == "meat" and remains
		node.get_node("Mushroom%d" % i).visible = kind == "mushroom" and remains
		node.get_node("Berry%d" % i).visible = kind == "berries" and remains
		node.get_node("PlovBowl/RicePiece%d" % i).visible = kind == "plov" and remains

static func food_lift(time: float) -> float:
	if time < 0:
		return 0
	if time < 0.65:
		return smoothstep(0, 0.65, time)
	if time < 2.8:
		return 0.9 + cos((time - 0.65) * TAU / 0.72) * 0.1
	return 1.0 - smoothstep(2.8, 3.6, time)

static func food_bites(time: float) -> int:
	return (1 if time >= 1.1 else 0) + (1 if time >= 1.85 else 0) + (1 if time >= 2.6 else 0)

static func pose_skewer(node: Node3D, time: float) -> void:
	for i in range(3):
		node.get_node("Meat%d" % (2 - i)).visible = i >= food_bites(time)

# Five classic rear-wheel-drive silhouettes; fictional club liveries.
const RALLY_MODELS = [
	{"name": "Ралли-классика 1", "body": "d84b33", "accent": "f3e7ca", "length": 3.9, "roof_end": 0.95, "lights": "round", "number": 17, "sponsor": "Rally Fans Map", "trim": "c4c6b9"},
	{"name": "Ралли-универсал", "body": "e4c452", "accent": "314b39", "length": 4.15, "roof_end": 1.65, "lights": "round", "number": 24, "sponsor": "Rally Fans Map", "trim": "c4c6b9"},
	{"name": "Ралли-классика 2", "body": "ece6d1", "accent": "b43e34", "length": 4.08, "roof_end": 1.05, "lights": "twin", "number": 33, "sponsor": "Rally Fans Map", "trim": "d3d7ca"},
	{"name": "Ралли-классика 3", "body": "53868e", "accent": "f0d66a", "length": 4.0, "roof_end": 1.03, "lights": "square", "number": 51, "sponsor": "Rally Fans Map", "trim": "242d2c"},
	{"name": "Ралли-классика 4", "body": "314c80", "accent": "ede9d5", "length": 4.12, "roof_end": 1.02, "lights": "square", "number": 77, "sponsor": "Rally Fans Map", "trim": "cdd0c2"},
	{"name": "Ралли-такси 65", "body": "727c83", "accent": "e5e7d8", "length": 4.12, "roof_end": 1.02, "lights": "square", "number": 65, "sponsor": "Rally Fans Map", "trim": "bcc4c2"},
]

# Compact block lettering uses only triangles, including on minimal Web templates.
static func flag_wordmark(text: String, pixel: float) -> ArrayMesh:
	var glyphs = {
		"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
		"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
		"L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
		"Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
		"F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
		"N": ["10001", "11001", "11001", "10101", "10011", "10011", "10001"],
		"M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
		"P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
		"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"]
	}
	var vertices = PackedVector3Array()
	var width = float(text.length() * 6 - 1)
	for i in range(text.length()):
		var rows: Array = glyphs.get(text.substr(i, 1), [])
		for row in range(rows.size()):
			for col in range(5):
				if rows[row].substr(col, 1) != "1":
					continue
				var x = (i * 6 + col - width * 0.5) * pixel
				var y = (3.5 - row) * pixel
				var a = Vector3(x, y, 0)
				var b = Vector3(x + pixel, y, 0)
				var c = Vector3(x + pixel, y - pixel, 0)
				var d = Vector3(x, y - pixel, 0)
				vertices.append_array(PackedVector3Array([a, b, c, a, c, d]))
	return panel_mesh(vertices)

static func rally_fans_map_flag(parent: Node3D, pos: Vector3, yaw: float, index: int = 0) -> Node3D:
	var root = Node3D.new()
	root.name = "RallyFansMapFlag_%d" % (index + 1)
	root.position = pos
	root.rotation.y = yaw
	root.set_meta("rally_fans_map_flag", true)
	root.set_meta("flag_index", index)
	parent.add_child(root)
	# The silhouette is geometry, not an alpha texture: no transparent sorting.
	cylinder(root, Vector3(0, 1.55, 0), 0.055, 0.045, 3.1, Color("263238"), 7)
	var cloth = MeshInstance3D.new()
	cloth.name = "FlagCloth"
	var outline = PackedVector2Array([
		Vector2(-0.66, 1.26), Vector2(-0.28, 1.325), Vector2(0.32, 1.28),
		Vector2(0.64, 1.12), Vector2(0.54, 0.58), Vector2(0.68, 0.04),
		Vector2(0.53, -0.58), Vector2(0.63, -1.25), Vector2(-0.65, -1.18),
		Vector2(-0.57, -0.58), Vector2(-0.69, 0.12), Vector2(-0.57, 0.72)
	])
	var vertices = PackedVector3Array()
	for i in range(outline.size()):
		var next = outline[(i + 1) % outline.size()]
		vertices.append_array(PackedVector3Array([Vector3.ZERO, Vector3(outline[i].x, outline[i].y, 0), Vector3(next.x, next.y, 0)]))
	cloth.mesh = panel_mesh(vertices)
	var cloth_material = material(Color("ee531b"))
	cloth_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cloth_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	cloth.material_override = cloth_material
	root.add_child(cloth)
	cloth.position = Vector3(0.72, 1.65, 0)
	# Opaque glyph triangles avoid font generation, SVG import and alpha sorting.
	# Separate outward-facing meshes keep the back readable, not mirrored.
	for face in [-1, 1]:
		for line in range(2):
			var text = MeshInstance3D.new()
			text.name = "Wordmark_%s_%d" % ["Front" if face > 0 else "Back", line]
			var title = "RALLY" if line == 0 else "FANS MAP"
			text.set_meta("wordmark", title)
			text.mesh = flag_wordmark(title, 0.035 if line == 0 else 0.021)
			var ink = material(Color("fff4e6"))
			ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			ink.cull_mode = BaseMaterial3D.CULL_DISABLED
			text.material_override = ink
			text.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(text)
			text.position = Vector3(0.72, 1.75 if line == 0 else 1.34, face * 0.035)
			text.rotation.y = PI if face < 0 else 0.0
	return root

static func label_3d(parent: Node3D, pos: Vector3, text: String, size: int, pixel_size: float, color: Color, yaw: float = 0.0) -> Label3D:
	var label = Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_size = 0
	label.no_depth_test = false
	parent.add_child(label)
	label.position = pos
	label.rotation.y = yaw
	return label

static func rally_car(variant: int, number_override: int = -1, sponsor_override: String = "") -> Node3D:
	variant = posmod(variant, RALLY_MODELS.size())
	var profile: Dictionary = RALLY_MODELS[variant].duplicate()
	if number_override >= 0:
		profile.number = number_override
	if sponsor_override != "":
		profile.sponsor = sponsor_override
	var root = Node3D.new()
	root.name = "Rally_%d" % variant
	root.set_meta("model", profile.name)
	root.set_meta("variant", variant)
	root.set_meta("number", profile.number)
	var body = Color(profile.body)
	var accent = Color(profile.accent)
	var trim = Color(profile.trim)
	var length: float = profile.length
	var front = -length * 0.5
	var rear = length * 0.5
	var roof_end: float = profile.roof_end
	box(root, Vector3(0, 0.68, 0), Vector3(1.74, 0.62, length), body)
	box(root, Vector3(0, 0.93, -1.15), Vector3(1.72, 0.12, 1.35), body)
	# Dark glass cabin with slanted front windshield and visible body pillars.
	box(root, Vector3(0, 1.22, (roof_end - 0.7) * 0.5), Vector3(1.53, 0.55, roof_end + 0.7), Color("294047"))
	var windscreen = box(root, Vector3(0, 1.22, -0.76), Vector3(1.45, 0.56, 0.04), Color("37525a"))
	windscreen.rotation.x = -0.23
	box(root, Vector3(0, 1.53, (roof_end - 0.55) * 0.5), Vector3(1.63, 0.11, roof_end + 0.55), body)
	for side in [-1, 1]:
		for z in [-0.55, 0.25, roof_end - 0.05]:
			box(root, Vector3(side * 0.78, 1.22, z), Vector3(0.07, 0.59, 0.09), body)
		box(root, Vector3(side * 0.8, 0.98, 0.15), Vector3(0.045, 0.07, roof_end + 0.7), trim)
		box(root, Vector3(side * 0.88, 1.03, -0.57), Vector3(0.23, 0.13, 0.18), Color("242d2c"))
		for z in [-1.25, 1.27]:
			var wheel = cylinder(root, Vector3(side * 0.9, 0.38, z), 0.38, 0.38, 0.3, Color("202826"), 10)
			wheel.rotation.z = PI / 2
			wheel.set_meta("rolling_wheel_radius", 0.38)
			var hub = cylinder(root, Vector3(side * 1.06, 0.38, z), 0.23, 0.23, 0.035, accent, 8)
			hub.rotation.z = PI / 2
			hub.set_meta("rolling_wheel_radius", "inherit")
			box(root, Vector3(side * 0.9, 0.47, z + 0.4), Vector3(0.27, 0.44, 0.06), Color("212a24"))
			box(root, Vector3(side * 0.89, 0.79, z), Vector3(0.13, 0.13, 0.77), accent)
		# Door number panels, club sponsor and lower sill stripes.
		var x: float = side * 0.884
		var yaw: float = side * PI / 2
		box(root, Vector3(x, 0.77, 0.12), Vector3(0.015, 0.4, 0.67), Color("f4efdc"))
		label_3d(root, Vector3(side * 0.899, 0.79, 0.12), str(profile.number), 96, 0.0029, Color("202d29"), yaw)
		box(root, Vector3(x, 0.7, -0.72), Vector3(0.02, 0.23, 0.62), accent)
		label_3d(root, Vector3(side * 0.905, 0.7, -0.72), profile.sponsor, 30, 0.0015, Color("172724"), yaw)
		box(root, Vector3(x, 0.4, 0), Vector3(0.03, 0.12, 2.9), accent)
		if variant != 5:
			label_3d(root, Vector3(side * 0.798, 1.35, 0.48), "CREW / RUS", 32, 0.0018, Color("f5edcf"), yaw)
		# Chequered sponsor sticker on rear quarters.
		for row in range(2):
			for col in range(4):
				box(root, Vector3(x, 0.85 + row * 0.075, 1.12 + col * 0.075), Vector3(0.02, 0.075, 0.075), Color("ede7d5") if (row + col) % 2 == 0 else Color("202b26"))
	box(root, Vector3(0, 0.47, front - 0.05), Vector3(1.82, 0.13, 0.12), trim)
	box(root, Vector3(0, 0.47, rear + 0.05), Vector3(1.82, 0.13, 0.12), trim)
	box(root, Vector3(0, 0.78, front - 0.016), Vector3(1.48, 0.31, 0.03), Color("1c2825"))
	for y in [0.67, 0.74, 0.81, 0.88]:
		box(root, Vector3(0, y, front - 0.035), Vector3(0.7 if variant not in [4, 5] else 0.54, 0.026, 0.02), trim)
	if profile.lights == "square":
		for x in [-0.59, 0.59]:
			box(root, Vector3(x, 0.79, front - 0.05), Vector3(0.4, 0.22, 0.05), Color("fff0ba"))
		if variant in [4, 5]:
			box(root, Vector3(0, 0.8, front - 0.064), Vector3(0.6, 0.4, 0.025), trim)
			box(root, Vector3(0, 0.8, front - 0.08), Vector3(0.49, 0.31, 0.012), Color("26302b"))
			for x in [-0.18, -0.06, 0.06, 0.18]:
				box(root, Vector3(x, 0.8, front - 0.092), Vector3(0.026, 0.3, 0.012), trim)
	else:
		var headlights = [-0.66, -0.43, 0.43, 0.66] if profile.lights == "twin" else [-0.6, 0.6]
		for x in headlights:
			var light = cylinder(root, Vector3(x, 0.78, front - 0.06), 0.115 if profile.lights == "twin" else 0.15, 0.115 if profile.lights == "twin" else 0.15, 0.055, Color("fff0ba"), 10)
			light.rotation.x = PI / 2
	for x in [-0.62, 0.62]:
		box(root, Vector3(x, 0.77, rear + 0.025), Vector3(0.33, 0.21 if variant != 1 else 0.35, 0.06), Color("b34230"))
	# Hood stripes and windshield banner are actual geometry / text decals.
	for x in [-0.23, 0.23]:
		box(root, Vector3(x, 0.998, -1.21), Vector3(0.16, 0.012, 1.25), accent)
	box(root, Vector3(0, 1.45, -0.818), Vector3(1.43, 0.14, 0.025), accent)
	label_3d(root, Vector3(0, 1.45, -0.84), profile.sponsor, 32, 0.0018, Color("172724"), PI)
	if variant == 0:
		# A pair of round auxiliary lamps on the classic sedan.
		for x in [-0.28, 0.28]:
			var lamp = cylinder(root, Vector3(x, 0.51, front - 0.19), 0.13, 0.13, 0.09, Color("eac970"), 8)
			lamp.rotation.x = PI / 2
	elif variant == 1:
		# A wagon, with a long roof, roof rack and upright rear door.
		for x in [-0.6, 0.6]:
			box(root, Vector3(x, 1.64, 0.5), Vector3(0.05, 0.1, 1.7), trim)
		for z in [-0.15, 0.6, 1.25]:
			box(root, Vector3(0, 1.69, z), Vector3(1.45, 0.05, 0.05), trim)
		box(root, Vector3(0, 1.19, 1.76), Vector3(1.57, 0.57, 0.1), body)
		box(root, Vector3(0, 1.29, 1.822), Vector3(1.37, 0.33, 0.025), Color("294047"))
	elif variant != 5:
		for x in [-0.55, 0.55]:
			box(root, Vector3(x, 1.15, rear - 0.22), Vector3(0.06, 0.24, 0.06), trim)
		box(root, Vector3(0, 1.3, rear - 0.22), Vector3(1.82, 0.09, 0.32), accent)
	if variant == 5:
		# Neutral silver #65 livery with widened arches and coloured panels.
		for side in [-1, 1]:
			var yaw = side * PI / 2
			for z in [-1.25, 1.27]:
				box(root, Vector3(side * 0.94, 0.87, z), Vector3(0.22, 0.12, 0.96), Color("ccd1c9"))
			box(root, Vector3(side * 0.90, 0.86, 0.16), Vector3(0.028, 0.36, 0.81), Color("eceddd"))
			box(root, Vector3(side * 0.92, 1.02, 0.16), Vector3(0.025, 0.12, 0.81), Color("279e85"))
			label_3d(root, Vector3(side * 0.94, 0.94, -0.10), "65", 96, 0.0026, Color("e5e02a"), yaw)
			label_3d(root, Vector3(side * 0.82, 1.36, 0.54), "65", 96, 0.0030, Color("f06424"), yaw)
			box(root, Vector3(side * 0.94, 0.48, 0.35), Vector3(0.025, 0.15, 2.35), Color("625c46"))
		box(root, Vector3(0, 1.46, -0.85), Vector3(1.46, 0.15, 0.027), Color("23a887"))
		box(root, Vector3(0, 1.46, -0.87), Vector3(0.94, 0.15, 0.028), Color("f0efe1"))
		label_3d(root, Vector3(0, 1.46, -0.90), "Rally Fans Map", 32, 0.0019, Color("299a78"), PI)
		box(root, Vector3(0, 1.01, -1.35), Vector3(0.55, 0.025, 0.42), Color("299e86"))
		box(root, Vector3(0, 0.39, front - 0.15), Vector3(1.95, 0.22, 0.15), Color("d3d7d0"))
		# Must sit on the trunk, behind the rear window, rather than on the roof.
		var taxi = box(root, Vector3(0, 1.12, 1.65), Vector3(0.68, 0.22, 0.23), Color("eabe2c"))
		taxi.name = "TrunkTaxi"
		for face in [-1, 1]:
			for row in range(2):
				for col in range(8):
					if (row + col) % 2 == 0:
						box(taxi, Vector3(-0.245 + col * 0.07, -0.04 + row * 0.07, face * 0.12), Vector3(0.06, 0.06, 0.01), Color("242a25"))
	return root

static func course_car(role: String, zero_index: int = 0) -> Node3D:
	if role == "zero":
		var node = rally_car([0, 2, 4][clampi(zero_index - 1, 0, 2)], 0, "БЕЗОПАСНОСТЬ")
		node.name = "ZeroCrew_%d" % zero_index
		node.set_meta("model", "Нулевой экипаж %d" % zero_index)
		node.set_meta("role", role)
		return node
	var node = car(Color("f0f2ee"))
	node.name = "Police"
	node.set_meta("model", "Замыкающая полиция" if role == "closing_police" else "Полиция открытия СУ")
	node.set_meta("number", 0)
	node.set_meta("role", role)
	for side in [-1, 1]:
		box(node, Vector3(side * 0.936, 0.86, 0), Vector3(0.025, 0.21, 3.45), Color("2458aa"))
		label_3d(node, Vector3(side * 0.96, 0.86, 0.1), "ПОЛИЦИЯ", 64, 0.0020, Color.WHITE, side * PI / 2)
	box(node, Vector3(0, 1.66, 0.2), Vector3(1.25, 0.09, 0.29), Color("27323c"))
	var blue = box(node, Vector3(-0.38, 1.78, 0.2), Vector3(0.43, 0.17, 0.25), Color("247fff"))
	blue.name = "BeaconBlue"
	var red = box(node, Vector3(0.38, 1.78, 0.2), Vector3(0.43, 0.17, 0.25), Color("ff4038"))
	red.name = "BeaconRed"
	for light in [blue, red]:
		unique_material(light)
		light.material_override.emission_enabled = true
		light.material_override.emission = light.material_override.albedo_color
		light.material_override.emission_energy_multiplier = 2.5
	return node

static func update_course_lights(node: Node3D, clock: float) -> void:
	var blue = node.get_node_or_null("BeaconBlue")
	if blue == null:
		return
	blue.visible = posmod(int(clock * 5), 2) == 0
	node.get_node("BeaconRed").visible = not blue.visible

static func beer_hand(variant: int = 0) -> Node3D:
	var profile = spectator_profile(variant)
	var skin = Color(profile.skin)
	var forearm = Color(profile.shirt) if profile.hat == "beanie" else skin
	var root = Node3D.new()
	root.name = "BeerHand"
	# Wrist and a thumb wrapping around the can, in camera-local space.
	var sleeve = faceted(root, Vector3(0.08, -0.32, 0.1), Vector3(0.18, 0.42, 0.20), forearm, 8, 4)
	sleeve.rotation.z = -0.18
	box(root, Vector3(0.035, -0.1, 0.045), Vector3(0.13, 0.17, 0.12), skin)
	box(root, Vector3(-0.065, -0.035, 0.025), Vector3(0.045, 0.11, 0.07), skin.lightened(0.04))
	for y in [-0.085, -0.045, -0.005]:
		box(root, Vector3(0.01, y, 0.084), Vector3(0.11, 0.03, 0.035), skin.lightened(0.04))
	cylinder(root, Vector3.ZERO, 0.065, 0.065, 0.23, Color("dbb54e"), 10)
	cylinder(root, Vector3(0, 0.12, 0), 0.062, 0.062, 0.008, Color("c4cac5"), 10)
	cylinder(root, Vector3(0, -0.12, 0), 0.062, 0.062, 0.008, Color("c4cac5"), 10)
	box(root, Vector3(0, 0, 0.064), Vector3(0.095, 0.12, 0.006), Color("35482c"))
	label_3d(root, Vector3(0, 0.014, 0.071), "ПИВО", 48, 0.0009, Color("f3e6b8"))
	label_3d(root, Vector3(0, -0.025, 0.071), "0.5", 32, 0.0008, Color("f3e6b8"))
	var tab = box(root, Vector3(0, 0.128, 0.015), Vector3(0.025, 0.006, 0.045), Color("888f89"))
	tab.name = "PullTab"
	var opening = cylinder(root, Vector3(0, 0.126, -0.022), 0.018, 0.018, 0.002, Color("222c24"), 8)
	opening.name = "Opening"
	opening.hide()
	# Hands should never cast a giant shadow into the world.
	for child in root.get_children():
		if child is GeometryInstance3D:
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root

static func tree(parent: Node3D, pos: Vector3, height: float, shade: float) -> void:
	var tree_root = Node3D.new()
	parent.add_child(tree_root)
	tree_root.position = pos
	cylinder(tree_root, Vector3(0, height * 0.32, 0), 0.2, 0.13, height * 0.64, Color("67543d"), 5)
	for i in range(3):
		cylinder(tree_root, Vector3(0, height * (0.47 + i * 0.18), 0), height * (0.28 - i * 0.055), 0, height * 0.49, Color(0.17 + shade, 0.28 + shade, 0.21 + shade), 6)

static func table(parent: Node3D) -> void:
	box(parent, Vector3(0, 0.82, 0), Vector3(2.1, 0.12, 1.05), Color("c9ac78"))
	for x in [-0.85, 0.85]:
		for z in [-0.35, 0.35]:
			box(parent, Vector3(x, 0.4, z), Vector3(0.07, 0.8, 0.07), Color("ded9c9"))
	box(parent, Vector3(0.4, 0.94, 0), Vector3(0.45, 0.1, 0.3), Color("ede7d5"))
	cylinder(parent, Vector3(-0.6, 1.02, 0.15), 0.1, 0.1, 0.28, Color("ae6936"))

static func chair(parent: Node3D, pos: Vector3) -> void:
	box(parent, pos + Vector3(0, 0.48, 0), Vector3(0.65, 0.09, 0.65), Color("cf703e"))
	box(parent, pos + Vector3(0, 0.85, 0.3), Vector3(0.65, 0.65, 0.08), Color("cf703e"))
	for x in [-0.27, 0.27]:
		for z in [-0.27, 0.27]:
			box(parent, pos + Vector3(x, 0.23, z), Vector3(0.06, 0.46, 0.06), Color("dcd7c7"))

static func wood_bundle(parent: Node3D, point: Vector3 = Vector3.ZERO) -> Node3D:
	var root = Node3D.new()
	parent.add_child(root)
	root.position = point
	for i in range(5):
		var log = cylinder(root, Vector3((i % 3 - 1) * 0.12, 0.04 + (i / 3) * 0.10, 0), 0.065, 0.065, 0.42, Color("705035"), 7)
		log.rotation.x = PI / 2
	box(root, Vector3(0, 0.10, 0), Vector3(0.38, 0.025, 0.04), Color("d2bf89"))
	return root

static func campfire(parent: Node3D) -> Node3D:
	var root = Node3D.new()
	root.name = "Campfire"
	parent.add_child(root)
	for i in range(10):
		var angle = i * TAU / 10
		faceted(root, Vector3(cos(angle) * 0.7, 0.09, sin(angle) * 0.7), Vector3(0.27, 0.18, 0.23), Color("686e6a"), 6, 3)
	for i in range(5):
		var log = cylinder(root, Vector3(0, 0.17 + i * 0.035, 0), 0.075, 0.065, 0.95, Color("62412c"), 7)
		log.rotation = Vector3(PI / 2, i * 1.3, 0)
	var flames = Node3D.new()
	flames.name = "Flames"
	root.add_child(flames)
	for i in range(5):
		var flame = faceted(flames, Vector3(sin(i * 2.4) * 0.23, 0.35, cos(i * 2.4) * 0.23), Vector3(0.19, 0.55, 0.19), Color("ff751e") if i % 2 else Color("ffc53f"), 5, 3)
		unique_material(flame)
		flame.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return root

static func cauldron(parent: Node3D) -> Node3D:
	var root = Node3D.new()
	root.name = "Cauldron"
	parent.add_child(root)
	# Three-legged stand and hollow tapered bowl; the inside stays visible when empty.
	for i in range(3):
		var angle = i * TAU / 3
		var a = Vector3(cos(angle) * 0.68, 0.05, sin(angle) * 0.68)
		var b = Vector3(cos(angle) * 0.50, 1.24, sin(angle) * 0.50)
		var leg = cylinder(root, (a + b) / 2, 0.025, 0.025, a.distance_to(b), Color("444c50"), 6)
		leg.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
	var vertices = PackedVector3Array()
	var rim_vertices = PackedVector3Array()
	for i in range(16):
		var a = i * TAU / 16
		var b = (i + 1) * TAU / 16
		var low_a = Vector3(cos(a) * 0.32, 0.86, sin(a) * 0.32)
		var low_b = Vector3(cos(b) * 0.32, 0.86, sin(b) * 0.32)
		var high_a = Vector3(cos(a) * 0.55, 1.28, sin(a) * 0.55)
		var high_b = Vector3(cos(b) * 0.55, 1.28, sin(b) * 0.55)
		vertices.append_array(PackedVector3Array([low_a, high_a, high_b, low_a, high_b, low_b]))
		var inner_a = Vector3(cos(a) * 0.50, 1.28, sin(a) * 0.50)
		var inner_b = Vector3(cos(b) * 0.50, 1.28, sin(b) * 0.50)
		rim_vertices.append_array(PackedVector3Array([high_a, inner_a, inner_b, high_a, inner_b, high_b]))
	var metal = material(Color("303a40"))
	metal.cull_mode = BaseMaterial3D.CULL_DISABLED
	for data in [vertices, rim_vertices]:
		var bowl = MeshInstance3D.new()
		bowl.mesh = panel_mesh(data)
		bowl.material_override = metal
		root.add_child(bowl)
	cylinder(root, Vector3(0, 0.88, 0), 0.32, 0.32, 0.025, Color("151d22"), 16).name = "EmptyBottom"
	for side in [-1, 1]:
		box(root, Vector3(side * 0.60, 1.15, 0), Vector3(0.22, 0.055, 0.10), Color("303a40"))
	var rice = Node3D.new()
	rice.name = "Rice"
	root.add_child(rice)
	var surface = cylinder(rice, Vector3.ZERO, 0.36, 0.465, 0.26, Color("e1ba64"), 16)
	surface.name = "FoodSurface"
	unique_material(surface)
	for i in range(FOOD_PORTIONS):
		var portion = Node3D.new()
		portion.name = "Portion_%02d" % i
		rice.add_child(portion)
		var angle = i * 2.4
		var radius = 0.12 + (i % 3) * 0.12
		portion.position = Vector3(cos(angle) * radius, 0.145, sin(angle) * radius)
		for j in range(4):
			var grain = box(portion, Vector3((j % 2) * 0.035, 0.008, (j / 2) * 0.035), Vector3(0.026, 0.020, 0.055), Color("f5d994"))
			grain.rotation.y = j * 0.7
		box(portion, Vector3(-0.03, 0.015, 0), Vector3(0.045, 0.035, 0.06), Color("d87e2f"))
		box(portion, Vector3(0.03, 0.027, -0.025), Vector3(0.06, 0.05, 0.045), Color("895033"))
	var bubbles = Node3D.new()
	bubbles.name = "Bubbles"
	root.add_child(bubbles)
	for i in range(4):
		faceted(bubbles, Vector3(cos(i * 2.3) * 0.28, 1.18, sin(i * 2.3) * 0.28), Vector3.ONE * 0.045, Color("fff0bb"), 6, 3)
	var steam = Node3D.new()
	steam.name = "Steam"
	root.add_child(steam)
	for i in range(5):
		faceted(steam, Vector3.ZERO, Vector3.ONE * 0.13, Color("dbe0d6"), 6, 3)
	pose_cauldron(root, "empty", 0, 0, 0)
	return root

static func pose_cauldron(root: Node3D, phase: String, progress: float, servings: int, time: float) -> void:
	root.set_meta("phase", phase)
	root.set_meta("servings", servings)
	var rice = root.get_node("Rice")
	var visible = phase == "cooking" or (phase == "ready" and servings > 0)
	rice.visible = visible
	var fraction = lerpf(0.15, 1.0, clampf(progress, 0, 1)) if phase == "cooking" else float(servings) / FOOD_PORTIONS
	rice.scale = Vector3(lerpf(0.70, 1.0, fraction), maxf(0.05, fraction), lerpf(0.70, 1.0, fraction))
	rice.position.y = 0.95 + 0.13 * fraction
	var surface = rice.get_node("FoodSurface")
	surface.material_override.albedo_color = Color("eee3b5").lerp(Color("e1ba64"), clampf(progress, 0, 1)) if phase == "cooking" else Color("e1ba64")
	for i in range(FOOD_PORTIONS):
		rice.get_node("Portion_%02d" % i).visible = phase == "cooking" or i < servings
	var bubbles = root.get_node("Bubbles")
	bubbles.visible = phase == "cooking"
	for i in range(bubbles.get_child_count()):
		var bubble = bubbles.get_child(i)
		bubble.position.y = rice.position.y + 0.13 * fraction + 0.03 + sin(time * 8 + i) * 0.014
		bubble.scale = Vector3.ONE * (0.7 + sin(time * 7 + i * 2) * 0.3)
	var steam = root.get_node("Steam")
	steam.visible = visible
	for i in range(steam.get_child_count()):
		var puff = steam.get_child(i)
		var cycle = fposmod(time * 0.45 + i * 0.2, 1.0)
		puff.position = Vector3(sin(time + i) * 0.16, 1.30 + cycle * 0.65, cos(time * 0.7 + i) * 0.16)
		puff.scale = Vector3.ONE * sin(cycle * PI)

static func cargo_point(profile: Dictionary, index: int) -> Vector3:
	if index < 3:
		return Vector3((index - 1) * 0.39, profile.floor + 0.18, profile.rear - 0.30)
	return Vector3(-0.30 if index == 3 else 0.30, profile.floor + 0.43, profile.rear - 0.33)

static func grill(parent: Node3D) -> Node3D:
	var root = Node3D.new()
	root.name = "PicnicGrill"
	root.set_meta("servings", FOOD_PORTIONS)
	parent.add_child(root)
	box(root, Vector3(0, 0.65, 0), Vector3(1.05, 0.32, 0.55), Color("393d37"))
	for x in [-0.43, 0.43]:
		for z in [-0.2, 0.2]:
			box(root, Vector3(x, 0.3, z), Vector3(0.05, 0.6, 0.05), Color("555c52"))
	box(root, Vector3(0, 0.83, 0), Vector3(0.9, 0.03, 0.4), Color("d9612e"))
	for i in range(5):
		box(root, Vector3(-0.36 + i * 0.18, 0.87, 0), Vector3(0.02, 0.02, 0.8), Color("d9cdb4"))
	# Ten visible parallel skewers. Each skewer is a removable child so all
	# copies of a grill can show its exact remaining serving count.
	for i in range(FOOD_PORTIONS):
		var skewer_node = Node3D.new()
		skewer_node.name = "FoodSkewer_%02d" % i
		root.add_child(skewer_node)
		var x = -0.42 + i * (0.84 / (FOOD_PORTIONS - 1))
		box(skewer_node, Vector3(x, 0.93, 0), Vector3(0.012, 0.018, 0.72), Color("b9b3a3"))
		box(skewer_node, Vector3(x, 0.95, -0.39), Vector3(0.018, 0.022, 0.16), Color("a57949"))
		var meat_group = Node3D.new()
		meat_group.name = "MeatPieces"
		skewer_node.add_child(meat_group)
		for z in [-0.22, 0, 0.22]:
			var meat = box(meat_group, Vector3(x, 0.99, z), Vector3(0.048, 0.055, 0.075), Color("99502e").lightened(float(i % 3) * 0.035))
			meat.rotation.y = float(i % 2) * 0.25
		var mushroom_group = Node3D.new()
		mushroom_group.name = "MushroomFood"
		skewer_node.add_child(mushroom_group)
		for z in [-0.2, 0.0, 0.2]:
			cylinder(mushroom_group, Vector3(x, 0.96, z), 0.015, 0.012, 0.05, Color("d3c49b"), 5)
			faceted(mushroom_group, Vector3(x, 1.0, z), Vector3(0.055, 0.035, 0.07), Color("956337"), 12, 6).name = "MushroomCap_%s" % str(z)
		mushroom_group.hide()
	return root

static func set_grill_servings(grill_node: Node3D, servings: int) -> void:
	if grill_node == null:
		return
	var count = clampi(servings, 0, FOOD_PORTIONS)
	var mushrooms = clampi(int(grill_node.get_meta("mushrooms", 0)), 0, FOOD_PORTIONS - count)
	var state = Vector2i(count, mushrooms)
	if grill_node.get_meta("serving_visual_state", Vector2i(-1, -1)) == state:
		return
	grill_node.set_meta("serving_visual_state", state)
	grill_node.set_meta("servings", count)
	for i in range(FOOD_PORTIONS):
		var skewer_node = grill_node.get_node_or_null("FoodSkewer_%02d" % i)
		if skewer_node != null:
			skewer_node.visible = i < count + mushrooms
			skewer_node.get_node("MeatPieces").visible = i < count
			skewer_node.get_node("MushroomFood").visible = i >= count and i < count + mushrooms
static func rope(parent: Node3D, a: Vector3, b: Vector3) -> MeshInstance3D:
	var n = cylinder(parent, (a + b) / 2, 0.025, 0.025, a.distance_to(b), Color("e7b44c"), 5)
	n.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
	return n

static func course_official(role: String, variant: int = 0) -> Node3D:
	var avatar = player_avatar(variant + 1)
	avatar.name = "Marshal_%d" % variant if role == "marshal" else "Judge_%d" % variant
	avatar.set_meta("role", role)
	var vest = Color("e8f12c") if role == "marshal" else Color("f28a24")
	var vest_root = Node3D.new()
	vest_root.name = "SafetyVest"
	avatar.add_child(vest_root)
	# Open-front high-visibility vest with two reflective bands, on both faces.
	for side in [-1.0, 1.0]:
		box(vest_root, Vector3(side * 0.185, 1.08, -0.245), Vector3(0.29, 0.53, 0.055), vest)
		box(vest_root, Vector3(side * 0.19, 1.38, -0.07), Vector3(0.13, 0.09, 0.40), vest)
	box(vest_root, Vector3(0, 1.09, 0.225), Vector3(0.63, 0.55, 0.055), vest)
	for y in [0.95, 1.15]:
		for face in [-1.0, 1.0]:
			box(vest_root, Vector3(0, y, face * 0.278), Vector3(0.62, 0.045, 0.014), Color("e5ece8"))
	label_3d(vest_root, Vector3(0, 1.27, 0.265), "MARSHAL" if role == "marshal" else "СУДЬЯ", 36, 0.0018, Color("222c31"))
	for side in ["LeftArm", "RightArm"]:
		var arm = avatar.get_node(side)
		arm.rotation.x = 0.08
	var right = avatar.get_node("RightArm")
	right.get_node("BeerCan").hide()
	right.get_node("Skewer").hide()
	if role == "judge":
		var clipboard = box(right, Vector3(0, -0.47, -0.13), Vector3(0.19, 0.27, 0.025), Color("dadaca"))
		clipboard.name = "TimingClipboard"
		right.rotation.x = 0.65
	else:
		box(avatar, Vector3(-0.37, 1.28, 0.07), Vector3(0.11, 0.13, 0.06), Color("263336")).name = "Radio"
	return avatar

static func judges_car() -> Node3D:
	var car = player_car(6)
	car.name = "JudgesCar"
	car.set_meta("role", "judge_car")
	car.set_meta("model", "Судейская машина")
	# White upper body, orange door stripe, amber roof beacon and readable signs.
	car.get_node("BodyShell").material_override.albedo_color = Color("e5e9e6")
	for side in [-1.0, 1.0]:
		box(car, Vector3(side * 0.88, 0.75, 0.2), Vector3(0.025, 0.28, 2.15), Color("ee8529"))
		label_3d(car, Vector3(side * 0.90, 0.77, 0.15), "СУДЬИ", 54, 0.0024, Color("222c31"), side * PI / 2)
	box(car, Vector3(0, 1.58, 0.1), Vector3(0.95, 0.07, 0.24), Color("293339"))
	var beacon = cylinder(car, Vector3(0, 1.72, 0.1), 0.12, 0.09, 0.22, Color("ffb52b"), 8)
	beacon.name = "AmberBeacon"
	unique_material(beacon)
	beacon.material_override.emission_enabled = true
	beacon.material_override.emission = Color("ffaf26")
	beacon.material_override.emission_energy_multiplier = 0.6
	return car

# Opening bodywork is cut from the existing model, keeping its original shape.
static func clip_panel(poly: Array, normal: Vector3, limit: float, inside: bool) -> Array:
	var result: Array = []
	if poly.is_empty():
		return result
	var previous: Vector3 = poly[-1]
	var previous_distance = previous.dot(normal) - limit
	for current in poly:
		var distance: float = current.dot(normal) - limit
		var a = previous_distance <= 0 if inside else previous_distance >= 0
		var b = distance <= 0 if inside else distance >= 0
		if a != b:
			result.append(previous.lerp(current, previous_distance / (previous_distance - distance)))
		if b:
			result.append(current)
		previous = current
		previous_distance = distance
	return result

static func panel_triangles(target: PackedVector3Array, polygon: Array) -> PackedVector3Array:
	for i in range(1, polygon.size() - 1):
		target.append_array(PackedVector3Array([polygon[0], polygon[i], polygon[i + 1]]))
	return target

static func panel_mesh(vertices: PackedVector3Array) -> ArrayMesh:
	var mesh = ArrayMesh.new()
	if vertices.is_empty():
		return mesh
	var normals = PackedVector3Array()
	for i in range(0, vertices.size(), 3):
		var normal = (vertices[i + 1] - vertices[i]).cross(vertices[i + 2] - vertices[i]).normalized()
		normals.append_array(PackedVector3Array([normal, normal, normal]))
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

static func trunk_profile(variant: int) -> Dictionary:
	var p = PLAYER_MODELS[posmod(variant, PLAYER_MODELS.size())]
	var hatch = variant in [2, 7, 8]
	var rear: float = p.length / 2
	return {"rear": rear, "half": p.width * 0.37, "hinge": (0.35 if variant == 8 else (1.26 if hatch else rear - 0.80)), "floor": 0.70 if hatch else 0.56, "top": p.height - 0.02 if hatch else (0.99 if variant in [3, 6, 9] else 0.94), "hatch": hatch}

static func gear_box(parent: Node3D, kind: String, point: Vector3 = Vector3.ZERO) -> Node3D:
	if kind == "firewood":
		var bundle = wood_bundle(parent, point)
		bundle.name = "Box_firewood"
		return bundle
	var root = Node3D.new()
	root.name = "Box_" + kind
	parent.add_child(root)
	root.position = point
	var colors = {"table": "caa571", "chairs": "7fa78a", "grill": "a0a8b3", "cauldron": "52626b"}
	box(root, Vector3.ZERO, Vector3(0.34, 0.30, 0.48), Color(colors.get(kind, "caa571")))
	box(root, Vector3(0, 0.157, 0), Vector3(0.05, 0.014, 0.49), Color("ead9b6"))
	var titles = {"table": "СТОЛ", "chairs": "СТУЛ", "grill": "МАНГАЛ", "cauldron": "КАЗАН"}
	label_3d(root, Vector3(0, 0.02, 0.246), titles.get(kind, kind), 36, 0.0018, Color("18292e"), 0)
	return root

static func add_player_trunk(root: Node3D, variant: int) -> Node3D:
	var p = trunk_profile(variant)
	var hinge = Node3D.new()
	hinge.name = "TrunkHinge"
	root.add_child(hinge)
	# Only the imported hatch uses a tighter rear-door cut. The trunk profile
	# still controls cargo placement, so seats and stored equipment do not move.
	var lid_start: float = float(root.get_meta("trunk_lid_start_z", p.hinge))
	hinge.position = Vector3(0, p.top, lid_start)
	var planes = [Vector4(1, 0, 0, p.half), Vector4(-1, 0, 0, p.half), Vector4(0, 0, -1, -lid_start), Vector4(0, -1, 0, -p.floor - 0.10), Vector4(0, 1, 0, p.top + 0.07)]
	var bodywork: Array = root.get_children().duplicate()
	for child in bodywork:
		if not child is MeshInstance3D:
			continue
		var arrays = child.mesh.surface_get_arrays(0)
		var source: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var fixed = PackedVector3Array()
		var moving = PackedVector3Array()
		var size = indices.size() if not indices.is_empty() else source.size()
		for i in range(0, size, 3):
			var poly: Array = []
			for j in range(3):
				var index = indices[i + j] if not indices.is_empty() else i + j
				poly.append(child.transform * source[index])
			for plane in planes:
				var normal = Vector3(plane.x, plane.y, plane.z)
				fixed = panel_triangles(fixed, clip_panel(poly, normal, plane.w, false))
				poly = clip_panel(poly, normal, plane.w, true)
				if poly.is_empty():
					break
			moving = panel_triangles(moving, poly)
		if moving.is_empty():
			continue
		var lid = MeshInstance3D.new()
		lid.name = child.name + "_Lid"
		hinge.add_child(lid)
		lid.position = -hinge.position
		lid.mesh = panel_mesh(moving)
		lid.material_override = child.material_override
		# Preserve the existing named nodes for model details and tests.
		child.transform = Transform3D.IDENTITY
		if fixed.is_empty():
			child.hide()
		else:
			child.mesh = panel_mesh(fixed)
	box(root, Vector3(0, p.floor, (p.hinge + p.rear) / 2), Vector3(p.half * 2, 0.06, p.rear - p.hinge), Color("172027")).name = "TrunkWell"
	var boxes = Node3D.new()
	boxes.name = "TrunkBoxes"
	root.add_child(boxes)
	for i in range(CARGO_KINDS.size()):
		gear_box(boxes, CARGO_KINDS[i], cargo_point(p, i))
	boxes.hide()
	root.set_meta("trunk_profile", p)
	return root

static func update_player_trunk(root: Node3D, opened: bool, stored: Array, delta: float) -> void:
	var hinge = root.get_node_or_null("TrunkHinge")
	if hinge == null:
		return
	hinge.rotation.x = move_toward(hinge.rotation.x, -1.18 if opened else 0.0, delta * 1.75)
	var boxes = root.get_node("TrunkBoxes")
	boxes.visible = absf(hinge.rotation.x) > 0.12
	for i in range(boxes.get_child_count()):
		boxes.get_child(i).visible = bool(stored[i]) if i < stored.size() else true
