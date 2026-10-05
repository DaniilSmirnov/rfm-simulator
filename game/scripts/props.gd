extends RefCounted
class_name RallyProps

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
			var hub = cylinder(root, Vector3(x * 1.15, 0.39, z), 0.22, 0.22, 0.03, Color("ddd7c3"), 8)
			hub.rotation.z = PI / 2
	if rally:
		box(root, Vector3(0, 1.3, 1.65), Vector3(2, 0.1, 0.42), Color("273230"))
		box(root, Vector3(0, 0.86, -0.7), Vector3(0.65, 0.1, 2), Color("f2e8d0"))
		for x in [-0.936, 0.936]:
			box(root, Vector3(x, 0.81, 0.15), Vector3(0.03, 0.32, 0.55), Color("f2e8d0"))
	return root

# Five classic rear-wheel-drive silhouettes; fictional club liveries.
const RALLY_MODELS = [
	{"name": "Копейка 2101", "body": "d84b33", "accent": "f3e7ca", "length": 3.9, "roof_end": 0.95, "lights": "round", "number": 17, "sponsor": "TAIGA", "trim": "c4c6b9"},
	{"name": "Универсал 2102", "body": "e4c452", "accent": "314b39", "length": 4.15, "roof_end": 1.65, "lights": "round", "number": 24, "sponsor": "FOREST", "trim": "c4c6b9"},
	{"name": "Тройка 2103", "body": "ece6d1", "accent": "b43e34", "length": 4.08, "roof_end": 1.05, "lights": "twin", "number": 33, "sponsor": "VOLNA", "trim": "d3d7ca"},
	{"name": "Пятёрка 2105", "body": "53868e", "accent": "f0d66a", "length": 4.0, "roof_end": 1.03, "lights": "square", "number": 51, "sponsor": "GRAVEL", "trim": "242d2c"},
	{"name": "Семёрка 2107", "body": "314c80", "accent": "ede9d5", "length": 4.12, "roof_end": 1.02, "lights": "square", "number": 77, "sponsor": "SUMMIT", "trim": "cdd0c2"},
]

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

static func rally_car(variant: int) -> Node3D:
	variant = posmod(variant, RALLY_MODELS.size())
	var profile: Dictionary = RALLY_MODELS[variant]
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
			var hub = cylinder(root, Vector3(side * 1.06, 0.38, z), 0.23, 0.23, 0.035, accent, 8)
			hub.rotation.z = PI / 2
			box(root, Vector3(side * 0.9, 0.47, z + 0.4), Vector3(0.27, 0.44, 0.06), Color("212a24"))
			box(root, Vector3(side * 0.89, 0.79, z), Vector3(0.13, 0.13, 0.77), accent)
		# Door number panels, club sponsor and lower sill stripes.
		var x: float = side * 0.884
		var yaw: float = side * PI / 2
		box(root, Vector3(x, 0.77, 0.12), Vector3(0.015, 0.4, 0.67), Color("f4efdc"))
		label_3d(root, Vector3(side * 0.899, 0.79, 0.12), str(profile.number), 96, 0.0029, Color("202d29"), yaw)
		box(root, Vector3(x, 0.7, -0.72), Vector3(0.02, 0.23, 0.62), accent)
		label_3d(root, Vector3(side * 0.905, 0.7, -0.72), profile.sponsor, 48, 0.0017, Color("172724"), yaw)
		box(root, Vector3(x, 0.4, 0), Vector3(0.03, 0.12, 2.9), accent)
		label_3d(root, Vector3(side * 0.798, 1.35, 0.48), "CREW / RUS", 32, 0.0018, Color("f5edcf"), yaw)
		# Chequered sponsor sticker on rear quarters.
		for row in range(2):
			for col in range(4):
				box(root, Vector3(x, 0.85 + row * 0.075, 1.12 + col * 0.075), Vector3(0.02, 0.075, 0.075), Color("ede7d5") if (row + col) % 2 == 0 else Color("202b26"))
	box(root, Vector3(0, 0.47, front - 0.05), Vector3(1.82, 0.13, 0.12), trim)
	box(root, Vector3(0, 0.47, rear + 0.05), Vector3(1.82, 0.13, 0.12), trim)
	box(root, Vector3(0, 0.78, front - 0.016), Vector3(1.48, 0.31, 0.03), Color("1c2825"))
	for y in [0.67, 0.74, 0.81, 0.88]:
		box(root, Vector3(0, y, front - 0.035), Vector3(0.7 if variant != 4 else 0.54, 0.026, 0.02), trim)
	if profile.lights == "square":
		for x in [-0.59, 0.59]:
			box(root, Vector3(x, 0.79, front - 0.05), Vector3(0.4, 0.22, 0.05), Color("fff0ba"))
		if variant == 4:
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
	label_3d(root, Vector3(0, 1.45, -0.84), profile.sponsor + " RALLY", 48, 0.0018, Color("172724"), PI)
	if variant == 0:
		# A pair of round auxiliary lamps on the classic 2101.
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
	else:
		for x in [-0.55, 0.55]:
			box(root, Vector3(x, 1.15, rear - 0.22), Vector3(0.06, 0.24, 0.06), trim)
		box(root, Vector3(0, 1.3, rear - 0.22), Vector3(1.82, 0.09, 0.32), accent)
	return root

