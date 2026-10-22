extends RefCounted
# Rally crews on the stage: the convoy and competitors driving, leaving the road,
# rejoining, being towed back; gravel thrown by their tyres. The host (or a
# solo player) simulates them; guests see them through the room snapshot.
# State lives on game (racers, stones, tow) where the room and HUD read it.
const CarRegistry = preload("res://scripts/cars/car_registry.gd")
const Hitbox = preload("res://scripts/cars/car_hitbox.gd")
const PropContact = preload("res://scripts/cars/prop_contact.gd")
const Motion = preload("res://scripts/cars/vehicle_motion.gd")
const Props = preload("res://scripts/core/props.gd")
const RallyHandling = preload("res://scripts/traffic/rally_handling.gd")
const RallyRejoin = preload("res://scripts/traffic/rally_rejoin.gd")
const RallyTracks = preload("res://scripts/traffic/rally_tracks.gd")
const Recovery = preload("res://scripts/cars/recovery.gd")
const Stage = preload("res://scripts/stages/stage.gd")
const ServiceTraffic = preload("res://scripts/traffic/service_traffic.gd")
const Traffic = preload("res://scripts/traffic/rally_traffic.gd")
const RallyDriver = preload("res://scripts/traffic/rally_driver.gd")
const Loc = preload("res://scripts/ui/loc.gd")

var game
# Somebody is towing the local player's own car (set by recovery.gd).
var car_towed = false
# A stone reuses its last floor sample within this sideways distance (m) while
# it is at least this high (m) above it.
const FLOOR_REUSE_DISTANCE = 0.4
const FLOOR_REUSE_HEIGHT = 0.8
# Condition (%) a crew knocks off the local player's car when it rams it.
const CAR_RAM_MIN_SPEED = 3.0
const CAR_RAM_FULL_SPEED = 20.0
const CAR_RAM_MAX_DAMAGE = 30.0
# A police car that gains less than POLICE_STALL_DISTANCE (m) of road in
# POLICE_STALL_SECONDS waits behind something: everybody is asked to clear it.
const POLICE_STALL_DISTANCE = 1.5
const POLICE_STALL_SECONDS = 2.0
# A crew or zero car standing this long (s) behind something it cannot pass,
# such as a car left across a narrow road, retires: the stage goes on.
const CREW_PATIENCE = 30.0
# Seconds after a tow until a crew drives at its full launch again, and the
# share of that launch it starts with.
const RECOVERY_RAMP = 6.0
const RECOVERY_PULL = 0.2
# Driving smoothness. The pedal (m/s²) aims at SPEED_RESPONSE times the speed
# gap (BRAKE_RESPONSE when slowing, at least MIN_BRAKE so a stop ends) and
# moves by at most PEDAL_JERK m/s³, faster behind a blocker.
const SPEED_RESPONSE = 1.2
const BRAKE_RESPONSE = 4.0
const MIN_BRAKE = 3.0
const PEDAL_JERK = 40.0
const PEDAL_JERK_BLOCKED = 160.0
# Sideways (m/s per m of gap, m/s²) and heading (rad/s per rad, rad/s, rad/s²).
const LINE_RESPONSE = 3.0
const LINE_ACCEL = 6.0
const YAW_RESPONSE = 5.0
const MAX_TURN = 2.5
const YAW_ACCEL = 12.0

func car_ram_damage(impact_speed: float) -> float:
	return CAR_RAM_MAX_DAMAGE * clampf((impact_speed - CAR_RAM_MIN_SPEED) / (CAR_RAM_FULL_SPEED - CAR_RAM_MIN_SPEED), 0.0, 1.0)

func spawn_course_car(role: String, id: int, zero_index: int = 0) -> void:
	if game.dead or game.finished or (game.room.is_guest()):
		return
	# The car waiting at the start line, when the service park sent one.
	var waiting = game.park_traffic.take(game.park_traffic.key_of({"role": role, "zero_index": zero_index, "id": id}))
	var node = waiting if waiting != null else Props.course_car(role, zero_index)
	var racer = add_course_vehicle(node, id, "pass", 0, role, zero_index)
	racer.pace = 1.0 if role == "zero" else 0.72
	racer.drive_speed = 0.0 if waiting != null else Traffic.speed_limit(game, racer, 0.0)
	racer.bias = 0.0
	racer.phase = 0.0
	game.toast(game.course.caption())

func race_station(point: Vector3) -> float:
	var station = game.stage.road_s(point)
	return game.stage.length - station if game.course.pass_index == 2 else station

func race_at(progress: float) -> Vector3:
	var station = clampf(progress, 0, game.stage.length)
	return RallyHandling.path(game.stage, game.stage.length - station if game.course.pass_index == 2 else station)

func race_direction(progress: float) -> Vector3:
	return RallyHandling.direction(game.stage, game.stage.length - progress if game.course.pass_index == 2 else progress, game.course.pass_index == 2)

