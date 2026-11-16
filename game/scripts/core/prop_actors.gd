extends Node3D
# Existing cars are kinematic; expose their measured poses to props.
const Hitbox = preload("res://scripts/cars/car_hitbox.gd")
var game
var bodies: Dictionary = {}
var frame = -1
# Only cars move props: people get no collider here. Walkers and spectators
# shoved camp gear (and squeezed it into the ground) just by walking into it.

func _physics_process(_delta: float) -> void:
	update(get_parent().tiles)

func update(tiles: Dictionary) -> void:
	if frame == Engine.get_physics_frames(): return
	frame = Engine.get_physics_frames()
	var present: Dictionary = {}
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
	for key in bodies.keys():
		if not present.has(key):
			bodies[key].queue_free()
			bodies.erase(key)

# Moving a body, even onto the same spot, makes the physics server recheck its
# contacts and wake every prop it touches: rewriting the poses of parked cars
# every tick kept the props around them awake for good.
func _pose(body: Node3D, pose: Transform3D) -> void:
	if not body.global_transform.is_equal_approx(pose):
		body.global_transform = pose

# A body is born where it stands. Created at the origin and then posed, it
# moved there in one step: the physics took that for a kinematic velocity of
# thousands of m/s, and camp gear beside it flew 10 m.
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
