extends Node3D
# Existing cars and walkers are kinematic; expose their measured poses to props.
const Hitbox = preload("res://scripts/cars/car_hitbox.gd")
var game
var bodies: Dictionary = {}
var frame = -1

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
		present[person.key] = true
		if not bodies.has(person.key):
			var shape = CapsuleShape3D.new()
			shape.radius = 0.28
			shape.height = 1.7
			_create(person.key, shape)
		bodies[person.key].global_position = p + Vector3.UP * 0.85
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
		if not bodies.has(key):
			var shape = BoxShape3D.new()
			shape.size = box.size
			_create(key, shape)
		bodies[key].global_transform = car.global_transform * Transform3D(Basis.IDENTITY, box.get_center())
	for key in bodies.keys():
		if not present.has(key):
			bodies[key].queue_free()
			bodies.erase(key)

func _create(key: String, shape: Shape3D) -> void:
	var body = AnimatableBody3D.new()
	body.sync_to_physics = false
	body.collision_layer = 1 << 13
	body.collision_mask = 1
	var collider = CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	add_child(body)
	bodies[key] = body