func race_side(progress: float) -> Vector3:
	return race_direction(progress).cross(Vector3.UP).normalized()

func race_speed(progress: float) -> float:
	return game.stage.rally_speed(game.stage.length - progress if game.course.pass_index == 2 else progress)

func add_course_vehicle(node: Node3D, id: int, kind: String, variant: int, role: String = "racer", zero_index: int = 0) -> Dictionary:
	var focus = clampf(race_station(game.player_position()), 45, game.stage.length - 80)
	if node.get_parent() == null:
		game.add_child(node)
	var s = 0.0
	node.position = race_at(s)
	var direction = race_direction(s)
	node.rotation.y = atan2(-direction.x, -direction.z)
	node.set_meta("room_id", id)
	var driver = Traffic.profile(id)
	var racer = {"bias": driver.bias, "phase": driver.phase, "pace": driver.pace, "line": 0.0, "drive_speed": race_speed(s) * driver.pace, "avoiding": false, "avoid_line": 0.0, "role": role, "zero_index": zero_index, "id": id, "node": node, "s": s, "focus": focus, "kind": kind, "state": "racing", "offset": 0.0, "age": 0.0, "counted": false, "start": Vector3.ZERO, "target": Vector3.ZERO, "variant": variant, "launch": CarRegistry.launch(float(node.get_meta("zero_to_100", 2.0))), "motion": Motion.new(), "previous": node.position, "slide": 0.0, "slide_speed": 0.0, "line_speed": 0.0, "heading_rate": 0.0, "pedal": 0.0}
	racer.track_parts = RallyTracks.choose(game.stage, game.rng, role)
	if role == "racer":
		racer.nerve = Traffic.nerve(id)
	if RallyDriver.applies(racer):
		RallyDriver.Mistakes.apply(racer)
	game.racers.append(racer)
	return racer

func spawn_racer(forced: String = "") -> void:
	if game.course.phase != "racing" or game.rally_spawn_count >= game.RALLY_CREW_LIMIT or game.dead or game.finished or (game.room.is_guest()):
		return
	game.racing = true
	var kind = forced
	if kind == "":
		var roll = game.rng.randf()
		kind = "crash" if roll < 0.25 else ("stuck" if roll < 0.45 else "pass")
	# Keep at most one stranded car, so the stage cannot clog permanently.
	for existing in game.racers:
		if existing.state == "stranded" and kind in ["stuck", "crash"]:
			kind = "pass"
	var variant = Props.RallyCarModel.spawn_variant(game.rally_spawn_count)
	var waiting = game.park_traffic.take("crew%d" % game.rally_spawn_count)
	game.rally_spawn_count += 1
	var node = waiting if waiting != null else Props.rally_car(variant)
	var racer = add_course_vehicle(node, game.rally_spawn_count + (game.course.pass_index - 1) * 200, kind, variant)
	# A standing start from the line; a car placed straight on the road flies.
	racer.drive_speed = 0.0 if waiting != null else Traffic.speed_limit(game, racer, 0.0)
	game.toast(Loc.t("Приближается %s, номер %d!") % [Loc.t(node.get_meta("model")), node.get_meta("number")])

func prop_collision(racer: Dictionary, start: Vector3, end: Vector3, delta: float) -> Dictionary:
	var result = PropContact.resolve(game.stage, racer.motion, start, end, delta, Hitbox.shape(Hitbox.bounds(racer.node), racer.node.rotation.y))
	for impact in result.hits:
		game.knock_solid(impact.hit, impact.velocity)
	if result.blocked:
		stop_at_obstacle(racer)
	return result

func stop_at_obstacle(racer: Dictionary) -> void:
	racer.motion.velocity = Vector3.ZERO
	racer.drive_speed = 0.0
	racer.self_rejoin = false
	racer.state = "stranded" if racer.kind in ["stuck", "crash"] else "stopped"
	racer.age = 0.0

# Every client rolls the wheels of the crews, course cars and park convoy it
# sees, whoever moves them: the host's simulation or a guest's snapshots.
func animate_wheels() -> void:
	for racer in game.racers:
		Props.animate_wheels(racer.node)
	for entry in game.park_traffic.movers:
		Props.animate_wheels(entry.node)

func update_racers(delta: float) -> void:
	var start = {}
	for racer in game.racers:
		start[racer.id] = racer.node.position
	var remaining = maxf(delta, 0)
	while remaining > 0.000001:
		var step = minf(remaining, 1.0 / 60.0)
		update_racers_step(step)
		remaining -= step
	# Guests run crews ahead of their last snapshot with this velocity; it is
	# taken over the whole frame, as a short last step would amplify noise.
	if delta > 0.001:
		for racer in game.racers:
			racer.velocity = (racer.node.position - start[racer.id]) / delta if start.has(racer.id) else Vector3.ZERO
	watch_police(delta)

