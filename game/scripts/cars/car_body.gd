extends RefCounted
# The one procedural car body: generic player cars (data/cars.json), the rally
# fleet (data/rally_cars.json) and the course police car are all built here
# from a profile. build() returns the measured frame, so a livery
# (rally_livery.gd) can be laid on the doors, bonnet and roof afterwards.
#
# Profile fields (defaults in each data file):
#   length, width, height, color, suv, bonnet_rise, deck_rise
#   shape: windscreen base, roof front, roof rear and rear-glass base stations,
#          then the front and rear wheel offsets from the bumpers
#   pillar (B-pillar z), doors (2 or 4), wheel (CarParts look), wheel_radius
#   lights: round | twin | square | slim | wide; lamp_tilt; tail: block | band | pillar
#   grille, grille_style (slats | chrome_lines | chrome_pair | mesh), lower_grille
#   trim (bumpers), plate (number plate colour), roof_color, stripe, spare_wheel, roof_rails,
#   spoiler (lip | wing | duck), flares, scoop, mudflaps, sunroof, aux_lamps
const P = preload("res://scripts/core/props.gd")
const CarParts = preload("res://scripts/cars/car_parts.gd")
const GLASS = Color("304a55")
const LAMP = Color("eee8b4")
const TAIL = Color("ab3631")
const DARK = Color("1f2a2e")

static func build(root: Node3D, p: Dictionary) -> Dictionary:
	var f = frame(p)
	_shell(root, p, f)
	for side in [-1.0, 1.0]:
		_side(root, p, f, side)
	_front(root, p, f)
	_rear(root, p, f)
	_extras(root, p, f)
	return f

# Measured stations shared by the shell, the details and the livery.
static func frame(p: Dictionary) -> Dictionary:
	var shape: Array = p.shape
	var suv: bool = p.get("suv", false)
	var base = 0.81 if suv else 0.67
	var bonnet = base + float(p.get("bonnet_rise", 0.27))
	var radius = float(p.get("wheel_radius", 0.43 if suv else 0.36))
	var half = float(p.width) / 2
	return {
		"front": -float(p.length) / 2, "rear": float(p.length) / 2, "half": half,
		"base": base, "bonnet": bonnet, "deck": bonnet - 0.02 + float(p.get("deck_rise", 0.0)),
		"floor": bonnet - 0.02, "height": float(p.height), "glass_half": half * 0.86,
		"radius": radius, "axles": [-float(p.length) / 2 + float(shape[4]), float(p.length) / 2 - float(shape[5])],
		"shape": shape,
		# The sides run down to the sill; each wheel sits in a round arch.
		"sill": base - 0.36, "arch": radius + 0.07,
		"track": half - (0.06 if p.get("flares", false) else 0.10),
	}

static func _shell(root: Node3D, p: Dictionary, f: Dictionary) -> void:
	var paint = Color(p.color)
	var shape: Array = f.shape
	var half: float = f.half
	var low: float = f.base - 0.26
	var sill: float = f.sill
	# Rounded nose and tail: the corners taper over the last 10 cm.
	var sections = [
		Vector4(f.front, half * 0.86, low + 0.06, f.bonnet - 0.15),
		Vector4(f.front + 0.10, half * 0.96, sill + 0.08, f.bonnet - 0.07),
		Vector4(f.front + 0.38, half, sill, f.bonnet - 0.03),
		Vector4(shape[0], half, sill, f.bonnet),
		Vector4(shape[3], half, sill, f.deck),
	]
	if f.rear - 0.10 > float(shape[3]) + 0.02:
		sections.append(Vector4(f.rear - 0.10, half * 0.97, sill + 0.08, f.deck - 0.03))
	sections.append(Vector4(f.rear, half * 0.88, low + 0.06, f.deck - 0.08))
	var arches = []
	for z in f.axles:
		arches.append(Vector3(z, f.radius, f.arch))
	var body = P.car_shell_arched(root, sections, paint, arches)
	body.name = "BodyShell"
	body.material_override.roughness = 0.5 # paint catches the sun
	var gh: float = f.glass_half
	var top: float = f.height
	var glass = P.car_shell(root, [
		Vector4(shape[0], gh, f.floor - 0.06, f.floor + 0.13),
		Vector4(shape[1], gh * 0.94, f.floor, top - 0.06),
		Vector4(shape[2], gh * 0.93, f.floor, top - 0.06),
		Vector4(shape[3], gh, f.deck - 0.08, f.deck + 0.11),
	], GLASS)
	glass.name = "GlassCabin"
	glass.material_override.roughness = 0.2
	var roof = P.car_shell(root, [
		Vector4(shape[1] - 0.03, gh * 0.95, top - 0.07, top + 0.02),
		Vector4(shape[2] + 0.03, gh * 0.94, top - 0.07, top + 0.02),
	], Color(p.get("roof_color", p.color)))
	roof.name = "Roof"
	roof.material_override.roughness = 0.5

