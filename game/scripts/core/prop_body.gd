extends RigidBody3D
# Keep the gameplay node (and its local-space API) while Godot owns its pose.
const Settler = preload("res://scripts/stages/rigid_settler.gd")
var record: Dictionary
var solids
var game
var moving = false
var actors
var pull_velocity = Vector3.ZERO
# Resting-contact jitter (a chair on bumpy ground, a car on its wheels) can keep
# a body just above Godot's sleep thresholds forever, and every awake prop is a
# full physics step plus a ground refresh each tick. A body that has not really
# moved for REST_TICKS is put to sleep; any contact wakes it again. A traffic
# cone free to tilt chattered 1.6 cm up and down every tick and never counted
# as still with a 1 cm tolerance.
const REST_TICKS = 30
const REST_DISTANCE = 0.02
const REST_ANGLE = 0.01
var _rest_pose = Transform3D()
var _rest_ticks = 0
var _grounded_at = Vector3.INF
# Upright furniture keeps its tilt unless a car may tip it over (allow_tip). The window stays open while the prop
# tumbles. A prop already lying over settles freely; a walker who drags it
# turns it back upright.
const GUARD_ANGLE = 0.35
const TUMBLE_SPIN = 0.5
const TIPPED_ANGLE = 0.5
const UPRIGHT_ANGLE = 0.05
const RIGHTING_GAIN = 5.0
const RIGHTING_SPEED = 3.0
# Without a tipping impact a prop only slides at walking pace. A walker's
# collider that ends up inside a prop (a cauldron mounted over the spot where
# its owner stands) pushed it out at tens of metres per second.
const MAX_DRIFT = 3.0
var righting = false
var _rising = false
var _tip_time = 0.0
var _guarded = false
# A pose the prop belongs in (a cauldron over its campfire, see movable_props).
# return_to() carries it back there along a low arc, upright again.
const RETURN_SECONDS = 1.2
const RETURN_LIFT = 0.5
var home = null
var _return_from = Transform3D()
var _return_to = Transform3D()
var _return_t = -1.0

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
	body._guard(not r.has("tree") and r.node.is_inside_tree() and r.node.global_basis.y.normalized().angle_to(Vector3.UP) < GUARD_ANGLE)
	body.sleeping = true
	r.node.add_child(body)
	body.top_level = true
	body.global_transform = r.node.global_transform
	if r.has("tree"):
		world_solids.stage.fallen[r.tree].dynamic = true
		var stage = world_solids.stage
		var f: Dictionary = stage.fallen[r.tree]
		var axis: Vector3 = Basis(Vector3.UP.cross(f.direction).normalized(), float(f.get("lie", PI * 0.5))) * Vector3.UP
		var length: float = stage.forest_data[r.tree].height * 0.64
		var collider = CollisionShape3D.new()
		var shape = CapsuleShape3D.new()
		shape.radius = 0.2
		shape.height = maxf(0.7, length)
		collider.shape = shape
		body.add_child(collider)
		collider.position = axis * length * 0.5 + Vector3.UP * 0.2
		collider.basis = Basis(Quaternion(Vector3.UP, axis))
		body.center_of_mass = collider.position
		# A round trunk on a hillside rolled away as soon as it landed. It only
		# turns about the vertical while dragged.
		body.axis_lock_angular_x = true
		body.axis_lock_angular_z = true
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
	# A felled tree already lies on the ground it fell onto and waits for a drag.
	if not r.anchored and owner_game.room.is_authority() and not r.has("tree") and (r.key.begins_with("camp:") or bottom > floor + 0.001):
		body.wake()
	return body

func place() -> void:
	home = null
	_return_t = -1.0
	freeze = true
	global_transform = record.node.global_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	# Once guarded, a prop stays guarded until a car tips it, so a pose set
	# here decides afresh: a chair placed lying over settles lying over.
	_slope_at = Vector3.INF
	_strain = 0.0
	_guard(not record.has("tree") and _lean() < GUARD_ANGLE)
	if game.room.is_authority() and not record.anchored: wake()

func wake() -> void:
	freeze = false
	sleeping = false
	record.changed = true
	record.node.set_meta("prop_dynamic", true)
	_rest_ticks = 0
	_grounded_at = global_transform * center_of_mass
	_ground()

