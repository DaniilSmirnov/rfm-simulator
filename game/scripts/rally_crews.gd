extends RefCounted
# Rally crews on the stage: the convoy and competitors driving, leaving the road,
# rejoining, being towed back; gravel thrown by their tyres. The host (or a
# solo player) simulates them; guests see them through the room snapshot.
# State lives on game (racers, stones, tow) where the room and HUD read it.
const CarRegistry = preload("res://scripts/car_registry.gd")
const Motion = preload("res://scripts/vehicle_motion.gd")
const Props = preload("res://scripts/props.gd")
const RallyHandling = preload("res://scripts/rally_handling.gd")
const RallyRejoin = preload("res://scripts/rally_rejoin.gd")
const RallyTracks = preload("res://scripts/rally_tracks.gd")
const Recovery = preload("res://scripts/recovery.gd")
const Stage = preload("res://scripts/stage.gd")
const ServiceTraffic = preload("res://scripts/service_traffic.gd")
const Traffic = preload("res://scripts/rally_traffic.gd")

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
# Seconds after a tow until a crew drives at its full launch again, and the
# share of that launch it starts with.
const RECOVERY_RAMP = 6.0
const RECOVERY_PULL = 0.2

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
	return Stage.LENGTH - station if game.course.pass_index == 2 else station

func race_at(progress: float) -> Vector3:
	var station = clampf(progress, 0, Stage.LENGTH)
	return RallyHandling.path(game.stage, Stage.LENGTH - station if game.course.pass_index == 2 else station)

func race_direction(progress: float) -> Vector3:
	return RallyHandling.direction(game.stage, Stage.LENGTH - progress if game.course.pass_index == 2 else progress, game.course.pass_index == 2)

func race_side(progress: float) -> Vector3:
	return race_direction(progress).cross(Vector3.UP).normalized()

func race_speed(progress: float) -> float:
	return game.stage.rally_speed(Stage.LENGTH - progress if game.course.pass_index == 2 else progress)

func add_course_vehicle(node: Node3D, id: int, kind: String, variant: int, role: String = "racer", zero_index: int = 0) -> Dictionary:
	var focus = clampf(race_station(game.player_position()), 45, Stage.LENGTH - 80)
	if node.get_parent() == null:
		game.add_child(node)
	var s = 0.0
	node.position = race_at(s)
	var direction = race_direction(s)
	node.rotation.y = atan2(-direction.x, -direction.z)
	node.set_meta("room_id", id)
	var driver = Traffic.profile(id)
	var racer = {"bias": driver.bias, "phase": driver.phase, "pace": driver.pace, "line": 0.0, "drive_speed": race_speed(s) * driver.pace, "avoiding": false, "avoid_line": 0.0, "role": role, "zero_index": zero_index, "id": id, "node": node, "s": s, "focus": focus, "kind": kind, "state": "racing", "offset": 0.0, "age": 0.0, "counted": false, "start": Vector3.ZERO, "target": Vector3.ZERO, "variant": variant, "launch": CarRegistry.launch(float(node.get_meta("zero_to_100", 2.0))), "motion": Motion.new(), "previous": node.position, "slide": 0.0, "slide_speed": 0.0}
	racer.track_parts = RallyTracks.choose(game.stage, game.rng, role)
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
	game.toast("Приближается %s, номер %d!" % [node.get_meta("model"), node.get_meta("number")])

# Every client rolls the wheels of the crews, course cars and park convoy it
# sees, whoever moves them: the host's simulation or a guest's snapshots.
func animate_wheels() -> void:
	for racer in game.racers:
		Props.animate_wheels(racer.node)
	for entry in game.park_traffic.movers:
		Props.animate_wheels(entry.node)

func update_racers(delta: float) -> void:
	var remaining = maxf(delta, 0)
	while remaining > 0.000001:
		var step = minf(remaining, 1.0 / 60.0)
		update_racers_step(step)
		remaining -= step

