extends RefCounted
# Towing and pushing cars by hand: rally crews stuck off the road and the cars
# of players, including their own. It runs on the host (or in a solo game), from every player's state and from NPC helpers; guests see the result
# through the room snapshot.
#
# A rope pulls a car towards the person holding it, from any side and to
# anywhere on the stage; closer than ROPE_SLACK the rope hangs loose. A push
# moves the car the way the pusher walks. Helpers add up. A rally crew counts as
# recovered as soon as it stands on the carriageway again.
#
# recovery_links: one entry per rope, {"player", "pos", "racer": id} or
# {"player", "pos", "car": owner id}; "hitch": true marks a rope between two
# cars (car_rides.gd). The room snapshot carries them.
const ROPE_RANGE = 6.0
const ROPE_SLACK = 2.4
# Reach from the measured body, including the walker's collision clearance.
const PUSH_RANGE = 0.65
const Hitbox = preload("res://scripts/cars/car_hitbox.gd")
const Motion = preload("res://scripts/cars/vehicle_motion.gd")
# Speed (m/s) one helper gives a car, and the most any team gives.
const HELPER_SPEED = 1.1
const MAX_SPEED = 3.0
# How fast (rad/s) a dragged car turns its nose towards the pull.
const TURN_RATE = 1.2

# Direction from a crew towards the nearest point of the road (along the road
# when it is already there): NPC helpers push this way.
static func road_direction(game, racer: Dictionary) -> Vector3:
	var position: Vector3 = racer.node.position
	var direction: Vector3 = game.stage.at(game.stage.road_s(position)) - position
	direction.y = 0
	if direction.length() < 0.01:
		direction = game.stage.direction(game.stage.road_s(position))
	return direction.normalized()

# Metres from pos to the edge of the carriageway; zero on the road.
static func road_gap(game, pos: Vector3) -> float:
	var station: float = game.stage.road_s(pos)
	return maxf(0.0, game.stage.road_distance(pos) - game.stage.road_width(station) * 0.5)

static func update(game, players: Dictionary, delta: float) -> void:
	if game.paused or game.dead or game.finished:
		game.crews.clear_recovery_ropes()
		return
	game.recovery_links.clear()
	game.injuries.play.injuries = game.injuries
	var occupied = game.injuries.play.update(players, delta)
	var targets = _targets(game, players)
	var forces: Dictionary = {}
	var helpers: Dictionary = {}
	var slack: Dictionary = {}
	var pulling: Dictionary = {}
	var participants = players.duplicate()
	participants.merge(game.spectators.push_helpers())
	participants.merge(game.stage.officials.push_helpers(game))
	for id in participants:
		if occupied.has(str(id)) or game.movable_props.grips.has(id):
			continue
		var p: Dictionary = participants[id]
		if p.get("in_car", true) or p.get("seated", false) or p.get("airborne", false) or int(p.get("beers", 0)) >= 30:
			continue
		if game.injuries.is_down("player:%s" % id):
			continue
		var effort = _effort(game, p, targets)
		if effort.is_empty():
			continue
		occupied[str(id)] = true
		var key: String = effort.target.key
		forces[key] = forces.get(key, Vector3.ZERO) + effort.force
		helpers[key] = int(helpers.get(key, 0)) + 1
		if effort.rope:
			pulling[key] = true
			slack[key] = minf(float(slack.get(key, INF)), effort.slack)
		if effort.rope:
			var link = {"player": str(id), "pos": p.pos}
			if effort.target.has("racer"):
				link.racer = effort.target.racer.id
			else:
				link.car = effort.target.owner
			game.recovery_links.append(link)
	# Keep car towing available beside camp furniture; an existing prop grip persists.
	game.movable_props.update(players, occupied, delta)
	for racer in game.racers:
		racer.recovery_helpers = int(helpers.get("racer:%d" % racer.id, 0))
	for target in targets:
		if helpers.has(target.key):
			_drag(game, target, forces[target.key], delta, float(slack.get(target.key, INF)), pulling.has(target.key))
	game.rides.pull(players, delta)
	local_target(game)
	game.crews.draw_recovery_ropes()

