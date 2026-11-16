extends RefCounted
# Service-park equipment that makes the paddock read like a real rally service:
# team trucks behind the tents, environmental mats under the bays, a fire
# extinguisher at every bay, the time-control boards at the way in, barrier
# tape along the sides, parts shelves, bins and work lamps for the night.
# Everything is placed in park space with ServiceParkModel.at() and baked with
# the rest of the park; only the solids listed here are added.
const P = preload("res://scripts/core/props.gd")
const NightLights = preload("res://scripts/core/night_lights.gd")
const TYRE = Color("1d1f21")
const RIM = Color("a9adb0")
const STEEL = Color("8c9294")
const GLASS = Color("2b3540")
const CHASSIS = Color("2a2d30")

static func at(x: float, z: float, y: float = 0.0) -> Vector3:
	return Vector3(x, y, -z)

# A box truck in its own frame: length along +x with the cab at +x, width
# along z, wheels on the ground at y = 0. `length` is the box body's.
static func truck(parent: Node3D, pos: Vector3, yaw: float, body: Color, cab: Color, band: Color, name: String = "", length: float = 5.2) -> Node3D:
	var node = Node3D.new()
	node.name = "Truck"
	parent.add_child(node)
	node.position = pos
	node.rotation.y = yaw
	var back = -length * 0.5
	var front = length * 0.5 + 1.9
	P.box(node, Vector3((back + front) * 0.5, 0.62, 0), Vector3(front - back - 0.2, 0.22, 1.6), CHASSIS)
	P.box(node, Vector3(0, 2.05, 0), Vector3(length, 2.5, 2.4), body)
	for side in [-1.0, 1.0]:
		# A livery band and the team name along each side of the box.
		P.box(node, Vector3(0, 1.45, side * 1.205), Vector3(length - 0.3, 0.35, 0.02), band)
		P.box(node, Vector3(0, 3.2, side * 1.205), Vector3(length, 0.1, 0.02), band.darkened(0.2))
		if name != "":
			P.label_3d(node, Vector3(0, 2.8, side * 1.22), name, 96, 0.008, band.darkened(0.35), 0.0 if side > 0 else PI)
		# Side skirts between the axles.
		P.box(node, Vector3(back + length * 0.5 - 0.3, 0.68, side * 1.1), Vector3(length * 0.45, 0.3, 0.03), STEEL)
	# Rear roller door with its ribs, and the tail lights.
	P.box(node, Vector3(back - 0.01, 2.0, 0), Vector3(0.02, 2.2, 2.1), body.darkened(0.12))
	for i in range(5):
		P.box(node, Vector3(back - 0.025, 1.1 + i * 0.45, 0), Vector3(0.01, 0.04, 2.05), body.darkened(0.25))
	for side in [-1.0, 1.0]:
		P.box(node, Vector3(back - 0.03, 0.85, side * 0.95), Vector3(0.03, 0.12, 0.3), Color("b3261e"))
	_cab(node, length * 0.5, cab)
	for x in [back + 0.8, back + 1.85, length * 0.5 + 1.15]:
		wheel(node, Vector3(x, 0.48, 0), 0.48, 1.08)
	return node

static func _cab(node: Node3D, start: float, color: Color) -> void:
	var x = start + 0.95
	P.box(node, Vector3(x, 1.55, 0), Vector3(1.9, 1.9, 2.35), color)
	P.box(node, Vector3(x - 0.15, 2.62, 0), Vector3(1.4, 0.25, 2.2), color.darkened(0.1))
	# Windscreen, side windows, grille, bumper and headlamps.
	P.box(node, Vector3(start + 1.91, 2.0, 0), Vector3(0.02, 0.75, 2.1), GLASS)
	for side in [-1.0, 1.0]:
		P.box(node, Vector3(x + 0.25, 2.0, side * 1.18), Vector3(0.9, 0.65, 0.02), GLASS)
		P.box(node, Vector3(start + 1.92, 0.95, side * 0.85), Vector3(0.03, 0.18, 0.35), Color("f3efd7"))
		P.box(node, Vector3(x + 0.4, 2.15, side * 1.32), Vector3(0.06, 0.32, 0.16), CHASSIS)
	P.box(node, Vector3(start + 1.92, 1.2, 0), Vector3(0.03, 0.55, 1.3), CHASSIS.lightened(0.15))
	P.box(node, Vector3(start + 1.95, 0.7, 0), Vector3(0.12, 0.25, 2.35), CHASSIS)

