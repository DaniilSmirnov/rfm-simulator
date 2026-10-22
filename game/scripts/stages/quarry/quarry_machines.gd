extends RefCounted
# Pit machines of «Асбестовский карьер», built from primitives at real size:
# a 130-tonne BelAZ dump truck, an electric rope shovel of the ЭКГ family that
# loads it, and a rotary blast-hole drill. Each builder returns a node whose
# origin is on the ground under the machine's middle and whose front looks
# along -z. Moving parts are left in their own unbatched nodes (named below)
# so quarry_life.gd can work them; everything else is baked by the caller.
const Props = preload("res://scripts/core/props.gd")
const MeshMerge = preload("res://scripts/core/mesh_merge.gd")

const BELAZ_YELLOW = Color("d9a521")
const BELAZ_BODY = Color("b98d2a")
const TYRE = Color("2e2d2a")
const STEEL = Color("6f726e")
const DARK = Color("2b2e30")
const GLASS = Color("34434c")
const SHOVEL_ORANGE = Color("d6862a")
const SHOVEL_GREY = Color("8b8f88")
const ORE = Color("7d877b")
const DUSTED = 0.18

# Outline of the truck (width, height, length) and of the shovel's crawlers.
const BELAZ_SIZE = Vector3(7.0, 6.2, 11.6)
const TYRE_RADIUS = 1.55
const SHOVEL_TRACKS = Vector3(7.2, 1.6, 8.6)
# Height of the shovel's turntable, its boom foot and the boom's length.
const TURNTABLE = 2.9
const BOOM_FOOT = Vector3(0.0, 3.6, -3.6)
const BOOM_LENGTH = 14.0
const BOOM_ANGLE = 0.82

# Trims, glass and plates stand at least PROUD proud of the face they sit on:
# the machines are seen from across the pit, where thinner offsets fall
# within one step of the depth buffer and flicker.
const PROUD = 0.1

# Everything in the pit wears a coat of white dust.
static func dusted(color: Color, amount: float = DUSTED) -> Color:
	return color.lerp(Color("d9d9d0"), amount)

static func _wheel(parent: Node3D, at: Vector3, width: float) -> void:
	var tyre = Props.cylinder(parent, at, TYRE_RADIUS, TYRE_RADIUS, width, dusted(TYRE, 0.3), 14)
	tyre.rotation.z = PI * 0.5
	var rim = Props.cylinder(parent, at, 0.82, 0.82, width + PROUD * 2.0, dusted(BELAZ_YELLOW), 10)
	rim.rotation.z = PI * 0.5

