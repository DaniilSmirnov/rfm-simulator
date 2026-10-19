extends RefCounted
# What stands in a service park: team tents with their workbenches, tool
# chests and tyre stacks, a service truck, a generator, fuel cans, a portable
# toilet, the park sign at the entrance and cones along the lane. Everything is
# placed in park space (x across, z into the park; see service_parks.gd) under
# one root at the end of the road, and baked into a single shared mesh.
const Movable = preload("res://scripts/core/prop_registry.gd")
const P = preload("res://scripts/core/props.gd")
const MeshMerge = preload("res://scripts/core/mesh_merge.gd")
const TEAMS = [
	{"name": "RFM RACING", "roof": Color("c9302c"), "trim": Color("f2f0e8")},
	{"name": "VETRA SPORT", "roof": Color("2c5aa0"), "trim": Color("f1c232")},
	{"name": "TAIGA TEAM", "roof": Color("3a7a46"), "trim": Color("f2f0e8")},
	{"name": "NIGHT GRAVEL", "roof": Color("26292c"), "trim": Color("e2762b")},
]
const TENTS = [Vector2(13.5, 22.5), Vector2(-13.5, 22.5), Vector2(13.5, 34.0), Vector2(-13.5, 34.0)]
const TYRE = Color("1d1f21")
const STEEL = Color("8c9294")

# Park space to the root's local space: x stays, z runs along the root's -Z.
static func at(x: float, z: float, y: float = 0.0) -> Vector3:
	return Vector3(x, y, -z)

static func build(stage: Node3D, parks, index: int) -> Node3D:
	var end: Dictionary = parks.ends[index]
	var root = Node3D.new()
	root.name = "ServicePark_%d" % index
	stage.add_child(root)
	root.position = end.origin
	root.rotation.y = atan2(-end.forward.x, -end.forward.z)
	for i in range(TENTS.size()):
		tent(stage, root, TENTS[i], TEAMS[(i + index) % TEAMS.size()])
	_entrance(stage, root)
	_far_end(stage, root)
	_cones(stage, root, parks)
	MeshMerge.bake(root, "service_park")
	return root