# Flags the course while a police car stands still on the stage; a red flag
# stop is not a blockage. Guests read the flag from the course snapshot.
func watch_police(delta: float) -> void:
	var blocked = false
	for racer in game.racers:
		if not racer.get("role", "") in ["opening_police", "closing_police"] or racer.state != "racing":
			continue
		if game.course.red_flag or absf(racer.s - float(racer.get("stall_s", -100.0))) > POLICE_STALL_DISTANCE:
			racer.stall_s = racer.s
			racer.stall_time = 0.0
		else:
			racer.stall_time = float(racer.get("stall_time", 0.0)) + delta
		blocked = blocked or racer.stall_time >= POLICE_STALL_SECONDS
	game.course.police_blocked = blocked

func update_racers_step(delta: float) -> void:
	var to_remove: Array[Dictionary] = []
	var finished_course: Array[int] = []
	var parked: Array[Dictionary] = []
	for racer in game.racers:
		var node: Node3D = racer.node
		racer.previous = node.position
		var service_before = ServiceTraffic.save(racer)
		var was_racing = racer.state == "racing"
		racer.age += delta
		var service = racer.get("role", "racer") != "racer"
		var red_hold = game.course.red_flag and racer.get("role", "racer") != "ambulance"
		if service:
			Props.update_course_lights(node, game.elapsed)
		if racer.state == "racing":
			var traffic = Traffic.plan(game, racer)
			if ServiceTraffic.applies(racer):
				traffic = ServiceTraffic.pedestrian_plan(game, racer, traffic)
			if red_hold:
				traffic.speed = 0.0
				traffic.line = racer.line
				traffic.can_pass = false
			racer.avoiding = traffic.avoiding
			racer.avoid_line = traffic.line
			var physical = RallyDriver.applies(racer)
			var actual_speed: float
			if physical:
				# The driver's own pedals and the tyres shape the speed; the plan
				# only says what it should be. drive_speed is what the car does.
				RallyDriver.take_over(self, racer)
				actual_speed = minf(float(traffic.speed), float(traffic.get("advance", INF)) / maxf(delta, 0.001))
				racer.drive_speed = racer.motion.velocity.length()
			else:
				actual_speed = drive_pedals(racer, traffic, delta)
				racer.drive_speed = actual_speed
			if not ServiceTraffic.applies(racer) and not red_hold:
				racer.held = float(racer.get("held", 0.0)) + delta if racer.drive_speed < 0.3 else 0.0
				if racer.held >= CREW_PATIENCE:
					stop_at_obstacle(racer)
					racer.state = "stopped"
					racer.retired = true
					game.toast("Экипаж не может проехать и сошёл с дистанции.")
					continue
			# Keep the racing state: no towing/despawn or timetable transition while
			# waiting. Freeze lateral corrections too, so stopped cars cannot creep.
			if red_hold and actual_speed <= 0.0 and (not physical or racer.motion.velocity.length() < RallyDriver.HOLD_SPEED):
				racer.slide_speed = 0.0
				racer.line_speed = 0.0
				racer.heading_rate = 0.0
				racer.motion.velocity = Vector3.ZERO
				racer.motion.suspension(node, game.stage, delta, node.rotation.y)
				continue
			var race_speed = maxf(actual_speed, 0.1)
			if not physical:
				var advance = RallyHandling.advance(game.stage, racer.s, delta * actual_speed, game.course.pass_index == 2, racer.line + racer.slide)
				racer.s += minf(advance, float(traffic.get("advance", INF)))
			if red_hold:
				racer.s = minf(racer.s, game.stage.length - 1.0)
			# A crew braking just short of lateral clearance must finish its slow
			# manoeuvre; tying all steering motion to zero forward speed deadlocks it.
			var lateral_rate = minf(2.8, actual_speed * 0.14)
			if traffic.get("can_pass", false):
				lateral_rate = maxf(lateral_rate, float(traffic.get("lateral_rate", 0.6)))
			ease_line(racer, float(traffic.line), lateral_rate, delta)
			if physical:
				RallyDriver.follow(self, racer, actual_speed, float(traffic.get("advance", INF)), delta)

			var s: float = racer.s
			var road_yaw = atan2(-race_direction(s).x, -race_direction(s).z)
			var ahead = race_direction(s + 7)
			var bend = wrapf(atan2(-ahead.x, -ahead.z) - road_yaw, -PI, PI) / maxf(Vector2((race_at(s + 7) - race_at(s)).x, (race_at(s + 7) - race_at(s)).z).length(), 1.0)
			var lateral_accel = 0.0
			var reference = RallyTracks.sample(racer.get("track_parts", PackedInt32Array()), s, game.course.pass_index == 2, racer.get("role", "racer") == "zero")
			if physical:
				racer.motion.suspension(node, game.stage, delta, node.rotation.y, racer.motion.handling.lateral_accel)
			elif not service:
				# Free-road tyre slip is already recorded. Keep live correction while
				# avoiding blockers and preserve externally applied lateral momentum.
				lateral_accel = RallyHandling.slide(racer, bend if reference.is_empty() or traffic.avoiding else 0.0, race_speed, game.stage.grip(node.position), delta)
			if not physical:
				place_on_line(racer, s, road_yaw, bend, race_speed, actual_speed, reference, traffic.avoiding, lateral_accel, service, delta)
			var movement = node.position - racer.previous
			if ServiceTraffic.guard(game, racer, service_before):
				# A guarded stop can also be the prescribed medical parking
				# position; do not skip dispatch while the casualty is ahead.
				if racer.get("role", "") == "ambulance":
					game.injuries.ambulance_step(racer)
				continue
			if racer.get("role", "") == "ambulance":
				game.injuries.ambulance_step(racer)
			if game.stage.water != null:
				var spray_depth = game.stage.water.depth(node.position)
				if spray_depth > 0.0:
					game.stage.water.wake(node.get_instance_id(), node.position, movement / maxf(delta, 0.001), spray_depth, delta, 1.3)
			if racer.get("role", "racer") in ["racer", "zero"] and ((not red_hold and s >= racer.focus and racer.kind != "pass") or (absf(racer.slide) > 3.4 and not physical) or absf(racer.line + racer.slide) > Traffic.line_limit(game, s) + 0.8):
				racer.state = "offroad"
				racer.age = 0
				if racer.kind == "pass":
					racer.kind = "crash"
				racer.self_rejoin = RallyRejoin.eligible(racer)
				racer.rejoin_time = 0.0
				racer.rejoin_plan = 0.0
				RallyHandling.departure(racer, movement / maxf(delta, 0.001), race_side(s), bend)
				game.toast("ВЫЛЕТ! Отойди с траектории!")
			elif s > racer.focus + 45 and not racer.counted:
				count_racer(racer)
			if s >= game.stage.length - 1 and not red_hold:
				# On into the service park at the finish, or off the map.
				var finished_id: int = racer.id
				var course_car = racer.get("role", "racer") != "racer"
				if game.park_traffic.arrive(racer):
					if course_car:
						finished_course.append(finished_id)
					parked.append(racer)
					continue
				to_remove.append(racer)
		elif racer.state in ["offroad", "rock_bounce"]:
			var steps = maxi(1, int(ceil(delta / RallyHandling.STEP)))
			var dt = delta / steps
			for step in range(steps):
				var previous: Vector3 = node.position
				var driving = not red_hold and racer.get("self_rejoin", false) and racer.age > 0.6 and RallyRejoin.step(game, racer, dt)
				if not driving:
					RallyHandling.free_step(racer, game.stage, dt, red_hold)
				var contact = Hitbox.rocks(game.stage, previous, node.position, Hitbox.shape(Hitbox.bounds(node), node.rotation.y))
				var solid = prop_collision(racer, previous, contact.position if not contact.is_empty() else node.position, dt)
				node.position = solid.position
				if not solid.blocked and not contact.is_empty():
					var impact: float = racer.motion.rock_impulse(contact.normal, node.rotation.y)
					if float(contact.get("radius", 0)) >= 1.0: stop_at_obstacle(racer)
					if impact > 9.0: racer.self_rejoin = false
					if float(contact.get("radius", 0)) < 1.0: racer.state = "rock_bounce"
					count_racer(racer)
				if racer.state in ["racing", "stopped", "stranded"]:
					break
			if racer.state != "racing" and not racer.get("self_rejoin", false) and racer.motion.grounded and racer.motion.velocity.length() < 0.65:
				racer.motion.velocity = Vector3.ZERO
				racer.state = "stranded" if racer.kind in ["stuck", "crash"] else "stopped"
				racer.age = 0.0
				if racer.state == "stranded":
					game.toast("Экипаж застрял. Нужен трос — T рядом с машиной.")
		elif racer.state in ["stopped", "stranded", "parked"]:
			racer.motion.suspension(node, game.stage, delta, node.rotation.y)
			if racer.state == "stopped" and not red_hold and (not service or racer.get("retired", false)) and racer.age > 18 and racer.node != game.tow_target and not racer.get("towed", false) and int(racer.get("recovery_helpers", 0)) == 0:
				to_remove.append(racer)
		if was_racing and not ServiceTraffic.priority(racer):
			var contact = Hitbox.rocks(game.stage, racer.previous, node.position, Hitbox.shape(Hitbox.bounds(node), node.rotation.y))
			if not contact.is_empty():
				racer.motion.velocity = (node.position - racer.previous) / maxf(delta, 0.001)
				racer.motion.velocity.y = 0
				node.position = contact.position
				var impact: float = racer.motion.rock_impulse(contact.normal, node.rotation.y)
				racer.self_rejoin = RallyRejoin.eligible(racer) and impact <= 9.0
				racer.rejoin_time = 0.0
				racer.rejoin_plan = 0.0
				racer.state = "rock_bounce"
				if float(contact.get("radius", 0)) >= 1.0: stop_at_obstacle(racer)
				racer.age = 0.0
				count_racer(racer)
		if was_racing and racer.state in ["racing", "offroad"] and not ServiceTraffic.priority(racer):
			var velocity: Vector3 = (node.position - racer.previous) / maxf(delta, 0.001)
			velocity.y = 0
			# A crew on the tyre model already carries its own velocity; its
			# frame movement also holds the driver's low-speed shuffles.
			if not (racer.state == "racing" and RallyDriver.applies(racer)):
				racer.motion.velocity = velocity
			var solid = prop_collision(racer, racer.previous, node.position, delta)
			node.position = solid.position
			if not solid.blocked and velocity.length() > 0.001:
				racer.drive_speed *= racer.motion.velocity.length() / velocity.length()
		if racer.state in ["racing", "offroad", "rock_bounce"]:
			var tree_hit = Hitbox.tree(game.stage, racer.previous, node.position, Hitbox.shape(Hitbox.bounds(node), node.rotation.y))
			if tree_hit >= 0 and not ServiceTraffic.priority(racer):
				if not game.stage.fallen.has(tree_hit):
					game.knock_tree(tree_hit, node.position - racer.previous)
				node.position = racer.previous
				stop_at_obstacle(racer)

			# Competitors can hit people; police and ambulances yield and use the safety guard.
			if not ServiceTraffic.applies(racer):
				game.injuries.vehicle_sweep(racer.previous, node.position, (node.position - racer.previous) / maxf(delta, 0.001), game.injuries.CREW_SPEED, Hitbox.shape(Hitbox.bounds(node), node.rotation.y))
		if racer.state in ["racing", "offroad", "rock_bounce"] and not ServiceTraffic.applies(racer):
			car_contact(racer, delta)
		if racer.state in ["stranded", "stopped"]:
			count_racer(racer)
	for racer in to_remove:
		racer.node.queue_free()
		game.racers.erase(racer)
		if racer.get("role", "racer") != "racer":
			game.course.vehicle_finished(game, racer.id)
	for racer in parked:
		game.racers.erase(racer)
	for id in finished_course:
		game.course.vehicle_finished(game, id)

