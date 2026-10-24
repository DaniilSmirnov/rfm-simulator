extends RefCounted
# Crews far from every player step less often. Each crew step plans traffic,
# sweeps rocks, trees, props and people and settles the suspension; eight
# crews at 60 steps a second were half of a host's frame. A far crew keeps the
# same physics (the driver still integrates in its own 1/120 s substeps) and
# the same total time, so the course timetable does not drift; only its
# planning and collision checks run FAR_STEP apart. Nobody is close enough to
# see the coarser steps; guests draw it between snapshots as before.

# A crew within this distance (m) of any player steps every frame.
const NEAR = 200.0
# How often (s) a far crew steps.
const FAR_STEP = 1.0 / 20.0

const RallyDriver = preload("res://scripts/traffic/rally_driver.gd")

# The driver aims at its line in steps of at most a frame (1/60 s) even in a
# long far step: aiming at one point for FAR_STEP at 50 m/s let the car run
# wide into the rocks. The plan's room ahead holds for the whole step.
static func follow(crews, racer: Dictionary, speed: float, advance: float, delta: float) -> void:
	var start: float = racer.s
	var chunks = maxi(1, int(ceil(delta / (1.0 / 60.0) - 0.001)))
	for i in range(chunks):
		RallyDriver.follow(crews, racer, speed, advance - (float(racer.s) - start), delta / chunks)

# Where the players are: this game's player (not on a dedicated server, which
# has none) and every member's car or walker.
static func watchers(game) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if game.room == null or not game.room.Dedicated.active():
		result.append(game.player_position())
	if game.room != null:
		for peer in game.room.peers.values():
			if peer.state != null:
				result.append(game.room.v(peer.state.pos))
	return result

static func near(racer: Dictionary, points: Array[Vector3]) -> bool:
	# The ambulance works a casualty scene with the medics; it always steps.
	if racer.get("role", "") == "ambulance" or racer.get("towed", false):
		return true
	var position: Vector3 = racer.node.position
	for point in points:
		if position.distance_squared_to(point) < NEAR * NEAR:
			return true
	return false

# Splits this frame's crews: the near ones step with every substep; a far one
# collects time and is returned in `due` with the time it has to cover once
# that reaches FAR_STEP. The first far step of each comes early by a third of
# a step per id, so far crews do not all land on the same frame; the time
# they cover is always the time that passed.
static func split(game, delta: float, everyone: bool = false) -> Dictionary:
	var points = watchers(game)
	var close: Array[Dictionary] = []
	var due: Array = []
	for racer in game.racers:
		var owed = float(racer.get("lod_time", 0.0))
		if everyone or near(racer, points):
			# Coming close, it first covers the time it collected.
			if owed > 0.0:
				due.append([racer, owed])
			racer.lod_time = 0.0
			racer.lod_lead = FAR_STEP * float(int(racer.id) % 3) / 3.0
			close.append(racer)
			continue
		racer.lod_time = owed + delta
		if racer.lod_time + float(racer.get("lod_lead", FAR_STEP * float(int(racer.id) % 3) / 3.0)) >= FAR_STEP:
			due.append([racer, float(racer.lod_time)])
			racer.lod_time = 0.0
			racer.lod_lead = 0.0
	return {"close": close, "due": due}