# Crews that may be towed, and the cars of all players in the room.
static func _targets(game, players: Dictionary) -> Array:
	var result: Array = []
	for racer in game.racers:
		if game.can_tow_racer(racer):
			result.append({"key": "racer:%d" % racer.id, "racer": racer, "node": racer.node, "pos": racer.node.position})
	if not game.room.connected:
		result.append({"key": "car:local", "owner": "local", "node": game.car, "pos": game.car.position})
	else:
		for id in players:
			var position = car_position(game, str(id))
			if position != null:
				var node = game.car if str(id) == game.room.player_id else game.room.peers[id].car
				var yaw: float = game.heading if str(id) == game.room.player_id else float(players[id].get("heading", node.rotation.y))
				if game.room.host_drives.has(str(id)): yaw = game.room.host_drives[str(id)].yaw
				result.append({"key": "car:%s" % id, "owner": str(id), "node": node, "yaw": yaw, "pos": position})
	return result

# The nearest target this person pulls (rope) or pushes (walking into it).
static func _effort(game, p: Dictionary, targets: Array) -> Dictionary:
	var pos: Vector3 = game.room.v(p.pos)
	var push: Vector3 = game.room.v(p.get("push", [0, 0, 0]))
	push.y = 0
	var best = INF
	var result: Dictionary = {}
	for target in targets:
		if target.has("racer") and int(p.get("racer", target.racer.id)) != target.racer.id:
			continue
		# Marshals and spectators only help crews.
		if target.has("owner") and p.has("racer"):
			continue
		var offset: Vector3 = target.pos - pos
		if absf(offset.y) > 3:
			continue
		offset.y = 0
		var distance = offset.length()
		if distance >= best or distance < 0.01:
			continue
		# NPC navigation stages helpers two metres behind the crew; walkers
		# instead meet the actual mesh collider in player_motion.gd.
		var contact = push_offset(target, pos)
		var touching = distance <= 2.6 if p.has("racer") else contact.length() <= PUSH_RANGE
		var inward = offset if p.has("racer") or contact.length_squared() < 0.0001 else contact
		if p.get("tow", false) and distance <= ROPE_RANGE:
			var force = -offset / distance if distance > ROPE_SLACK else Vector3.ZERO
			result = {"target": target, "force": force, "rope": true, "slack": maxf(0.0, distance - ROPE_SLACK)}
			best = distance
		elif touching and push.length() > 0.2 and push.normalized().dot(inward.normalized()) > 0.5:
			result = {"target": target, "force": push.normalized(), "rope": false}
			best = distance
	return result

# A centre radius loses contact at long bumpers and pushes from empty space at
# the sides. Measure the gap in the body's horizontal frame instead.
static func push_offset(target: Dictionary, pos: Vector3) -> Vector3:
	var node: Node3D = target.node
	var yaw = float(target.get("yaw", node.rotation.y))
	var local: Vector3 = (pos - target.pos).rotated(Vector3.UP, -yaw)
	var box: AABB = Hitbox.bounds(node)
	var nearest = local.clamp(box.position, box.end)
	return Vector3(nearest.x - local.x, 0, nearest.z - local.z).rotated(Vector3.UP, yaw)

# Moves a target along the summed pull; a rope never drags the car past the
# point where it would hang loose (`reach`, metres left until then).
static func _drag(game, target: Dictionary, force: Vector3, delta: float, reach: float, pulling: bool = true) -> void:
	var start: Vector3 = target.pos
	var next = start
	var heading = force.normalized()
	if force.length() > 0.05:
		next = start + heading * minf(minf(MAX_SPEED, force.length() * HELPER_SPEED) * maxf(0.0, delta), reach)
		next.y = game.stage.vehicle_ground(next)
		var blocked = not game.stage.rock_hit(start, next, 0.85).is_empty() or game.stage.obstacle_hit(start, next, 0.85, true) >= 0
		blocked = blocked or not game.stage.solids.hit(start, next, 0.85).is_empty()
		if blocked:
			game.toast("Путь перекрыт. Тяни в другую сторону или освободи проход.")
			next = start
	# A side push translates the body; turning its nose into every contact
	# repeatedly swings the collision surface into and away from the walker.
	var yaw = atan2(-heading.x, -heading.z) if pulling and force.length() > 0.05 else NAN
	if target.has("racer"):
		var racer: Dictionary = target.racer
		racer.node.position = next
		racer.towed = true
		if not is_nan(yaw):
			racer.node.rotation.y = rotate_toward(racer.node.rotation.y, yaw, TURN_RATE * delta)
		racer.motion.follow_ground(racer.node, game.stage, racer.node.rotation.y)
		racer.previous = racer.node.position
		if road_gap(game, next) <= 0.0:
			game.recover_racer(racer)
			game.recovery_links = game.recovery_links.filter(func(link): return int(link.get("racer", -1)) != racer.id)
			game.toast("Вытащили! Экипаж благодарит и продолжает СУ.")
	else:
		move_car(game, target.owner, next, yaw, delta)

