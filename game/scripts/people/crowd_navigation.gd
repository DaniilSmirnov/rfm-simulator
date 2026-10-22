extends RefCounted
# Bounded local A*: swept edges prevent diagonal corner cutting.
const CELL = 1.5
const RADIUS = 0.35
const MAX_VISITS = 420
# Time the whole crowd may spend searching for routes in one frame.
const SEARCH_USEC_PER_FRAME = 4000
static var _search_frame = -1
static var _search_deadline = 0
# Seconds between full re-checks of the current route leg.
const RECHECK = 0.25
# Obstacle search margin (m) around a single step; the widest solid is a car
# point of radius 1.0 plus the walker's RADIUS.
const STEP_MARGIN = 3.0
const STEP_AHEAD = 0.6

static func flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)

# Obstacles within `margin` metres of the box spanning start and goal.
static func context(game, person: Dictionary, start: Vector3, goal: Vector3, roadside: bool, margin: float = 13.0) -> Dictionary:
	var solids: Array = []
	var low = flat(start).min(flat(goal)) - Vector2.ONE * margin
	var high = flat(start).max(flat(goal)) + Vector2.ONE * margin
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
	# A walker's sweep passes under a tabletop and over a grill's legs, but
	# the walker's body does not: crowds walked through camp tables and
	# shoved them along.
	for group in game.spectators.groups:
		for gear in [[group.table, 1.1], [group.grill, 0.65]]:
			var p = flat(gear[0].position)
			if p.x >= low.x - 2 and p.x <= high.x + 2 and p.y >= low.y - 2 and p.y <= high.y + 2:
				solids.append({"pos": gear[0].position, "radius": gear[1], "height": 1.0})
	if game.camp != null:
		solids.append({"pos": game.camp.position, "radius": 1.1, "height": 1.0})
	if game.grill != null:
		solids.append({"pos": game.grill.position, "radius": 0.65, "height": 1.0})
	for chair in game.personal_chairs.values():
		solids.append({"pos": chair.position, "radius": 0.5, "height": 1.0})
	return {"solids": solids, "roadside": roadside, "low": low, "high": high}

static func clear(game, a: Vector3, b: Vector3, ctx: Dictionary) -> bool:
	if b.x < -185 or b.x > 185 or b.z < game.stage.parks.z_limits.x or b.z > game.stage.parks.z_limits.y:
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

# A whole plan at once (tests, one-off checks); people search step by step.
static func plan(game, start: Vector3, goal: Vector3, ctx: Dictionary) -> Array:
	var search = begin(game, start, goal, ctx)
	if not search.has("route"):
		step(game, search, MAX_VISITS)
	# A search that spends its whole budget stops before it can note failure.
	return search.get("route", [])

# An A* search over CELL squares around start. It holds "route" once finished
# (empty when there is none). A long detour visits a few hundred cells at
# ~0.3 ms each; done in one go that was 50-200 ms, two at a time when the crowd
# walked out at the start of a stage, so people search a few cells a frame
# from a time budget they share (SEARCH_USEC_PER_FRAME).
static func begin(game, start: Vector3, goal: Vector3, ctx: Dictionary) -> Dictionary:
	if clear(game, start, goal, ctx):
		return {"route": [goal]}
	# A goal inside an obstacle (a spectator's seat now that camp chairs are
	# solid props) has no detour: searching the whole grid for one took ~100 ms
	# and was retried every 0.8 s.
	# (Sweeps may leave an obstacle, so the test is approaching the goal: from
	# all four sides blocked means the goal itself is inside something.)
	var reachable = false
	for side in [Vector3(0.4, 0, 0), Vector3(-0.4, 0, 0), Vector3(0, 0, 0.4), Vector3(0, 0, -0.4)]:
		reachable = reachable or clear(game, goal + side, goal, ctx)
	if not reachable:
		return {"route": []}
	var root = Vector2i.ZERO
	var frontier: Array[Vector2i] = [root]
	return {"start": start, "goal": goal, "ctx": ctx, "frontier": frontier, "scores": {root: 0.0},
		"priorities": {root: flat(start).distance_to(flat(goal))}, "parents": {}, "closed": {},
		"points": {root: point(game, start, root)}, "queued": {root: true}, "visits": 0}

# Each cell's ground is sampled once per search (cells are reached from up to
# eight neighbours).
static func _cell(game, search: Dictionary, cell: Vector2i) -> Vector3:
	if not search.points.has(cell):
		search.points[cell] = point(game, search.start, cell)
	return search.points[cell]