# A crew running into a car stops; the local player's car takes the damage.
func car_contact(racer: Dictionary, delta: float) -> void:
	var node: Node3D = racer.node
	var car_box: AABB = Hitbox.bounds(node)
	var car_shape = Hitbox.shape(car_box, node.rotation.y)
	var travel = node.position - racer.previous
	var midpoint = (node.position + racer.previous) * 0.5
	var travel_radius = Vector2(travel.x, travel.z).length() * 0.5
	var car_radius = Vector2(car_box.size.x, car_box.size.z).length() * 0.5
	var blockers = [Hitbox.contact(game.car)]
	for peer in game.room.peers.values():
		if peer.state != null:
			blockers.append({"position": game.room.v(peer.state.car), "yaw": peer.state.get("heading", 0), "box": Hitbox.bounds(peer.car)})
	for other in game.racers:
		if other.id < racer.id or other.state in ["stopped", "stranded", "parked"]:
			blockers.append(Hitbox.contact(other.node))
	for blocker in blockers:
		var blocker_box: AABB = blocker.get("box", Hitbox.player(0))
		var blocker_radius = Vector2(blocker_box.size.x, blocker_box.size.z).length() * 0.5
		var gap = Vector2(blocker.position.x - midpoint.x, blocker.position.z - midpoint.z).length()
		if gap > travel_radius + car_radius + blocker_radius:
			continue
		if Hitbox.blocked(racer.previous, node.position, car_shape, blocker):
			var collision_speed = racer.motion.velocity.length() if racer.state in ["offroad", "rock_bounce"] else racer.previous.distance_to(node.position) / maxf(delta, 0.001)
			node.position = racer.previous
			racer.state = "stranded" if racer.kind in ["stuck", "crash"] else "stopped"
			racer.age = 0
			game.toast("Столкновение машин! Экипаж остановился.")
			if blocker.position == game.car.position:
				var damage = car_ram_damage(collision_speed)
				if damage > 0.0:
					game.condition = maxf(0.0, game.condition - damage)
					game.impact_shake = clampf(damage / CAR_RAM_MAX_DAMAGE, 0.1, 1.0)
					game.toast("Раллийная машина врезалась в твою легковушку!")
			return

