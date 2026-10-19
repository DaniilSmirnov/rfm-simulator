extends "res://tests/harness.gd"
const Ground = preload("res://scripts/camp/camp_ground.gd")
const Props = preload("res://scripts/core/props.gd")
const Physics = preload("res://tests/core/test_prop_physics.gd")
const Registry = preload("res://scripts/core/prop_registry.gd")
const Movables = preload("res://scripts/core/movable_props.gd")

func _initialize() -> void:
	call_deferred("run")

func surface(p: Vector3) -> float:
	return 0.25 * p.x + 0.08 * sin(p.z * 3.0)

func gap(node: Node3D, sampler: Callable) -> float:
	var result = INF
	for child in node.get_children():
		if not child is Node3D or child is CollisionObject3D or not child.visible: continue
		if child is MeshInstance3D and child.mesh != null:
			for vertex in child.mesh.get_faces():
				var p: Vector3 = child.global_transform * vertex
				result = minf(result, p.y - sampler.call(p))
		result = minf(result, gap(child, sampler))
	return result

func run() -> void:
	var world = Physics.World.new()
	root.add_child(world)
	var nodes: Array[Node3D] = []
	var table = Node3D.new()
	world.add_child(table)
	Props.table(table)
	nodes.append(table)
	var chair = Node3D.new()
	world.add_child(chair)
	Props.chair(chair, Vector3.ZERO)
	nodes.append(chair)
	nodes.append(Props.grill(world))
	nodes.append(Props.campfire(world))
	var pot = Props.cauldron(world)
	nodes.append(pot)
	nodes.append(Props.rally_fans_map_flag(world, Vector3.ZERO, 0))
	for i in range(nodes.size()):
		var node = nodes[i]
		for sloped in [false, true]:
			var sampler: Callable = surface if sloped else world.stage.ground
			var spot = Vector3(i * 4, 0, 0)
			var up = Vector3(-0.25, 1, -0.24).normalized() if sloped else Vector3.UP
			var right = up.cross(Basis(Vector3.UP, 0.7).z).normalized()
			node.basis = Basis(right, up, right.cross(up))
			node.position = Vector3(spot.x, Ground.height(node, spot, node.basis, sampler), spot.z)
			var clearance = gap(node, sampler)
			check(absf(clearance) < 0.002, "gear %d touches the actual surface, slope=%s gap=%.4f" % [i, sloped, clearance])
		# A second placement must reuse local feet rather than a previous world pose.
		node.basis = Basis.IDENTITY
		node.position = Vector3(i * 4, Ground.height(node, Vector3(i * 4, 0, 0), node.basis, world.stage.ground), 0)
		check(absf(gap(node, world.stage.ground)) < 0.002, "gear %d returns to flat ground" % i)
	var props = Movables.new()
	props.game = world
	for i in range(nodes.size()):
		Registry.register(world.stage.solids, nodes[i], 25, i == 3, "contact:%d" % i)
	props.refresh()
	for record in props.records.values():
		if not record.anchored: record.body.wake()
	for i in range(180):
		props.update({}, {}, 1.0 / 60.0)
		await physics_frame
	await process_frame
	for i in range(nodes.size()):
		var clearance = gap(nodes[i], world.stage.ground)
		check(absf(clearance) < 0.025, "gear %d remains on the ground after physics settles (%.4f)" % [i, clearance])
	world.free()
	finish()
