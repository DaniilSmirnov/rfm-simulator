extends "res://tests/harness.gd"
# Drives the police and the ambulance over a whole stage, both passes, with the
# stage's own spectators, marshals and villagers and with players' cars left in
# the typical spots: the service parks, the verge of the narrowest bits of
# road, fords and bridges. Every vehicle must get from the start line to the
# finish (the police into its bay in the other park) without stalling.
# A local check, not part of CI (about 80 s a stage):
# godot --headless --path game --script res://tools/profile/service_route.gd -- [--stage=N] [--seed=N]
# `--stage=N` runs one stage; without it every stage runs.
const PeerView = preload("res://scripts/net/peer_view.gd")
const Room = preload("res://scripts/net/room.gd")
const Parks = preload("res://scripts/traffic/service_parks.gd")
const ServiceTraffic = preload("res://scripts/traffic/service_traffic.gd")
const STEP = 1.0 / 30.0
# Seconds without a metre of progress that count as stuck.
const STALL = 25.0

var stages: Array = []
# `-- --seed=N` changes the crews' and villagers' timing and which verge the
# first car stands on.
var seed = 21102026

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--stage="):
			stages.append(arg.trim_prefix("--stage=").to_int())
		if arg.begins_with("--seed="):
			seed = arg.trim_prefix("--seed=").to_int()
	call_deferred("run")

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.rng.seed = seed
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	if stages.is_empty():
		stages = range(game.Stage.STAGES.size())
	for variant in stages:
		game.playing = false
		game.select_stage(variant)
		await game.start_game()
		var name: String = game.stage.stage_id
		for pass_index in [1, 2]:
			begin_pass(game, pass_index)
			park_visitors(game, pass_index)
			check(drive(game, "opening_police", 101, "police_open"), "%s pass %d: opening police drives the whole stage" % [name, pass_index])
			var spots = park_on_route(game)
			print("  %s pass %d: players' cars at stations %s" % [name, pass_index, spots])
			check(drive(game, "ambulance", 900, ""), "%s pass %d: ambulance drives the whole stage past parked cars" % [name, pass_index])
			check(drive(game, "closing_police", 105, "police_close"), "%s pass %d: closing police drives the whole stage past parked cars" % [name, pass_index])
			block_narrowest(game)
			check(drive(game, "ambulance", 901, ""), "%s pass %d: ambulance gets past a car across the narrowest road" % [name, pass_index])
			clear_peers(game)
	await game._shutdown_audio()
	game.free()
	print("SERVICE ROUTE RESULT: %d checks, %d failures" % [checks, failures])
	finish()

func begin_pass(game, pass_index: int) -> void:
	for racer in game.racers:
		racer.node.queue_free()
	game.racers.clear()
	game.course.red_flag = false
	game.course.active_id = -1
	game.park_traffic.reset()
	game.course.pass_index = pass_index
	game.course.phase = "opening_police"
	if pass_index == 2:
		game.park_traffic.settle()
	game.in_car = true

# The local player's car and friends' cars in the visitors' rows of both parks.
func park_visitors(game, pass_index: int) -> void:
	var parks = game.stage.parks
	if parks == null:
		return
	var pose: Transform3D = parks.visitor_pose(pass_index - 1, 0)
	place(game.car, pose.origin, pose.basis.get_euler().y)
	for index in range(2):
		for slot in range(1, Parks.VISITORS.size()):
			var at: Transform3D = parks.visitor_pose(index, slot)
			add_peer(game, at.origin, at.basis.get_euler().y)

# Stations where a player's car stands on the verge: the narrowest road, the
# biome's ford or bridge and regular stops along the stage, alternating sides.
func park_on_route(game) -> Array:
	var stage = game.stage
	var wanted: Array = []
	# No verge on the bridge itself: cars stand at either end of it.
	if "BRIDGE_S" in stage.biome:
		for end in [-1.0, 1.0]:
			wanted.append(float(stage.biome.BRIDGE_S) + end * (float(stage.biome.BRIDGE_HALF_LENGTH) + 10.0))
	if "FORD_STATION" in stage.biome:
		wanted.append(float(stage.biome.FORD_STATION))
	wanted.append_array(narrowest(stage, 3))
	var station = 250.0
	while station < stage.length - 200.0:
		wanted.append(station)
		station += 400.0
	# One car at a time: two on opposite verges a few metres apart close
	# any road to anything but the ambulance.
	var spots: Array = []
	for at in wanted:
		if spots.all(func(other): return absf(other - at) > 40.0):
			spots.append(at)
	var side = 1.0 if seed % 2 == 0 else -1.0
	for at in spots:
		var lateral = stage.road_width(at) * 0.5 + 0.5
		add_peer(game, stage.at(at) + stage.side(at) * lateral * side, yaw_at(stage, at))
		side = -side
	return spots.map(func(s): return int(s))

# A car parked across the middle of the narrowest road.
func block_narrowest(game) -> void:
	var at: float = narrowest(game.stage, 1)[0]
	add_peer(game, game.stage.at(at), yaw_at(game.stage, at) + PI * 0.5)

