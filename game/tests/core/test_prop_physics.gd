extends "res://tests/harness.gd"
const Movables = preload("res://scripts/core/movable_props.gd")
const Registry = preload("res://scripts/core/prop_registry.gd")
const Props = preload("res://scripts/core/props.gd")
const Contact = preload("res://scripts/cars/prop_contact.gd")
const Motion = preload("res://scripts/cars/vehicle_motion.gd")
const Solids = preload("res://scripts/stages/stage_solids.gd")
const Service = preload("res://scripts/traffic/service_park_model.gd")

class Terrain extends Node3D:
	var slope = 0.0
	var solids = Solids.new()
	var fallen: Dictionary = {}
	var trees: Array[Vector3] = []
	var forest_data: Array[Dictionary] = []
	var rocks: Array[Dictionary] = []
	var indexed_tree_count = 0
	var tree_cells: Dictionary = {}
	func _rebuild_tree_index() -> void: indexed_tree_count = trees.size()
	func _init() -> void:
		solids.stage = self
		add_child(solids)
	func ground(p: Vector3) -> float: return slope * p.x
	func walking_ground(p: Vector3) -> float: return ground(p)
	func rock_hit(_a, _b, _r) -> Dictionary: return {}
	func obstacle_hit(_a, _b, _r, _escape = false, _ignored = -1) -> int: return -1

class Room extends RefCounted:
	var guest = false
	var peers: Dictionary = {}
	func is_authority() -> bool: return not guest
	func is_guest() -> bool: return guest
	func a(p: Vector3) -> Array: return [p.x, p.y, p.z]
	func v(p: Array) -> Vector3: return Vector3(p[0], p[1], p[2])

class Packing extends RefCounted:
	func items() -> Array: return []

class People extends RefCounted:
	var entries: Array = []
	func people() -> Array: return entries
	func is_down(_key: String) -> bool: return false

class Cargo extends RefCounted:
	var held: Dictionary = {}

class World extends Node3D:
	var stage = Terrain.new()
	var room = Room.new()
	var packing = Packing.new()
	var cargo = Cargo.new()
	var injuries = People.new()
	var car = Node3D.new()
	var racers: Array = []
	var seated = false
	var playing = true
	var paused = false
	var dead = false
	var finished = false
	func _init() -> void:
		add_child(stage)
		add_child(car)
		car.position = Vector3(1000, 0, 1000)
	func player_position() -> Vector3: return Vector3.ZERO

var world: World
var props = Movables.new()

func _initialize() -> void:
	call_deferred("run")

func chair(at: Vector3, key: String, rotation: Vector3 = Vector3.ZERO) -> Node3D:
	var node = Node3D.new()
	world.stage.add_child(node)
	node.position = at
	node.rotation = rotation
	Props.chair(node, Vector3.ZERO)
	Registry.register(world.stage.solids, node, 5, false, key)
	props.refresh()
	return node

func advance(frames: int) -> void:
	for i in range(frames):
		props.update({}, {}, 1.0 / 60.0)
		await physics_frame
	await process_frame

# A walker slides furniture, even running or jumping into it; only cars tip it.
func walk_into(node: Node3D, step: float, players_state: Dictionary) -> void:
	var start: Vector3 = node.global_position - Vector3.RIGHT * 1.5
	world.injuries.entries = [{"key": "player:walker", "pos": start}]
	for i in range(int(2.5 / step)):
		world.injuries.entries[0].pos += Vector3.RIGHT * step
		var players: Dictionary = {}
		for id in players_state:
			var state: Dictionary = players_state[id].duplicate()
			state.pos = world.room.a(world.injuries.entries[0].pos)
			players[id] = state
		props.update(players, {}, 1.0 / 60.0)
		await physics_frame
	world.injuries.entries = []
	await advance(120)

func tipping() -> void:
	for yaw in [0.0, PI / 4]:
		var stroll = chair(Vector3(80, 0, 4 + yaw * 8), "stroll-%d" % int(yaw * 100), Vector3(0, yaw, 0))
		await advance(60)
		var start = stroll.global_position
		await walk_into(stroll, 0.04, {"walker": {"in_car": false}})
		check(stroll.global_position.distance_to(start) > 0.1, "walking into an upright chair pushes it (yaw %.2f)" % yaw)
		check(stroll.global_basis.y.dot(Vector3.UP) > 0.95, "walking into an upright chair cannot tip it over (yaw %.2f)" % yaw)
	var run = chair(Vector3(100, 0, 4), "run")
	await advance(60)
	await walk_into(run, 0.12, {"walker": {"in_car": false, "running": true}})
	check(run.global_basis.y.dot(Vector3.UP) > 0.95, "running into a chair cannot knock it over")
	var jump = chair(Vector3(120, 0, 4), "jump")
	await advance(60)
	await walk_into(jump, 0.08, {"walker": {"in_car": false, "airborne": true}})
	check(jump.global_basis.y.dot(Vector3.UP) > 0.95, "jumping into a chair cannot knock it over")
	var tipped = chair(Vector3(140, 0.4, 4), "tipped", Vector3(0, 0, PI / 2))
	props.knock("tipped", Vector3.DOWN)
	await advance(180)
	check(tipped.global_basis.y.dot(Vector3.UP) < 0.5, "a sideways chair lies on the ground before it is dragged")
	var puller = {"pos": world.room.a(props.center(props.records["tipped"]) + Vector3.RIGHT * 2), "tow": true, "in_car": false}
	var lowest = 1.0
	for i in range(60):
		props.update({"helper": puller}, {}, 1.0 / 60.0)
		await physics_frame
		if i == 10: lowest = tipped.global_basis.y.dot(Vector3.UP)
	await advance(60)
	check(lowest < 0.95, "a dragged tipped chair turns upright gradually, not in one frame")
	check(tipped.global_basis.y.dot(Vector3.UP) > 0.97, "dragging a tipped chair turns it back upright")

