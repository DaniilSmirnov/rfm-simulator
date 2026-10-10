extends RefCounted
# Rally crews on the stage: the convoy and competitors driving, leaving the road,
# rejoining, being towed back; gravel thrown by their tyres. The host (or a
# solo player) simulates them; guests see them through the room snapshot.
# State lives on game (racers, stones, tow) where the room and HUD read it.
const Motion = preload("res://scripts/vehicle_motion.gd")
const Props = preload("res://scripts/props.gd")
const RallyHandling = preload("res://scripts/rally_handling.gd")
const RallyRejoin = preload("res://scripts/rally_rejoin.gd")
const RallyTracks = preload("res://scripts/rally_tracks.gd")
const Recovery = preload("res://scripts/recovery.gd")
const Stage = preload("res://scripts/stage.gd")
const Traffic = preload("res://scripts/rally_traffic.gd")

var game

func spawn_course_car(role: String, id: int, zero_index: int = 0) -> void:
	if game.dead or game.finished or (game.room.is_guest()):
		return
	var node = Props.course_car(role, zero_index)
	var racer = add_course_vehicle(node, id, "pass", 0, role, zero_index)
	racer.pace = 1.0 if role == "zero" else 0.72
	racer.drive_speed = Traffic.speed_limit(game, racer, 0.0)
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
	game.add_child(node)
	var s = 0.0
	node.position = race_at(s)
	var direction = race_direction(s)
	node.rotation.y = atan2(-direction.x, -direction.z)
	node.set_meta("room_id", id)
	var driver = Traffic.profile(id)
	var racer = {"bias": driver.bias, "phase": driver.phase, "pace": driver.pace, "line": 0.0, "drive_speed": race_speed(s) * driver.pace, "avoiding": false, "avoid_line": 0.0, "role": role, "zero_index": zero_index, "id": id, "node": node, "s": s, "focus": focus, "kind": kind, "state": "racing", "offset": 0.0, "age": 0.0, "counted": false, "start": Vector3.ZERO, "target": Vector3.ZERO, "variant": variant, "motion": Motion.new(), "previous": node.position, "slide": 0.0, "slide_speed": 0.0}
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
	var variant = [5, 0, 1, 2, 3, 4][game.rally_spawn_count % Props.RALLY_MODELS.size()]
	game.rally_spawn_count += 1
	var node = Props.car(Color.WHITE, true, variant)
	var racer = add_course_vehicle(node, game.rally_spawn_count + (game.course.pass_index - 1) * 200, kind, variant)
	racer.drive_speed = Traffic.speed_limit(game, racer, 0.0)
	game.toast("Приближается %s, номер %d!" % [node.get_meta("model"), node.get_meta("number")])

func update_racers(delta: float) -> void:
	var remaining = maxf(delta, 0)
	while remaining > 0.000001:
		var step = minf(remaining, 1.0 / 60.0)
		update_racers_step(step)
		remaining -= step

