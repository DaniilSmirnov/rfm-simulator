extends RefCounted
# Campfire geometry; flames are visual only and do not support a walker.
const Props = preload("res://scripts/props.gd")

static func build(parent: Node3D) -> Node3D:
	var root = Node3D.new()
	root.name = "Campfire"
	parent.add_child(root)
	for i in range(10):
		var angle = i * TAU / 10
		Props.faceted(root, Vector3(cos(angle) * 0.7, 0.09, sin(angle) * 0.7), Vector3(0.27, 0.18, 0.23), Color("686e6a"), 6, 3)
	for i in range(5):
		var log = Props.cylinder(root, Vector3(0, 0.17 + i * 0.035, 0), 0.075, 0.065, 0.95, Color("62412c"), 7)
		log.rotation = Vector3(PI / 2, i * 1.3, 0)
	var flames = Node3D.new()
	flames.name = "Flames"
	root.add_child(flames)
	for i in range(5):
		var flame = Props.faceted(flames, Vector3(sin(i * 2.4) * 0.23, 0.35, cos(i * 2.4) * 0.23), Vector3(0.19, 0.55, 0.19), Color("ff751e") if i % 2 else Color("ffc53f"), 5, 3)
		flame.set_meta("perch_ignore", true)
		Props.unique_material(flame)
		flame.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return load("res://scripts/perches.gd").mark(root, false)