func return_to(target: Transform3D) -> void:
	_return_from = global_transform
	_return_to = target
	_return_t = 0.0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = true

func returning() -> bool:
	return _return_t >= 0.0

func _carry_home(delta: float) -> void:
	_return_t = minf(1.0, _return_t + delta / RETURN_SECONDS)
	var k: float = smoothstep(0.0, 1.0, _return_t)
	var pose: Transform3D = _return_from.interpolate_with(_return_to, k)
	pose.origin.y += sin(PI * k) * RETURN_LIFT
	global_transform = pose
	record.node.global_transform = pose
	record.changed = true
	record.node.set_meta("prop_dynamic", true)
	if _return_t >= 1.0:
		_return_t = -1.0
		wake()

func allow_tip(seconds: float) -> void:
	_tip_time = maxf(_tip_time, seconds)
	_guard(false)

# The guard keeps upright furniture from tipping without locking its tilt.
# Axis locks did that before, but a body that cannot tilt rests on one or two
# corners of the terrain tiles: camp tables, benches, service-park gear and NPC
# cars crept across the ground at 0.05-0.5 m/s and never slept. Now a prop
# leans freely onto the slope it stands on (up to LEAN_FREE off that slope)
# and is only turned back once it leans further.
const LEAN_FREE = 0.25
const SLOPE_REACH = 0.6
const TILT_DAMP = 0.85
# A leg on a rock or a tile edge can hold a prop past LEAN_FREE; righting it
# for good kept it awake. After STRAIN_SECONDS it rests as it stands, unless
# it leans past GUARD_ANGLE.
const STRAIN_SECONDS = 1.0
var _strain = 0.0
var _slope_at = Vector3.INF
var _slope_up = Vector3.UP

func _guard(on: bool) -> void:
	_guarded = on

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not _guarded: return
	var up: Vector3 = state.transform.basis.y.normalized()
	var target: Vector3 = _standing(up, state.transform * center_of_mass)
	var spin: Vector3 = state.angular_velocity
	var yaw: Vector3 = target * spin.dot(target)
	var lean: float = up.angle_to(target)
	var axis: Vector3 = up.cross(target)
	if lean < LEAN_FREE or axis.length_squared() < 0.000001:
		# Damped rocking. Assigning a velocity wakes the body, so a slow one is
		# left alone and can fall asleep.
		if (spin - yaw).length_squared() > 0.0025:
			state.angular_velocity = yaw + (spin - yaw) * TILT_DAMP
		return
	if _strain < STRAIN_SECONDS or lean > GUARD_ANGLE:
		state.angular_velocity = yaw + axis.normalized() * minf((lean - LEAN_FREE) * RIGHTING_GAIN, RIGHTING_SPEED)

func _tilt() -> float:
	return global_basis.y.normalized().angle_to(Vector3.UP)

# Tilt from the nearer of two ways to stand: level, or square to the ground
# under the prop. The ground is sampled over a metre, so a prop on a level
# patch of a hillside (a camp grill) still counts as standing.
func _lean() -> float:
	var up: Vector3 = global_basis.y.normalized()
	return up.angle_to(_standing(up, global_transform * center_of_mass))

func _standing(up: Vector3, center: Vector3) -> Vector3:
	var slope: Vector3 = _slope(center)
	return slope if up.dot(slope) > up.y else Vector3.UP

func _slope(center: Vector3) -> Vector3:
	if center.distance_squared_to(_slope_at) > 0.25:
		_slope_at = center
		var stage = solids.stage
		var x := Vector3(SLOPE_REACH, 0, 0)
		var z := Vector3(0, 0, SLOPE_REACH)
		_slope_up = Vector3(stage.ground(center - x) - stage.ground(center + x), 2.0 * SLOPE_REACH, stage.ground(center - z) - stage.ground(center + z)).normalized()
	return _slope_up

func _upright_spin() -> Vector3:
	var up: Vector3 = global_basis.y.normalized()
	var axis: Vector3 = up.cross(Vector3.UP)
	if axis.length_squared() < 0.000001:
		axis = global_basis.x
	return axis.normalized() * minf(_tilt() * RIGHTING_GAIN, RIGHTING_SPEED)