# BelAZ 75131-class haul truck: two-axle, dual rear wheels, cab on the left
# of the upper deck under the dump body's canopy. `load` fills the body.
static func belaz(load: bool = false) -> Node3D:
	var truck = Node3D.new()
	truck.name = "Belaz"
	var yellow = dusted(BELAZ_YELLOW)
	# Frame, axles and wheels.
	Props.box(truck, Vector3(0, 1.7, 0.4), Vector3(2.0, 1.0, 9.6), dusted(DARK, 0.25))
	for x in [-2.95, 2.95]:
		_wheel(truck, Vector3(x, TYRE_RADIUS, -3.4), 1.0)
	for x in [-2.55, -3.5, 2.55, 3.5]:
		_wheel(truck, Vector3(x, TYRE_RADIUS, 2.4), 0.9)
	Props.box(truck, Vector3(0, TYRE_RADIUS, 2.4), Vector3(4.4, 0.9, 1.1), dusted(DARK, 0.25))
	# Front: radiator and grille, the upper deck with its rails, the stairs.
	Props.box(truck, Vector3(0, 2.6, -4.6), Vector3(3.0, 2.4, 2.0), yellow)
	Props.box(truck, Vector3(0, 2.5, -5.6 - PROUD * 0.5), Vector3(2.6, 1.8, PROUD), DARK)
	for y in [1.9, 2.3, 2.7, 3.1]:
		Props.box(truck, Vector3(0, y, -5.6 - PROUD * 1.5), Vector3(2.5, 0.08, PROUD), STEEL)
	Props.box(truck, Vector3(0, 3.95, -4.5), Vector3(6.8, 0.3, 2.6), yellow)
	Props.box(truck, Vector3(0, 1.0, -5.55), Vector3(6.4, 0.6, 0.5), yellow.darkened(0.15))
	for x in [-3.35, 3.35]:
		Props.box(truck, Vector3(x, 4.55, -4.5), Vector3(0.06, 0.06, 2.6), Color("e7e4da"))
		Props.box(truck, Vector3(x, 4.25, -5.75), Vector3(0.06, 0.6, 0.06), Color("e7e4da"))
	Props.box(truck, Vector3(0, 4.55, -5.75), Vector3(6.7, 0.06, 0.06), Color("e7e4da"))
	var stairs = Props.box(truck, Vector3(1.6, 2.6, -5.95), Vector3(1.0, 0.1, 3.4), STEEL)
	stairs.rotation.x = -1.05
	# Headlights on the bumper and the deck.
	for x in [-2.4, -1.6, 1.6, 2.4]:
		Props.box(truck, Vector3(x, 4.0, -5.8 - PROUD * 0.5), Vector3(0.4, 0.26, PROUD), Color("efe8c8"))
	# Cab on the left of the deck.
	Props.box(truck, Vector3(-2.1, 5.1, -4.3), Vector3(2.4, 2.0, 2.2), yellow)
	Props.box(truck, Vector3(-2.1, 5.35, -5.4 - PROUD * 0.5), Vector3(2.1, 1.1, PROUD), GLASS)
	Props.box(truck, Vector3(-3.3 - PROUD * 0.5, 5.35, -4.3), Vector3(PROUD, 1.1, 1.7), GLASS)
	# Dump body: floor, sides with their ribs, front wall, canopy over the cab,
	# and the floor turned up at the tail.
	var body = dusted(BELAZ_BODY, 0.28)
	Props.box(truck, Vector3(0, 3.25, 1.3), Vector3(6.8, 0.4, 8.6), body)
	for x in [-3.3, 3.3]:
		Props.box(truck, Vector3(x, 4.5, 1.3), Vector3(0.24, 2.6, 8.6), body)
		for z in [-1.6, 0.6, 2.8, 5.0]:
			Props.box(truck, Vector3(signf(x) * (3.42 + PROUD * 0.5), 4.4, z), Vector3(PROUD, 2.3, 0.3), body.darkened(0.12))
	Props.box(truck, Vector3(0, 4.9, -3.0), Vector3(6.8, 3.4, 0.3), body)
	Props.box(truck, Vector3(0, 6.45, -4.5), Vector3(7.0, 0.3, 3.1), body)
	var tail = Props.box(truck, Vector3(0, 4.0, 5.85), Vector3(6.6, 0.3, 1.8), body)
	tail.rotation.x = 0.5
	if load:
		for i in range(5):
			var heap = Props.faceted(truck, Vector3((i % 3 - 1) * 1.9, 5.2 + (i % 2) * 0.4, -1.6 + i * 1.6), Vector3(2.6, 1.6, 2.4), dusted(ORE, 0.25 + 0.05 * (i % 2)), 7, 3)
			heap.rotation.y = i * 1.3
	return truck

