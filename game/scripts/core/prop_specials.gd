extends RefCounted
# Existing simulated lamps and instanced trees retain their native world snapshots.
static func refresh(game, records: Dictionary) -> void:
	var stage = game.stage
	for i in range(stage.solids.lamps.size()):
		var lamp: Dictionary = stage.solids.lamps[i]
		var key = "lamp:%d" % i
		if lamp.fallen and not records.has(key):
			records[key] = {"key": key, "node": lamp.body, "box": AABB(Vector3(-0.17, -2, -0.17), Vector3(0.34, 4, 0.34)), "mass": 28.0, "anchored": false, "changed": false, "velocity": Vector3.ZERO, "spin": Vector3.ZERO, "lamp": i}
	for index in stage.fallen:
		var key = "tree:%d" % index
		if records.has(key):
			records[key].node.position = stage.trees[index]
			continue
		if stage.fallen[index].age < 1.3: continue
		var node = Node3D.new()
		stage.add_child(node)
		node.position = stage.trees[index]
		var length: float = stage.forest_data[index].height * 0.64
		var direction: Vector3 = stage.fallen[index].direction
		var end = direction * length
		var box = AABB(Vector3.ZERO.min(end) - Vector3(0.35, 0, 0.35), end.abs() + Vector3(0.7, 0.7, 0.7))
		records[key] = {"key": key, "node": node, "box": box, "mass": 120.0, "anchored": false, "changed": false, "velocity": Vector3.ZERO, "spin": Vector3.ZERO, "tree": index}

static func move_lamp(game, r: Dictionary) -> void:
	var body: RigidBody3D = r.node
	game.stage.solids._ground_under(game.stage.solids.lamps[r.lamp], body.position)
	body.sleeping = false
	body.linear_velocity.x = r.velocity.x
	body.linear_velocity.z = r.velocity.z
	r.velocity = Vector3.ZERO
	r.changed = false

static func move_tree(stage, r: Dictionary) -> void:
	var index: int = r.tree
	var old: Vector3 = stage.trees[index]
	var next: Vector3 = r.node.position
	var old_cell: Vector2i = stage._tree_cell(old)
	var new_cell: Vector2i = stage._tree_cell(next)
	if old_cell != new_cell:
		if stage.tree_cells.has(old_cell): stage.tree_cells[old_cell].erase(index)
		if not stage.tree_cells.has(new_cell): stage.tree_cells[new_cell] = []
		stage.tree_cells[new_cell].append(index)
	stage.trees[index] = next
	stage.fallen[index].erase("rendered_age")
	stage.update_fallen(0)
