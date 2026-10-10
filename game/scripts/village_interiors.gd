extends RefCounted
# Original procedural interiors (church tower, roof-terrace house) built through
# the village architecture kit; walk surfaces and viewpoints go to stage solids.
const Props = preload("res://scripts/props.gd")
const STONE = Color("d8c7a4")
const WOOD = Color("73513b")

static func block(arch, root: Node3D, p: Vector3, size: Vector3, color: Color, solid: bool = true) -> void:
	Props.box(root, p, size, color)
	if solid:
		arch.solids.solid(root, p, size, "building")

static func surface(arch, root: Node3D, p: Vector3, width: float, depth: float, rise: float = 0.0, yaw: float = 0.0) -> void:
	var pose = root.transform * Transform3D(Basis(Vector3.UP, yaw), p)
	arch.solids.walk_surfaces.append({"pose": pose, "inverse": pose.affine_inverse(), "half": Vector2(width * 0.5, depth * 0.5), "reach": maxf(width, depth), "rise": rise})

static func floor_panel(arch, root: Node3D, p: Vector3, width: float, depth: float) -> void:
	# Floors are support surfaces, not obstacles to the feet-level swept sphere.
	block(arch, root, p - Vector3.UP * 0.08, Vector3(width, 0.16, depth), Color("b2a58d"), false)
	surface(arch, root, p, width, depth)

static func stairs(arch, root: Node3D, start: Vector3, width: float, length: float, rise: float, yaw: float = 0.0) -> void:
	var basis = Basis(Vector3.UP, yaw)
	var count = ceili(rise / 0.15)
	for i in range(count):
		var height = rise * float(i + 1) / count
		var z = length * (float(i) + 0.5) / count
		block(arch, root, start + basis * Vector3(0, height - 0.075, z), Vector3(width, 0.15, length / count + 0.01), WOOD, false)
	# Register the same tread heights as the visible steps.
	surface(arch, root, start + basis * Vector3(0, 0, length * 0.5), width, length, rise, yaw)
	arch.solids.walk_surfaces.back()["steps"] = count

static func rail(arch, root: Node3D, p: Vector3, size: Vector3) -> void:
	# A single collision volume keeps the player behind the open balustrade.
	arch.solids.solid(root, p + Vector3.UP * 0.65, Vector3(size.x, 1.3, size.z), "wall")
	Props.box(root, p + Vector3.UP * 1.2, Vector3(size.x, 0.12, size.z), WOOD)
	var count = ceili(maxf(size.x, size.z) / 0.7)
	for i in range(count + 1):
		var offset = Vector3(size.x - 0.12, 0, size.z - 0.12) * (float(i) / count - 0.5)
		Props.box(root, p + offset + Vector3.UP * 0.6, Vector3(0.09, 1.2, 0.09), WOOD)

static func door_wall(arch, root: Node3D, z: float, width: float, height: float, leaves: bool = true) -> void:
	var side_width = (width - 2.4) * 0.5
	for sign_value in [-1.0, 1.0]:
		block(arch, root, Vector3(sign_value * (1.2 + side_width * 0.5), height * 0.5, z), Vector3(side_width, height, 0.35), STONE)
	block(arch, root, Vector3(0, (height + 3.0) * 0.5, z), Vector3(2.4, height - 3.0, 0.35), STONE)
	if not leaves:
		return
	# Door leaves stand open beside the passage.
	for sign_value in [-1.0, 1.0]:
		block(arch, root, Vector3(sign_value * 1.35, 1.4, z - 0.6), Vector3(0.12, 2.8, 1.2), WOOD)

