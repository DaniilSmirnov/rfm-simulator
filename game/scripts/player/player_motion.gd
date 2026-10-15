extends RefCounted
# The local player: driving the car, walking, jumping and wading, sitting,
# getting in and out, the camera, and how beer wears off.
# State lives on game (walker, car, heading, speed, ...) where the room,
# subsystems and tests read it.
const DeepSnowRules = preload("res://scripts/stages/winter/deep_snow.gd")
const PropContact = preload("res://scripts/cars/prop_contact.gd")
const Motion = preload("res://scripts/cars/vehicle_motion.gd")
const CarRegistry = preload("res://scripts/cars/car_registry.gd")
const Stage = preload("res://scripts/stages/stage.gd")

var game:
	set(value):
		game = value
		relief.game = value
		perches.game = value
var relief = preload("res://scripts/player/tree_relief.gd").new()
var perches = preload("res://scripts/player/perches.gd").new()

func drive(delta: float) -> void:
	game.rides.update()
	if game.rides.riding():
		game.rides.follow()
		return
	if game.room.connected and game.room.predict_drive(delta):
		return
	# Carry fractional ticks across render frames; cap long stalls at one second.
	game.vehicle_motion.drive_clock += clampf(delta, 0, 1.0)
	var dt: float = game.vehicle_motion.handling.STEP
	var steps = int(floor((game.vehicle_motion.drive_clock + 0.000001) / dt))
	game.vehicle_motion.drive_clock = maxf(0, game.vehicle_motion.drive_clock - steps * dt)
	var initial_forward = Vector3(-sin(game.heading), 0, -cos(game.heading))
	var initial_speed: float = game.vehicle_motion.velocity.dot(initial_forward)
	# Support explicit resets/recovery without discarding tangential momentum.
	if absf(game.speed - initial_speed) > 3:
		game.vehicle_motion.velocity += initial_forward * (game.speed - initial_speed)
	# A broken car no longer drives: it only rolls to a stop or follows a tow rope.
	var wrecked = game.condition <= 0
	for step in range(steps):
		var throttle = 0.0 if wrecked else Input.get_axis("back", "forward")
		var steer = 0.0 if wrecked else Input.get_axis("left", "right")
		var offroad = game.stage.road_distance(game.car.position) > 4.1
		var max_speed = CarRegistry.OFFROAD_SPEED if offroad else CarRegistry.TOP_SPEED
		var braking = wrecked or Input.is_action_pressed("brake")
		var previous_heading = game.heading
		game.heading = game.vehicle_motion.handling.advance(game.vehicle_motion, game.heading, throttle, steer, braking, game.stage.grip(game.car.position), max_speed, game.selected_car, dt)
		var forward = Vector3(-sin(game.heading), 0, -cos(game.heading))
		game.speed = game.vehicle_motion.velocity.dot(forward)
		game.rock_impact_timer = maxf(0.0, game.rock_impact_timer - dt)
		var previous = game.car.position
		var next = previous + game.vehicle_motion.velocity * dt
		next.x = clampf(next.x, -185, 185)
		next.z = clampf(next.z, game.stage.parks.z_limits.x, game.stage.parks.z_limits.y)
		# Fast enough, the car throws people in its way instead of stopping.
		game.injuries.vehicle_sweep(previous, next, game.vehicle_motion.velocity, game.injuries.PLAYER_CAR_SPEED)
		var rock_hit = game.stage.rock_hit(previous, next, 0.85)
		if not rock_hit.is_empty():
			next = rock_hit.position
			var closing = game.vehicle_motion.rock_impulse(rock_hit.normal, game.heading)
			if float(rock_hit.get("radius", 0)) >= 1.0: game.vehicle_motion.velocity = Vector3.ZERO
			game.speed = game.vehicle_motion.velocity.dot(forward)
			if closing > 1.0 and game.rock_impact_timer <= 0:
				game.condition = maxf(0, game.condition - minf(14.0, closing * 0.65))
				game.impact_shake = minf(0.8, closing * 0.055)
				game.rock_impact_timer = 0.4
				game.toast("Удар о камень! Можно отъехать назад.")
		var solid = PropContact.resolve(game.stage, game.vehicle_motion, previous, next, dt)
		next = solid.position
		for impact in solid.hits:
			game.knock_solid(impact.hit, impact.velocity)
		game.speed = game.vehicle_motion.velocity.dot(forward)
		if solid.closing > 1 and game.rock_impact_timer <= 0:
			game.condition = maxf(0, game.condition - minf(20.0, solid.closing * 0.85))
			game.impact_shake = minf(0.8, solid.closing * 0.055)
			game.rock_impact_timer = 0.4
			game.toast("Столкновение с препятствием!")
		var tree_index = game.stage.obstacle_hit(previous, next, 0.95, true)
		var hit = tree_index >= 0
		if hit and game.vehicle_motion.velocity.length() > 5 and not game.stage.fallen.has(tree_index):
			knock_tree(tree_index, game.vehicle_motion.velocity)
		if contact_blocked(previous, next, true):
			hit = true
		if hit:
			game.condition = maxf(0, game.condition - game.vehicle_motion.velocity.length() * 1.4)
			game.vehicle_motion.velocity = Vector3.ZERO if tree_index >= 0 else game.vehicle_motion.velocity * -0.25
			game.speed = game.vehicle_motion.velocity.dot(forward)
			game.toast("Удар! Сбавь скорость.")
		else:
			game.car.position = next
		game.vehicle_motion.suspension(game.car, game.stage, dt, game.heading, (game.heading - previous_heading) / dt * game.speed)
		if offroad and absf(game.speed) > 5:
			game.condition = maxf(0, game.condition - dt * 0.15)
	var flooded = game.stage.water != null and game.vehicle_motion.flood > 0.25
	if flooded:
		# Water in the cabin: the engine drowns unless the car leaves the lake.
		game.condition = maxf(0, game.condition - delta * 6.0 * game.vehicle_motion.flood)
		if game.vehicle_motion.flood > 0.3 and game.toast_time <= 0:
			game.toast("Машина набирает воду! Выезжай на берег или выходи (F).")
	# Alone nobody can tow the car or give a lift; in a room car_rides.gd decides.
	if game.condition <= 0 and not game.room.connected:
		if flooded:
			game.die("Легковушка утонула в финском озере.\nДальше только пешком.")
			return
		game.die("Легковушка сдалась раньше тебя.\nРазбитый СУ победил подвеску.")