static func beer_hand() -> Node3D:
	var root = Node3D.new()
	root.name = "BeerHand"
	# Wrist and a thumb wrapping around the can, in camera-local space.
	var sleeve = box(root, Vector3(0.08, -0.32, 0.1), Vector3(0.15, 0.42, 0.17), Color("526846"))
	sleeve.rotation.z = -0.18
	box(root, Vector3(0.035, -0.1, 0.045), Vector3(0.13, 0.17, 0.12), Color("caa07a"))
	box(root, Vector3(-0.065, -0.035, 0.025), Vector3(0.045, 0.11, 0.07), Color("d8af88"))
	for y in [-0.085, -0.045, -0.005]:
		box(root, Vector3(0.01, y, 0.084), Vector3(0.11, 0.03, 0.035), Color("d8af88"))
	cylinder(root, Vector3.ZERO, 0.065, 0.065, 0.23, Color("dbb54e"), 10)
	cylinder(root, Vector3(0, 0.12, 0), 0.062, 0.062, 0.008, Color("c4cac5"), 10)
	cylinder(root, Vector3(0, -0.12, 0), 0.062, 0.062, 0.008, Color("c4cac5"), 10)
	box(root, Vector3(0, 0, 0.064), Vector3(0.095, 0.12, 0.006), Color("35482c"))
	label_3d(root, Vector3(0, 0.014, 0.071), "LES", 48, 0.0009, Color("f3e6b8"))
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

static func grill(parent: Node3D) -> Node3D:
	var root = Node3D.new()
	parent.add_child(root)
	box(root, Vector3(0, 0.65, 0), Vector3(1.05, 0.32, 0.55), Color("393d37"))
	for x in [-0.43, 0.43]:
		for z in [-0.2, 0.2]:
			box(root, Vector3(x, 0.3, z), Vector3(0.05, 0.6, 0.05), Color("555c52"))
	box(root, Vector3(0, 0.83, 0), Vector3(0.9, 0.03, 0.4), Color("d9612e"))
	for i in range(5):
		box(root, Vector3(-0.36 + i * 0.18, 0.87, 0), Vector3(0.02, 0.02, 0.8), Color("d9cdb4"))
		for z in [-0.14, 0.0, 0.14]:
			box(root, Vector3(-0.36 + i * 0.18, 0.91, z), Vector3(0.13, 0.1, 0.13), Color("99542e"))
	return root

static func rope(parent: Node3D, a: Vector3, b: Vector3) -> MeshInstance3D:
	var n = cylinder(parent, (a + b) / 2, 0.025, 0.025, a.distance_to(b), Color("e7b44c"), 5)
	n.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
	return n