func stone_impact(id: String) -> void:
	game.impact_serials[id] = int(game.impact_serials.get(id, 0)) + 1
	if game.room.is_host and game.room.host_drives.has(id) and game.room.peers.has(id) and game.rides.driving(game.room.peers[id].state):
		game.room.host_drives[id].condition = maxf(0, game.room.host_drives[id].condition - 0.8)
	if id == game.room.player_id or id == "local":
		game.impact_shake = 0.8
		if game.in_car and not game.rides.riding():
			game.condition = maxf(0, game.condition - 0.8)
		game.toast("Гравий из-под колёс! Отойди дальше от края СУ.")

func acquire_gravel(size: float) -> MeshInstance3D:
	var node: MeshInstance3D
	while not game.gravel_pool.is_empty() and not is_instance_valid(game.gravel_pool.back()):
		game.gravel_pool.pop_back()
	if game.gravel_pool.is_empty():
		node = Props.box(game, Vector3.ZERO, Vector3.ONE, Color("9b9079"))
	else:
		node = game.gravel_pool.pop_back()
	node.rotation = Vector3.ZERO
	node.scale = Vector3.ONE * size
	node.show()
	return node

func release_gravel(node: MeshInstance3D) -> void:
	node.hide()
	if game.gravel_pool.size() < 48:
		game.gravel_pool.append(node)
	else:
		node.queue_free()

