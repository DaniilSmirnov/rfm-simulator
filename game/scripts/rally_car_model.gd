extends RefCounted
# The rally fleet of res://data/rally_cars.json: a car_body.gd body plus a club
# livery (door numbers, sponsor panels, bonnet and roof stripes, windscreen
# banner, roof number). Every difference between cars is data, so there are
# no per-variant branches here. The course police car uses the same body.
const P = preload("res://scripts/props.gd")
const CarBody = preload("res://scripts/car_body.gd")
const CarRegistry = preload("res://scripts/car_registry.gd")
const PATH = "res://data/rally_cars.json"
const PANEL = Color("f4efdc")
static var spec: Dictionary = _load()
static var models: Array = CarRegistry.merge_records(spec.get("defaults", {}), spec.get("cars", []))

static func _load() -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary or not data.get("cars") is Array or data.cars.is_empty():
		push_error("Rally fleet is missing: " + PATH)
		return {"defaults": {}, "cars": [{"name": "Ралли-классика", "body": "d84b33", "accent": "f3e7ca", "number": 1, "sponsor": "Rally Fans Map", "length": 4.1, "width": 1.68, "height": 1.42, "shape": [-0.75, -0.55, 0.62, 0.95, 0.68, 0.70]}]}
	return data

# Variant of the n-th crew to start, cycling through spawn_order.
static func spawn_variant(count: int) -> int:
	var order: Array = spec.get("spawn_order", [])
	if order.is_empty():
		return posmod(count, models.size())
	return posmod(int(order[posmod(count, order.size())]), models.size())

static func zero_variant(zero_index: int) -> int:
	var zero: Array = spec.get("zero_cars", [0])
	return posmod(int(zero[clampi(zero_index - 1, 0, zero.size() - 1)]), models.size())

static func build(variant: int, number_override: int = -1, sponsor_override: String = "") -> Node3D:
	variant = posmod(variant, models.size())
	var p: Dictionary = models[variant].duplicate(true)
	p.color = p.body
	p.number = int(p.number)
	if number_override >= 0:
		p.number = number_override
	if sponsor_override != "":
		p.sponsor = sponsor_override
	var root = Node3D.new()
	root.name = "Rally_%d" % variant
	root.set_meta("model", p.name)
	root.set_meta("variant", variant)
	root.set_meta("number", p.number)
	var f = CarBody.build(root, p)
	for side in [-1.0, 1.0]:
		_doors(root, p, f, side)
	_bonnet_and_roof(root, p, f)
	if p.taxi:
		_taxi(root, f)
	return root

static func police() -> Node3D:
	var p: Dictionary = spec.get("course", {}).get("police", models[0])
	var root = Node3D.new()
	root.name = "Police"
	var f = CarBody.build(root, p)
	var stripe_y: float = (f.base + f.bonnet) * 0.5
	for side in [-1.0, 1.0]:
		var x: float = side * (f.half + 0.012)
		P.box(root, Vector3(x, stripe_y, 0), Vector3(0.012, 0.2, float(p.length) - 0.7), Color("2458aa"))
		P.label_3d(root, Vector3(side * (f.half + 0.02), stripe_y, 0.1), "ПОЛИЦИЯ", 64, 0.0020, Color.WHITE, side * PI / 2)
	var roof_z: float = (float(f.shape[1]) + float(f.shape[2])) * 0.5
	P.box(root, Vector3(0, f.height + 0.06, roof_z), Vector3(1.1, 0.08, 0.27), Color("27323c"))
	var blue = P.box(root, Vector3(-0.32, f.height + 0.17, roof_z), Vector3(0.38, 0.15, 0.24), Color("247fff"))
	blue.name = "BeaconBlue"
	var red = P.box(root, Vector3(0.32, f.height + 0.17, roof_z), Vector3(0.38, 0.15, 0.24), Color("ff4038"))
	red.name = "BeaconRed"
	return root

