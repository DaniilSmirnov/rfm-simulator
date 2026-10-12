extends RefCounted
# The fans' folding camp table: a roll-up slatted aluminium top on tube legs,
# covered with what a rally camp leaves on it. Disposable plates and cups,
# forks and napkins, the printed start list and a stage map, and a handful of
# odd things (bottles, bread, chips, a thermos, a radio, sunglasses...). Which
# of them and where comes from `variant`, so every camp along the stage looks
# lived in and different, while host and guests see the same table.
#   TableModel.build(parent, variant)            # a spectators' camp table
#   TableModel.build(parent, variant, "desk")    # the timing desk: papers only
# Everything is baked into one mesh per (style, variant).
const P = preload("res://scripts/props.gd")
const MeshMerge = preload("res://scripts/mesh_merge.gd")
const VARIANTS = 6
const TOP = 0.885
const HALF_X = 1.05
const HALF_Z = 0.525
const FRAME = Color("a7adb0")
const SLAT = Color("a17d52")
const SLAT_ALT = Color("94714a")
const PAPER = Color("f2f0e8")
const INK = Color("4a4f55")
const PLASTIC = Color("f4f3ee")
const RED_CUP = Color("c9302c")

static func build(parent: Node3D, variant: int = 0, style: String = "camp") -> void:
	var v = posmod(variant, VARIANTS)
	_frame(parent)
	var rng = RandomNumberGenerator.new()
	rng.seed = 7919 + v * 104729 + (1 if style == "desk" else 0)
	# Places on the top: a 4 x 2 grid of cells, shuffled, one item group per cell.
	var cells: Array = []
	for i in range(4):
		for j in range(2):
			cells.append(Vector3(-0.75 + i * 0.5, TOP, -0.24 + j * 0.48))
	_shuffle(cells, rng)
	var items: Array = ["start_list", "map"] if style == "desk" else ["start_list", "plates", "cups"]
	var extras: Array = ["water", "ketchup", "bread", "chips", "thermos", "radio", "sunglasses", "cans", "napkins", "cap", "phone", "towels"]
	if style == "desk":
		extras = ["water", "radio", "thermos", "phone"]
	_shuffle(extras, rng)
	var count = mini(cells.size() - items.size(), 3 + rng.randi_range(0, 2))
	for i in range(count):
		items.append(extras[i])
	var holders: Array = []
	for i in range(items.size()):
		var spot = cells[i] + Vector3(rng.randf_range(-0.08, 0.08), 0, rng.randf_range(-0.05, 0.05))
		holders.append(_item(parent, str(items[i]), spot, rng.randf_range(-0.6, 0.6), rng))
	MeshMerge.bake(parent, "table:%s:%d" % [style, v])
	# The baked mesh replaced their contents; the empty holders go too.
	for holder in holders:
		holder.free()