# A gazebo tent open to the aisle, its back wall printed with the team name,
# with a workbench, a tool chest, tyres and a jack under it.
static func tent(stage: Node3D, root: Node3D, center: Vector2, team: Dictionary) -> void:
	var first = root.get_child_count()
	var outward = signf(center.x)
	var half = Vector2(2.6, 3.0)
	for dx in [-half.x, half.x]:
		for dz in [-half.y, half.y]:
			P.box(root, at(center.x + dx, center.y + dz, 1.25), Vector3(0.06, 2.5, 0.06), STEEL)
			stage.solids.solid(root, at(center.x + dx, center.y + dz, 1.25), Vector3(0.08, 2.5, 0.08), "service")
	P.box(root, at(center.x, center.y, 2.55), Vector3(half.x * 2 + 0.2, 0.1, half.y * 2 + 0.2), team.roof)
	P.box(root, at(center.x, center.y, 2.75), Vector3(half.x * 1.2, 0.3, half.y * 1.2), team.roof.darkened(0.08))
	P.box(root, at(center.x, center.y, 2.95), Vector3(half.x * 0.5, 0.18, half.y * 0.5), team.roof.darkened(0.15))
	# Valance strips around the roof, in the trim colour.
	for dz in [-half.y - 0.1, half.y + 0.1]:
		P.box(root, at(center.x, center.y + dz, 2.38), Vector3(half.x * 2 + 0.2, 0.24, 0.02), team.trim)
	for dx in [-half.x - 0.1, half.x + 0.1]:
		P.box(root, at(center.x + dx, center.y, 2.38), Vector3(0.02, 0.24, half.y * 2 + 0.2), team.trim)
	# Back wall on the outer side with the team name, facing the aisle.
	var back_x = center.x + outward * half.x
	P.box(root, at(back_x, center.y, 1.25), Vector3(0.03, 2.3, half.y * 2), team.roof.lightened(0.1))
	P.box(root, at(back_x - outward * 0.02, center.y, 1.6), Vector3(0.02, 0.5, half.y * 1.6), team.trim)
	P.label_3d(root, at(back_x - outward * 0.035, center.y, 1.6), str(team.name), 96, 0.006, team.roof.darkened(0.3), -PI / 2 if outward > 0 else PI / 2)
	# Keep equipment keys stable after excluding the former movable tent slot.
	root.set_meta("prop_count", int(root.get_meta("prop_count", 0)) + 1)
	stage.solids.solid(root, at(back_x, center.y, 1.25), Vector3(0.03, 2.3, half.y * 2), "service")
	stage.solids.solid(root, at(center.x, center.y, 2.55), Vector3(half.x * 2 + 0.2, 0.1, half.y * 2 + 0.2), "service")
	first = root.get_child_count()
	# Workbench along the back wall, a red tool chest and a jack.
	var bench_x = back_x - outward * 0.55
	P.box(root, at(bench_x, center.y - 0.6, 0.9), Vector3(0.8, 0.06, 2.2), Color("6b5b45"))
	for dz in [-1.6, 0.4]:
		P.box(root, at(bench_x, center.y + dz, 0.44), Vector3(0.7, 0.88, 0.06), STEEL)
	P.box(root, at(bench_x, center.y - 1.1, 0.99), Vector3(0.35, 0.12, 0.5), Color("d8572d"))
	P.box(root, at(bench_x, center.y + 0.1, 1.0), Vector3(0.25, 0.15, 0.25), Color("4b6a86"))
	stage.solids.solid(root, at(bench_x, center.y - 0.6, 0.47), Vector3(0.8, 0.94, 2.2), "service")
	Movable.group(stage.solids, root, first, 35)
	first = root.get_child_count()
	var chest = Vector2(bench_x, center.y + 1.9)
	P.box(root, at(chest.x, chest.y, 0.55), Vector3(0.6, 0.9, 0.75), Color("c3302b"))
	for row in range(5):
		P.box(root, at(chest.x - outward * 0.305, chest.y, 0.22 + row * 0.16), Vector3(0.01, 0.025, 0.6), Color("d9dcdc"))
	stage.solids.solid(root, at(chest.x, chest.y, 0.5), Vector3(0.6, 1.0, 0.75), "service")
	Movable.group(stage.solids, root, first, 40)
	first = root.get_child_count()
	tyres(stage, root, Vector2(center.x - outward * 0.6, center.y + 2.4), 4)
	tyres(stage, root, Vector2(center.x - outward * 1.5, center.y + 2.4), 3)
	first = root.get_child_count()
	P.box(root, at(center.x - outward * 0.5, center.y - 2.3, 0.08), Vector3(0.35, 0.12, 0.9), Color("b8241e"))
	Movable.group(stage.solids, root, first, 12)
	first = root.get_child_count()
	# A feather flag at the front corner.
	var flag = Vector2(center.x - outward * (half.x + 0.6), center.y - half.y)
	P.cylinder(root, at(flag.x, flag.y, 1.7), 0.02, 0.02, 3.4, STEEL, 6)
	P.box(root, at(flag.x, flag.y + 0.25, 2.25), Vector3(0.02, 2.0, 0.5), team.roof)
	P.box(root, at(flag.x, flag.y + 0.25, 2.25), Vector3(0.04, 1.4, 0.1), team.trim)
	Movable.group(stage.solids, root, first, 5, true)

static func tyres(stage: Node3D, root: Node3D, spot: Vector2, count: int) -> void:
	for i in range(count):
		var first = root.get_child_count()
		P.cylinder(root, at(spot.x, spot.y, 0.12 + i * 0.22), 0.32, 0.32, 0.21, TYRE, 12)
		var tyre = Movable.group(stage.solids, root, first, 8)
		tyre.set_meta("prop_roll", true)

# The park sign beside the lane and two feather flags at the gate.
static func _entrance(stage: Node3D, root: Node3D) -> void:
	var first = root.get_child_count()
	var sign = Vector2(7.6, 8.0)
	# Posts flank the board instead of crossing its faces, so they never cut
	# the lettering on either side.
	for dx in [-1.56, 1.56]:
		P.box(root, at(sign.x + dx, sign.y, 1.3), Vector3(0.12, 2.6, 0.12), STEEL)
	P.box(root, at(sign.x, sign.y, 2.2), Vector3(3.0, 0.9, 0.06), Color("f2f0e8"))
	# The red header overhangs the board by 1 cm on every side.
	P.box(root, at(sign.x, sign.y, 2.59), Vector3(3.02, 0.16, 0.08), Color("ce4830"))
	# Readable from the road and from inside the park; the block lettering
	# (2.5 m wide) stays within the 3 m board.
	for face in [-1.0, 1.0]:
		P.label_3d(root, at(sign.x, sign.y - face * 0.035, 2.15), "ПАРК СЕРВИСА", 96, 0.0037, Color("23272b"), 0.0 if face > 0 else PI)
	stage.solids.solid(root, at(sign.x, sign.y, 1.3), Vector3(3.24, 2.6, 0.3), "service")
	Movable.group(stage.solids, root, first, 30, true)
	for side in [-1.0, 1.0]:
		first = root.get_child_count()
		var x = side * 9.0
		P.cylinder(root, at(x, 12.5, 1.9), 0.025, 0.025, 3.8, STEEL, 6)
		P.box(root, at(x, 12.8, 2.5), Vector3(0.02, 2.2, 0.55), Color("ce4830"))
		P.box(root, at(x, 12.8, 2.5), Vector3(0.04, 1.6, 0.12), Color.WHITE)
		Movable.group(stage.solids, root, first, 6, true)