# Electric rope shovel (ЭКГ): crawlers, a turntable, the machinery house with
# its cab and A-frame, the boom with its point sheaves, the stick through the
# saddle block and the dipper on hoist ropes. The house and everything on it
# swing in the node "ShovelHouse"; the stick and dipper crowd in "ShovelStick".
static func shovel() -> Node3D:
	var machine = Node3D.new()
	machine.name = "Shovel"
	for x in [-2.6, 2.6]:
		Props.box(machine, Vector3(x, 0.8, 0), Vector3(2.0, 1.6, SHOVEL_TRACKS.z), dusted(DARK, 0.3))
		for z in range(-4, 5):
			Props.box(machine, Vector3(x, 1.6 + PROUD * 0.5, z * 0.95), Vector3(2.0 + PROUD * 2.0, PROUD * 2.0, 0.3), dusted(STEEL, 0.3))
	Props.box(machine, Vector3(0, 1.3, 0), Vector3(3.4, 1.0, 5.0), dusted(DARK, 0.25))
	Props.cylinder(machine, Vector3(0, 2.25, 0), 3.0, 3.0, 0.9, dusted(SHOVEL_GREY), 16)
	var house = Node3D.new()
	house.name = "ShovelHouse"
	house.set_meta("unbatched", true)
	machine.add_child(house)
	house.position = Vector3(0, TURNTABLE, 0)
	var orange = dusted(SHOVEL_ORANGE)
	Props.box(house, Vector3(0, 2.4, 1.2), Vector3(6.4, 4.4, 8.4), orange)
	Props.box(house, Vector3(0, 4.7, 1.2), Vector3(6.6, 0.2, 8.6), dusted(SHOVEL_GREY))
	Props.box(house, Vector3(0, 1.4, 5.7), Vector3(6.2, 2.6, 1.2), dusted(SHOVEL_GREY, 0.25))
	for z in [-1.0, 1.0, 3.0]:
		Props.box(house, Vector3(3.2 + PROUD * 0.5, 3.2, z), Vector3(PROUD, 0.8, 1.4), DARK)
	# Operator's cab at the front left, with a window on the boom.
	Props.box(house, Vector3(-2.4, 3.2, -3.6), Vector3(2.0, 2.4, 2.2), orange)
	Props.box(house, Vector3(-2.4, 3.5, -4.7 - PROUD * 0.5), Vector3(1.7, 1.2, PROUD), GLASS)
	Props.box(house, Vector3(-3.4 - PROUD * 0.5, 3.5, -3.6), Vector3(PROUD, 1.2, 1.6), GLASS)
	# A-frame (gantry) with the boom suspension ropes to the boom point.
	var gantry_top = Vector3(0, 9.0, 1.0)
	for x in [-2.2, 2.2]:
		Props.car_beam(house, Vector3(x, 4.8, -1.4), gantry_top + Vector3(x * 0.3, 0, 0), 0.4, dusted(SHOVEL_GREY))
		Props.car_beam(house, Vector3(x, 4.8, 4.2), gantry_top + Vector3(x * 0.3, 0, 0), 0.4, dusted(SHOVEL_GREY))
	var foot = BOOM_FOOT - Vector3(0, TURNTABLE, 0)
	var point = foot + Vector3(0, sin(BOOM_ANGLE), -cos(BOOM_ANGLE)) * BOOM_LENGTH
	for x in [-0.7, 0.7]:
		Props.car_beam(house, foot + Vector3(x, 0, 0), point + Vector3(x * 0.6, 0, 0), 0.55, orange)
		Props.car_beam(house, gantry_top + Vector3(x, 0, 0), point + Vector3(x * 0.5, 0.2, 0), 0.07, DARK)
	for k in range(1, 6):
		var t = k / 6.0
		Props.car_beam(house, foot.lerp(point, t) + Vector3(-0.7, 0, 0), foot.lerp(point, t) + Vector3(0.7, 0, 0), 0.2, orange)
	var sheave = Props.cylinder(house, point, 1.2, 1.2, 0.5, dusted(SHOVEL_GREY), 14)
	sheave.rotation.z = PI * 0.5
	# Stick through the saddle block halfway up the boom, dipper at its end.
	var stick = Node3D.new()
	stick.name = "ShovelStick"
	stick.set_meta("unbatched", true)
	house.add_child(stick)
	stick.position = foot.lerp(point, 0.48)
	Props.box(house, stick.position, Vector3(1.9, 1.0, 1.4), dusted(SHOVEL_GREY))
	for x in [-0.5, 0.5]:
		Props.box(stick, Vector3(x, -2.0, -1.0), Vector3(0.4, 0.5, 9.0), orange)
	var dipper = Vector3(0, -3.8, -5.6)
	Props.box(stick, dipper, Vector3(2.8, 2.6, 2.6), dusted(SHOVEL_GREY, 0.25))
	Props.box(stick, dipper + Vector3(0, 1.4, 0), Vector3(2.8 + PROUD * 2.0, 0.3, 2.6 + PROUD * 2.0), orange)
	for x in [-1.1, -0.37, 0.37, 1.1]:
		Props.box(stick, dipper + Vector3(x, -1.0, -1.55), Vector3(0.3, 0.3, 0.6), DARK)
	MeshMerge.bake(stick)
	# Counterweight and the power cable's reel at the back.
	Props.box(house, Vector3(0, 2.2, 6.0 + PROUD), Vector3(6.0, 2.0, 0.6), dusted(DARK, 0.2))
	MeshMerge.bake(house)
	return machine

# Rotary blast-hole drill (СБШ): crawlers, house, cab and a tall lattice mast.
static func drill() -> Node3D:
	var rig = Node3D.new()
	rig.name = "Drill"
	for x in [-1.8, 1.8]:
		Props.box(rig, Vector3(x, 0.6, 0), Vector3(1.0, 1.2, 7.4), dusted(DARK, 0.3))
	var body = dusted(Color("c9a43a"))
	Props.box(rig, Vector3(0, 2.4, 0.8), Vector3(4.2, 2.4, 5.4), body)
	Props.box(rig, Vector3(-1.2, 2.9, -3.0), Vector3(1.8, 2.2, 2.0), body)
	Props.box(rig, Vector3(-1.2, 3.2, -4.0 - PROUD * 0.5), Vector3(1.5, 1.0, PROUD), GLASS)
	var height = 17.0
	for x in [-0.6, 0.6]:
		for z in [-4.6, -3.6]:
			Props.box(rig, Vector3(x, 1.0 + height * 0.5, z), Vector3(0.18, height, 0.18), body)
	for k in range(1, 12):
		var y = 1.0 + k * height / 12.0
		Props.box(rig, Vector3(0, y, -4.1), Vector3(1.3, 0.1, 1.1), body.darkened(0.1))
	Props.box(rig, Vector3(0, 1.2 + height, -4.1), Vector3(1.6, 0.6, 1.6), body)
	Props.cylinder(rig, Vector3(0, height * 0.5, -4.1), 0.16, 0.16, height, STEEL, 8)
	return rig