func knock_tree(index: int, direction_hint: Vector3) -> void:
	if game.stage.fell(index, direction_hint):
		if game.room.is_guest():
			game.tree_requests[index] = direction_hint.normalized()
		game.toast("Дерево падает!")

# A walker meets cars as perches (perches.gd: climbed onto or walked into),
# a driver as round volumes. `limit` is the highest top the walker's feet can
# take (default: a step up from `start`).
func contact_blocked(start: Vector3, end: Vector3, driving: bool, limit: float = NAN) -> bool:
	var cars = []
	var people = []
	if not driving:
		perches.near(start)
		if perches.blocked(start, end, start.y + perches.STEP_UP if is_nan(limit) else limit):
			return true
	for person in game.spectators.people:
		if not game.injuries.holds(person.avatar):
			# Spectators are solid for walkers; drivers meet them as people.
			people.append(person.avatar.position)
	if driving:
		for group in game.spectators.groups:
			cars.append(group.car.position)
		for racer in game.racers:
			cars.append(racer.node.position)
		cars.append_array(game.park_traffic.car_positions())
	for peer in game.room.peers.values():
		if peer.state == null:
			continue
		if driving:
			cars.append(game.room.v(peer.state.car))
		var feet = game.room.v(peer.state.pos)
		# Somebody standing on a car rides over the road, not in the way.
		if not peer.state.in_car and not game.injuries.is_down("player:%s" % peer.id) and not (driving and perches.riding_above(feet, start)):
			people.append(feet)
	for other in cars:
		if Motion.swept_hit(start + Vector3(0, 0.65, 0), end + Vector3(0, 0.65, 0), other + Vector3(0, 0.65, 0), 2.5 if driving else 1.75):
			# Let an initially overlapping walker move out of the volume.
			if end.distance_to(other) <= start.distance_to(other):
				return true
	for person in people:
		if not driving and minf(start.y, end.y) >= person.y + 1.5:
			continue
		if Motion.swept_hit(start + Vector3(0, 0.7, 0), end + Vector3(0, 0.7, 0), person + Vector3(0, 0.7, 0), 1.55 if driving else 0.6):
			if end.distance_to(person) <= start.distance_to(person):
				return true
	return false