static func _side(root: Node3D, p: Dictionary, f: Dictionary, side: float) -> void:
	var paint = Color(p.color)
	var shape: Array = f.shape
	var half: float = f.half
	var x: float = side * f.glass_half
	var top: float = f.height
	P.car_beam(root, Vector3(x, f.floor + 0.04, shape[0]), Vector3(x * 0.94, top - 0.04, shape[1]), 0.065, paint)
	P.car_beam(root, Vector3(x * 0.93, top - 0.04, shape[2]), Vector3(x, f.deck + 0.06, shape[3]), 0.08, paint)
	var pillar = float(p.get("pillar", 0.1))
	# Blacked-out B-pillar and a bright waist moulding under the side glass.
	P.car_beam(root, Vector3(x, f.floor, pillar), Vector3(x * 0.94, top - 0.05, pillar), 0.07, DARK)
	var waist = Color(p.get("waist", "aab3b2"))
	var belt: Array = [float(shape[0]) + 0.04, float(shape[3]) - 0.04]
	P.box(root, Vector3(x * 1.01, f.floor + 0.005, (belt[0] + belt[1]) * 0.5), Vector3(0.03, 0.03, belt[1] - belt[0]), waist)
	if p.get("rub_strip", true):
		side_band(root, f, side * (half + 0.012), (f.sill + f.bonnet) * 0.5 + 0.05, 0.045, f.front + 0.3, f.rear - 0.3, DARK.lightened(0.06))
	# Mirror on the door shoulder, just behind the windscreen base.
	var mirror_z = float(shape[0]) + 0.16
	P.car_beam(root, Vector3(side * half * 0.9, f.bonnet + 0.02, mirror_z), Vector3(side * (half + 0.04), f.bonnet + 0.09, mirror_z), 0.04, DARK)
	P.box(root, Vector3(side * (half + 0.07), f.bonnet + 0.11, mirror_z + 0.02), Vector3(0.09, 0.11, 0.15), DARK).name = "Mirror"
	# Door seams and handles, two doors or four.
	var skin = side * (half + 0.004)
	var seams = [float(shape[0]) + 0.05, pillar + 0.02]
	if int(p.get("doors", 4)) == 4:
		seams.append(minf(float(shape[3]) - 0.05, f.axles[1] - f.arch - 0.04))
	for z in seams:
		P.box(root, Vector3(skin, (f.sill + 0.08 + f.bonnet) * 0.5, z), Vector3(0.012, f.bonnet - f.sill - 0.08, 0.018), paint.darkened(0.3))
	# Dark rocker strip along the sill, from arch to arch.
	var rocker: Array = [f.axles[0] + f.arch + 0.01, f.axles[1] - f.arch - 0.01]
	P.box(root, Vector3(side * (half + 0.006), f.sill + 0.035, (rocker[0] + rocker[1]) * 0.5), Vector3(0.02, 0.07, rocker[1] - rocker[0]), Color(p.get("trim", "303d41")).darkened(0.25))
	var handles = [pillar - 0.22]
	if seams.size() == 3:
		handles.append(seams[2] - 0.22)
	for z in handles:
		P.box(root, Vector3(skin * 1.003, f.bonnet - 0.10, z), Vector3(0.016, 0.03, 0.13), Color("c5cbc7"))
	if p.get("stripe", "") != "":
		side_band(root, f, skin * 1.004, f.base + 0.06, 0.06, f.front + 0.3, f.rear - 0.3, Color(p.stripe))
	var look: Dictionary = p.get("wheel", {})
	for i in range(2):
		var z: float = f.axles[i]
		CarParts.wheel(root, Vector3(side * f.track, f.radius, z), f.radius, 0.24, side, look)
		wheel_well(root, side * (half - 0.03), f, z)
		if p.get("flares", false):
			_arch(root, side * (half + 0.03), f, z, paint, 0.09)
		elif p.get("suv", false):
			_arch(root, side * (half + 0.015), f, z, Color("35413d"), 0.07)
		if p.get("mudflaps", false) and i == 1:
			P.box(root, Vector3(side * (half - 0.06), f.radius * 0.45, z + f.radius + 0.12), Vector3(0.24, f.radius * 0.8, 0.02), Color("1b2124"))