func _at_rest() -> bool:
	var pose = global_transform
	var still = pose.origin.distance_to(_rest_pose.origin) < REST_DISTANCE and pose.basis.get_rotation_quaternion().angle_to(_rest_pose.basis.get_rotation_quaternion()) < REST_ANGLE
	if not still:
		_rest_pose = pose
		_rest_ticks = 0
		return false
	_rest_ticks += 1
	return _rest_ticks >= REST_TICKS

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

# A body pushed under the terrain tiles fell for good (a camp table at -80 m)
# and stayed awake. Put it back on the ground where it went through.
func _rescue(center: Vector3) -> void:
	var ground: float = solids.stage.ground(center)
	if center.y > ground - 1.0: return
	global_position.y += ground + record.box.size.y * 0.5 + 0.02 - center.y
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_grounded_at = global_transform * center_of_mass
	_ground()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(record.node) or record.node.is_queued_for_deletion(): return
	var simulate: bool = game.room.is_authority() and game.playing and not game.paused and not game.dead and not game.finished
	if returning():
		if simulate: _carry_home(delta)
		return
	# Assign only on change: setting `freeze`, even to its current value, resets
	# the body mode in the physics server and wakes it, so no prop ever slept.
	var frozen: bool = record.anchored or not simulate
	if freeze != frozen:
		var asleep: bool = sleeping
		freeze = frozen
		# Unfreezing wakes the body too: every prop in the camps and service
		# parks woke when play started, and settling on the heightmap tiles some
		# never slept again. A prop that slept while frozen keeps sleeping.
		if not frozen and asleep:
			sleeping = true
	if frozen: return
	if _tip_time > 0.0 and angular_velocity.length() < TUMBLE_SPIN:
		_tip_time -= delta
	if not righting or record.has("tree"):
		_rising = false
	elif not _rising and _tilt() > TIPPED_ANGLE:
		_rising = true
	elif _rising and _tilt() < UPRIGHT_ANGLE:
		_rising = false
	if not sleeping:
		var lean: float = _lean()
		_guard(not record.has("tree") and _tip_time <= 0.0 and not _rising and (_guarded or lean < GUARD_ANGLE))
		_strain = _strain + delta if _guarded and lean >= LEAN_FREE else 0.0
	if pull_velocity.length_squared() > 0.0001 or _rising:
		if sleeping: wake()
	elif record.has("tree") and not sleeping:
		# Let go, a trunk stays where it was dragged instead of sliding downhill.
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		sleeping = true
	if pull_velocity.length_squared() > 0.0001:
		var planar = Vector3(linear_velocity.x, 0, linear_velocity.z)
		var force = (pull_velocity - planar) * mass * 20.0
		# A pull must overcome contact friction before the velocity servo can act.
		force += pull_velocity.normalized() * mass * 6.5
		apply_central_force(force)
	if _rising:
		angular_velocity = _upright_spin()
	elif pull_velocity.length_squared() > 0.0001:
		angular_velocity = angular_velocity.move_toward(Vector3.ZERO, delta * 8.0)
	if _guarded:
		var drift = Vector3(linear_velocity.x, maxf(0.0, linear_velocity.y), linear_velocity.z)
		if drift.length() > MAX_DRIFT:
			linear_velocity -= drift - drift.limit_length(MAX_DRIFT)
	var active = not sleeping
	if active and pull_velocity.length_squared() <= 0.0001 and not _rising and _at_rest():
		# Velocities first: assigning one wakes the body again.
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		sleeping = true
		active = false
		_tip_time = 0.0
	if active:
		if not moving and game.seated and "movable_props" in game:
			game.movable_props._unseat(record)
		record.changed = true
		record.node.set_meta("prop_dynamic", true)
		# The collision tiles around a prop only need refreshing once it has
		# travelled; per tick it rebuilt nothing but cost a scan of all trunks.
		var center: Vector3 = global_transform * center_of_mass
		if center.distance_squared_to(_grounded_at) > 1.0:
			_grounded_at = center
			_ground()
			_rescue(center)
	if active or moving:
		record.node.global_transform = global_transform
		if record.has("tree"):
			load("res://scripts/core/prop_specials.gd").move_tree(solids.stage, record)
	if active != moving:
		moving = active
		solids.set_dynamic(record.key, moving)