func update_racers_step(delta: float) -> void:
	var to_remove: Array[Dictionary] = []
	var nearest: Node3D = null
	var nearest_d = 9999.0
	for racer in game.racers:
		var node: Node3D = racer.node
		racer.previous = node.position
		var was_racing = racer.state == "racing"
		racer.age += delta
		var service = racer.get("role", "racer") != "racer"
		if service:
			Props.update_course_lights(node, game.elapsed)
		if racer.state == "racing":
			var traffic = Traffic.plan(game, racer)
			racer.avoiding = traffic.avoiding
			racer.avoid_line = traffic.line
			var actual_speed = move_toward(float(racer.get("drive_speed", race_speed(racer.s))), float(traffic.speed), delta * (Traffic.BRAKE if traffic.speed < racer.get("drive_speed", 0) else 8.0))
			actual_speed = minf(actual_speed, float(traffic.get("advance", INF)) / maxf(delta, 0.001))
			racer.drive_speed = actual_speed
			var race_speed = maxf(actual_speed, 0.1)
			var advance = RallyHandling.advance(game.stage, racer.s, delta * actual_speed, game.course.pass_index == 2, racer.line + racer.slide)
			racer.s += minf(advance, float(traffic.get("advance", INF)))
			# A crew braking just short of lateral clearance must finish its slow
			# manoeuvre; tying all steering motion to zero forward speed deadlocks it.
			var lateral_rate = minf(2.8, actual_speed * 0.14)
			if traffic.get("can_pass", false):
				lateral_rate = maxf(lateral_rate, 0.6)
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
			if game.stage.water != null:
				var spray_depth = game.stage.water.depth(node.position)
				if spray_depth > 0.0:
					game.stage.water.wake(node.get_instance_id(), node.position, movement / maxf(delta, 0.001), spray_depth, delta, 1.3)
			if racer.get("role", "racer") in ["racer", "zero"] and ((s >= racer.focus and racer.kind != "pass") or absf(racer.slide) > 3.4 or absf(racer.line + racer.slide) > Traffic.line_limit(game, s) + 0.8):
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
			if s >= Stage.LENGTH - 1:
				to_remove.append(racer)
		elif racer.state in ["offroad", "rock_bounce"]:
			var steps = maxi(1, int(ceil(delta / RallyHandling.STEP)))
			var dt = delta / steps
			for step in range(steps):
				var previous: Vector3 = node.position
				var driving = racer.get("self_rejoin", false) and racer.age > 0.6 and RallyRejoin.step(game, racer, dt)
				if not driving:
					RallyHandling.free_step(racer, game.stage, dt)
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
		elif racer.state in ["stopped", "stranded"]:
			racer.motion.suspension(node, game.stage, delta, node.rotation.y)
			if racer.state == "stopped" and not service and racer.age > 18 and racer.node != game.tow_target and float(racer.get("recovery_progress", 0)) <= 0 and int(racer.get("recovery_helpers", 0)) == 0:
				to_remove.append(racer)
		if was_racing:
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
		if was_racing:
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
			if tree_hit >= 0:
				if not game.stage.fallen.has(tree_hit):
					game.knock_tree(tree_hit, node.position - racer.previous)
				else:
					racer.state = "stranded" if racer.kind in ["stuck", "crash"] else "stopped"
					racer.age = 0
			if Motion.swept_hit(racer.previous + Vector3(0, 0.7, 0), node.position + Vector3(0, 0.7, 0), game.player_position() + Vector3(0, 0.7, 0), 2.6 if game.in_car else 1.65):
				game.die("Раллийная машина попала в тебя.\nНа этом выезд закончился.")
				return
		if racer.state in ["racing", "offroad", "rock_bounce"]:
			var blockers = [game.car.position]
			for peer in game.room.peers.values():
				if peer.state != null:
					blockers.append(game.room.v(peer.state.car))
			for other in game.racers:
				if other.id < racer.id or other.state in ["stopped", "stranded"]:
					blockers.append(other.node.position)
			for blocker in blockers:
				if Motion.swept_hit(racer.previous + Vector3(0, 0.65, 0), node.position + Vector3(0, 0.65, 0), blocker + Vector3(0, 0.65, 0), 2.5):
					node.position = racer.previous
					racer.state = "stranded" if racer.kind in ["stuck", "crash"] else "stopped"
					racer.age = 0
					game.toast("Столкновение машин! Экипаж остановился.")
					break
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
	if nearest != null:
		game.rally_audio.position = nearest.position
		game.rally_audio.pitch_scale = 1.8
		if not game.rally_audio.playing:
			game._play_audio(game.rally_audio)
	else:
		game.rally_audio.stop()

func stone_impact(id: String) -> void:
	game.impact_serials[id] = int(game.impact_serials.get(id, 0)) + 1
	if game.room.is_host and game.room.host_drives.has(id) and game.room.peers.has(id) and game.room.peers[id].state.in_car:
		game.room.host_drives[id].condition = maxf(0, game.room.host_drives[id].condition - 0.8)
	if id == game.room.player_id or id == "local":
		game.impact_shake = 0.8
		if game.in_car:
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
	var floor_height = game.stage.ground(next) + 0.05
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

func nearby_tow_racer() -> bool:
	for racer in game.racers:
		if not game.in_car and can_tow_racer(racer) and game.walker.distance_to(racer.node.position) < 6:
			return true
	return false

func recover_racer(racer: Dictionary) -> void:
	racer.erase("rejoin_residual")
	# Restart ahead of the impact, with no old slide/impulse or swept crash path.
	racer.s = clampf(race_station(racer.node.position) + 12.0, 0, Stage.LENGTH - 2)
	racer.node.position = race_at(racer.s)
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
	racer.line = 0.0
	racer.avoiding = false
	racer.avoid_line = 0.0
	racer.drive_speed = Traffic.speed_limit(game, racer, racer.s)
	racer.state = "racing"
	racer.kind = "pass"
	count_racer(racer)
	racer.age = 0.0
	for key in ["recovery_start", "recovery_goal", "recovery_progress", "recovery_helpers"]:
		racer.erase(key)
	game.helped += 1

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
		for racer in game.racers:
			if racer.id != int(link.racer):
				continue
			var origin = game.room.v(link.pos)
			if link.player == game.room.player_id or (not game.room.connected and link.player == "local"):
				origin = game.walker
			elif game.room.peers.has(link.player) and game.room.peers[link.player].has("avatar"):
				origin = game.room.peers[link.player].avatar.position
			var rope = Props.rope(game, origin + Vector3(0, 1, 0), racer.node.position + Vector3(0, 0.5, 0))
			game.recovery_ropes.append(rope)
			if game.rope_mesh == null:
				game.rope_mesh = rope

func cancel_tow() -> void:
	game.tow_target = null
	game.tow_progress = 0
	game.recovery_links.clear()
	game.recovery_helpers = 0
	clear_recovery_ropes()
