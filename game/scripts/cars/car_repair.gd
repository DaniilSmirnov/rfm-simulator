extends RefCounted
# Repairing a broken car (condition 0) under its bonnet. Walk up to the nose
# of a broken car, your own or a friend's, and the bonnet swings open on the
# engine bay (car_hood.gd). F at the open bay starts the work: the fan stands
# at the nose for SECONDS while a spanner strikes the engine parts one after
# another, with a clank and a spark at each blow. When the time is up the car
# drives again at full condition. F again, or walking off, abandons the job.
#
# In a room the host owns every car's condition: a guest finishing a repair
# sends "repair_car" with the bay's position, and the host mends the broken
# car found there (fix_at). The repairer's state carries "repair", so every
# client strikes the parts of that car and bends the fan over the bay.
const CarHood = preload("res://scripts/cars/car_hood.gd")
const SoundBank = preload("res://scripts/core/sound_bank.gd")
const Loc = preload("res://scripts/ui/loc.gd")
const SECONDS = 8.0
const REPAIRED = 100.0
# Metres from the bay a fan reaches into it, and from which the bonnet opens.
const REACH = 2.4
const OPEN_RADIUS = 3.6
# One blow of the spanner: wind up, strike, rest on the part.
const STRIKE = 0.6
const RAISE = 0.6
const HIT = 0.75
const SWING = 0.95
const BLOWS_PER_PART = 3
const SPARK_SECONDS = 0.08

var game
var owner = "" # the car being repaired by the local player, "" when idle
var elapsed = 0.0

func me() -> String:
	return game.rides.me()

func active() -> bool:
	return owner != ""

func progress() -> float:
	return clampf(elapsed / SECONDS, 0.0, 1.0)

# Every player's car this client draws, by owner.
func cars() -> Dictionary:
	var result = {}
	for id in [me()] + game.room.peers.keys():
		var node = game.rides.car_node(str(id))
		if node != null and node.has_node("HoodHinge"):
			result[str(id)] = node
	return result

func can_start() -> bool:
	return not active() and not game.in_car and not game.seated and not game.injuries.down and game.beers < game.COLLAPSE_BEERS \
		and game.drink_time < 0 and game.eat_time < 0 and game.placement_kind == "" and not game.cargo.blocks(game.chair_owner()) \
		and not game.player.relief.active

# The open bay of a broken car, aimed at from the nose.
func offers(items: Array, interaction) -> void:
	if not can_start():
		return
	var all = cars()
	for id in all:
		var node: Node3D = all[id]
		if game.rides.broken(id) and CarHood.is_open(node):
			interaction.offer(items, CarHood.bay_point(node), 0.7, REACH, "repair_car", "Чинить двигатель", id)

func start(id: String) -> void:
	if not can_start() or not game.rides.broken(id) or not cars().has(id):
		return
	owner = id
	elapsed = 0.0
	game.toast("Чиним гаечным ключом… F — бросить.")

func stop() -> void:
	owner = ""
	elapsed = 0.0

func target() -> Dictionary:
	return {"action": "repair_stop", "label": Loc.t("Ремонт %d%% · F — бросить") % int(progress() * 100)}

# One frame of the local job. Returns true while the fan stands at the bay.
func update(delta: float) -> bool:
	if not active():
		return false
	var node = cars().get(owner)
	if node == null or game.in_car or game.injuries.down or game.beers >= game.COLLAPSE_BEERS or game.walker.distance_to(CarHood.bay_point(node)) > REACH + 0.8:
		stop()
		return false
	if not game.rides.broken(owner):
		stop()
		game.toast("Машина уже на ходу.")
		return false
	elapsed += delta
	if elapsed < SECONDS:
		return true
	var point: Vector3 = CarHood.bay_point(node)
	var id = owner
	stop()
	if not game.room.submit("repair_car", {"pos": game.room.a(point)}):
		fix(id)
	game.toast("Готово, мотор ожил! Можно ехать." if id == me() else "Готово: машина друга снова на ходу.")
	return false

# Host or solo: mend the broken car whose bay is at `spot`, reached from `from`.
func fix_at(spot: Vector3, from: Vector3) -> bool:
	var all = cars()
	for id in all:
		var bay = CarHood.bay_point(all[id])
		if game.rides.broken(id) and bay.distance_to(spot) < 1.0 and from.distance_to(bay) <= REACH + 1.5:
			fix(id)
			return true
	return false