# A wheel standing on the ground, its axle along z: tyre, rim and hub, one per
# side `track` apart (0 for a single loose wheel).
static func wheel(node: Node3D, center: Vector3, radius: float, track: float) -> void:
	var sides = [-1.0, 1.0] if track > 0.0 else [0.0]
	for side in sides:
		var z = center.z + side * track
		var tyre = P.cylinder(node, Vector3(center.x, center.y, z), radius, radius, 0.3, TYRE, 14)
		tyre.rotation.x = PI / 2
		var rim = P.cylinder(node, Vector3(center.x, center.y, z + side * 0.01), radius * 0.6, radius * 0.6, 0.3, RIM, 10)
		rim.rotation.x = PI / 2
		var hub = P.cylinder(node, Vector3(center.x, center.y, z + side * 0.03), radius * 0.2, radius * 0.2, 0.3, CHASSIS, 6)
		hub.rotation.x = PI / 2

# The team's truck parked behind its tent, cab towards the way in, its side
# facing the aisle over the tent's back wall.
static func team_truck(stage: Node3D, root: Node3D, x: float, z: float, team: Dictionary) -> void:
	truck(root, at(x, z), -PI / 2, Color("eceae4"), team.roof, team.roof, str(team.name), 6.4)
	# The truck's frame runs from 3.2 m behind z to 5.1 m ahead of it.
	stage.solids.solid(root, at(x, z - 0.95, 1.6), Vector3(2.5, 3.2, 8.4), "service")

# An absorbent ground sheet under a parked car, as the rules ask for.
static func mat(root: Node3D, x: float, z: float) -> void:
	P.box(root, at(x, z, 0.012), Vector3(5.0, 0.02, 2.8), Color("3f4549"))
	P.box(root, at(x, z, 0.014), Vector3(4.7, 0.02, 2.5), Color("4d5458"))

# A red extinguisher on its own little stand.
static func extinguisher(root: Node3D, x: float, z: float) -> void:
	P.box(root, at(x, z, 0.02), Vector3(0.3, 0.04, 0.3), CHASSIS)
	P.cylinder(root, at(x, z, 0.3), 0.09, 0.09, 0.52, Color("c8231c"), 10)
	P.cylinder(root, at(x, z, 0.6), 0.04, 0.05, 0.08, CHASSIS, 6)
	P.box(root, at(x + 0.06, z, 0.62), Vector3(0.12, 0.03, 0.03), CHASSIS)

# A time-control board on its post, face towards the cars coming in: yellow
# warns, red is the control itself, beige ends the zone. A clock on yellow and
# red, three bars on beige.
static func control_board(stage: Node3D, root: Node3D, x: float, z: float, color: Color, clock: bool) -> void:
	P.box(root, at(x, z, 0.9), Vector3(0.08, 1.8, 0.08), STEEL)
	P.box(root, at(x, z - 0.05, 1.9), Vector3(0.72, 0.72, 0.03), color)
	P.box(root, at(x, z - 0.04, 1.9), Vector3(0.78, 0.78, 0.02), Color("f2f0e8"))
	if clock:
		var face = P.cylinder(root, at(x, z - 0.075, 1.9), 0.24, 0.24, 0.02, CHASSIS, 16)
		face.rotation.x = PI / 2
		var dial = P.cylinder(root, at(x, z - 0.085, 1.9), 0.2, 0.2, 0.02, Color("f2f0e8"), 16)
		dial.rotation.x = PI / 2
		P.box(root, at(x, z - 0.1, 1.96), Vector3(0.025, 0.13, 0.01), CHASSIS)
		P.box(root, at(x + 0.05, z - 0.1, 1.9), Vector3(0.1, 0.025, 0.01), CHASSIS)
	else:
		for i in range(3):
			var bar = P.box(root, at(x - 0.18 + i * 0.18, z - 0.075, 1.9), Vector3(0.06, 0.6, 0.01), CHASSIS)
			bar.rotation.z = 0.6
	stage.solids.solid(root, at(x, z, 1.0), Vector3(0.2, 2.0, 0.2), "service")