# Faceted lip round a wheel arch: widened arches or plastic SUV cladding.
static func _arch(root: Node3D, x: float, f: Dictionary, z: float, paint: Color, width: float) -> void:
	var r: float = f.arch + 0.02
	for segment in range(8):
		var a = segment * PI / 8.0
		var b = (segment + 1) * PI / 8.0
		P.car_beam(root, Vector3(x, f.radius + sin(a) * r, z + cos(a) * r), Vector3(x, f.radius + sin(b) * r, z + cos(b) * r), width, paint)

# Dark wheel-well liner just inside the arch, so the arch reads as a hole.
static func wheel_well(root: Node3D, x: float, f: Dictionary, z: float) -> void:
	var r: float = f.arch - 0.015
	for segment in range(8):
		var a = segment * PI / 8.0
		var b = (segment + 1) * PI / 8.0
		var mid = (a + b) * 0.5
		var liner = P.box(root, Vector3(x, f.radius + sin(mid) * r, z + cos(mid) * r), Vector3(0.05, 0.02, r * PI / 8.0 + 0.01), Color("171c1e"))
		liner.rotation.x = -mid + PI / 2

static func _front(root: Node3D, p: Dictionary, f: Dictionary) -> void:
	var nose: float = f.front - 0.02
	var lamp_y: float = f.bonnet - 0.24
	# Lamp lenses stand 1 cm ahead of the grille and its chrome (front faces at
	# nose - 0.04), so where they overlap no two faces share a depth.
	var lens: float = nose - 0.05
	var style = str(p.get("lights", "square"))
	for side in [-1.0, 1.0]:
		var x: float = side * f.half * 0.66
		# Dark bezel round the lamps, so the face reads from a distance.
		var bezel = Vector3(f.half * 0.56, 0.21, 0.02) if style in ["round", "twin"] else Vector3(0.54 if style == "wide" else 0.44, 0.13 if style == "slim" else 0.20, 0.02)
		var bezel_x: float = side * f.half * (0.665 if style == "twin" else 0.66)
		P.box(root, Vector3(bezel_x, lamp_y + (0.02 if style == "slim" else 0.0), lens + 0.03), bezel, DARK).rotation.z = 0.0 if style in ["round", "twin"] else side * float(p.get("lamp_tilt", 0.0))
		match style:
			"round":
				_disc(root, Vector3(x, lamp_y, lens + 0.025), 0.10, LAMP)
			"twin":
				_disc(root, Vector3(side * f.half * 0.78, lamp_y, lens + 0.025), 0.08, LAMP)
				_disc(root, Vector3(side * f.half * 0.55, lamp_y, lens + 0.025), 0.08, LAMP)
			_:
				var size = Vector3(0.48 if style == "wide" else 0.38, 0.09 if style == "slim" else 0.15, 0.04)
				var lamp = P.box(root, Vector3(x, lamp_y + (0.02 if style == "slim" else 0.0), lens + 0.02), size, LAMP)
				lamp.rotation.z = side * float(p.get("lamp_tilt", 0.0))
		P.box(root, Vector3(side * f.half * 0.86, f.base - 0.09, nose - 0.01), Vector3(0.12, 0.05, 0.03), Color("e8be6c"))
	P.box(root, Vector3(0, lamp_y, nose - 0.01), Vector3(float(p.get("grille", 0.8)), 0.14, 0.03), Color("1f2e33")).name = "Grille"
	match str(p.get("grille_style", "")):
		"slats":
			for x in [-0.22, -0.11, 0, 0.11, 0.22]:
				P.box(root, Vector3(x, lamp_y, nose - 0.03), Vector3(0.05, 0.13, 0.02), Color("bdc6c3"))
		"chrome_lines":
			P.box(root, Vector3(0, lamp_y + 0.04, nose - 0.03), Vector3(float(p.get("grille", 0.8)), 0.022, 0.02), Color("c2cac5"))
			P.box(root, Vector3(0, lamp_y - 0.03, nose - 0.03), Vector3(float(p.get("grille", 0.8)), 0.022, 0.02), Color("c2cac5"))
		"chrome_pair":
			for x in [-0.15, 0.15]:
				P.box(root, Vector3(x, lamp_y, nose - 0.03), Vector3(0.24, 0.10, 0.02), Color("b8c5c7"))
		"mesh":
			for y in [-0.04, 0.0, 0.04]:
				P.box(root, Vector3(0, lamp_y + y, nose - 0.03), Vector3(float(p.get("grille", 0.8)) * 0.94, 0.012, 0.015), Color("3c474b"))
	if float(p.get("lower_grille", 0.0)) > 0.0:
		P.box(root, Vector3(0, f.base - 0.10, nose - 0.06), Vector3(float(p.lower_grille), 0.12, 0.02), Color("1d2b31"))
	_bumper(root, p, f, nose - 0.025)
	for i in range(int(p.get("aux_lamps", 0))):
		var count = int(p.aux_lamps)
		var x = (i - (count - 1) * 0.5) * 0.36
		_disc(root, Vector3(x, f.base - 0.02, nose - 0.08), 0.10, Color("f3dc8b"))

