extends RefCounted
# Towing and pushing cars by hand: rally crews stuck off the road and the cars
# of other players. It runs where the cars are simulated, the host (or a solo
# game), from every player's state and from NPC helpers; guests see the result
# through the room snapshot.
#
# A rope pulls a car towards the person holding it, from any side and to
# anywhere on the stage; closer than ROPE_SLACK the rope hangs loose. A push
# moves the car the way the pusher walks. Helpers add up. A rally crew counts as
# recovered as soon as it stands on the carriageway again.
#
# recovery_links: one entry per rope, {"player", "pos", "racer": id} or
# {"player", "pos", "car": owner id}; the room snapshot carries them.
const ROPE_RANGE = 6.0
const ROPE_SLACK = 2.4
const PUSH_RANGE = 2.6
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
		game._clear_recovery_ropes()
		return
	game.recovery_links.clear()
	var targets = _targets(game, players)
	var forces: Dictionary = {}
	var helpers: Dictionary = {}
	var slack: Dictionary = {}
	var participants = players.duplicate()
	participants.merge(game.spectators.push_helpers())
	participants.merge(game.stage.officials.push_helpers(game))
	for id in participants:
		var p: Dictionary = participants[id]
		if p.get("in_car", true) or p.get("seated", false) or p.get("airborne", false) or int(p.get("beers", 0)) >= 30:
			continue
		var effort = _effort(game, str(id), p, targets)
		if effort.is_empty():
			continue
		var key: String = effort.target.key
		forces[key] = forces.get(key, Vector3.ZERO) + effort.force
		helpers[key] = int(helpers.get(key, 0)) + 1
		if effort.rope:
			slack[key] = minf(float(slack.get(key, INF)), effort.slack)
		if effort.rope:
			var link = {"player": str(id), "pos": p.pos}
			if effort.target.has("racer"):
				link.racer = effort.target.racer.id
			else:
				link.car = effort.target.owner
			game.recovery_links.append(link)
	for racer in game.racers:
		racer.recovery_helpers = int(helpers.get("racer:%d" % racer.id, 0))
	for target in targets:
		if helpers.has(target.key):
			_drag(game, target, forces[target.key], delta, float(slack.get(target.key, INF)))
	local_target(game)
	game.draw_recovery_ropes()

# Crews that may be towed, and the cars of all players in the room.
static func _targets(game, players: Dictionary) -> Array:
	var result: Array = []
	for racer in game.racers:
		if game.can_tow_racer(racer):
			result.append({"key": "racer:%d" % racer.id, "racer": racer, "pos": racer.node.position})
	if game.room.connected:
		for id in players:
			var position = car_position(game, str(id))
			if position != null:
				result.append({"key": "car:%s" % id, "owner": str(id), "pos": position})
	return result

# The nearest target this person pulls (rope) or pushes (walking into it).
static func _effort(game, id: String, p: Dictionary, targets: Array) -> Dictionary:
	var pos: Vector3 = game.room.v(p.pos)
	var push: Vector3 = game.room.v(p.get("push", [0, 0, 0]))
	push.y = 0
	var best = INF
	var result: Dictionary = {}
	for target in targets:
		if target.has("racer") and int(p.get("racer", target.racer.id)) != target.racer.id:
			continue
		# Nobody tows their own car; marshals and spectators only help crews.
		if target.has("owner") and (target.owner == id or p.has("racer")):
			continue
		var offset: Vector3 = target.pos - pos
		if absf(offset.y) > 3:
			continue
		offset.y = 0
		var distance = offset.length()
		if distance >= best or distance < 0.01:
			continue
		if p.get("tow", false) and distance <= ROPE_RANGE:
			var force = -offset / distance if distance > ROPE_SLACK else Vector3.ZERO
			result = {"target": target, "force": force, "rope": true, "slack": maxf(0.0, distance - ROPE_SLACK)}
			best = distance
		elif distance <= PUSH_RANGE and push.length() > 0.2 and push.normalized().dot(offset / distance) > 0.5:
			result = {"target": target, "force": push.normalized(), "rope": false}
			best = distance
	return result

# Moves a target along the summed pull; a rope never drags the car past the
# point where it would hang loose (`reach`, metres left until then).
static func _drag(game, target: Dictionary, force: Vector3, delta: float, reach: float) -> void:
	var start: Vector3 = target.pos
	var next = start
	var heading = force.normalized()
	if force.length() > 0.05:
		next = start + heading * minf(minf(MAX_SPEED, force.length() * HELPER_SPEED) * maxf(0.0, delta), reach)
		next.y = game.stage.ground(next)
		var blocked = not game.stage.rock_hit(start, next, 0.85).is_empty() or game.stage.obstacle_hit(start, next, 0.85, true) >= 0
		blocked = blocked or not game.stage.solids.hit(start, next, 0.85).is_empty()
		if blocked:
			game.toast("Путь перекрыт. Тяни в другую сторону или освободи проход.")
			next = start
	var yaw = atan2(-heading.x, -heading.z) if force.length() > 0.05 else NAN
	if target.has("racer"):
		var racer: Dictionary = target.racer
		racer.node.position = next
		racer.previous = next
		racer.towed = true
		if not is_nan(yaw):
			racer.node.rotation.y = rotate_toward(racer.node.rotation.y, yaw, TURN_RATE * delta)
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
	if owner == room.player_id:
		return game.car.position
	if room.host_drives.has(owner):
		return room.host_drives[owner].node.position
	if room.peers.has(owner) and room.peers[owner].state != null:
		return room.v(room.peers[owner].state.car)
	return null

static func move_car(game, owner: String, next: Vector3, yaw: float, delta: float) -> void:
	var room = game.room
	if owner == room.player_id:
		game.car.position = next
		if not game.in_car and not is_nan(yaw):
			game.heading = rotate_toward(game.heading, yaw, TURN_RATE * delta)
			game.car.rotation.y = game.heading
		return
	var peer = room.peers.get(owner)
	if room.host_drives.has(owner):
		var solver = room.host_drives[owner]
		solver.node.position = next
		if peer != null and peer.state != null and not peer.state.in_car and not is_nan(yaw):
			solver.yaw = rotate_toward(solver.yaw, yaw, TURN_RATE * delta)
			solver.node.rotation.y = solver.yaw
	if peer != null and peer.state != null:
		peer.state.car = room.a(next)

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
	if owner == game.room.player_id:
		return game.car
	if game.room.peers.has(owner) and game.room.peers[owner].has("car"):
		return game.room.peers[owner].car
	return null
