extends RefCounted
# The bonnet of a player car and the engine under it. CarHood.add() cuts the
# bonnet out of the bodywork onto HoodHinge (hinged at the windscreen, like the
# trunk lid on TrunkHinge) and lays out EngineBay below it: a dark tub, the
# radiator, the engine with its valve cover, the air filter, the battery and
# the coolant tank. The bay stays hidden, and costs nothing, while the bonnet
# is shut. CarHood.animate() swings it open and shut; car_repair.gd decides
# when, and strikes the parts with the Wrench while a car is being repaired.
#
# The bonnet's extent comes from the car record: from the nose to the
# windscreen base (shape[0]) at the bonnet height (base + bonnet_rise), or
# from "hood": {"back", "top", "nose", "lip"} for models drawn by their own
# scripts ("lip": metres of the nose that stay put, with the lamps in them).
const Props = preload("res://scripts/core/props.gd")
const CarRegistry = preload("res://scripts/cars/car_registry.gd")
const OPEN_ANGLE = 1.15
# The bay starts this far behind the nose and goes this deep under the cut.
const BAY_NOSE = 0.24
const BAY_DEPTH = 0.44
const SWING_RATE = 1.9
const TUB = Color("1c2226")
const STEEL = Color("6d7378")
const CHROME = Color("c3cacd")
# Parts the wrench strikes, by node name under EngineBay.
const TARGETS = ["ValveCover", "AirFilter", "Battery", "Radiator", "CoolantTank", "EngineBlock"]

static func profile(variant: int) -> Dictionary:
	var p: Dictionary = CarRegistry.car(variant)
	var hood: Dictionary = p.get("hood", {})
	var shape = p.get("shape")
	var base = 0.81 if p.get("suv", false) else 0.67
	var top = float(hood.get("top", base + float(p.get("bonnet_rise", 0.27))))
	var back = float(hood.get("back", float(shape[0]) - 0.03 if shape is Array else -0.9))
	var front = -float(p.length) / 2
	# A wedge nose ("nose": the bonnet height at the front) tilts the cut.
	var nose = float(hood.get("nose", top))
	return {"front": front, "back": back, "top": top, "cut": (top + nose) * 0.5 - 0.10, "lip": front + float(hood.get("lip", 0.0)), "slope": (top - nose) / (back - front),
		"nose_cut": nose - 0.10, "half": float(hood.get("half", float(p.width) * 0.5 - 0.13))}

static func has_hood(variant: int) -> bool:
	return not CarRegistry.flies(variant)

static func add(root: Node3D, variant: int) -> void:
	if not has_hood(variant):
		return
	var h = profile(variant)
	var hinge = Node3D.new()
	hinge.name = "HoodHinge"
	root.add_child(hinge)
	hinge.position = Vector3(0, h.top, h.back)
	# Above the line from the nose to the windscreen base: -y + slope * z <= -(nose_cut - slope * front).
	var above = Vector4(0, -1, h.slope, -(h.nose_cut - h.slope * h.front))
	# Models drawn by their own scripts keep the bodywork in one group node.
	var source: Node3D = root.get_node_or_null(str(root.get_meta("bodywork", "")))
	Props.cut_panel(root, hinge, [Vector4(1, 0, 0, h.half), Vector4(-1, 0, 0, h.half), Vector4(0, 0, 1, h.back), Vector4(0, 0, -1, -h.lip), above], true, source)
	# Whatever of the body is left inside the bay (floor panels, arch tops)
	# would cover the engine: cut it out too, and drop it.
	var scrap = Node3D.new()
	Props.cut_panel(root, scrap, [Vector4(1, 0, 0, h.half), Vector4(-1, 0, 0, h.half), Vector4(0, 0, 1, h.back - 0.03), Vector4(0, 0, -1, -(h.front + BAY_NOSE)), Vector4(0, -1, 0, -(h.cut - BAY_DEPTH))], false, source)
	scrap.free()
	_bay(root, h)
	root.set_meta("hood_profile", h)

