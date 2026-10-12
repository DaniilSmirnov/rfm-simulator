extends "res://tests/harness.gd"
# The camp props: the folding table dressed differently per camp but the same
# for everyone in a room, everything lying on its top; the steel mangal with
# skewers resting on its rims above the coals.
const Props = preload("res://scripts/props.gd")
const TableModel = preload("res://scripts/table_model.gd")
const GrillModel = preload("res://scripts/grill_model.gd")

func _initialize() -> void:
	call_deferred("run")

var world: Node3D

func table(variant: int, style: String = "camp") -> Node3D:
	var node = Node3D.new()
	world.add_child(node)
	Props.table(node, variant, style)
	return node

func baked_mesh(node: Node3D) -> Mesh:
	return node.get_node("Baked").mesh

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	var a = table(0)
	var again = table(0)
	var b = table(1)
	check(baked_mesh(a) == baked_mesh(again), "the same camp table is built once and shared")
	check(baked_mesh(a) != baked_mesh(b), "neighbouring camps lay their tables differently")
	check(a.get_child_count() == 1, "a dressed table is a single draw call")
	var bounds: AABB = baked_mesh(a).get_aabb()
	check(bounds.size.x <= TableModel.HALF_X * 2 + 0.01 and bounds.size.z <= TableModel.HALF_Z * 2 + 0.05, "everything stays on the table top")
	check(bounds.end.y > TableModel.TOP + 0.1 and bounds.end.y < TableModel.TOP + 0.45, "things stand on the table and none floats above it")
	var desk = table(0, "desk")
	check(baked_mesh(desk) != baked_mesh(a), "the timing desk is laid out on its own")
	var camp_faces = baked_mesh(a).get_faces().size()
	check(camp_faces > baked_mesh(desk).get_faces().size() + 600, "the camp table carries plates, cups and odd things the desk does not (%d)" % camp_faces)
	var grill = Props.grill(world)
	var zone = GrillModel.slot_zone(grill, 0, Props.FOOD_PORTIONS)
	check(zone.point.y > GrillModel.RIM, "skewers rest above the mangal's rims")
	check(grill.get_node("GrillFire/Coals").get_child(0).position.y < GrillModel.RIM, "the coals lie inside the firebox")
	var grill_bounds: AABB = grill.get_node("Baked").mesh.get_aabb()
	check(grill_bounds.size.x > 1.0 and grill_bounds.size.x < 1.3 and grill_bounds.size.z < 0.6, "the mangal keeps its footprint (%s)" % str(grill_bounds.size))
	world.free()
	print("CAMP MODELS RESULT: %d checks, %d failures" % [checks, failures])
	finish()