# The marshals' time-control desk under a small parasol, beside the lane.
static func control_desk(stage: Node3D, root: Node3D, x: float, z: float) -> void:
	P.box(root, at(x, z, 0.74), Vector3(1.2, 0.05, 0.7), Color("e9e7df"))
	for dx in [-0.55, 0.55]:
		for dz in [-0.3, 0.3]:
			P.box(root, at(x + dx, z + dz, 0.37), Vector3(0.04, 0.74, 0.04), STEEL)
	P.box(root, at(x - 0.2, z, 0.8), Vector3(0.3, 0.05, 0.22), Color("2c5aa0"))
	P.box(root, at(x + 0.3, z - 0.1, 0.78), Vector3(0.16, 0.02, 0.22), Color("f2f0e8"))
	P.cylinder(root, at(x, z + 0.1, 1.3), 0.02, 0.02, 1.9, STEEL, 6)
	P.cylinder(root, at(x, z + 0.1, 2.3), 0.8, 0.05, 0.25, Color("ce4830"), 8)
	stage.solids.solid(root, at(x, z, 0.4), Vector3(1.2, 0.8, 0.7), "service")

# Red-and-white barrier tape on stakes from z0 to z1 along x.
static func tape(root: Node3D, x: float, z0: float, z1: float) -> void:
	var stakes = maxi(2, ceili((z1 - z0) / 4.0) + 1)
	var pitch = (z1 - z0) / (stakes - 1)
	for i in range(stakes):
		P.box(root, at(x, z0 + i * pitch, 0.5), Vector3(0.05, 1.0, 0.05), Color("d7d2c4"))
	var pieces = ceili((z1 - z0) / 0.8)
	var piece = (z1 - z0) / pieces
	for i in range(pieces):
		var color = Color("d8261c") if i % 2 == 0 else Color("f2f0e8")
		P.box(root, at(x, z0 + (i + 0.5) * piece, 0.92), Vector3(0.01, 0.07, piece), color)

# A steel parts shelf with crates and spare wheels.
static func shelf(stage: Node3D, root: Node3D, x: float, z: float) -> void:
	for dz in [-0.48, 0.48]:
		for dx in [-0.22, 0.22]:
			P.box(root, at(x + dx, z + dz, 0.9), Vector3(0.04, 1.8, 0.04), STEEL)
	var crates = [Color("2c5aa0"), Color("e3b51e"), Color("3a7a46"), Color("c3302b")]
	for level in range(4):
		var y = 0.15 + level * 0.52
		P.box(root, at(x, z, y), Vector3(0.5, 0.03, 1.0), STEEL.darkened(0.2))
		if level < 3:
			P.box(root, at(x, z - 0.22, y + 0.13), Vector3(0.4, 0.22, 0.38), crates[level])
			P.box(root, at(x, z + 0.24, y + 0.11), Vector3(0.38, 0.18, 0.3), crates[(level + 2) % 4])
	stage.solids.solid(root, at(x, z, 0.9), Vector3(0.5, 1.8, 1.0), "service")

# A work lamp under a tent roof: a bar that glows at night and the light.
static func work_lamp(root: Node3D, x: float, z: float, length: float) -> void:
	P.box(root, at(x, z, 2.47), Vector3(0.12, 0.05, length), CHASSIS)
	var glow = P.box(root, at(x, z, 2.43), Vector3(0.09, 0.02, length - 0.1), Color.WHITE)
	glow.material_override = NightLights.glow_material()
	NightLights.glow(glow)
	var light = Node3D.new()
	light.name = "WorkLamp"
	root.add_child(light)
	light.position = at(x, z, 2.2)
	NightLights.mark(light, "worklamp")

# Wheelie bins for waste and a drum for used oil.
static func bins(stage: Node3D, root: Node3D, x: float, z: float) -> void:
	for i in range(2):
		var bx = x + i * 0.75
		P.box(root, at(bx, z, 0.52), Vector3(0.6, 1.0, 0.7), Color("2f6b3a") if i == 0 else Color("2c5aa0"))
		P.box(root, at(bx, z - 0.02, 1.05), Vector3(0.64, 0.06, 0.76), Color("26292c"))
		var castor = P.cylinder(root, at(bx - 0.2, z + 0.36, 0.1), 0.1, 0.1, 0.06, TYRE, 8)
		castor.rotation.z = PI / 2
	P.cylinder(root, at(x + 1.75, z, 0.45), 0.29, 0.29, 0.9, Color("3a3f44"), 12)
	P.cylinder(root, at(x + 1.75, z, 0.91), 0.29, 0.29, 0.02, Color("e3b51e"), 12)
	stage.solids.solid(root, at(x + 0.85, z, 0.5), Vector3(2.4, 1.0, 0.8), "service")