static func _rear(root: Node3D, p: Dictionary, f: Dictionary) -> void:
	var tail: float = f.rear + 0.02
	var y: float = f.deck - 0.20
	match str(p.get("tail", "block")):
		"band":
			P.box(root, Vector3(0, y, tail), Vector3(f.half * 1.7, 0.12, 0.04), TAIL.darkened(0.1))
			for side in [-1.0, 1.0]:
				P.box(root, Vector3(side * f.half * 0.66, y, tail + 0.01), Vector3(0.36, 0.10, 0.03), TAIL)
		"pillar":
			# Tall lamps up the rear corners of a box-backed wagon.
			for side in [-1.0, 1.0]:
				P.box(root, Vector3(side * f.half * 0.84, f.deck, tail), Vector3(0.16, 0.48, 0.045), TAIL)
		_:
			# Framed cluster: red outboard, amber indicator, white reverse lamp.
			var tall = 0.24 if p.get("suv", false) else 0.15
			for side in [-1.0, 1.0]:
				var x: float = side * f.half * 0.68
				P.box(root, Vector3(x, y, tail - 0.005), Vector3(0.37, tall + 0.04, 0.04), DARK)
				P.box(root, Vector3(x + side * 0.06, y, tail + 0.01), Vector3(0.2, tall, 0.03), TAIL)
				P.box(root, Vector3(x - side * 0.075, y, tail + 0.01), Vector3(0.07, tall, 0.03), Color("e39a3b"))
				P.box(root, Vector3(x - side * 0.14, y, tail + 0.01), Vector3(0.05, tall, 0.03), Color("e9ecea"))
	_bumper(root, p, f, tail + 0.025)
	if p.get("spare_wheel", false):
		var spare = CarParts.wheel(root, Vector3(0, f.base + 0.22, f.rear + 0.17), 0.36, 0.2, 1.0, p.get("wheel", {}))
		spare.rotation.y = PI / 2
		spare.remove_meta("rolling_wheel_radius")

