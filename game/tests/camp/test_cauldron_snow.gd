extends "res://tests/harness.gd"
# A plov cauldron on the snowy stages: heavy enough that a car nudging it stops
# against it, never buried in the snow after a crash, never thrown sky-high.
const PropContact = preload("res://scripts/cars/prop_contact.gd")
const STEP = 1.0 / 60.0

func _initialize() -> void: call_deferred("run")

func dig_around(stage, spot: Vector3) -> void:
	for x in range(-5, 6):
		for z in range(-5, 6):
			stage.snow.dig(stage, spot + Vector3(x * 0.5, 0, z * 0.5))

func center(host, pot: Node3D) -> Vector3:
	var r: Dictionary = host.movable_props.records[str(pot.get_meta("prop_key"))]
	return r.body.global_transform * r.body.center_of_mass

# Height of the centre of mass over the lowest snow within half a metre.
func clearance(host, pot: Node3D) -> float:
	var c: Vector3 = center(host, pot)
	var low = INF
	for dx in [-0.5, 0.0, 0.5]:
		for dz in [-0.5, 0.0, 0.5]:
			low = minf(low, host.stage.ground(c + Vector3(dx, 0, dz)))
	return c.y - low

func step(host, frames: int, watch: Callable = func(): pass) -> void:
	for i in range(frames):
		host.movable_props.update({}, {}, STEP)
		await physics_frame
		watch.call()

func camp(host, origin: Vector3) -> bool:
	var stage = host.stage
	if host.camp_cooking.fire != null:
		host.camp_cooking.fire.queue_free()
		host.camp_cooking.fire = null
	host.camp_cooking.remove_pot()
	await process_frame
	origin.y = stage.ground(origin)
	dig_around(stage, origin)
	host.car.global_position = origin + Vector3(0, 0, 40)
	var trunk = host.cargo.point(host.cargo.poses()["local"])
	host.walker = trunk
	host.cargo.take("firewood")
	host.walker = origin + Vector3(1.6, 0, 0)
	if not host.cargo.deploy("firewood", origin, 0.0): return false
	host.walker = trunk
	host.cargo.take("cauldron")
	host.walker = origin + Vector3(1.6, 0, 0)
	if not host.camp_cooking.mount() or host.camp_cooking.pot == null: return false
	await step(host, 30)
	return true

# Drives the player's car at the cauldron through the same contact code as play.
func ram(host, pot: Node3D, speed: float, frames: int, watch: Callable) -> bool:
	var stage = host.stage
	var dir := Vector3(0.8, 0, 0.6).normalized()
	var motion = host.vehicle_motion
	motion.velocity = dir * speed
	motion.prop_contacts.clear()
	var at: Vector3 = pot.global_position - dir * 8.0
	var blocked = false
	for i in range(frames):
		var next: Vector3 = at + motion.velocity * STEP
		next.y = stage.ground(next)
		var result = PropContact.resolve(stage, motion, at, next, STEP, {})
		for impact in result.hits: host.knock_solid(impact.hit, impact.velocity)
		blocked = blocked or result.blocked
		at = result.position
		at.y = stage.ground(at)
		host.car.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), at)
		host.movable_props.update({}, {}, STEP)
		await physics_frame
		watch.call()
	host.car.global_position = at + Vector3(0, 0, 40)
	return blocked

func run() -> void:
	for stage_index in [1, 6]:
		var host = load("res://main.tscn").instantiate()
		root.add_child(host)
		await process_frame
		host.set_process(false)
		host.room.set_process(false)
		host.select_stage(stage_index, true)
		await host.start_game()
		host.in_car = false
		var stage = host.stage
		var name = stage.biome.get_script().resource_path.get_file()
		check(stage.has_snow, "%s is a snowy stage" % name)
		var origin: Vector3 = Vector3.INF
		for offset in [Vector3(3, 0, 3), Vector3(-4, 0, 3), Vector3(10, 0, 3), Vector3(3, 0, -5)]:
			if await camp(host, stage.clearings[0] + offset):
				origin = stage.clearings[0] + offset
				break
		check(origin != Vector3.INF, "%s: a campfire and cauldron are set up in dug snow" % name)
		if origin == Vector3.INF:
			host.queue_free()
			continue
		var pot: Node3D = host.camp_cooking.pot
		var r: Dictionary = host.movable_props.records[str(pot.get_meta("prop_key"))]
		check(r.mass >= 100.0, "%s: the cauldron of plov is heavy (%.0f kg)" % [name, r.mass])
		# A car creeping or nudging at town speed stops against it.
		var home: Vector3 = pot.global_position
		var lowest = [INF]
		var watch = func(): lowest[0] = minf(lowest[0], clearance(host, pot))
		var blocked = await ram(host, pot, 6.0, 150, watch)
		check(blocked, "%s: a car at 22 km/h stops against the cauldron" % name)
		check(pot.global_position.distance_to(home) < 0.1 and pot.global_basis.y.dot(Vector3.UP) > 0.97, "%s: a slow car leaves the cauldron upright on its fire (moved %.2f m)" % [name, pot.global_position.distance_to(home)])
		# Pressed into the snow (the bug: a car ran it 0.5 m under the surface
		# and it stayed buried), it is put back on top at once.
		r.body.wake()
		r.body.global_position.y -= clearance(host, pot) + 0.5
		check(clearance(host, pot) < -0.4, "%s: test buries the cauldron's centre under the snow" % name)
		await step(host, 3)
		check(clearance(host, pot) > 0.0, "%s: a cauldron pushed under the snow comes back on top of it (%.2f m)" % [name, clearance(host, pot)])
		await step(host, 240)
		# A crash still knocks it off, but it lands on the snow, not in it or the sky.
		var highest = [-INF]
		lowest[0] = INF
		watch = func():
			var c = clearance(host, pot)
			lowest[0] = minf(lowest[0], c)
			highest[0] = maxf(highest[0], c)
		home = pot.global_position
		await ram(host, pot, 36.0, 360, watch)
		check(pot.global_position.distance_to(home) > 0.3 or pot.global_basis.y.dot(Vector3.UP) < 0.97 or r.body.home != null, "%s: a 130 km/h crash knocks the cauldron" % name)
		check(highest[0] < 8.0, "%s: a crash does not throw the cauldron sky-high (%.1f m)" % [name, highest[0]])
		check(clearance(host, pot) > 0.0, "%s: after a crash the cauldron rests on the snow, not in it (%.2f m)" % [name, clearance(host, pot)])
		check(lowest[0] > -0.5, "%s: a crash never buries the cauldron (%.2f m)" % [name, lowest[0]])
		host.queue_free()
		await process_frame
	finish()