# Back of the paddock: a service truck, a generator with fuel cans and a
# portable toilet.
static func _far_end(stage: Node3D, root: Node3D) -> void:
	var first = root.get_child_count()
	var truck = Vector2(-9.5, 43.0)
	P.box(root, at(truck.x, truck.y, 1.75), Vector3(5.2, 2.6, 2.3), Color("e7e7e1"))
	P.box(root, at(truck.x + 3.4, truck.y, 1.25), Vector3(1.7, 1.9, 2.25), Color("2c5aa0"))
	P.box(root, at(truck.x + 4.26, truck.y, 1.55), Vector3(0.02, 0.7, 2.0), Color("3b4a55"))
	P.box(root, at(truck.x, truck.y + 1.16, 2.0), Vector3(4.6, 0.6, 0.02), Color("ce4830"))
	for wx in [-1.6, 0.4, 3.4]:
		for wz in [-1.0, 1.0]:
			# Tyres stand 2 cm proud of the body sides instead of flush with them.
			var wheel = P.cylinder(root, at(truck.x + wx, truck.y + wz * 1.02, 0.42), 0.42, 0.42, 0.3, TYRE, 12)
			wheel.rotation.x = PI / 2
	stage.solids.solid(root, at(truck.x + 0.85, truck.y, 1.5), Vector3(6.9, 3.0, 2.3), "service")
	Movable.group(stage.solids, root, first, 3500)
	first = root.get_child_count()
	var generator = Vector2(4.5, 43.5)
	P.box(root, at(generator.x, generator.y, 0.35), Vector3(0.9, 0.55, 0.6), Color("e3b51e"))
	P.box(root, at(generator.x, generator.y, 0.68), Vector3(0.7, 0.12, 0.45), Color("2a2d30"))
	P.box(root, at(generator.x, generator.y, 0.04), Vector3(1.1, 0.08, 0.7), Color("2a2d30"))
	stage.solids.solid(root, at(generator.x, generator.y, 0.4), Vector3(1.1, 0.8, 0.7), "service")
	Movable.group(stage.solids, root, first, 45)
	for i in range(3):
		first = root.get_child_count()
		P.box(root, at(generator.x + 1.0 + i * 0.32, generator.y + 0.2, 0.22), Vector3(0.28, 0.44, 0.17), Color("c3302b"))
		Movable.group(stage.solids, root, first, 12)
	first = root.get_child_count()
	var toilet = Vector2(15.5, 44.0)
	P.box(root, at(toilet.x, toilet.y, 1.15), Vector3(1.15, 2.3, 1.15), Color("2f6fb5"))
	P.box(root, at(toilet.x, toilet.y, 2.35), Vector3(1.25, 0.1, 1.25), Color("e7e7e1"))
	P.box(root, at(toilet.x - 0.59, toilet.y, 1.1), Vector3(0.02, 1.9, 0.8), Color("285e9a"))
	stage.solids.solid(root, at(toilet.x, toilet.y, 1.15), Vector3(1.15, 2.3, 1.15), "service")
	Movable.group(stage.solids, root, first, 70)

# Traffic cones along both sides of the lane.
static func _cones(stage: Node3D, root: Node3D, parks) -> void:
	for side in [-1.0, 1.0]:
		for i in range(5):
			var first = root.get_child_count()
			var spot = Vector2(side * (parks.LANE_HALF - 0.3), 1.0 + i * 2.6)
			# The cone stands on its base instead of sinking through it.
			P.cylinder(root, at(spot.x, spot.y, 0.28), 0.13, 0.03, 0.5, Color("ef6a1f"), 8)
			P.cylinder(root, at(spot.x, spot.y, 0.33), 0.09, 0.075, 0.08, Color.WHITE, 8)
			P.box(root, at(spot.x, spot.y, 0.015), Vector3(0.34, 0.03, 0.34), Color("2a2d30"))
			Movable.group(stage.solids, root, first, 2)