# A cauldron knocked off its campfire glides back onto it; dragged away, it stays.
func hearth() -> void:
	# Only the horizontal offset to the fire counts: keep its collider clear.
	chair(Vector3(200, -3, 4), "camp:firewood:a")
	props.records["camp:firewood:a"].anchored = true
	var pot = chair(Vector3(200, 0, 4), "camp:cauldron:a")
	await advance(120)
	var home: Transform3D = pot.global_transform
	props.knock("camp:cauldron:a", Vector3(8, 0, 3))
	await advance(20)
	check(pot.global_position.distance_to(home.origin) > 0.6, "a knocked cauldron leaves its campfire")
	var step = 0.0
	var previous = pot.global_position
	for i in range(420):
		await advance(1)
		step = maxf(step, pot.global_position.distance_to(previous))
		previous = pot.global_position
	check(pot.global_position.distance_to(home.origin) < 0.1 and pot.global_basis.y.dot(Vector3.UP) > 0.97, "a knocked cauldron returns upright onto its campfire")
	check(step < 0.25, "a cauldron returns to its campfire smoothly, not in one jump (%.2f m)" % step)
	var puller = {"pos": world.room.a(props.center(props.records["camp:cauldron:a"]) + Vector3.RIGHT * 2), "tow": true, "in_car": false}
	for i in range(90):
		props.update({"helper": puller}, {}, 1.0 / 60.0)
		await physics_frame
	await advance(240)
	check(pot.global_position.distance_to(home.origin) > 0.6, "a cauldron a player drags off the fire stays where it was left")