func walk(delta: float) -> void:
	game.rides.update()
	perches.carry()
	if relief.update(delta):
		return
	perches.gather(game.walker)
	var remaining = maxf(delta, 0.0)
	while remaining > 0.000001:
		var step = minf(remaining, 1.0 / 60.0)
		walk_step(step)
		remaining -= step
	perches.settle()

func walk_step(delta: float) -> void:
	var previous_feet: Vector3 = game.walker
	if game.beers >= 30 or game.seated or game.injuries.down:
		return
	var motion = Vector2(Input.get_axis("left", "right"), Input.get_axis("forward", "back"))
	if motion.length() > 1:
		motion = motion.normalized()
	var dir = Vector3(motion.x, 0, motion.y).rotated(Vector3.UP, game.view_yaw)
	var water_factor = game.stage.water.walk_factor(game.walker) if game.stage.water != null else 1.0
	var wading = snow_wading()
	var next = game.walker + dir * delta * water_factor * game.injuries.walk_factor() * game.mushroom_effect.movement_multiplier() * lerpf(1.0, game.SNOW_WADE_SPEED, wading) * (1.4 if game.drink_time >= 0 or game.eat_time >= 0 else (game.RUN_SPEED if running() else game.WALK_SPEED))
	next.x = clampf(next.x, -185, 185)
	next.z = clampf(next.z, game.stage.parks.z_limits.x, game.stage.parks.z_limits.y)
	var old_floor = game.walker.y - game.jump_height
	var floor_height = game.stage.solids.walking_floor(next, game.walker.y)
	floor_height = game.stage.walk_floor(next, floor_height)
	# Cars, furniture, lying people, boxes and rocks within reach of the feet.
	var limit = game.walker.y + perches.allowance()
	var perch = perches.support(next, limit)
	# Coming down, a top within the ledge reach is climbed, not bumped into.
	var lift = limit if game.jump_velocity < 0.0 else -INF
	if perch >= floor_height:
		floor_height = perch
		lift = maxf(lift, perch + 0.01)
	if game.stage.water != null:
		if game.stage.water.depth(next) > 0.2 and next.distance_to(game.walker) > 0.0001:
			game.stage.water.wake(game.get_instance_id(), next, (next - game.walker) / maxf(delta, 0.001), minf(game.stage.water.depth(next), 1.0), delta, 0.35)
	next.y = floor_height if game.jump_height <= 0 and floor_height >= old_floor - 0.45 else game.walker.y
	# Landing on a top: the way there is tested at its height, not below it.
	var from = Vector3(game.walker.x, maxf(game.walker.y, lift), game.walker.z)
	var to = Vector3(next.x, maxf(next.y, lift), next.z)
	var hit = game.stage.biome.walk_blocked(to, from.y) or not game.stage.solids.hit(from, to, 0.3).is_empty() or not game.stage.rock_hit(from, to, 0.3).is_empty() or game.stage.obstacle_hit(from, to, 0.3, true) >= 0 or contact_blocked(from, to, false, maxf(limit, perch + perches.STEP_UP))
	if not hit:
		game.walker = next
	else:
		floor_height = old_floor
	# Small steps follow the stairs; leaving a roof starts a real fall.
	if game.jump_height > 0 or old_floor - floor_height > 0.45:
		game.jump_height = maxf(0, game.walker.y - floor_height)
	var remaining = maxf(0, delta)
	while remaining > 0.000001:
		var step = minf(remaining, 1.0 / 120.0)
		game.jump_height += game.jump_velocity * step - game.WALK_GRAVITY * step * step * 0.5
		game.jump_velocity -= game.WALK_GRAVITY * step
		if game.jump_height <= 0:
			game.jump_height = 0
			game.jump_velocity = 0
		remaining -= step
	game.walker.y = floor_height + game.jump_height
	game.injuries.play.injuries = game.injuries
	game.injuries.play.landing(game.injuries.local_key(), previous_feet, game.walker)
	snow_hint(delta)