static func _bumper(root: Node3D, p: Dictionary, f: Dictionary, z: float) -> void:
	var trim = Color(p.get("trim", "303d41"))
	P.box(root, Vector3(0, f.base - 0.19, z), Vector3(float(p.width) * 0.97, 0.15, 0.10), trim)
	# The bumper wraps round the corners as far as the wheel arch.
	var axle: float = f.axles[0] if z < 0 else f.axles[1]
	var wrap = minf(0.30, absf(axle - z) - f.arch - 0.02)
	if wrap > 0.06:
		for side in [-1.0, 1.0]:
			P.box(root, Vector3(side * (f.half - 0.01), f.base - 0.19, z - signf(z) * (wrap * 0.5 - 0.05)), Vector3(0.08, 0.15, wrap), trim)
	P.box(root, Vector3(0, f.base - 0.12, z + signf(z) * 0.055), Vector3(0.36, 0.09, 0.015), Color(p.get("plate", "e8e5d0"))).name = "Plate"

static func _extras(root: Node3D, p: Dictionary, f: Dictionary) -> void:
	var shape: Array = f.shape
	var paint = Color(p.color)
	if p.get("roof_rails", false):
		for side in [-1.0, 1.0]:
			P.box(root, Vector3(side * f.glass_half * 0.82, f.height + 0.07, (shape[1] + shape[2]) * 0.5), Vector3(0.05, 0.06, shape[2] - shape[1] + 0.2), Color("38413a"))
	if p.get("sunroof", false):
		P.box(root, Vector3(0, f.height + 0.025, shape[1] + 0.35), Vector3(f.glass_half * 0.9, 0.012, 0.5), GLASS)
	if p.get("scoop", false):
		P.box(root, Vector3(0, f.bonnet + 0.04, (f.front + shape[0]) * 0.5 + 0.1), Vector3(0.5, 0.07, 0.45), paint.darkened(0.08))
		P.box(root, Vector3(0, f.bonnet + 0.05, (f.front + shape[0]) * 0.5 - 0.13), Vector3(0.42, 0.05, 0.02), DARK)
	match str(p.get("spoiler", "")):
		"lip":
			P.box(root, Vector3(0, f.deck - 0.03, f.rear - 0.18), Vector3(f.half * 1.7, 0.04, 0.16), paint.darkened(0.1))
		"duck":
			var duck = P.box(root, Vector3(0, f.deck + 0.05, f.rear - 0.1), Vector3(f.half * 1.8, 0.05, 0.3), paint)
			duck.rotation.x = 0.25
		"wing":
			var wing_z = minf(f.rear - 0.25, float(shape[3]) + 0.25)
			var wing_y = maxf(f.deck + 0.32, f.height - 0.12) if float(shape[3]) > f.rear - 0.4 else f.deck + 0.32
			for side in [-0.55, 0.55]:
				P.box(root, Vector3(side, (f.deck + wing_y) * 0.5, wing_z), Vector3(0.05, wing_y - f.deck, 0.12), DARK)
			P.box(root, Vector3(0, wing_y, wing_z), Vector3(f.half * 1.9, 0.05, 0.34), Color(p.get("wing_color", p.color)))

static func _disc(root: Node3D, pos: Vector3, radius: float, color: Color) -> void:
	var lamp = P.cylinder(root, pos, radius, radius, 0.05, color, 10)
	lamp.rotation.x = PI / 2

# A flat band on a side panel from z0 to z1, broken where it would cross a
# wheel arch (liveries and service stripes).
static func side_band(root: Node3D, f: Dictionary, x: float, y: float, height: float, z0: float, z1: float, color: Color) -> void:
	var cuts: Array = [z0]
	if y - height * 0.5 < f.radius + f.arch:
		for axle in f.axles:
			var reach = sqrt(maxf(0.0, f.arch * f.arch - pow(maxf(0.0, y - height * 0.5 - f.radius), 2))) + 0.02
			cuts.append_array([axle - reach, axle + reach])
	cuts.append(z1)
	for i in range(0, cuts.size(), 2):
		var a = maxf(cuts[i], z0)
		var b = minf(cuts[i + 1], z1)
		if b - a > 0.05:
			P.box(root, Vector3(x, y, (a + b) * 0.5), Vector3(0.012, height, b - a), color)
