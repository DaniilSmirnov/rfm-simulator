extends Node3D
# Existing cars and walkers are kinematic; expose their measured poses to props.
const Hitbox = preload("res://scripts/cars/car_hitbox.gd")
var game
var bodies: Dictionary = {}
var frame = -1
# People who stand or sit still get no collider: a crew sitting on its camp
# chairs, or standing at its table, overlapped them for good and kept them
# (and everything they touch) awake. A walker pushes props for STILL_TICKS after
# it stops, so a shove still lands.
const STILL_TICKS = 30
var _last: Dictionary = {}
var _still: Dictionary = {}

func _physics_process(_delta: float) -> void:
	update(get_parent().tiles)

func update(tiles: Dictionary) -> void:
	if frame == Engine.get_physics_frames(): return
	frame = Engine.get_physics_frames()
	var present: Dictionary = {}
	for person in game.injuries.people():
		if game.injuries.is_down(person.key): continue
		var p: Vector3 = person.pos
		if not tiles.has(Vector2i(floori(p.x / 16.0), floori(p.z / 16.0))): continue
		var moved = not _last.has(person.key) or Vector3(_last[person.key]).distance_squared_to(p) > 0.000004
		_last[person.key] = p
		_still[person.key] = 0 if moved else int(_still.get(person.key, STILL_TICKS)) + 1
		if _still[person.key] >= STILL_TICKS: continue
		present[person.key] = true
		var stance = Transform3D(Basis.IDENTITY, p + Vector3.UP * 0.85)
		if not bodies.has(person.key):
			var shape = CapsuleShape3D.new()
			shape.radius = 0.28
			shape.height = 1.7
			_create(person.key, shape, stance)
		_pose(bodies[person.key], stance)
	var cars: Array = [game.car]
	for peer in game.room.peers.values():
		if peer.has("car"): cars.append(peer.car)
	for racer in game.racers: cars.append(racer.node)
	for car in cars:
		if not is_instance_valid(car): continue
		var p: Vector3 = car.global_position
		if not tiles.has(Vector2i(floori(p.x / 16.0), floori(p.z / 16.0))): continue
		var key = "car:%d" % car.get_instance_id()
		present[key] = true
		var box: AABB = Hitbox.bounds(car)
		var pose: Transform3D = car.global_transform * Transform3D(Basis.IDENTITY, box.get_center())
		if not bodies.has(key):
			var shape = BoxShape3D.new()
			shape.size = box.size
			_create(key, shape, pose)
		_pose(bodies[key], pose)
	for key in _last.keys():
		if not present.has(key) and not _still.has(key):
			_last.erase(key)
	for key in bodies.keys():
		if not present.has(key):
			bodies[key].queue_free()
			bodies.erase(key)

# Moving a body, even onto the same spot, makes the physics server recheck its
# contacts and wake every prop it touches. Spectators stand still beside the camp
# chairs and tables, so rewriting their poses every tick kept a hundred props
# awake for good and the physics step took most of the frame.
func _pose(body: Node3D, pose: Transform3D) -> void:
	if not body.global_transform.is_equal_approx(pose):
		body.global_transform = pose

# A body is born where it stands. Created at the origin and then posed, it
# moved there in one step: the physics took that for a kinematic velocity of
# thousands of m/s, and a camp chair beside a spectator who set off flew 10 m.
func _create(key: String, shape: Shape3D, pose: Transform3D) -> void:
	var body = AnimatableBody3D.new()
	body.transform = global_transform.affine_inverse() * pose
	body.sync_to_physics = false
	body.collision_layer = 1 << 13
	body.collision_mask = 1
	var collider = CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	add_child(body)
	bodies[key] = body