static func church(arch, root: Node3D) -> void:
	root.set_meta("accessible", true)
	var footprint = root.transform * Transform3D(Basis.IDENTITY, Vector3(0, 0, -2))
	arch.solids.interior_footprints.append({"inverse": footprint.affine_inverse(), "half": Vector2(5.6, 12.6)})
	for x in [-4.8, 4.8]:
		block(arch, root, Vector3(x, 4.5, 1), Vector3(0.4, 9, 19), STONE)
	block(arch, root, Vector3(0, 4.5, 10.3), Vector3(10, 9, 0.4), STONE)
	door_wall(arch, root, -8.3, 10, 9, false)
	floor_panel(arch, root, Vector3(0, 0.10, 1), 9.6, 19)
	# Terminate the nave roof before the tower stairwell, including tile courses.
	var nave_roof = Node3D.new()
	nave_roof.name = "NaveRoof"
	root.add_child(nave_roof)
	nave_roof.position.z = 1.2
	arch.roof(nave_roof, 11, 18, 9, 3.4, Color("b4693f"))
	for z in [-5.0, -2.5, 0.0, 2.5, 5.0]:
		for x in [-2.8, 2.8]:
			block(arch, root, Vector3(x, 0.5, z), Vector3(2.4, 0.18, 0.7), WOOD)
			block(arch, root, Vector3(x, 0.9, z - 0.3), Vector3(2.4, 0.8, 0.15), WOOD)
			for leg in [-0.9, 0.9]:
				Props.box(root, Vector3(x + leg, 0.25, z), Vector3(0.12, 0.5, 0.5), WOOD)
	block(arch, root, Vector3(0, 0.6, 8.5), Vector3(3, 1.0, 1.3), Color("eee4c9"))
	Props.box(root, Vector3(0, 4.0, 10.0), Vector3(0.16, 2.8, 0.12), WOOD)
	Props.box(root, Vector3(0, 4.5, 9.98), Vector3(1.5, 0.16, 0.12), WOOD)
	for x in [-1.0, 1.0]:
		Props.cylinder(root, Vector3(x, 1.3, 8.5), 0.09, 0.09, 0.4, Color("e4c774"), 8)
	for z in [-5.0, 1.0, 7.0]:
		for x in [-4.55, 4.55]:
			# Bright inset panes can be seen from inside and outside.
			Props.box(root, Vector3(x, 5, z), Vector3(0.12, 2.8, 1.2), Color("78988e"))
	for x in [-5.3, 5.3]:
		for z in [-7.0, -2.0, 3.0, 8.0]:
			block(arch, root, Vector3(x, 3.2, z), Vector3(0.8, 6.4, 0.8), Color("c3b9a1"))
			arch.window(root, Vector3(x * 0.96, 5, z), -signf(x) * PI / 2, Color("aeb3a2"), "")
	# Taller hollow tower. Nave access and street entrance stay open.
	for x in [-2.8, 2.8]:
		block(arch, root, Vector3(x, 12, -11.1), Vector3(0.4, 24, 6), STONE)
	door_wall(arch, root, -14.0, 6, 24, false)
	door_wall(arch, root, -8.2, 6, 24, false)
	floor_panel(arch, root, Vector3(0, 0.1, -11.1), 5.6, 6)
	# Ten alternating flights, connected by full-width landings.
	for flight in range(10):
		var y = 0.1 + flight * 2.4
		var forward = flight % 2 == 0
		var x = -1.45 if forward else 1.45
		stairs(arch, root, Vector3(x, y, -13.0 if forward else -9.4), 1.8, 3.6, 2.4, 0.0 if forward else PI)
		floor_panel(arch, root, Vector3(0, y + 2.4, -9.2 if forward else -13.2), 5.5, 1.4)
		# Inner balustrade leaves headroom for the flight above.
		if flight < 9:
			rail(arch, root, Vector3(0, y + 2.4, -8.65 if forward else -13.75), Vector3(5.5, 0, 0.12))
	floor_panel(arch, root, Vector3(-1.45, 24.1, -11.1), 3.9, 6.7)
	# Close the outer strip beside the stairwell, with overlap at panel seams.
	floor_panel(arch, root, Vector3(2.85, 24.1, -11.1), 1.05, 6.7)
	floor_panel(arch, root, Vector3(0, 24.1, -13.7), 6.7, 1.5)
	floor_panel(arch, root, Vector3(0, 24.1, -8.5), 6.7, 1.5)
	# Keep an opening above the last stair flight.
	# Final flight ascends along x=+1.45 towards the front landing.
	rail(arch, root, Vector3(0.55, 24.1, -11.1), Vector3(0.12, 0, 3.0))
	var bell = load("res://scripts/church_bell.gd").new()
	bell.name = "ChurchBell"
	root.add_child(bell)
	bell.position = Vector3(-1.2, 27.2, -11.1)
	bell.build()
	arch.solids.bell = bell
	for x in [-3.3, 3.3]:
		rail(arch, root, Vector3(x, 24.1, -11.1), Vector3(0.12, 0, 6.6))
	for z in [-14.4, -7.8]:
		rail(arch, root, Vector3(0, 24.1, z), Vector3(6.6, 0, 0.12))
	for x in [-2.8, 2.8]:
		for z in [-13.8, -8.4]:
			block(arch, root, Vector3(x, 26, z), Vector3(0.35, 3.8, 0.35), STONE)
	# Provençal wrought-iron bell cage (campanile) on a low stone cornice.
	Props.box(root, Vector3(0, 28.1, -11.1), Vector3(6.4, 0.4, 6.4), STONE.lightened(0.05))
	for i in range(8):
		var angle = i * TAU / 8.0
		var bar = Props.box(root, Vector3(cos(angle) * 1.5, 29.6, -11.1 + sin(angle) * 1.5), Vector3(0.06, 2.6, 0.06), Color("2e3330"))
		bar.rotation = Vector3(sin(angle) * 0.25, 0, -cos(angle) * 0.25)
	Props.cylinder(root, Vector3(0, 28.4, -11.1), 1.9, 1.9, 0.08, Color("2e3330"), 12)
	Props.cylinder(root, Vector3(0, 30.9, -11.1), 0.35, 0.35, 0.1, Color("2e3330"), 10)
	Props.box(root, Vector3(0, 32.0, -11.1), Vector3(0.1, 2.0, 0.1), Color("2e3330"))
	Props.box(root, Vector3(0, 32.5, -11.1), Vector3(0.8, 0.1, 0.1), Color("2e3330"))
	for y in [5.2, 10.8, 18.0, 23.9]:
		for x in [-3.0, 3.0]:
			Props.box(root, Vector3(x, y, -11.1), Vector3(0.3, 0.25, 6.3), Color("e5dcc4"))
		for z in [-14.1, -8.1]:
			Props.box(root, Vector3(0, y, z), Vector3(6.3, 0.25, 0.3), Color("e5dcc4"))
	var clock = Props.cylinder(root, Vector3(0, 18, -14.25), 1, 1, 0.08, Color("eee4c9"), 24)
	clock.rotation.x = PI / 2
	Props.box(root, Vector3(0, 18.3, -14.32), Vector3(0.08, 0.6, 0.06), WOOD)
	Props.box(root, Vector3(0.3, 18, -14.32), Vector3(0.6, 0.08, 0.06), WOOD)
	arch.solids.viewpoints.append({"kind": "tower", "pose": root.transform, "position": root.transform * Vector3(-1, 24.1, -11.1)})