func update_stones(delta: float) -> void:
	game.stone_clock -= delta
	if game.stone_clock <= 0:
		game.stone_clock = 0.09
		for racer in game.racers:
			if racer.state != "racing" or racer.get("drive_speed", 27.0) < 4 or not racer.motion.grounded or game.stones.size() >= 48:
				continue
			if not game.stage.loose_surface(racer.node.position):
				continue # Clean asphalt and cobbles do not throw a constant stream of gravel.
			var s: float = racer.s
			var direction = race_direction(s)
			var side = race_side(s) * (-1.0 if game.rng.randf() < 0.5 else 1.0)
			var node = acquire_gravel(game.rng.randf_range(0.07, 0.14))
			node.position = racer.node.position - direction * 1.6 + side * 0.65 + Vector3(0, 0.25, 0)
			game.stone_serial += 1
			game.stones.append({"id": game.stone_serial, "node": node, "velocity": direction * game.rng.randf_range(-5, 3) + side * game.rng.randf_range(5, 12) + Vector3(0, game.rng.randf_range(3, 7), 0), "life": 2.0, "bounces": 0})
	for stone in game.stones.duplicate():
		var previous: Vector3 = stone.node.position
		var alive = advance_gravel(stone, delta)
		stone.life -= delta
		stone.node.rotation += Vector3(7, 4, 6) * delta
		var hit = Motion.swept_hit(previous, stone.node.position, game.player_position() + Vector3(0, 1.0, 0), 1.2 if game.in_car else 0.55)
		if hit:
			stone_impact(game.room.player_id if game.room.connected else "local")
		if game.room.connected:
			for peer in game.room.peers.values():
				if peer.state != null and Motion.swept_hit(previous, stone.node.position, game.room.v(peer.state.pos) + Vector3(0, 1.0, 0), 1.2 if peer.state.in_car else 0.55):
					stone_impact(peer.id)
					hit = true
		if hit or stone.life <= 0 or not alive:
			release_gravel(stone.node)
			game.stones.erase(stone)

# Also used by guests for prediction between authoritative room snapshots.
func advance_gravel(stone: Dictionary, delta: float) -> bool:
	var previous: Vector3 = stone.node.position
	var next: Vector3 = previous + stone.velocity * delta + Vector3(0, -4.9 * delta * delta, 0)
	stone.velocity.y -= 9.8 * delta
	var contact = game.stage.solids.hit(previous, next, 0.06, true, Vector3.ZERO)
	if contact.is_empty():
		contact = game.stage.rock_hit(previous, next, 0.06)
	if not contact.is_empty():
		next = contact.position
		var normal: Vector3 = contact.normal
		var closing = stone.velocity.dot(normal)
		if closing < 0:
			stone.velocity -= normal * closing * 1.4
			stone.velocity *= 0.7
			stone.bounces = int(stone.get("bounces", 0)) + 1
	if game.stage.water != null and game.stage.water.depth(next) > 0.0 and next.y < game.stage.water.level(next):
		game.stage.water.splash(Vector3(next.x, game.stage.water.level(next), next.z), 0.2)
		stone.node.position = next
		return false
	# Ground height is re-sampled once the stone drifts sideways or nears the
	# last sampled floor; most of a flight is spent well above it.
	var floor_height: float
	if stone.has("floor_y") and Vector2(next.x, next.z).distance_to(stone.floor_xz) < FLOOR_REUSE_DISTANCE and next.y > float(stone.floor_y) + FLOOR_REUSE_HEIGHT:
		floor_height = float(stone.floor_y)
	else:
		floor_height = game.stage.ground(next) + 0.05
		stone.floor_xz = Vector2(next.x, next.z)
		stone.floor_y = floor_height
	var alive = true
	if next.y <= floor_height:
		next.y = floor_height
		if stone.velocity.y < 0:
			stone.bounces = int(stone.get("bounces", 0)) + 1
			alive = stone.bounces <= 2 and absf(stone.velocity.y) > 1.0
			stone.velocity = Vector3(stone.velocity.x * 0.58, -stone.velocity.y * 0.4, stone.velocity.z * 0.58)
	stone.node.position = next
	return alive and int(stone.get("bounces", 0)) <= 2

