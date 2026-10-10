extends RefCounted
# Bounded local A*: swept edges prevent diagonal corner cutting.
const CELL = 1.5
const RADIUS = 0.35
const MAX_VISITS = 420

static func flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)

static func context(game, person: Dictionary, start: Vector3, goal: Vector3, roadside: bool) -> Dictionary:
	var solids: Array = []
	var low = flat(start).min(flat(goal)) - Vector2.ONE * 13
	var high = flat(start).max(flat(goal)) + Vector2.ONE * 13
	for rock in game.stage.rocks_in_bounds(low, high):
		if rock.get("actor", null) == person.avatar:
			continue
		var p = flat(rock.pos)
		if p.x + rock.radius >= low.x and p.x - rock.radius <= high.x and p.y + rock.radius >= low.y and p.y - rock.radius <= high.y:
			solids.append(rock)
	var cars: Array = [game.car]
	for group in game.spectators.groups:
		cars.append(group.car)
	for peer in game.room.peers.values():
		if peer.has("car"):
			cars.append(peer.car)
	for racer in game.racers:
		if int(person.get("helper", -1)) != racer.id:
			cars.append(racer.node)
	for car in cars:
		if not is_instance_valid(car):
			continue
		for z in [-1.1, 0.0, 1.1]:
			var position: Vector3 = car.position + Vector3(0, 0, z).rotated(Vector3.UP, car.rotation.y)
			var p = flat(position)
			if p.x >= low.x - 2 and p.x <= high.x + 2 and p.y >= low.y - 2 and p.y <= high.y + 2:
				solids.append({"pos": position, "radius": 1.0, "height": 1.8})
	if game.camp != null:
		solids.append({"pos": game.camp.position, "radius": 1.1, "height": 1.0})
	if game.grill != null:
		solids.append({"pos": game.grill.position, "radius": 0.65, "height": 1.0})
	for chair in game.personal_chairs.values():
		solids.append({"pos": chair.position, "radius": 0.5, "height": 1.0})
	return {"solids": solids, "roadside": roadside, "low": low, "high": high}

static func clear(game, a: Vector3, b: Vector3, ctx: Dictionary) -> bool:
	if b.x < -185 or b.x > 185 or b.z < -game.stage.LENGTH + 5 or b.z > 10:
		return false
	if ctx.roadside:
		var samples = maxi(1, ceili(flat(a).distance_to(flat(b)) / 0.75))
		var initial = game.stage.road_distance(a)
		for step in range(1, samples + 1):
			var distance = game.stage.road_distance(a.lerp(b, float(step) / samples))
			if distance < 5.2 and distance < initial - 0.001:
				return false
	if game.stage.obstacle_hit(a, b, RADIUS, true) >= 0:
		return false
	if not game.stage.solids.hit(a, b, RADIUS).is_empty():
		return false
	var start = flat(a)
	var end = flat(b)
	var travel = end - start
	for solid in ctx.solids:
		if minf(a.y, b.y) > solid.pos.y + solid.height:
			continue
		var center = flat(solid.pos)
		var offset = start - center
		var padding: float = solid.radius + RADIUS
		if offset.length() < padding and end.distance_to(center) > offset.length() + 0.00001 and offset.dot(travel) >= 0:
			continue
		var t = clampf((center - start).dot(travel) / maxf(travel.length_squared(), 0.000001), 0, 1)
		if (start + travel * t).distance_to(center) < padding:
			return false
	return true

static func point(game, origin: Vector3, cell: Vector2i) -> Vector3:
	var p = origin + Vector3(cell.x * CELL, 0, cell.y * CELL)
	p.y = game.stage.ground(p)
	return p

static func plan(game, start: Vector3, goal: Vector3, ctx: Dictionary) -> Array:
	if clear(game, start, goal, ctx):
		return [goal]
	var root = Vector2i.ZERO
	var frontier: Array[Vector2i] = [root]
	var scores = {root: 0.0}
	var priorities = {root: flat(start).distance_to(flat(goal))}
	var parents = {}
	var closed = {}
	for visit in range(MAX_VISITS):
		if frontier.is_empty():
			break
		var best = 0
		for i in range(1, frontier.size()):
			if priorities[frontier[i]] < priorities[frontier[best]]:
				best = i
		var current: Vector2i = frontier.pop_at(best)
		var here = point(game, start, current)
		if flat(here).distance_to(flat(goal)) <= CELL * 1.5 and clear(game, here, goal, ctx):
			var route: Array = [goal]
			var cursor = current
			while cursor != root:
				route.push_front(point(game, start, cursor))
				cursor = parents[cursor]
			return route
		closed[current] = true
		for x in [-1, 0, 1]:
			for z in [-1, 0, 1]:
				if x == 0 and z == 0:
					continue
				var next = current + Vector2i(x, z)
				if closed.has(next):
					continue
				var there = point(game, start, next)
				var p = flat(there)
				if p.x < ctx.low.x or p.x > ctx.high.x or p.y < ctx.low.y or p.y > ctx.high.y or not clear(game, here, there, ctx):
					continue
				var cost: float = scores[current] + flat(here).distance_to(p)
				if cost >= float(scores.get(next, INF)):
					continue
				scores[next] = cost
				parents[next] = current
				priorities[next] = cost + p.distance_to(flat(goal))
				if next not in frontier:
					frontier.append(next)
	return []

static func move(game, person: Dictionary, goal: Vector3, delta: float, roadside: bool = true) -> void:
	if delta <= 0:
		return
	var start: Vector3 = person.avatar.position
	goal.y = game.stage.ground(goal)
	if flat(start).distance_to(flat(goal)) < 0.08:
		return
	if not person.has("navigation"):
		person.navigation = {"goal": goal, "route": [], "retry": 0.0}
	var state: Dictionary = person.navigation
	state.retry = maxf(0, float(state.retry) - delta)
	var ctx = context(game, person, start, goal, roadside)
	var changed = flat(state.goal).distance_to(flat(goal)) > 1.0
	var route: Array = state.route
	while not route.is_empty() and flat(start).distance_to(flat(route[0])) < 0.18:
		route.pop_front()
	var blocked = not route.is_empty() and not clear(game, start, route[0], ctx)
	if changed or blocked or (route.is_empty() and state.retry <= 0):
		if not game.spectators.navigation_budget.request(person.avatar.get_instance_id()):
			return
		state.goal = goal
		state.route = plan(game, start, goal, ctx)
		state.retry = 0.8
		route = state.route
	if route.is_empty():
		return
	var direction: Vector3 = route[0] - start
	direction.y = 0
	var next = start + direction.normalized() * minf(direction.length(), delta * 2.7)
	next.y = game.stage.ground(next)
	if clear(game, start, next, ctx):
		person.avatar.position = next
	else:
		state.route = []