func run() -> void:
	world = World.new()
	root.add_child(world)
	props.game = world
	var node = chair(Vector3(0, 5, 0), "fall", Vector3(0, 0, PI / 2))
	await advance(2)
	check(node.global_position.y > 4.5, "a dropped prop falls over time instead of being clamped to the terrain")
	await advance(238)
	check(node.global_position.y < 1.0 and node.global_position.y > -0.2, "a dropped chair reaches the ground without penetration")
	check(absf(node.global_basis.y.dot(Vector3.UP)) < 0.5, "a dropped sideways chair stays fallen")
	var resting = node.global_transform
	await advance(120)
	check(node.global_transform.origin.distance_to(resting.origin) < 0.03 and node.global_basis.is_equal_approx(resting.basis), "a resting prop keeps its orientation")
	var body = props.records["fall"].get("body")
	check(body is RigidBody3D and body.can_sleep and body.sleeping, "a stable prop sleeps through the native contact solver")
	props.knock("fall", Vector3.RIGHT * 10)
	await advance(20)
	check(node.global_position.distance_to(resting.origin) > 0.1, "a second impact wakes and moves a fallen prop")
	chair(Vector3(-2, 0, 4), "pusher")
	var other = chair(Vector3(0, 0, 4), "other")
	var initial = other.global_position
	props.knock("pusher", Vector3.RIGHT * 6)
	await advance(240)
	check(other.global_position.distance_to(initial) > 0.05, "moving props transfer impulse to other props")
	var car_chair = chair(Vector3(0, 0, 12), "car-chair")
	var motion = Motion.new()
	motion.velocity = Vector3.RIGHT * 20
	var collision = Contact.resolve(world.stage, motion, Vector3(-3, 0, 12), Vector3(3, 0, 12), 1.0 / 60.0)
	for impact in collision.hits: props.solid_hit(impact.hit, impact.velocity)
	await advance(240)
	check(motion.velocity.x > 19 and not collision.blocked, "a high-speed swept car contact retains momentum against a chair")
	check(absf(car_chair.global_basis.y.dot(Vector3.UP)) < 0.7, "a chair struck through the car contact path falls and stays fallen")
	var bump = chair(Vector3(40, 0, 4), "walker-chair")
	props.knock("walker-chair", Vector3.DOWN)
	await advance(240)
	var bump_start = bump.global_position
	world.injuries.entries = [{"key": "npc:0", "pos": bump_start - Vector3.RIGHT * 2}]
	for i in range(100):
		world.injuries.entries[0].pos += Vector3.RIGHT * 0.04
		await advance(1)
	check(bump.global_position.distance_to(bump_start) > 0.1, "a moving NPC wakes sleeping props after all props have settled")
	await tipping()
	await hearth()
	var heavy = chair(Vector3(60, 0, 4), "heavy")
	props.records["heavy"].mass = 3500.0
	props.records["heavy"].body.mass = 3500.0
	var puller = {"pos": world.room.a(props.center(props.records["heavy"]) + Vector3.RIGHT * 2), "tow": true, "in_car": false}
	for i in range(90):
		props.update({"helper": puller}, {}, 1.0 / 60.0)
		await physics_frame
	await process_frame
	check(heavy.global_position.x > 60.1, "heavy registered props retain their existing slow dragging interaction")
	props.update({}, {}, 1.0 / 60.0)
	var snapshot = props.snapshot()
	world.room.guest = true
	props.apply_snapshot(snapshot)
	var replicated = node.global_transform
	await advance(60)
	check(node.global_transform == replicated, "a guest cannot simulate or upright a replicated fallen prop")
	world.queue_free()
	await process_frame
	world = World.new()
	world.stage.slope = 0.25
	root.add_child(world)
	props.game = world
	world.stage.trees.append(Vector3.ZERO)
	world.stage.forest_data.append({"height": 8.0})
	world.stage.fallen[0] = {"direction": Vector3.RIGHT, "age": 1.3}
	var trunk = Node3D.new()
	world.stage.add_child(trunk)
	var fallen = {"key": "tree:0", "tree": 0, "node": trunk, "mass": 120.0, "anchored": false, "box": AABB(Vector3.ZERO, Vector3(5.12, 0.7, 0.7))}
	var trunk_body = Movables.Body.create(fallen, world.stage.solids, world)
	check(trunk_body.sleeping and trunk_body.axis_lock_angular_x and trunk_body.axis_lock_angular_z, "a newly fallen trunk on a slope lies still and cannot roll")
	trunk.free()
	world.stage.trees.clear()
	world.stage.forest_data.clear()
	world.stage.fallen.clear()
	node = chair(Vector3(0, 3, 0), "slope")
	props.knock("slope", Vector3(0, -1, 0))
	await advance(360)
	check(node.global_position.y < 2 and absf(node.global_rotation.z) > 0.08, "a chair falling on a slope follows actual terrain contacts")
	var floor_pose = Transform3D(Basis.IDENTITY, Vector3(0, 5, 30))
	world.stage.solids.walk_surfaces.append({"pose": floor_pose, "inverse": floor_pose.affine_inverse(), "half": Vector2(4, 4), "rise": 0.0, "reach": 4.0})
	var upstairs = chair(Vector3(0, 8, 30), "floor")
	await advance(240)
	check(upstairs.global_position.y > 4.8 and upstairs.global_position.y < 6, "authored interior floors support falling props above terrain")
	world.stage.rocks.append({"pos": Vector3(80, 20, 60), "radius": 28.0, "height": 5.0})
	var rock_edge = chair(Vector3(60, 28, 60), "rock-edge")
	await advance(240)
	check(rock_edge.global_position.y > 24.8, "a large rock supports props outside the tile containing its center")
	var table = Node3D.new()
	world.stage.add_child(table)
	Props.table(table)
	table.position = Vector3(0, 0, 60)
	Registry.register(world.stage.solids, table, 12, false, "table-gap")
	props.refresh()
	check(world.stage.solids.hit(Vector3(-0.1, 0.3, 60), Vector3(0.1, 0.3, 60), 0.02, false, Vector3.ZERO).is_empty(), "a baked table has no invisible box between its legs")
	var grill = Props.grill(world.stage)
	grill.position = Vector3(0, 0, 70)
	Registry.register(world.stage.solids, grill, 25, false, "grill-gap")
	props.refresh()
	check(world.stage.solids.hit(Vector3(-0.1, 0.45, 70), Vector3(0.1, 0.45, 70), 0.02, false, Vector3.ZERO).is_empty(), "a baked grill keeps open space under its firebox")
	var park = Node3D.new()
	world.stage.add_child(park)
	var first = world.stage.solids.movables.size()
	Service.tent(world.stage, park, Vector2(13.5, 22.5), Service.TEAMS[0])
	var tent_pos = Service.at(13.5 + 2.6, 22.5 + 3.0, 1.25)
	var hit = world.stage.solids.hit(tent_pos - Vector3.RIGHT, tent_pos + Vector3.RIGHT, 0.05, false, Vector3.ZERO)
	check(not hit.is_empty() and hit.get("prop", "") == "", "service tent poles remain static collision geometry")
	check(world.stage.solids.movables.slice(first).all(func(r): return r.mass != 90.0), "the service tent is excluded from movable registration")
	world.queue_free()
	await process_frame
	finish()