# 0 on firm ground, 1 when wading through a full-depth forest drift.
func snow_wading() -> float:
	if game.stage == null or not game.stage.has_snow or game.jump_height > 0.01: return 0.0
	return clampf(game.stage.snow_sink(game.walker) / (DeepSnowRules.FOOT_SINK * 0.78), 0.0, 1.0)

func snow_hint(delta: float) -> void:
	game.snow_hint_clock = maxf(0.0, game.snow_hint_clock - delta)
	var deep = game.stage.has_snow and game.stage.snow_sink(game.walker) > game.SNOW_HINT_DEPTH and game.jump_height <= 0.01
	if deep and not game.snow_stuck and game.snow_hint_clock <= 0.0:
		var carry = game.cargo.held.get(game.chair_owner(), {})
		if str(carry.get("kind", "")) == "shovel":
			game.toast("Глубокий снег. Наведи лопату на сугроб и нажми F, чтобы расчистить место.")
		else:
			game.toast("Ты провалился в сугроб! Возьми лопату из багажника и расчисти место под лагерь.")
		game.snow_hint_clock = game.SNOW_HINT_COOLDOWN
	game.snow_stuck = deep

func running() -> bool:
	return not game.in_car and not game.seated and game.beers < 30 and game.injuries.limp <= 0.0 and not game.injuries.down and not game.paused and not game.dead and not game.finished and game.drink_time < 0 and game.eat_time < 0 and Input.is_action_pressed("sprint") and (absf(Input.get_axis("left", "right")) + absf(Input.get_axis("forward", "back"))) > 0.01

func jump() -> bool:
	if game.injuries.down and not game.paused and not game.dead and not game.finished:
		if game.room.submit("stand_person"):
			return true
		game.injuries.play.injuries = game.injuries
		return game.injuries.play.stand(game.injuries.local_key())
	if not game.playing or relief.active or game.in_car or game.seated or game.beers >= 30 or game.injuries.down or game.injuries.limp > 0.0 or game.paused or game.dead or game.finished or game.drink_time >= 0 or game.eat_time >= 0 or game.jump_height > 0.01 or game.jump_velocity > 0:
		return false
	if game.stage.water != null and game.stage.water.depth(game.walker) > 0.6:
		return false # No push-off while wading deep or swimming.
	game.jump_velocity = game.JUMP_SPEED
	return true

func update_camera(delta: float) -> void:
	if game.capture_mode:
		return
	if game.injuries.down:
		game.injuries.update_camera(delta)
		return
	game.impact_shake = maxf(0, game.impact_shake - delta)
	game.collapse_time = minf(0.8, game.collapse_time + delta) if game.beers >= 30 else 0.0
	var collapse = smoothstep(0, 0.8, game.collapse_time)
	if game.in_car:
		var body: Node3D = game.rides.vehicle()
		var travel_yaw = game.rides.heading() + (PI if game.rides.speed() < -0.5 else 0.0)
		game.view_yaw = lerp_angle(game.view_yaw, travel_yaw, 1.0 - exp(-delta * 2.8))
		var behind = Vector3(sin(game.view_yaw), 0, cos(game.view_yaw))
		var elevation = clampf(atan2(4.4, 8.2) - (game.view_pitch + 0.12), 0.14, 1.25)
		var distance = Vector2(8.2, 4.4).length()
		var desired = body.position + behind * cos(elevation) * distance + Vector3.UP * sin(elevation) * distance
		desired.y = maxf(desired.y, game.stage.ground(desired) + 1.1)
		game.camera.position = game.camera.position.lerp(desired, 1 - exp(-delta * 7))
		game.camera.look_at(body.position + Vector3(0, 1.1, 0) - behind * 1.5)
	else:
		game.camera.position = game.walker + Vector3(0, lerpf(1.45 if game.seated else 1.72, 0.36, collapse) + sin(game.elapsed * 12) * 0.015, 0)
		var sip = sin(clampf((game.drink_time - 1.3) / 1.2, 0, 1) * PI) if game.drink_time >= 0 else 0.0
		game.camera.rotation = Vector3(game.view_pitch + sip * 0.035, game.view_yaw, 0.0)
		game.camera.fov = 68 - sip * 2.0

	# Bounded gentle sway, with an envelope that fades between sips.
	game.camera.rotation.z += sin(game.drunk_phase) * deg_to_rad(3.0) * game.drunk_strength + PI / 2 * collapse
	game.camera.rotation.x += sin(game.drunk_phase * 2.0) * deg_to_rad(0.6) * game.drunk_strength
	game.camera.position += Vector3(sin(game.elapsed * 91), cos(game.elapsed * 73), 0) * game.impact_shake * 0.12