func can_tow_racer(racer: Dictionary) -> bool:
	return racer.state in ["stranded", "stopped"] and is_instance_valid(racer.node)

# Something within rope range of the walking player: a stuck crew or a
# player's car, including their own.
func nearby_tow_target() -> bool:
	if game.in_car:
		return false
	for racer in game.racers:
		if can_tow_racer(racer) and game.walker.distance_to(racer.node.position) < Recovery.ROPE_RANGE:
			return true
	if game.walker.distance_to(game.car.position) < Recovery.ROPE_RANGE:
		return true
	for peer in game.room.peers.values():
		if peer.has("car") and is_instance_valid(peer.car) and game.walker.distance_to(peer.car.position) < Recovery.ROPE_RANGE:
			return true
	return false

func recover_racer(racer: Dictionary) -> void:
	racer.erase("rejoin_residual")
	# Restart where the car was brought onto the road, inside the carriageway,
	# with no old slide/impulse or swept crash path.
	racer.s = clampf(race_station(racer.node.position), 0, game.stage.length - 2)
	var side = race_side(racer.s)
	var half = maxf(0.0, game.stage.road_width(game.stage.road_s(racer.node.position)) * 0.5 - 0.6)
	var lateral = clampf((racer.node.position - race_at(racer.s)).dot(side), -half, half)
	racer.node.position = race_at(racer.s) + side * lateral
	racer.node.position.y = game.stage.ground(racer.node.position)
	var direction = race_direction(racer.s)
	racer.node.rotation = Vector3(0, atan2(-direction.x, -direction.z), 0)
	racer.previous = racer.node.position
	racer.start = racer.node.position
	racer.target = racer.node.position
	racer.motion = Motion.new()
	racer.slide = 0.0
	racer.slide_speed = 0.0
	racer.drift_yaw = 0.0
	racer.yaw_rate = 0.0
	racer.heading_rate = 0.0
	racer.line_speed = 0.0
	racer.pedal = 0.0
	racer.line = lateral
	racer.avoiding = false
	racer.avoid_line = 0.0
	# Pulled out by hand: the crew starts from a standstill and builds up
	# throttle gently (recovery_pull) instead of resuming at full pace.
	racer.drive_speed = 0.0
	racer.recovery_time = 0.0
	racer.state = "racing"
	racer.kind = "pass"
	count_racer(racer)
	racer.age = 0.0
	for key in ["towed", "recovery_helpers"]:
		racer.erase(key)
	game.helped += 1

# A kinematic course car (police, ambulance) sits on its line: position from
# the line and slide, heading from the road and the bend.
func place_on_line(racer: Dictionary, s: float, road_yaw: float, bend: float, race_speed: float, actual_speed: float, reference: Dictionary, avoiding: bool, lateral_accel: float, service: bool, delta: float) -> void:
	var node: Node3D = racer.node
	if not reference.is_empty() and not avoiding:
		lateral_accel = bend * race_speed * race_speed
	var height = node.position.y
	node.position = race_at(s) + race_side(s) * (racer.line + racer.slide)
	if racer.has("rejoin_residual"):
		racer.rejoin_residual = racer.rejoin_residual.move_toward(Vector3.ZERO, delta * maxf(actual_speed, 0.5) * 0.25)
		node.position += racer.rejoin_residual
	node.position.y = height
	var yaw = steer_heading(racer, road_yaw, bend, actual_speed, reference, service, delta)
	racer.motion.suspension(node, game.stage, delta, yaw, lateral_accel)

# Pedals: speed up along the car's launch curve (2 s to 100 km/h for crews)
# and brake up to BRAKE, easing in and out of either instead of switching
# between full throttle and full braking. Returns the speed for this step.
static func drive_pedals(racer: Dictionary, traffic: Dictionary, delta: float) -> float:
	var current_speed = float(racer.get("drive_speed", 0.0))
	var target = float(traffic.speed)
	var pull = CarRegistry.pull(float(racer.get("launch", CarRegistry.launch(2.0))), current_speed) * recovery_pull(racer, delta)
	var gap = target - current_speed
	var wanted = clampf(gap * SPEED_RESPONSE if gap > 0.0 else minf(gap * BRAKE_RESPONSE, -MIN_BRAKE), -Traffic.BRAKE, pull) if absf(gap) > 0.001 else 0.0
	racer.pedal = move_toward(float(racer.get("pedal", 0.0)), wanted, delta * (PEDAL_JERK_BLOCKED if traffic.avoiding else PEDAL_JERK))
	var speed = current_speed + racer.pedal * delta
	# Leftover pedal never carries the car past the speed it is after.
	if racer.pedal > 0.0:
		speed = minf(speed, maxf(current_speed, target))
	else:
		speed = maxf(speed, minf(current_speed, target))
	return maxf(0.0, minf(speed, float(traffic.get("advance", INF)) / maxf(delta, 0.001)))

