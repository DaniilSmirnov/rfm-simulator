extends "res://tests/harness.gd"
# The camp props: the folding table dressed differently per camp but the same
# for everyone in a room, everything lying on its top; the steel mangal with
# skewers resting on its rims above the coals; the folding hiking chair.
const Props = preload("res://scripts/core/props.gd")
const TableModel = preload("res://scripts/camp/table_model.gd")
const GrillModel = preload("res://scripts/camp/grill_model.gd")
const ChairModel = preload("res://scripts/camp/chair_model.gd")

func _initialize() -> void:
	call_deferred("run")

var world: Node3D

func table(variant: int, style: String = "camp") -> Node3D:
	var node = Node3D.new()
	world.add_child(node)
	Props.table(node, variant, style)
	return node

func chair(offset: Vector3 = Vector3.ZERO) -> Node3D:
	var node = Node3D.new()
	world.add_child(node)
	Props.chair(node, offset)
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
	var seat_a = chair()
	var seat_b = chair()
	var shifted = chair(Vector3(2, 0, 3))
	check(ChairModel.SEAT == Props.CHAIR_SEAT, "the chair model sits at the height the seat pose expects")
	check(seat_a.get_child_count() == 1 and baked_mesh(seat_a) == baked_mesh(seat_b), "every folding chair is one draw call and one shared mesh")
	check(is_equal_approx(shifted.get_node("Baked").position.x, 2.0) and is_equal_approx(shifted.get_node("Baked").position.z, 3.0), "a chair built at an offset keeps the shared mesh and moves only its node")
	var chair_bounds: AABB = baked_mesh(seat_a).get_aabb()
	check(chair_bounds.size.x > 0.65 and chair_bounds.size.x < 0.95 and chair_bounds.size.z > 0.6 and chair_bounds.size.z < 0.95, "the chair keeps a camp-chair footprint (%s)" % str(chair_bounds.size))
	check(chair_bounds.position.y > -0.01 and chair_bounds.end.y > 0.8 and chair_bounds.end.y < 1.0, "the back reaches a sitter's shoulders and the feet stand on the ground (%s)" % str(chair_bounds))
	var seat_top = -1.0
	var faces = baked_mesh(seat_a).get_faces()
	for vertex in faces:
		# The sling's corners between the side rails, well below the armrests.
		if absf(vertex.x) < 0.3 and vertex.y > 0.25 and vertex.y < 0.35 and vertex.z < 0.3:
			seat_top = maxf(seat_top, vertex.y)
	check(absf(seat_top - Props.CHAIR_SEAT) < 0.01, "the canvas seat top is where a sitter's thighs rest (%.3f)" % seat_top)
	var shapes: Array = seat_a.get_meta("prop_shapes")
	check(shapes.size() > 0 and shapes.size() <= 12, "a knocked-over chair collides with a few simple boxes (%d)" % shapes.size())
	var moved: Array = shifted.get_meta("prop_shapes")
	check(is_equal_approx(moved[0].position.x - shapes[0].position.x, 2.0), "collision boxes follow the chair's offset")
	world.free()
	print("CAMP MODELS RESULT: %d checks, %d failures" % [checks, failures])
	finish()