# Getting into a car (own or a friend's) needs free hands and firm feet.
func can_change_seat() -> bool:
	if not game.in_car and game.cargo.held.has(game.chair_owner()):
		game.toast("Сначала поставь предмет или верни коробку в багажник.")
		return false
	if game.jump_height > 0.01 or game.jump_velocity > 0:
		return false
	if game.beers >= 30 or game.injuries.down:
		game.toast("Ты лежишь. Дождись восстановления — три минуты." if game.beers >= 30 else "Ты лежишь. Дождись скорую.")
		return false
	if game.drink_time >= 0 or game.eat_time >= 0:
		game.toast("Сначала закончи есть или пить и освободи руки.")
		return false
	return true

func toggle_car() -> void:
	if game.rides.riding():
		game.rides.leave()
		return
	if not can_change_seat():
		return
	if game.in_car:
		if absf(game.speed) > 1:
			game.toast("Сначала остановись: Space — тормоз.")
			return
		game.in_car = false
		game.vehicle_motion.velocity = Vector3.ZERO
		game.speed = 0
		game.walker = game.car.position + Vector3(-2.1, 0, 0).rotated(Vector3.UP, game.heading)
		game.walker.y = game.stage.walking_ground(game.walker)
		game.view_yaw = game.heading
		game.toast("Z — стол, C — стулья, G — мангал. Устанавливай вне СУ.")
	elif game.walker.distance_to(game.car.position) < 4:
		game.in_car = true
		game.view_yaw = game.heading
		game.speed = 0
	else:
		game.toast("Подойди к своей машине, чтобы сесть.")

func walking_intent() -> Vector3:
	if relief.active or game.in_car or game.seated or game.jump_height > 0.01 or game.paused or game.dead or game.finished or game.beers >= 30 or game.drink_time >= 0 or game.eat_time >= 0:
		return Vector3.ZERO
	var input = Vector2(Input.get_axis("left", "right"), Input.get_axis("forward", "back")).limit_length(1)
	return Vector3(input.x, 0, input.y).rotated(Vector3.UP, game.view_yaw)

func sit_down() -> void:
	var owner = game.chair_owner()
	if not game.personal_chairs.has(owner) or game.in_car or game.beers >= 30 or game.jump_height > 0.01 or game.jump_velocity > 0:
		return
	game.seat_exit = game.walker
	var chair: Node3D = game.personal_chairs[owner]
	game.walker = chair.position
	game.view_yaw = chair.rotation.y
	game.seated = true
	game.toast("F — встать. Мышь — смотреть.")

func stand_up() -> void:
	game.seated = false
	game.walker = game.seat_exit
	game.walker.y = game.stage.ground(game.walker)

func update_sobriety(delta: float) -> void:
	if not game.playing or game.paused or game.dead or game.finished or (game.room.is_guest() and game.room.world_paused):
		return
	if game.beers < 30:
		game.sober_remaining = 0.0
		return
	if game.sober_remaining <= 0:
		game.sober_remaining = game.SOBER_SECONDS
	game.sober_remaining = maxf(0, game.sober_remaining - delta)
	if game.sober_remaining <= 0:
		game.beers = 0
		game.drunk_strength = 0
		game.drunk_phase = 0
		game.collapse_time = 0
		game.beer_timer = 0
		game.sobriety_panel.hide()
		game.toast("Ты протрезвел. Можно встать, собрать вещи и вернуться в машину.")

func update_intoxication(delta: float) -> void:
	game.drunk_strength = maxf(0.0, game.drunk_strength - delta / game.DRUNK_FADE_SECONDS)
	if game.drunk_strength > 0:
		game.drunk_phase = fposmod(game.drunk_phase + delta * 1.25, TAU)
	else:
		game.drunk_phase = 0.0