func update_racers_step(delta: float) -> void:
	var to_remove: Array[Dictionary] = []
	var finished_course: Array[int] = []
	var parked: Array[Dictionary] = []
	var nearest: Node3D = null
	var nearest_d = 9999.0
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
			# Speed up along the car's launch curve (2 s to 100 km/h for crews).
			var current_speed = float(racer.get("drive_speed", race_speed(racer.s)))
			var throttle = recovery_pull(racer, delta)
			var gain = Traffic.BRAKE if traffic.speed < current_speed else CarRegistry.pull(float(racer.get("launch", CarRegistry.launch(2.0))), current_speed) * throttle
			var actual_speed = move_toward(current_speed, float(traffic.speed), delta * gain)
			actual_speed = minf(actual_speed, float(traffic.get("advance", INF)) / maxf(delta, 0.001))
			racer.drive_speed = actual_speed
			# Keep the racing state: no towing/despawn or timetable transition while
			# waiting. Freeze lateral corrections too, so stopped cars cannot creep.
			if red_hold and actual_speed <= 0.0:
				racer.slide_speed = 0.0
				racer.motion.suspension(node, game.stage, delta, node.rotation.y)
				continue
			var race_speed = maxf(actual_speed, 0.1)
			var advance = RallyHandling.advance(game.stage, racer.s, delta * actual_speed, game.course.pass_index == 2, racer.line + racer.slide)
			racer.s += minf(advance, float(traffic.get("advance", INF)))
			if red_hold:
				racer.s = minf(racer.s, Stage.LENGTH - 1.0)
			# A crew braking just short of lateral clearance must finish its slow
			# manoeuvre; tying all steering motion to zero forward speed deadlocks it.
			var lateral_rate = minf(2.8, actual_speed * 0.14)
			if traffic.get("can_pass", false):
				lateral_rate = maxf(lateral_rate, float(traffic.get("lateral_rate", 0.6)))
			racer.line = move_toward(float(racer.get("line", 0.0)), float(traffic.line), delta * lateral_rate)

			var s: float = racer.s
			var road_yaw = atan2(-race_direction(s).x, -race_direction(s).z)
			var ahead = race_direction(s + 7)
			var bend = wrapf(atan2(-ahead.x, -ahead.z) - road_yaw, -PI, PI) / maxf(Vector2((race_at(s + 7) - race_at(s)).x, (race_at(s + 7) - race_at(s)).z).length(), 1.0)
			var lateral_accel = 0.0
			var reference = RallyTracks.sample(racer.get("track_parts", PackedInt32Array()), s, game.course.pass_index == 2, racer.get("role", "racer") == "zero")
			if not service:
				# Free-road tyre slip is already recorded. Keep live correction while
				# avoiding blockers and preserve externally applied lateral momentum.
				lateral_accel = RallyHandling.slide(racer, bend if reference.is_empty() or traffic.avoiding else 0.0, race_speed, game.stage.grip(node.position), delta)
			if not reference.is_empty() and not traffic.avoiding:
				lateral_accel = bend * race_speed * race_speed
			var height = node.position.y
			node.position = race_at(s) + race_side(s) * (racer.line + racer.slide)
			if racer.has("rejoin_residual"):
				racer.rejoin_residual = racer.rejoin_residual.move_toward(Vector3.ZERO, delta * maxf(actual_speed, 0.5) * 0.25)
				node.position += racer.rejoin_residual
				node.position.y = height
			node.position.y = height
			var movement = node.position - racer.previous
			var path_yaw = atan2(-movement.x, -movement.z) if Vector2(movement.x, movement.z).length() > 0.02 else road_yaw
			var recorded_yaw = float(reference.get("yaw", 0.0)) * clampf(actual_speed / maxf(float(reference.get("speed", 1.0)), 1.0), 0.0, 1.0)
			var desired_yaw = path_yaw + float(racer.get("drift_yaw", 0.0)) + recorded_yaw
			var yaw = node.rotation.y + clampf(wrapf(desired_yaw - node.rotation.y, -PI, PI), -2.5 * delta, 2.5 * delta)
			racer.motion.suspension(node, game.stage, delta, yaw, lateral_accel)
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
			if racer.get("role", "racer") in ["racer", "zero"] and ((not red_hold and s >= racer.focus and racer.kind != "pass") or absf(racer.slide) > 3.4 or absf(racer.line + racer.slide) > Traffic.line_limit(game, s) + 0.8):
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
			if s >= Stage.LENGTH - 1 and not red_hold:
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
				var contact = game.stage.rock_hit(previous, node.position, 0.85)
				var city_contact = game.stage.solids.hit(previous, node.position, 0.85)
				if not city_contact.is_empty() and (contact.is_empty() or previous.distance_squared_to(city_contact.position) < previous.distance_squared_to(contact.position)):
					contact = city_contact
				if not contact.is_empty():
					if contact.has("kind"):
						game.knock_solid(contact, racer.motion.velocity)
					node.position = contact.position
					var impact: float = racer.motion.rock_impulse(contact.normal, node.rotation.y)
					if impact > 9.0: racer.self_rejoin = false
					racer.state = "rock_bounce"
					count_racer(racer)
				if racer.state == "racing":
					break
			if racer.state != "racing" and not racer.get("self_rejoin", false) and racer.motion.grounded and racer.motion.velocity.length() < 0.65:
				racer.motion.velocity = Vector3.ZERO
				racer.state = "stranded" if racer.kind in ["stuck", "crash"] else "stopped"
				racer.age = 0.0
				if racer.state == "stranded":
					game.toast("Экипаж застрял. Нужен трос — T рядом с машиной.")
		elif racer.state in ["stopped", "stranded", "parked"]:
			racer.motion.suspension(node, game.stage, delta, node.rotation.y)
			if racer.state == "stopped" and not red_hold and not service and racer.age > 18 and racer.node != game.tow_target and not racer.get("towed", false) and int(racer.get("recovery_helpers", 0)) == 0:
				to_remove.append(racer)
		if was_racing and not ServiceTraffic.priority(racer):
			var contact = game.stage.rock_hit(racer.previous, node.position, 0.85)
			if not contact.is_empty():
				racer.motion.velocity = (node.position - racer.previous) / maxf(delta, 0.001)
				racer.motion.velocity.y = 0
				node.position = contact.position
				var impact: float = racer.motion.rock_impulse(contact.normal, node.rotation.y)
				racer.self_rejoin = RallyRejoin.eligible(racer) and impact <= 9.0
				racer.rejoin_time = 0.0
				racer.rejoin_plan = 0.0
				racer.state = "rock_bounce"
				racer.age = 0.0
				count_racer(racer)
		if was_racing and not ServiceTraffic.priority(racer):
			var city_hit = game.stage.solids.hit(racer.previous, node.position, 0.85)
			if not city_hit.is_empty():
				var velocity: Vector3 = (node.position - racer.previous) / maxf(delta, 0.001)
				game.knock_solid(city_hit, velocity)
				node.position = city_hit.position
				racer.motion.velocity = velocity
				racer.motion.velocity.y = 0
				var impact: float = racer.motion.rock_impulse(city_hit.normal, node.rotation.y)
				racer.self_rejoin = RallyRejoin.eligible(racer) and impact <= 9.0
				racer.rejoin_time = 0.0
				racer.rejoin_plan = 0.0
				racer.state = "rock_bounce"
				racer.age = 0.0
				count_racer(racer)
		if racer.state in ["racing", "offroad", "rock_bounce"]:
			var tree_hit = game.stage.obstacle_hit(racer.previous, node.position, 0.95)
			if tree_hit >= 0 and not ServiceTraffic.priority(racer):
				if not game.stage.fallen.has(tree_hit):
					game.knock_tree(tree_hit, node.position - racer.previous)
				else:
					racer.state = "stranded" if racer.kind in ["stuck", "crash"] else "stopped"
					racer.age = 0
			# Competitors can hit people; police and ambulances yield and use the safety guard.
			if not ServiceTraffic.applies(racer):
				game.injuries.vehicle_sweep(racer.previous, node.position, (node.position - racer.previous) / maxf(delta, 0.001), game.injuries.CREW_SPEED)
		if racer.state in ["racing", "offroad", "rock_bounce"] and not ServiceTraffic.applies(racer):
			car_contact(racer, delta)
		if racer.state in ["stranded", "stopped"]:
			count_racer(racer)
		var d = node.position.distance_to(game.player_position())
		if d < nearest_d and racer.state in ["racing", "offroad"]:
			nearest = node
			nearest_d = d
	for racer in to_remove:
		racer.node.queue_free()
		game.racers.erase(racer)
		if racer.get("role", "racer") != "racer":
			game.course.vehicle_finished(game, racer.id)
	for racer in parked:
		game.racers.erase(racer)
	for id in finished_course:
		game.course.vehicle_finished(game, id)
	if nearest != null:
		game.rally_audio.position = nearest.position
		game.rally_audio.pitch_scale = 1.8
		if not game.rally_audio.playing:
			game._play_audio(game.rally_audio)
	else:
		game.rally_audio.stop()

# A crew running into a car stops; the local player's car takes the damage.
func car_contact(racer: Dictionary, delta: float) -> void:
	var node: Node3D = racer.node
	var blockers = [game.car.position]
	for peer in game.room.peers.values():
		if peer.state != null:
			blockers.append(game.room.v(peer.state.car))
	for other in game.racers:
		if other.id < racer.id or other.state in ["stopped", "stranded", "parked"]:
			blockers.append(other.node.position)
	for blocker in blockers:
		if Motion.swept_hit(racer.previous + Vector3(0, 0.65, 0), node.position + Vector3(0, 0.65, 0), blocker + Vector3(0, 0.65, 0), 2.5):
			var collision_speed = racer.motion.velocity.length() if racer.state in ["offroad", "rock_bounce"] else racer.previous.distance_to(node.position) / maxf(delta, 0.001)
			node.position = racer.previous
			racer.state = "stranded" if racer.kind in ["stuck", "crash"] else "stopped"
			racer.age = 0
			game.toast("Столкновение машин! Экипаж остановился.")
			if blocker == game.car.position:
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
	racer.s = clampf(race_station(racer.node.position), 0, Stage.LENGTH - 2)
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