# Visits up to `budget` more cells, stopping early past `deadline` (ticks usec,
# 0 for none); returns how many it used.
static func step(game, search: Dictionary, budget: int, deadline: int = 0) -> int:
	var goal: Vector3 = search.goal
	var ctx: Dictionary = search.ctx
	var frontier: Array[Vector2i] = search.frontier
	var used = 0
	while used < budget and (deadline == 0 or used == 0 or Time.get_ticks_usec() < deadline):
		if frontier.is_empty() or int(search.visits) >= MAX_VISITS:
			search.route = []
			return used
		used += 1
		search.visits = int(search.visits) + 1
		var best = 0
		for i in range(1, frontier.size()):
			if search.priorities[frontier[i]] < search.priorities[frontier[best]]:
				best = i
		var current: Vector2i = frontier.pop_at(best)
		search.queued.erase(current)
		var here: Vector3 = _cell(game, search, current)
		if flat(here).distance_to(flat(goal)) <= CELL * 1.5 and clear(game, here, goal, ctx):
			var route: Array = [goal]
			var cursor = current
			while cursor != Vector2i.ZERO:
				route.push_front(_cell(game, search, cursor))
				cursor = search.parents[cursor]
			search.route = route
			return used
		search.closed[current] = true
		for x in [-1, 0, 1]:
			for z in [-1, 0, 1]:
				if x == 0 and z == 0:
					continue
				var next = current + Vector2i(x, z)
				if search.closed.has(next):
					continue
				var there: Vector3 = _cell(game, search, next)
				var p = flat(there)
				if p.x < ctx.low.x or p.x > ctx.high.x or p.y < ctx.low.y or p.y > ctx.high.y or not clear(game, here, there, ctx):
					continue
				var cost: float = search.scores[current] + flat(here).distance_to(p)
				if cost >= float(search.scores.get(next, INF)):
					continue
				search.scores[next] = cost
				search.parents[next] = current
				search.priorities[next] = cost + p.distance_to(flat(goal))
				if not search.queued.has(next):
					search.queued[next] = true
					frontier.append(next)
	return used

# The moment this frame's shared search time runs out.
static func _frame_deadline() -> int:
	if _search_frame != Engine.get_process_frames():
		_search_frame = Engine.get_process_frames()
		_search_deadline = Time.get_ticks_usec() + SEARCH_USEC_PER_FRAME
	return _search_deadline

static func move(game, person: Dictionary, goal: Vector3, delta: float, roadside: bool = true) -> void:
	if delta <= 0:
		return
	var start: Vector3 = person.avatar.position
	if flat(start).distance_to(flat(goal)) < 0.08:
		return
	if not person.has("navigation"):
		person.navigation = {"goal": goal, "route": [], "retry": 0.0}
	var state: Dictionary = person.navigation
	state.retry = maxf(0, float(state.retry) - delta)
	# Homes and watch spots are fixed: their ground height is sampled once a
	# second rather than every frame (dug snow can still change it).
	state.goal_age = float(state.get("goal_age", INF)) + delta
	if state.get("goal_xz", Vector2.INF) != flat(goal) or state.goal_age > 1.0:
		state.goal_xz = flat(goal)
		state.goal_y = game.stage.ground(goal)
		state.goal_age = 0.0
	goal.y = float(state.goal_y)
	var changed = flat(state.goal).distance_to(flat(goal)) > 1.0
	var route: Array = state.route
	while not route.is_empty() and flat(start).distance_to(flat(route[0])) < 0.18:
		route.pop_front()
	# The whole leg ahead is re-validated a few times a second; the step taken
	# this frame is always checked below, so nobody walks into a new obstacle.
	state.recheck = float(state.get("recheck", 0.0)) - delta
	var blocked = false
	var needs_plan = changed or (route.is_empty() and state.retry <= 0 and not state.has("search"))
	var ctx: Dictionary = {}
	if needs_plan or (not route.is_empty() and state.recheck <= 0.0):
		ctx = context(game, person, start, goal, roadside)
	if not route.is_empty() and state.recheck <= 0.0:
		state.recheck = RECHECK
		blocked = not clear(game, start, route[0], ctx)
	if needs_plan or blocked:
		if not person.get("navigation_budget", game.spectators.navigation_budget).request(person.avatar.get_instance_id()):
			return
		state.goal = goal
		state.search = begin(game, start, goal, ctx)
	if state.has("search"):
		var search: Dictionary = state.search
		var deadline = _frame_deadline()
		if not search.has("route") and Time.get_ticks_usec() < deadline:
			step(game, search, MAX_VISITS, deadline)
		if not search.has("route"):
			return
		state.erase("search")
		state.route = search.route
		# Unreachable goals are retried less and less often (0.8 s up to 6 s).
		state.fails = 0 if not state.route.is_empty() else int(state.get("fails", 0)) + 1
		state.retry = minf(6.0, 0.8 * pow(2.0, maxi(0, int(state.fails) - 1)))
		route = state.route
	if route.is_empty():
		return
	var direction: Vector3 = route[0] - start
	direction.y = 0
	var next = start + direction.normalized() * minf(direction.length(), delta * 2.7)
	next.y = game.stage.ground(next)
	# A step is a few centimetres: only obstacles right around it matter. The
	# stretch up to STEP_AHEAD is checked at once and trusted for RECHECK s (a
	# whole crowd checking every 4 cm step each frame cost 30-50 ms).
	var checked: Dictionary = state.get("checked", {})
	checked.age = float(checked.get("age", INF)) + delta
	if checked.get("target") == route[0] and checked.age < RECHECK and flat(next).distance_to(flat(checked.from)) <= float(checked.length):
		person.avatar.position = next
		return
	var reach = start + direction.normalized() * minf(direction.length(), STEP_AHEAD)
	reach.y = game.stage.ground(reach)
	if clear(game, start, reach, context(game, person, start, reach, roadside, STEP_MARGIN)):
		state.checked = {"from": start, "target": route[0], "length": flat(start).distance_to(flat(reach)), "age": 0.0}
		person.avatar.position = next
	elif clear(game, start, next, context(game, person, start, next, roadside, STEP_MARGIN)):
		state.erase("checked")
		person.avatar.position = next
	else:
		state.erase("checked")
		state.route = []