# Number panel on the front door, sponsor panel behind it, livery on the side.
static func _doors(root: Node3D, p: Dictionary, f: Dictionary, side: float) -> void:
	var accent = Color(p.accent)
	var skin: float = side * (f.half + 0.008)
	var yaw: float = side * PI / 2
	var mid_y: float = (f.base + f.bonnet) * 0.5
	var door_z: float = (float(f.shape[0]) + float(p.pillar)) * 0.5 + 0.06
	var rear_z: float = (float(p.pillar) + float(f.axles[1]) - f.radius) * 0.5
	var length: float = f.rear - f.front - 0.5
	match str(p.livery):
		"band":
			P.box(root, Vector3(skin, f.bonnet - 0.09, 0), Vector3(0.012, 0.09, length), accent)
		"split":
			P.box(root, Vector3(skin, f.base - 0.08, 0), Vector3(0.012, 0.22, length + 0.3), accent)
		"sash":
			_strip(root, Vector3(skin, f.base - 0.12, f.axles[0] + 0.25), Vector3(skin, f.bonnet - 0.06, f.axles[1] - 0.2), 0.10, accent, true)
		"hoops":
			P.box(root, Vector3(skin, f.bonnet - 0.07, door_z), Vector3(0.012, 0.11, 0.9), accent)
			P.box(root, Vector3(skin, f.base - 0.13, 0), Vector3(0.012, 0.12, length), accent.darkened(0.35))
		_:
			P.box(root, Vector3(skin, f.base - 0.12, 0), Vector3(0.012, 0.07, length), accent)
	P.box(root, Vector3(skin + side * 0.012, mid_y, door_z), Vector3(0.012, 0.36, 0.62), PANEL)
	P.label_3d(root, Vector3(skin + side * 0.02, mid_y + 0.01, door_z), str(p.number), 96, 0.0029, Color(p.number_color), yaw)
	if rear_z - door_z > 0.45:
		P.box(root, Vector3(skin + side * 0.012, mid_y - 0.04, rear_z), Vector3(0.012, 0.2, 0.56), accent)
		P.label_3d(root, Vector3(skin + side * 0.02, mid_y - 0.04, rear_z), p.sponsor, 30, 0.0015, Color("172724"), yaw)
	# Chequered club sticker on the rear wing.
	for row in range(2):
		for col in range(4):
			var cell = Color("ede7d5") if (row + col) % 2 == 0 else Color("202b26")
			P.box(root, Vector3(skin + side * 0.012, f.bonnet - 0.12 + row * 0.07, f.rear - 0.62 + col * 0.07), Vector3(0.012, 0.07, 0.07), cell)

# Twin bonnet stripes, windscreen banner and a roof number for the chase view.
static func _bonnet_and_roof(root: Node3D, p: Dictionary, f: Dictionary) -> void:
	var accent = Color(p.accent)
	var shape: Array = f.shape
	if str(p.livery) in ["stripes", "hoops"]:
		for x in [-0.2, 0.2]:
			_strip(root, Vector3(x, f.bonnet - 0.022, f.front + 0.40), Vector3(x, f.bonnet + 0.008, float(shape[0]) - 0.02), 0.15, accent)
			_strip(root, Vector3(x, f.height + 0.024, float(shape[1])), Vector3(x, f.height + 0.024, float(shape[2])), 0.15, accent)
	var gh: float = f.glass_half
	var low = Vector3(0, f.floor + 0.13, float(shape[0]))
	var high = Vector3(0, f.height - 0.06, float(shape[1]))
	_strip(root, low.lerp(high, 0.76) + Vector3(0, 0.0, -0.012), high + Vector3(0, -0.01, -0.012), gh * 1.7, accent)
	var banner = low.lerp(high, 0.88) + Vector3(0, 0.0, -0.03)
	P.label_3d(root, banner, p.sponsor, 32, 0.0018, Color("172724"), PI).rotation.x = -atan2(high.y - low.y, high.z - low.z) + PI / 2
	var roof_z: float = (float(shape[1]) + float(shape[2])) * 0.5
	P.box(root, Vector3(0, f.height + 0.028, roof_z), Vector3(0.5, 0.012, 0.42), PANEL)
	var roof_number = P.label_3d(root, Vector3(0, f.height + 0.04, roof_z), str(p.number), 96, 0.0032, Color(p.number_color))
	roof_number.rotation = Vector3(-PI / 2, 0, 0)

# Taxi checker on the boot lid, behind the rear window and below the roof.
static func _taxi(root: Node3D, f: Dictionary) -> void:
	var z: float = minf(f.rear - 0.35, (float(f.shape[3]) + f.rear) * 0.5)
	var taxi = P.box(root, Vector3(0, f.deck + 0.12, z), Vector3(0.68, 0.22, 0.23), Color("eabe2c"))
	taxi.name = "TrunkTaxi"
	for face in [-1, 1]:
		for row in range(2):
			for col in range(8):
				if (row + col) % 2 == 0:
					P.box(taxi, Vector3(-0.245 + col * 0.07, -0.04 + row * 0.07, face * 0.12), Vector3(0.06, 0.06, 0.01), Color("242a25"))

# A thin flat strip from a to b, a and b sharing x: lying across the car (on
# a bonnet, roof or windscreen) or, with `on_side`, flat on a side panel.
static func _strip(root: Node3D, a: Vector3, b: Vector3, width: float, color: Color, on_side: bool = false) -> void:
	var direction = (b - a).normalized()
	var size = Vector3(0.012, a.distance_to(b), width) if on_side else Vector3(width, a.distance_to(b), 0.012)
	var strip = P.box(root, (a + b) * 0.5, size, color)
	strip.basis = Basis(Vector3.RIGHT, direction, Vector3.RIGHT.cross(direction))