# The line eases sideways like a steered car instead of sliding across at a
# fixed rate; the sideways speed still never exceeds `rate`.
static func ease_line(racer: Dictionary, target: float, rate: float, delta: float) -> void:
	var wanted = clampf((target - float(racer.get("line", 0.0))) * LINE_RESPONSE, -rate, rate)
	racer.line_speed = move_toward(float(racer.get("line_speed", 0.0)), wanted, delta * LINE_ACCEL)
	racer.line = float(racer.get("line", 0.0)) + racer.line_speed * delta

# Heading follows the road's tangent plus the sideways drift, not the frame's
# movement, which jumps at spline seams and line changes. The body turns with
# the bend (feed-forward) and settles onto the desired heading; the turn rate
# changes no faster than YAW_ACCEL. Returns the new yaw.
static func steer_heading(racer: Dictionary, road_yaw: float, bend: float, speed: float, reference: Dictionary, service: bool, delta: float) -> float:
	var sideways = float(racer.get("line_speed", 0.0)) + (float(racer.get("slide_speed", 0.0)) if not service else 0.0)
	var recorded_yaw = float(reference.get("yaw", 0.0)) * clampf(speed / maxf(float(reference.get("speed", 1.0)), 1.0), 0.0, 1.0)
	var desired_yaw = road_yaw - atan2(sideways, maxf(speed, 1.0)) + float(racer.get("drift_yaw", 0.0)) + recorded_yaw
	var yaw: float = racer.node.rotation.y
	var turn = clampf(bend * speed + wrapf(desired_yaw - yaw, -PI, PI) * YAW_RESPONSE, -MAX_TURN, MAX_TURN)
	racer.heading_rate = move_toward(float(racer.get("heading_rate", 0.0)), turn, delta * YAW_ACCEL)
	return yaw + racer.heading_rate * delta

# Share of the launch a just-recovered crew uses; it eases up to 1 over
# RECOVERY_RAMP seconds, then the mark is dropped.
static func recovery_pull(racer: Dictionary, delta: float) -> float:
	if not racer.has("recovery_time"):
		return 1.0
	var time = float(racer.recovery_time) + delta
	if time >= RECOVERY_RAMP:
		racer.erase("recovery_time")
		return 1.0
	racer.recovery_time = time
	return lerpf(RECOVERY_PULL, 1.0, smoothstep(0.0, RECOVERY_RAMP, time))

func count_racer(racer: Dictionary) -> void:
	if racer.get("role", "racer") != "racer" or racer.get("counted", false):
		return
	racer.counted = true
	game.passed = mini(game.RALLY_CREW_LIMIT, game.passed + 1)

func update_tow(delta: float) -> void:
	Recovery.update(game, {"local": game.room.local_state()}, delta)

func clear_recovery_ropes() -> void:
	for rope in game.recovery_ropes:
		if is_instance_valid(rope):
			rope.queue_free()
	game.recovery_ropes.clear()
	game.rope_mesh = null

func draw_recovery_ropes() -> void:
	clear_recovery_ropes()
	for link in game.recovery_links:
		var towed = Recovery.link_node(game, link)
		if towed == null:
			continue
		var origin = game.room.v(link.pos)
		var lead = Recovery.link_node(game, {"car": link.player}) if link.get("hitch", false) else null
		if lead != null:
			# A rope between two cars: from the tow car's rear to the towed car.
			origin = lead.position + lead.basis.z.normalized() * 2.0 - Vector3(0, 0.5, 0)
		elif link.player == game.room.player_id or (not game.room.connected and link.player == "local"):
			origin = game.walker
		elif game.room.peers.has(link.player) and game.room.peers[link.player].has("avatar"):
			origin = game.room.peers[link.player].avatar.position
		var rope = Props.rope(game, origin + Vector3(0, 1, 0), towed.position + Vector3(0, 0.5, 0))
		game.recovery_ropes.append(rope)
		if game.rope_mesh == null:
			game.rope_mesh = rope

func cancel_tow() -> void:
	game.tow_target = null
	game.tow_distance = -1.0
	car_towed = false
	game.recovery_links.clear()
	game.recovery_helpers = 0
	clear_recovery_ropes()
