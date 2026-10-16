extends RigidBody3D
# Keep the gameplay node (and its local-space API) while Godot owns its pose.
const Settler = preload("res://scripts/stages/rigid_settler.gd")
var record: Dictionary
var solids
var game
var moving = false
var actors
var pull_velocity = Vector3.ZERO

static func create(r: Dictionary, world_solids, owner_game) -> RigidBody3D:
	var body = load("res://scripts/core/prop_body.gd").new()
	body.name = "PropBody"
	body.record = r
	body.solids = world_solids
	body.game = owner_game
	body.mass = r.mass
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.center_of_mass = r.box.get_center()
	body.collision_mask = 1 | (1 << 9) | (1 << 12) | (1 << 13)
	Settler.configure(body)
	var material = PhysicsMaterial.new()
	material.friction = 0.65
	material.bounce = 0.08
	body.physics_material_override = material
	body.freeze = r.anchored or not owner_game.room.is_authority()
	body.sleeping = true
	r.node.add_child(body)
	body.top_level = true
	body.global_transform = r.node.global_transform
	if r.has("tree"):
		world_solids.stage.fallen[r.tree].dynamic = true
		var direction: Vector3 = world_solids.stage.fallen[r.tree].direction
		var length: float = world_solids.stage.forest_data[r.tree].height * 0.64
		var collider = CollisionShape3D.new()
		var shape = CapsuleShape3D.new()
		shape.radius = 0.2
		shape.height = maxf(0.7, length)
		collider.shape = shape
		body.add_child(collider)
		collider.position = direction * length * 0.5 + Vector3.UP * 0.2
		collider.basis = Basis(Quaternion(Vector3.UP, direction))
		body.center_of_mass = collider.position
	for obstacle in world_solids.obstacles:
		if obstacle.get("prop", "") != r.key: continue
		var old: Node3D = obstacle.body
		for shape in old.get_children():
			if shape is CollisionShape3D:
				shape.reparent(body, true)
				obstacle.body = shape
		old.queue_free()
	var center: Vector3 = body.global_transform * body.center_of_mass
	var bottom: float = (r.node.global_transform * r.box).position.y
	var floor: float = world_solids.walking_floor(center, center.y)
	if not r.anchored and owner_game.room.is_authority() and (r.has("tree") or r.key.begins_with("camp:") or bottom > floor + 0.001):
		body.wake()
	return body

func place() -> void:
	freeze = true
	global_transform = record.node.global_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	if game.room.is_authority(): wake()

func wake() -> void:
	freeze = false
	sleeping = false
	record.changed = true
	record.node.set_meta("prop_dynamic", true)
	_ground()

func _ground() -> void:
	solids.physics_ground(global_transform * center_of_mass, record.box.size.length() * 0.5 + 2.0)
	if "injuries" in game:
		if not solids.prop_ground.has_node("Actors"):
			actors = load("res://scripts/core/prop_actors.gd").new()
			actors.name = "Actors"
			actors.game = game
			solids.prop_ground.add_child(actors)
		else:
			actors = solids.prop_ground.get_node("Actors")
		actors.update(solids.prop_ground.tiles)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(record.node) or record.node.is_queued_for_deletion(): return
	var simulate: bool = game.room.is_authority() and game.playing and not game.paused and not game.dead and not game.finished
	freeze = record.anchored or not simulate
	if freeze: return
	if pull_velocity.length_squared() > 0.0001:
		if sleeping: wake()
		var planar = Vector3(linear_velocity.x, 0, linear_velocity.z)
		var force = (pull_velocity - planar) * mass * 20.0
		# A pull must overcome contact friction before the velocity servo can act.
		force += pull_velocity.normalized() * mass * 6.5
		apply_central_force(force)
		angular_velocity = angular_velocity.move_toward(Vector3.ZERO, delta * 8.0)
	var active = not sleeping
	if active:
		if not moving and game.seated and "movable_props" in game:
			game.movable_props._unseat(record)
		record.changed = true
		record.node.set_meta("prop_dynamic", true)
		_ground()
	if active or moving:
		record.node.global_transform = global_transform
		if record.has("tree"):
			load("res://scripts/core/prop_specials.gd").move_tree(solids.stage, record)
	if active != moving:
		moving = active
		for obstacle in solids.obstacles:
			if obstacle.get("prop", "") == record.key: obstacle.dynamic = moving
		solids.indexed_obstacle_count = -1
