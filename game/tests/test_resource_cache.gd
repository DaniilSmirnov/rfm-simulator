extends SceneTree
const Props = preload("res://scripts/props.gd")
var failures = 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	var parent = Node3D.new()
	root.add_child(parent)
	var a = Props.box(parent, Vector3.ZERO, Vector3.ONE, Color.RED)
	var b = Props.box(parent, Vector3.UP, Vector3.ONE, Color.RED)
	check(a.mesh == b.mesh and a.material_override == b.material_override, "identical primitives share mesh and material")
	Props.unique_material(a)
	a.material_override.albedo_color = Color.BLUE
	check(b.material_override.albedo_color == Color.RED, "mutable copy leaves other objects untouched")
	var c = Props.cylinder(parent, Vector3.ZERO, 0.2, 0.1, 0.8, Color.RED, 8)
	var d = Props.cylinder(parent, Vector3.ONE, 0.2, 0.1, 0.8, Color.RED, 8)
	check(c.mesh == d.mesh and c.material_override == b.material_override, "cylinders reuse exact shape and common material")
	var e = Props.faceted(parent, Vector3.ZERO, Vector3.ONE, Color.RED)
	var f = Props.faceted(parent, Vector3.UP, Vector3.ONE, Color.RED)
	check(e.mesh == f.mesh, "faceted geometry is reused")
	var different = Props.faceted(parent, Vector3.ZERO, Vector3(1.000001, 1, 1), Color.RED)
	check(different.mesh != e.mesh, "close but unequal geometry never aliases")
	var pot_a = Props.cauldron(parent)
	var pot_b = Props.cauldron(parent)
	Props.pose_cauldron(pot_a, "cooking", 0.1, 0, 0)
	Props.pose_cauldron(pot_b, "ready", 1, 10, 0)
	check(pot_a.get_node("Rice/FoodSurface").material_override.albedo_color != pot_b.get_node("Rice/FoodSurface").material_override.albedo_color, "pots retain independent cooking colours")
	for i in range(600):
		var size = Vector3(10 + i, 1, 1)
		Props.box(parent, Vector3.ZERO, size, Color(float(i) / 600, 0.2, 0.1)).free()
		Props.cylinder(parent, Vector3.ZERO, 10 + i, 1, 1, Color.WHITE).free()
		Props.faceted(parent, Vector3.ZERO, size, Color.WHITE, 5, 3).free()
	for count in Props.resource_cache_sizes().values():
		check(count <= Props.RESOURCE_CACHE_LIMIT, "resource caches stay bounded under random content")
	parent.free()
	print("RESOURCE_CACHE failures=", failures)
	quit(1 if failures else 0)