func fix(id: String) -> void:
	if id == me():
		game.condition = REPAIRED
	elif game.room.host_drives.has(id):
		game.room.host_drives[id].condition = REPAIRED

# Every frame: bonnets open over broken cars somebody stands at, and the
# spanner works on the cars being repaired, by this player or a friend.
func update_hoods(delta: float) -> void:
	var walkers: Array = []
	var repairers: Array = []
	if not game.in_car:
		walkers.append(game.walker)
		if active():
			repairers.append(game.walker)
	for peer in game.room.peers.values():
		var pos = _pos(peer.get("state"))
		if pos != Vector3.INF:
			walkers.append(pos)
			if bool(peer.state.get("repair", false)):
				repairers.append(pos)
	var all = cars()
	for id in all:
		var node: Node3D = all[id]
		var bay = CarHood.bay_point(node)
		var broken: bool = game.rides.broken(id)
		var open = false
		var working = id == owner
		if broken:
			for pos in walkers:
				open = open or pos.distance_to(bay) < OPEN_RADIUS
			for pos in repairers:
				working = working or pos.distance_to(bay) < REACH + 0.8
		CarHood.animate(node, open or working, delta)
		_work(node, working and CarHood.is_open(node), delta)

static func _pos(state) -> Vector3:
	if not state is Dictionary or bool(state.get("in_car", true)) or not state.get("pos") is Array or state.pos.size() != 3:
		return Vector3.INF
	return Vector3(float(state.pos[0]), float(state.pos[1]), float(state.pos[2]))

# The spanner over the bay: a blow every STRIKE seconds, BLOWS_PER_PART on
# each part in turn; a struck part shudders, sparks and clanks.
func _work(node: Node3D, working: bool, delta: float) -> void:
	var bay: Node3D = node.get_node_or_null("EngineBay")
	if bay == null:
		return
	var wrench: Node3D = bay.get_node("Wrench")
	for part in CarHood.TARGETS:
		var piece = bay.get_node_or_null(part)
		if piece != null:
			piece.scale = piece.scale.lerp(Vector3.ONE, 1.0 - exp(-delta * 14.0))
	wrench.visible = working
	if not working:
		node.set_meta("repair_clock", 0.0)
		return
	var before = float(node.get_meta("repair_clock", 0.0))
	var clock = before + delta
	node.set_meta("repair_clock", clock)
	var blow = int(floor(clock / STRIKE))
	var part: String = CarHood.TARGETS[(blow / BLOWS_PER_PART) % CarHood.TARGETS.size()]
	var phase = fposmod(clock, STRIKE) / STRIKE
	var angle = 0.0
	if phase < RAISE:
		angle = SWING * ease(phase / RAISE, -2.0)
	elif phase < HIT:
		angle = SWING * (1.0 - (phase - RAISE) / (HIT - RAISE))
	var point = CarHood.strike_point(bay, part)
	var grip = point + Vector3(0.08, 0.2, -0.32)
	wrench.position = grip
	wrench.basis = Basis.looking_at(point - grip, Vector3.UP) * Basis(Vector3.RIGHT, angle)
	# The blow lands when the phase passes HIT.
	var landed = int(floor((clock - HIT * STRIKE) / STRIKE)) > int(floor((before - HIT * STRIKE) / STRIKE))
	var spark: Node3D = wrench.get_node("Spark")
	spark.visible = fposmod(clock - HIT * STRIKE, STRIKE) < SPARK_SECONDS and phase >= HIT
	if landed:
		var piece = bay.get_node_or_null(part)
		if piece != null:
			piece.scale = Vector3(1.05, 0.9, 1.05)
		_clank(bay)

func _clank(bay: Node3D) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var sound: AudioStreamPlayer3D = bay.get_node_or_null("Clank")
	if sound == null:
		sound = SoundBank.spatial(bay, -6.0, 3.0, 40.0, "wrench-clank")
		sound.name = "Clank"
	sound.pitch_scale = randf_range(0.9, 1.12)
	sound.play()

# A friend at work: bent over the bay, the hand going up and down with the blows.
func draw_peer(peer: Dictionary, state: Dictionary) -> bool:
	return bool(state.get("repair", false)) and not bool(state.get("in_car", false)) and peer.avatar.visible
