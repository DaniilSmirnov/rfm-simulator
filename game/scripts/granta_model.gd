extends RefCounted

# Original, unbranded low-poly compact sedan: Granta-inspired proportions.
# Independent model source; gameplay, cargo and hatch physics stay in RallyProps.
const P = preload("res://scripts/props.gd")
const PAINT = Color("111a2b") # near-black with a restrained blue tint
const PAINT_LIT = Color("1c2a40")
const PAINT_SHADE = Color("0a101c")
const GLASS = Color("223541")
const TRIM = Color("121820")
const CHROME = Color("737f89")
const RUBBER = Color("131719")

static func _box(root: Node3D, pos: Vector3, scale_value: Vector3, color: Color, part: String) -> MeshInstance3D:
	var node = P.box(root, pos, scale_value, color)
	node.name = part
	return node

static func build() -> Node3D:
	var root = Node3D.new()
	root.name = "PlayerCar_0"
	root.set_meta("model", "Компактный седан")
	root.set_meta("variant", 0)
	root.set_meta("model_source", "granta_detailed")
	# Faceted waistline, short high tail and sloping bonnet.
	P.car_shell(root, [
		Vector4(-2.13, 0.69, 0.39, 0.72),
		Vector4(-1.94, 0.79, 0.38, 0.87),
		Vector4(-1.41, 0.85, 0.37, 0.94),
		Vector4(-0.84, 0.85, 0.37, 0.95),
		Vector4(0.58, 0.84, 0.37, 0.97),
		Vector4(1.42, 0.85, 0.39, 1.00),
		Vector4(2.13, 0.70, 0.41, 0.89),
	], PAINT).name = "BodyShellGranta"
	P.car_shell(root, [
		Vector4(-0.88, 0.74, 0.94, 1.01),
		Vector4(-0.48, 0.68, 0.96, 1.44),
		Vector4(0.63, 0.66, 0.96, 1.43),
		Vector4(1.09, 0.72, 0.97, 1.01),
	], GLASS).name = "CabinGlazing"
	P.car_shell(root, [
		Vector4(-0.48, 0.685, 1.40, 1.49),
		Vector4(-0.30, 0.69, 1.44, 1.50),
		Vector4(0.49, 0.68, 1.43, 1.49),
		Vector4(0.63, 0.655, 1.39, 1.45),
	], PAINT).name = "RoofGranta"
	# Windscreen, rear screen and side window outlines.
	P.quad_panel(root, PackedVector3Array([
		Vector3(-0.73, 1.01, -0.88), Vector3(0.73, 1.01, -0.88),
		Vector3(0.65, 1.43, -0.49), Vector3(-0.65, 1.43, -0.49),
	]), GLASS).name = "Windscreen"
	P.quad_panel(root, PackedVector3Array([
		Vector3(-0.65, 1.41, 0.62), Vector3(0.65, 1.41, 0.62),
		Vector3(0.74, 0.99, 1.11), Vector3(-0.74, 0.99, 1.11),
	]), GLASS).name = "RearScreen"
	for side in [-1.0, 1.0]:
		var x = side * 0.75
		P.car_beam(root, Vector3(x, 1.00, -0.88), Vector3(side * 0.67, 1.45, -0.47), 0.07, PAINT)
		P.car_beam(root, Vector3(side * 0.67, 1.45, 0.60), Vector3(x, 1.00, 1.12), 0.08, PAINT)
		P.car_beam(root, Vector3(side * 0.71, 1.01, 0.04), Vector3(side * 0.67, 1.46, 0.04), 0.062, PAINT)
		# Door cut lines and handles.
		for z in [-0.28, 0.78]:
			_box(root, Vector3(side * 0.853, 0.91, z), Vector3(0.018, 0.035, 0.15), CHROME, "DoorHandle")
		for z in [-0.83, 0.07, 1.06]:
			_box(root, Vector3(side * 0.854, 0.62, z), Vector3(0.012, 0.49, 0.018), PAINT_SHADE, "DoorJoint")
		_box(root, Vector3(side * 0.852, 0.43, 0.03), Vector3(0.04, 0.10, 2.10), PAINT_SHADE, "SideSill")
		# Mirrors, arms and reflective caps.
		_box(root, Vector3(side * 0.88, 1.07, -0.95), Vector3(0.14, 0.055, 0.11), TRIM, "MirrorArm")
		_box(root, Vector3(side * 0.96, 1.13, -0.95), Vector3(0.24, 0.13, 0.18), PAINT_LIT, "MirrorCap")
		_box(root, Vector3(side * 1.083, 1.12, -0.95), Vector3(0.015, 0.075, 0.13), CHROME, "MirrorGlass")
		# Wheel arches and wheels with separate low-poly alloy hubs.
		for index in range(2):
			var z = -1.35 if index == 0 else 1.40
			var tire = P.cylinder(root, Vector3(side * 0.89, 0.37, z), 0.37, 0.37, 0.29, RUBBER, 16)
			tire.rotation.z = PI / 2
			tire.name = "WheelTire"
			var rim = P.cylinder(root, Vector3(side * 1.05, 0.37, z), 0.255, 0.255, 0.04, CHROME, 12)
			rim.rotation.z = PI / 2
			rim.name = "WheelRim"
			for spoke in range(6):
				var angle = spoke * TAU / 6.0
				P.car_beam(root, Vector3(side * 1.08, 0.37, z), Vector3(side * 1.08, 0.37 + cos(angle) * 0.21, z + sin(angle) * 0.21), 0.036, PAINT_SHADE)
		# Granta-inspired swept headlamps, but no badge or trademarks.
		P.quad_panel(root, PackedVector3Array([
			Vector3(side * 0.35, 0.74, -2.143), Vector3(side * 0.77, 0.75, -2.105),
			Vector3(side * 0.79, 0.93, -1.94), Vector3(side * 0.33, 0.88, -2.12),
		]), Color("dce7ed")).name = "FrontHeadlight"
		_box(root, Vector3(side * 0.62, 0.78, -2.12), Vector3(0.25, 0.035, 0.04), Color("e8be6c"), "FrontIndicator")
		_box(root, Vector3(side * 0.60, 0.75, 2.137), Vector3(0.37, 0.21, 0.045), Color("9d303b"), "RearLamp")
		_box(root, Vector3(side * 0.68, 0.81, 2.16), Vector3(0.18, 0.045, 0.03), Color("d6c5b7"), "ReverseLamp")
	# Front fascia, unbranded grille, bumper and tow detail.
	_box(root, Vector3(0, 0.72, -2.155), Vector3(0.68, 0.18, 0.055), TRIM, "Grille")
	for x in [-0.22, 0, 0.22]:
		_box(root, Vector3(x, 0.72, -2.185), Vector3(0.11, 0.025, 0.018), PAINT_LIT, "GrilleBar")
	_box(root, Vector3(0, 0.49, -2.17), Vector3(1.55, 0.15, 0.11), PAINT_SHADE, "FrontBumper")
	_box(root, Vector3(0, 0.47, -2.245), Vector3(0.83, 0.075, 0.035), TRIM, "LowerIntake")
	_box(root, Vector3(0, 0.53, 2.155), Vector3(1.52, 0.16, 0.09), PAINT_SHADE, "RearBumper")
	_box(root, Vector3(0, 0.89, 2.14), Vector3(0.30, 0.11, 0.025), PAINT_LIT, "BlankRearPlate")
	_box(root, Vector3(0, 0.79, -2.205), Vector3(0.27, 0.10, 0.025), PAINT_LIT, "BlankFrontPlate")
	# A subtle blue sheen is conveyed by the slightly brighter crown/bonnet facets,
	# not by a logo, badge or reflective texture.
	return P.add_player_trunk(root, 0)