static func narrowest(stage, count: int) -> Array:
	var widths: Array = []
	var s = 60.0
	while s < stage.length - 60.0:
		# Nobody parks on a bridge: it has no verge.
		if not ("BRIDGE_S" in stage.biome and absf(s - stage.biome.BRIDGE_S) < stage.biome.BRIDGE_HALF_LENGTH + 2.0):
			widths.append([stage.road_width(s) + stage.shoulder(s) * 2.0, s])
		s += 4.0
	widths.sort_custom(func(a, b): return a[0] < b[0])
	var result: Array = []
	for item in widths:
		if result.all(func(other): return absf(other - item[1]) > 150.0):
			result.append(item[1])
		if result.size() >= count:
			break
	return result

static func yaw_at(stage, station: float) -> float:
	var direction: Vector3 = stage.direction(station)
	return atan2(-direction.x, -direction.z)

static func place(node: Node3D, pos: Vector3, yaw: float) -> void:
	node.position = pos
	node.rotation = Vector3(0, yaw, 0)

func add_peer(game, pos: Vector3, yaw: float) -> void:
	pos.y = game.stage.ground(pos)
	var id = "parked%d" % game.room.peers.size()
	var peer = PeerView.create(game, {"id": id, "name": id, "slot": game.room.peers.size() % 4, "state": null})
	place(peer.car, pos, yaw)
	peer.state = {"car": Room.a(pos), "pos": Room.a(pos), "heading": yaw, "in_car": true}
	game.room.peers[id] = peer

func clear_peers(game) -> void:
	for peer in game.room.peers.values():
		PeerView.remove(peer)
	game.room.peers.clear()

# One vehicle from the start line to the finish; a police car also has to
# leave its bay before and back into the other park's bay after.
func drive(game, role: String, base_id: int, key: String) -> bool:
	var id: int = base_id + (game.course.pass_index - 1) * 200
	var started = Time.get_ticks_msec()
	if key != "":
		# Only this car is called to the line.
		for other in Parks.KEYS:
			game.park_traffic.called[other] = other != key
		game.park_traffic.called.erase(key)
		game.park_traffic.called_pass = game.park_traffic.pass_now()
		if not game.park_traffic.parked[game.park_traffic.start_end()].has(key):
			game.park_traffic.park(game.park_traffic.start_end(), key)
		var waited = 0.0
		while game.park_traffic.mover(key).get("state", "") != "at_start":
			tick(game)
			waited += STEP
			if waited > 90.0:
				print("    %s stuck leaving the park at %s" % [role, game.park_traffic.mover(key).get("node", game.car).position])
				return false
	game.spawn_course_car(role, id)
	var racer: Dictionary = game.racers[-1]
	var best = -INF
	var still = 0.0
	var time = 0.0
	while game.racers.has(racer):
		tick(game)
		time += STEP
		if float(racer.s) > best + 1.0:
			best = float(racer.s)
			still = 0.0
		else:
			still += STEP
		if still > STALL or racer.state != "racing":
			var pos: Vector3 = racer.node.position
			print("    %s %s at s=%.0f (station %.0f of %.0f, line %.2f, planned %.2f, road half %.2f, %s), priority=%s" % [role, "stopped" if racer.state != "racing" else "stalled", racer.s, game.stage.road_s(pos), game.stage.length, racer.line, float(racer.avoid_line), game.stage.road_width(game.stage.road_s(pos)) * 0.5, pos, ServiceTraffic.priority(racer)])
			blockers(game, racer)
			drop(game, racer)
			return false
	if key != "":
		var parked_after = 0.0
		while not game.park_traffic.mover(key).is_empty():
			tick(game)
			parked_after += STEP
			if parked_after > 90.0:
				print("    %s stuck on the way into its bay at %s" % [role, game.park_traffic.mover(key).node.position])
				return false
		if not game.park_traffic.parked[game.park_traffic.finish_end()].has(key):
			print("    %s never reached its bay" % role)
			return false
	print("    %s: %.0f m in %.0f s (%d ms)" % [role, game.stage.length, time, Time.get_ticks_msec() - started])
	return true

func tick(game) -> void:
	game.elapsed += STEP
	if game.stage.life != null and "rng" in game.stage.life and game.elapsed < STEP * 1.5:
		game.stage.life.rng.seed = seed
	game._update_racers(STEP)
	game.park_traffic.update(STEP)
	game.spectators.update(game.elapsed, STEP, false)
	game.stage.officials.update(game, STEP, false)
	game.stage.update_life(STEP, game.player_position())

func drop(game, racer: Dictionary) -> void:
	game.racers.erase(racer)
	racer.node.queue_free()

# What stands within 30 m ahead of a stuck vehicle.
func blockers(game, racer: Dictionary) -> void:
	var here: Vector3 = racer.node.position
	for person in ServiceTraffic.people(game):
		if person.pos.distance_to(here) < 30.0:
			var station: float = game.race_station(person.pos)
			print("      person %s at %.1f m: %.1f m ahead, line %.2f" % [person.key, person.pos.distance_to(here), station - float(racer.s), (person.pos - game.race_at(station)).dot(game.race_side(station))])
	for car in ServiceTraffic.cars(game, racer):
		if car.distance_to(here) < 30.0:
			print("      car at %.1f m" % car.distance_to(here))
	var ahead: Vector3 = game.race_at(racer.s + 6.0) + game.race_side(racer.s + 6.0) * float(racer.line)
	ahead.y = game.stage.ground(ahead)
	print("      rock=%s tree=%d solid=%s" % [not game.stage.rock_hit(here, ahead, 1.1).is_empty(), game.stage.obstacle_hit(here, ahead, 1.1, true), game.stage.solids.hit(here, ahead, 1.1)])