# The engine compartment, in car space (the nose is towards -Z).
static func _bay(root: Node3D, h: Dictionary) -> void:
	var bay = Node3D.new()
	bay.name = "EngineBay"
	root.add_child(bay)
	var front: float = h.front + BAY_NOSE
	var back: float = h.back - 0.03
	var depth: float = back - front
	var mid: float = (front + back) * 0.5
	var half: float = h.half - 0.02
	var floor_y: float = h.cut - BAY_DEPTH
	var rim: float = h.cut - 0.015
	var wall: float = rim - floor_y
	Props.box(bay, Vector3(0, floor_y, mid), Vector3(half * 2, 0.03, depth), TUB).name = "Tub"
	for side in [-1, 1]:
		Props.box(bay, Vector3(side * half, floor_y + wall * 0.5, mid), Vector3(0.03, wall, depth), TUB)
		# Strut towers by the fenders.
		Props.cylinder(bay, Vector3(side * (half - 0.13), rim - 0.08, back - depth * 0.3), 0.08, 0.07, 0.12, STEEL.darkened(0.25), 10)
	Props.box(bay, Vector3(0, floor_y + wall * 0.5, back), Vector3(half * 2, wall, 0.03), TUB).name = "Firewall"
	var radiator = Props.box(bay, Vector3(0, rim - 0.17, front + 0.04), Vector3(half * 1.7, 0.30, 0.06), Color("2a3034"))
	radiator.name = "Radiator"
	Props.box(radiator, Vector3(0, 0.16, 0), Vector3(half * 1.7, 0.04, 0.08), Color("3b4247"))
	Props.cylinder(radiator, Vector3(half * 0.4, 0.19, 0), 0.025, 0.025, 0.03, Color("b9b2a1"), 10)
	var block_z = mid + depth * 0.06
	var engine = Props.box(bay, Vector3(0, floor_y + 0.17, block_z), Vector3(minf(0.62, half * 1.0), 0.30, minf(0.5, depth * 0.5)), STEEL)
	engine.name = "EngineBlock"
	var cover = Props.box(bay, Vector3(0, floor_y + 0.355, block_z), Vector3(minf(0.5, half * 0.82), 0.07, minf(0.44, depth * 0.44)), Color("8c2b22"))
	cover.name = "ValveCover"
	Props.cylinder(cover, Vector3(0.1, 0.05, -0.08), 0.032, 0.032, 0.03, Color("d9b43a"), 10)
	for i in range(4):
		Props.box(cover, Vector3(-0.16 + i * 0.105, 0.045, 0.1), Vector3(0.025, 0.025, 0.04), Color("20262a"))
	var filter = Props.cylinder(bay, Vector3(-half * 0.55, rim - 0.12, block_z - depth * 0.08), 0.15, 0.15, 0.09, Color("2b3035"), 14)
	filter.name = "AirFilter"
	Props.cylinder(filter, Vector3(0, 0.05, 0), 0.03, 0.03, 0.02, CHROME, 8)
	var battery = Props.box(bay, Vector3(half * 0.58, floor_y + 0.24, back - depth * 0.22), Vector3(0.18, 0.18, 0.26), Color("181c1f"))
	battery.name = "Battery"
	Props.cylinder(battery, Vector3(0.05, 0.1, -0.08), 0.018, 0.018, 0.03, Color("b33a2c"), 8)
	Props.cylinder(battery, Vector3(0.05, 0.1, 0.08), 0.018, 0.018, 0.03, Color("2e3135"), 8)
	var tank = Props.cylinder(bay, Vector3(half * 0.62, rim - 0.12, front + depth * 0.32), 0.07, 0.07, 0.16, Color("dcd6c4"), 12)
	tank.name = "CoolantTank"
	Props.cylinder(tank, Vector3(0, 0.09, 0), 0.04, 0.04, 0.025, Color("2c4a6e"), 10)
	bay.add_child(wrench())
	bay.hide()

# An open-ended spanner, held at the origin with its head towards -Z.
static func wrench() -> Node3D:
	var root = Node3D.new()
	root.name = "Wrench"
	Props.box(root, Vector3(0, 0, -0.15), Vector3(0.04, 0.014, 0.30), CHROME).name = "Handle"
	var head = Node3D.new()
	head.position = Vector3(0, 0, -0.33)
	root.add_child(head)
	Props.box(head, Vector3.ZERO, Vector3(0.085, 0.016, 0.07), CHROME)
	for side in [-1, 1]:
		Props.box(head, Vector3(side * 0.029, 0, -0.055), Vector3(0.026, 0.016, 0.05), CHROME)
	var spark = Props.faceted(root, Vector3(0, 0, -0.37), Vector3(0.07, 0.07, 0.07), Color("ffe9a6"), 6, 3)
	spark.name = "Spark"
	var glow = Props.material(Color("ffe9a6"))
	glow.emission_enabled = true
	glow.emission = Color("ffcf6a")
	glow.emission_energy_multiplier = 3.0
	spark.material_override = glow
	spark.hide()
	root.hide()
	return root

# Where a wrench strikes `part` (a node under EngineBay), in bay space.
static func strike_point(bay: Node3D, part: String) -> Vector3:
	var node: Node3D = bay.get_node_or_null(part)
	if node == null:
		return Vector3.ZERO
	var top = node.position.y
	if node is MeshInstance3D and node.mesh != null:
		top += node.mesh.get_aabb().end.y
	return Vector3(node.position.x, top, node.position.z)

# Swings the bonnet towards open or shut; the bay shows while it is ajar.
static func animate(root: Node3D, open: bool, delta: float) -> void:
	var hinge = root.get_node_or_null("HoodHinge")
	if hinge == null:
		return
	hinge.rotation.x = move_toward(hinge.rotation.x, OPEN_ANGLE if open else 0.0, delta * SWING_RATE)
	root.get_node("EngineBay").visible = hinge.rotation.x > 0.05

static func is_open(root: Node3D) -> bool:
	var hinge = root.get_node_or_null("HoodHinge")
	return hinge != null and hinge.rotation.x > OPEN_ANGLE * 0.6

# The middle of the open bay in world space: what the repairer looks at.
static func bay_point(root: Node3D) -> Vector3:
	var h: Dictionary = root.get_meta("hood_profile", {})
	if h.is_empty():
		return Vector3.INF
	return (root.global_transform if root.is_inside_tree() else root.transform) * Vector3(0, h.cut - 0.15, (h.front + h.back) * 0.5)