static func _shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for i in range(values.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var swap = values[i]
		values[i] = values[j]
		values[j] = swap

static func _frame(parent: Node3D) -> void:
	# Roll-up top: slats across the short side, slightly gapped, alternating tone.
	var slats = 15
	var pitch = HALF_X * 2 / slats
	for i in range(slats):
		P.box(parent, Vector3(-HALF_X + pitch * (i + 0.5), TOP - 0.0125, 0), Vector3(pitch - 0.008, 0.025, HALF_Z * 2), SLAT if i % 2 == 0 else SLAT_ALT)
	# Aluminium rails under the slats.
	for z in [-HALF_Z + 0.03, HALF_Z - 0.03]:
		P.box(parent, Vector3(0, TOP - 0.045, z), Vector3(HALF_X * 2 - 0.02, 0.04, 0.025), FRAME)
	for x in [-HALF_X + 0.03, HALF_X - 0.03]:
		P.box(parent, Vector3(x, TOP - 0.045, 0), Vector3(0.025, 0.04, HALF_Z * 2 - 0.02), FRAME)
	# Tube legs, a stretcher between each pair and plastic feet.
	var leg_height = TOP - 0.065
	for x in [-0.88, 0.88]:
		for z in [-0.4, 0.4]:
			P.cylinder(parent, Vector3(x, leg_height * 0.5, z), 0.016, 0.016, leg_height, FRAME, 8)
			P.cylinder(parent, Vector3(x, 0.012, z), 0.024, 0.024, 0.024, Color("2b2e30"), 8)
		var stretcher = P.cylinder(parent, Vector3(x, 0.2, 0), 0.012, 0.012, 0.8, FRAME, 6)
		stretcher.rotation.x = PI / 2
	var spine = P.cylinder(parent, Vector3(0, 0.2, 0), 0.012, 0.012, 1.76, FRAME, 6)
	spine.rotation.z = PI / 2

# One thing (or one small group of things) on the table, standing at `spot`.
static func _item(parent: Node3D, kind: String, spot: Vector3, yaw: float, rng: RandomNumberGenerator) -> Node3D:
	var holder = Node3D.new()
	parent.add_child(holder)
	holder.position = spot
	holder.rotation.y = yaw
	match kind:
		"start_list": _start_list(holder, rng)
		"map": _stage_map(holder)
		"plates": _plates(holder, rng)
		"cups": _cups(holder, rng)
		"water":
			P.cylinder(holder, Vector3(0, 0.15, 0), 0.045, 0.045, 0.3, Color("a9d3e3"), 10)
			P.cylinder(holder, Vector3(0, 0.31, 0), 0.016, 0.016, 0.03, Color("2f6fb5"), 8)
			P.cylinder(holder, Vector3(0, 0.15, 0), 0.0465, 0.0465, 0.08, Color("2f6fb5"), 10)
		"ketchup":
			P.cylinder(holder, Vector3(0, 0.09, 0), 0.035, 0.03, 0.18, Color("b8241e"), 8)
			P.cylinder(holder, Vector3(0, 0.195, 0), 0.02, 0.012, 0.03, PLASTIC, 8)
			P.box(holder, Vector3(0, 0.09, 0.033), Vector3(0.04, 0.05, 0.002), Color("f0e2b0"))
		"bread":
			P.faceted(holder, Vector3(0, 0.05, 0), Vector3(0.26, 0.1, 0.13), Color("b9773d"), 8, 4)
			P.box(holder, Vector3(0.126, 0.045, 0), Vector3(0.008, 0.07, 0.1), Color("e8cf9a"))
		"chips":
			var bag = P.faceted(holder, Vector3(0, 0.03, 0), Vector3(0.18, 0.05, 0.25), Color("e9b92c"), 6, 3)
			bag.rotation.z = 0.1
			P.box(holder, Vector3(0, 0.055, 0), Vector3(0.09, 0.002, 0.08), Color("c8352b"))
		"thermos":
			P.cylinder(holder, Vector3(0, 0.15, 0), 0.045, 0.045, 0.3, Color("3f6b4a"), 10)
			P.cylinder(holder, Vector3(0, 0.32, 0), 0.047, 0.047, 0.05, Color("7e8686"), 10)
		"radio":
			P.box(holder, Vector3(0, 0.07, 0), Vector3(0.06, 0.14, 0.035), Color("2a2d30"))
			P.cylinder(holder, Vector3(0.018, 0.2, 0), 0.006, 0.006, 0.13, Color("2a2d30"), 6)
			P.box(holder, Vector3(0, 0.1, 0.0185), Vector3(0.035, 0.03, 0.002), Color("8ea98b"))
		"sunglasses":
			for x in [-0.035, 0.035]:
				var lens = P.cylinder(holder, Vector3(x, 0.012, 0), 0.025, 0.025, 0.006, Color("1e2328"), 8)
				lens.rotation.x = 0.25
			P.box(holder, Vector3(0, 0.02, 0), Vector3(0.12, 0.006, 0.006), Color("1e2328"))
			for x in [-0.06, 0.06]:
				P.box(holder, Vector3(x, 0.01, 0.06), Vector3(0.005, 0.005, 0.12), Color("1e2328"))
		"cans":
			for i in range(3 + rng.randi_range(0, 2)):
				var spot_can = Vector3((i % 3) * 0.075 - 0.075, 0.06, (i / 3) * 0.075)
				P.cylinder(holder, spot_can, 0.033, 0.033, 0.12, Color("3a7a46") if i % 2 == 0 else Color("b9bdc0"), 10)
			var fallen = P.cylinder(holder, Vector3(0.05, 0.033, -0.11), 0.033, 0.033, 0.12, Color("3a7a46"), 10)
			fallen.rotation = Vector3(0, 0.4, PI / 2)
		"napkins":
			P.box(holder, Vector3(0, 0.02, 0), Vector3(0.16, 0.04, 0.16), PLASTIC)
			var loose = P.box(holder, Vector3(0.12, 0.002, 0.08), Vector3(0.16, 0.003, 0.16), PLASTIC)
			loose.rotation.y = 0.5
		"cap":
			P.faceted(holder, Vector3(0, 0.04, 0), Vector3(0.19, 0.09, 0.21), Color("2c4f86"), 10, 4)
			P.box(holder, Vector3(0, 0.006, 0.13), Vector3(0.16, 0.008, 0.1), Color("2c4f86"))
		"phone":
			P.box(holder, Vector3(0, 0.005, 0), Vector3(0.075, 0.01, 0.155), Color("17191b"))
			P.box(holder, Vector3(0, 0.0105, 0), Vector3(0.065, 0.001, 0.14), Color("2f3d4d"))
		"towels":
			var roll = P.cylinder(holder, Vector3(0, 0.06, 0), 0.06, 0.06, 0.24, PLASTIC, 10)
			roll.rotation.z = PI / 2
	return holder

# The printed start list: a few stapled A4 sheets of crews and times, a little
# fanned out, the top one weighted down by nothing at all.
static func _start_list(holder: Node3D, rng: RandomNumberGenerator) -> void:
	for sheet in range(2 + rng.randi_range(0, 1)):
		var page = Node3D.new()
		holder.add_child(page)
		page.position = Vector3(sheet * 0.025, 0.0015 + sheet * 0.0012, sheet * 0.018)
		page.rotation.y = sheet * 0.12
		P.box(page, Vector3.ZERO, Vector3(0.21, 0.002, 0.297), PAPER)
		# Header: the event name in a bold bar, the RFM red mark beside it.
		P.box(page, Vector3(-0.02, 0.0016, -0.125), Vector3(0.13, 0.001, 0.016), Color("23272b"))
		P.box(page, Vector3(0.08, 0.0016, -0.125), Vector3(0.025, 0.001, 0.02), Color("d8572d"))
		# Table rows: number, crew and start time columns.
		for row in range(14):
			var z = -0.095 + row * 0.015
			P.box(page, Vector3(-0.085, 0.0016, z), Vector3(0.012, 0.001, 0.005), INK)
			P.box(page, Vector3(-0.02, 0.0016, z), Vector3(0.09 - (row % 3) * 0.015, 0.001, 0.005), INK)
			P.box(page, Vector3(0.075, 0.0016, z), Vector3(0.03, 0.001, 0.005), INK)
		P.box(page, Vector3(-0.085, 0.0016, -0.13), Vector3(0.012, 0.0015, 0.003), Color("9da3a8"))

# A printed stage map: a red route over pale contour lines.
static func _stage_map(holder: Node3D) -> void:
	P.box(holder, Vector3(0, 0.001, 0), Vector3(0.297, 0.002, 0.21), PAPER)
	for i in range(5):
		var contour = P.box(holder, Vector3(-0.1 + i * 0.05, 0.0022, 0.0), Vector3(0.004, 0.001, 0.17), Color("c9d4b8"))
		contour.rotation.y = 0.3 + i * 0.1
	var point = Vector3(-0.12, 0.0026, 0.07)
	for i in range(7):
		var next = Vector3(-0.12 + (i + 1) * 0.035, 0.0026, 0.07 * cos((i + 1) * 0.9))
		var segment = P.box(holder, (point + next) * 0.5, Vector3(0.006, 0.001, point.distance_to(next)), Color("c9302c"))
		segment.rotation.y = atan2(next.x - point.x, next.z - point.z)
		point = next

# Disposable plates: a stack and one or two used ones with leftovers.
static func _plates(holder: Node3D, rng: RandomNumberGenerator) -> void:
	for i in range(4):
		P.cylinder(holder, Vector3(0, 0.004 + i * 0.006, 0), 0.105, 0.11, 0.006, PLASTIC, 14)
	for i in range(1 + rng.randi_range(0, 1)):
		var spot = Vector3(0.22 * (1 if i == 0 else -1), 0.004, 0.08)
		P.cylinder(holder, spot, 0.105, 0.11, 0.006, PLASTIC, 14)
		P.cylinder(holder, spot + Vector3(0.02, 0.006, 0.01), 0.03, 0.03, 0.004, Color("b8241e"), 8)
		P.box(holder, spot + Vector3(-0.03, 0.009, -0.02), Vector3(0.04, 0.012, 0.03), Color("8c4527"))
		var fork = P.box(holder, spot + Vector3(0.0, 0.009, 0.04), Vector3(0.012, 0.004, 0.15), PLASTIC)
		fork.rotation.y = 0.9

# Plastic cups: a stack, a few standing, one knocked over.
static func _cups(holder: Node3D, rng: RandomNumberGenerator) -> void:
	for i in range(3):
		P.cylinder(holder, Vector3(0, 0.05 + i * 0.015, 0), 0.026, 0.037, 0.1, PLASTIC, 10)
	for i in range(2 + rng.randi_range(0, 1)):
		P.cylinder(holder, Vector3(0.1 + i * 0.08, 0.05, 0.03 * i), 0.026, 0.037, 0.1, RED_CUP if i % 2 == 0 else PLASTIC, 10)
	var tipped = P.cylinder(holder, Vector3(-0.1, 0.034, 0.08), 0.026, 0.037, 0.1, RED_CUP, 10)
	tipped.rotation = Vector3(PI / 2, 0, 0.4)