# Where a player's car is, on the host: its own car, or the host's
# simulation of a guest's car. Null when the player is unknown.
static func car_position(game, owner: String):
	var room = game.room
	if owner == (room.player_id if room.connected else "local"):
		return game.car.position
	if room.host_drives.has(owner):
		return room.host_drives[owner].node.position
	if room.peers.has(owner) and room.peers[owner].state != null:
		return room.v(room.peers[owner].state.car)
	return null

# A car towed by another car (`turn_rate` given) turns even with its owner inside.
static func move_car(game, owner: String, next: Vector3, yaw: float, delta: float, turn_rate: float = -1.0) -> void:
	var room = game.room
	var towed = turn_rate > 0
	if not towed:
		turn_rate = TURN_RATE
	if owner == (room.player_id if room.connected else "local"):
		game.car.position = next
		if (towed or not game.in_car) and not is_nan(yaw):
			game.heading = rotate_toward(game.heading, yaw, turn_rate * delta)
		game.vehicle_motion.follow_ground(game.car, game.stage, game.heading)
		return
	var peer = room.peers.get(owner)
	var node: Node3D = peer.car if peer != null else null
	var motion = Motion.new()
	if room.host_drives.has(owner):
		var solver = room.host_drives[owner]
		node = solver.node
		motion = solver.motion
		if peer != null and peer.state != null and (towed or not peer.state.in_car) and not is_nan(yaw):
			solver.yaw = rotate_toward(solver.yaw, yaw, turn_rate * delta)
		node.rotation.y = solver.yaw
	elif node != null and peer.state != null:
		node.rotation.y = float(peer.state.get("heading", node.rotation.y))
		if (towed or not peer.state.in_car) and not is_nan(yaw):
			node.rotation.y = rotate_toward(node.rotation.y, yaw, turn_rate * delta)
	if node != null:
		node.position = next
		motion.follow_ground(node, game.stage, node.rotation.y)
	if peer != null and peer.state != null:
		peer.state.car = room.a(node.position if node != null else next)
		if node != null:
			peer.state.heading = node.rotation.y
			peer.state.tilt = room.a(node.rotation)

# The rope the local player holds, for the HUD: game.tow_target is the towed
# node, game.tow_distance the metres a crew still has to the road (-1 for a
# player's car) and game.recovery_helpers how many people work on it.
# game.crews.car_towed: somebody is towing the local player's own car.
static func local_target(game) -> void:
	game.tow_target = null
	game.tow_distance = -1.0
	game.recovery_helpers = 0
	var me = game.room.player_id if game.room.connected else "local"
	game.crews.car_towed = game.recovery_links.any(func(link): return str(link.get("car", "")) == me)
	for link in game.recovery_links:
		if str(link.player) != me:
			continue
		game.tow_target = link_node(game, link)
		if link.has("racer"):
			for racer in game.racers:
				if racer.id == int(link.racer):
					game.tow_distance = road_gap(game, racer.node.position)
					game.recovery_helpers = maxi(1, int(racer.get("recovery_helpers", 1)))
		else:
			game.recovery_helpers = game.recovery_links.filter(func(other): return str(other.get("car", "")) == str(link.car)).size()
		return

# The towed car of a rope: a crew, the local car or a friend's car.
static func link_node(game, link: Dictionary) -> Node3D:
	if link.has("racer"):
		for racer in game.racers:
			if racer.id == int(link.racer):
				return racer.node
		return null
	var owner = str(link.get("car", ""))
	if owner == (game.room.player_id if game.room.connected else "local"):
		return game.car
	if game.room.peers.has(owner) and game.room.peers[owner].has("car"):
		return game.room.peers[owner].car
	return null
