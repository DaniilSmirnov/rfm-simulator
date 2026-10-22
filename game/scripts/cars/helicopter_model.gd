extends RefCounted
# Compact civil twin ducted-fan craft. The closed envelope is deliberately
# box-shaped, with no exposed blades or long tail outside the collision box.
const P = preload("res://scripts/core/props.gd")
const PAINT = Color("e4e8dc")
const TRIM = Color("e88736")
const DARK = Color("303d43")

static func build(variant: int) -> Node3D:
	var root = Node3D.new()
	root.name = "CivilHelicopter"
	root.set_meta("helicopter", true)
	root.set_meta("variant", variant)
	root.set_meta("model", "Вертолет")
	var cabin = P.car_shell(root, [Vector4(-2.65, 0.45, 0.65, 1.3), Vector4(-1.65, 1.0, 0.55, 2.05), Vector4(-0.8, 1.0, 0.55, 2.25), Vector4(1.25, 1.0, 0.55, 2.15), Vector4(2.1, 0.55, 0.8, 1.6)], PAINT)
	cabin.name = "Cabin"
	_cut_bay(cabin)
	P.car_shell(root, [Vector4(-2.67, 0.46, 1.12, 1.32), Vector4(-1.66, 1.018, 1.12, 2.08), Vector4(-0.79, 1.018, 1.12, 2.28)], Color("335d70")).name = "CockpitGlass"
	P.car_beam(root, Vector3(0, 1.28, -2.5), Vector3(0, 2.14, -0.85), 0.075, PAINT)
	P.box(root, Vector3(0, 1.8, 2.15), Vector3(2.0, 0.09, 0.65), TRIM)
	P.box(root, Vector3(0, 2.05, 2.15), Vector3(0.10, 0.8, 0.6), PAINT)
	# Pylons and ducts sit above head height: a walker steps under them to the
	# side door, so they stay out of the perch field (one baked overhead mesh).
	var ducts = Node3D.new()
	ducts.name = "Ducts"
	ducts.set_meta("unbatched", true)
	root.add_child(ducts)
	for side in [-1, 1]:
		P.box(root, Vector3(side * 1.02, 0.69, 0), Vector3(0.05, 0.16, 3.1), TRIM)
		P.box(root, Vector3(side * 1.2, 0.12, -0.1), Vector3(0.13, 0.19, 4.2), DARK).name = "LandingSkid"
		for z in [-1.25, 1.1]:
			P.car_beam(root, Vector3(side * 0.7, 0.8, z), Vector3(side * 1.2, 0.19, z), 0.1, DARK)
		P.box(ducts, Vector3(side * 1.1, 2.22, 0.2), Vector3(1.2, 0.19, 0.65), PAINT)
		_fan(root, ducts, side)
		P.box(root, Vector3(side * 0.6, 0.95, -2.25), Vector3(0.25, 0.12, 0.08), Color("fff3be"))
	# Cargo has an actual opening in the starboard side, with a sliding door.
	P.box(root, Vector3(0.65, 1.25, 0), Vector3(0.03, 1.1, 1.6), DARK).name = "CargoRecess"
	var hinge = Node3D.new()
	hinge.name = "TrunkHinge"
	root.add_child(hinge)
	P.box(hinge, Vector3(1.045, 1.25, 0), Vector3(0.05, 1.12, 1.62), PAINT)
	P.box(hinge, Vector3(1.08, 1.32, -0.5), Vector3(0.04, 0.06, 0.22), DARK)
	P.box(hinge, Vector3(1.08, 0.82, 0), Vector3(0.025, 0.14, 1.58), TRIM)
	var boxes = Node3D.new()
	boxes.name = "TrunkBoxes"
	root.add_child(boxes)
	var profile = P.trunk_profile(variant)
	for i in range(P.CARGO_KINDS.size()):
		var item = P.gear_box(boxes, P.CARGO_KINDS[i], P.cargo_point(profile, i))
		item.scale = Vector3.ONE * 0.7
		if i == 5: item.rotation.x = PI * 0.5
	boxes.hide()
	P.MeshMerge.bake(ducts, "helicopter:ducts", [], "BakedDucts").set_meta("perch_ignore", true)
	root.set_meta("trunk_profile", profile)
	# Conservative fixed box contains the ducts at every rotor angle.
	root.set_meta("car_hitbox", AABB(Vector3(-3.25, 0, -2.8), Vector3(6.5, 2.7, 5.6)))
	return root

static func _cut_bay(cabin: MeshInstance3D) -> void:
	var arrays = cabin.mesh.surface_get_arrays(0)
	var source: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var fixed = PackedVector3Array()
	var planes = [Vector4(-1, 0, 0, -0.7), Vector4(0, -1, 0, -0.7), Vector4(0, 1, 0, 1.8), Vector4(0, 0, 1, 0.8), Vector4(0, 0, -1, 0.8)]
	for i in range(0, source.size(), 3):
		var poly: Array = [source[i], source[i + 1], source[i + 2]]
		for plane in planes:
			var normal = Vector3(plane.x, plane.y, plane.z)
			fixed = P.panel_triangles(fixed, P.clip_panel(poly, normal, plane.w, false))
			poly = P.clip_panel(poly, normal, plane.w, true)
			if poly.is_empty(): break
	cabin.mesh = P.panel_mesh(fixed)

static func _fan(root: Node3D, ducts: Node3D, side: int) -> void:
	var center = Vector3(side * 2.1, 2.35, 0.2)
	# Low polygon ring, open at both ends: blades remain visible inside it.
	for i in range(24):
		var angle = (i + 0.5) * TAU / 24
		var part = P.box(ducts, center + Vector3(cos(angle), 0, sin(angle)) * 1.03, Vector3(0.29, 0.35, 0.14), PAINT)
		part.rotation.y = -angle + PI * 0.5
	var rotor = Node3D.new()
	rotor.name = "RotorLeft" if side < 0 else "RotorRight"
	rotor.set_meta("unbatched", true)
	root.add_child(rotor)
	rotor.position = center
	P.cylinder(rotor, Vector3.ZERO, 0.17, 0.13, 0.22, DARK, 12).set_meta("perch_ignore", true)
	for i in range(4):
		var blade = P.box(rotor, Vector3(0.45, 0, 0).rotated(Vector3.UP, i * PI * 0.5), Vector3(0.82, 0.045, 0.16), DARK)
		blade.rotation.y = i * PI * 0.5
		blade.set_meta("perch_ignore", true)

static func animate(root: Node3D) -> void:
	var phase = fmod(Time.get_ticks_msec() * 0.035, TAU)
	for name in ["RotorLeft", "RotorRight"]:
		var rotor = root.get_node_or_null(name)
		if rotor != null: rotor.rotation.y = phase if name == "RotorLeft" else -phase