static func house(arch, root: Node3D) -> void:
	root.set_meta("accessible", true)
	arch.solids.interior_footprints.append({"inverse": root.transform.affine_inverse(), "half": Vector2(4.2, 4.2)})
	for x in [-3.8, 3.8]:
		block(arch, root, Vector3(x, 3.0, 0), Vector3(0.4, 6, 8), STONE)
	block(arch, root, Vector3(0, 3.0, 4.0), Vector3(8, 6, 0.4), STONE)
	door_wall(arch, root, -3.8, 8, 6)
	floor_panel(arch, root, Vector3(0, 0.1, 0), 7.6, 7.6)
	stairs(arch, root, Vector3(2, 0.1, -3), 1.55, 6, 3)
	floor_panel(arch, root, Vector3(0, 3.1, 3.35), 6, 0.9)
	stairs(arch, root, Vector3(0, 3.1, 3), 1.55, 6, 3, PI)
	floor_panel(arch, root, Vector3(-2.2, 3.1, 0), 2.7, 7.6)
	# Rooftop strips leave the upper flight open, with a generous front landing.
	floor_panel(arch, root, Vector3(-2.2, 6.1, 0), 2.7, 7.6)
	floor_panel(arch, root, Vector3(2.2, 6.1, 0), 2.7, 7.6)
	floor_panel(arch, root, Vector3(0, 6.1, -3.35), 7.6, 0.9)
	floor_panel(arch, root, Vector3(0, 6.1, 3.35), 7.6, 0.9)
	for x in [-3.85, 3.85]:
		rail(arch, root, Vector3(x, 6.1, 0), Vector3(0.12, 0, 7.7))
	for z in [-3.85, 3.85]:
		rail(arch, root, Vector3(0, 6.1, z), Vector3(7.7, 0, 0.12))
	for x in [-0.85, 0.85]:
		rail(arch, root, Vector3(x, 6.1, 0), Vector3(0.12, 0, 5.1))
	# Half-width tiled roof shelters the left terrace without blocking the view.
	var shelter = Node3D.new()
	root.add_child(shelter)
	shelter.position.x = -2.2
	arch.roof(shelter, 3.0, 8.3, 8.3, 1.5, Color("9d513b"))
	for z in [-3.4, 3.4]:
		block(arch, root, Vector3(-2.2, 7.2, z), Vector3(0.18, 2.2, 0.18), WOOD)
	block(arch, root, Vector3(2.9, 7.1, 2.8), Vector3(0.65, 2, 0.65), STONE)
	# Ground-floor sitting room and a small upstairs bedroom.
	block(arch, root, Vector3(-2.2, 0.55, 1.3), Vector3(2.2, 0.8, 0.9), Color("6a7f67"))
	block(arch, root, Vector3(-2.2, 0.55, -0.5), Vector3(1.5, 0.7, 0.9), WOOD)
	Props.box(root, Vector3(-2.2, 1.0, -0.5), Vector3(0.45, 0.08, 0.3), Color("dbceb1"))
	block(arch, root, Vector3(-2.2, 3.5, 1.0), Vector3(1.7, 0.7, 2.0), Color("a4ae91"))
	block(arch, root, Vector3(-2.4, 4.0, -2.4), Vector3(1.6, 1.8, 0.6), WOOD)
	for x in [-3.55, 3.55]:
		for y in [1.8, 4.5]:
			Props.box(root, Vector3(x, y, 0), Vector3(0.10, 1.5, 1.2), Color("7d9990"))
	for y in [1.7, 4.6]:
		for x in [-2.5, 2.5]:
			arch.window(root, Vector3(x, y, -4.02), 0, Color("526b58"), "flowers" if y > 3 else "")
		for x in [-4.02, 4.02]:
			arch.window(root, Vector3(x, y, 0), -signf(x) * PI / 2, Color("526b58"), "")
	Props.box(root, Vector3(0, 0.03, -6), Vector3(2.4, 0.06, 4), Color("bbb39c"))
	arch.solids.viewpoints.append({"kind": "roof", "pose": root.transform, "position": root.transform * Vector3(2.2, 6.1, -2)})
