extends RefCounted
# Steaming in the lake sauna of "Финский лес" (lake_sauna.gd). Inside the hut,
# F at the upper bench sits the fan on it facing the road window; while there,
# F at the stove throws water on the stones (a hiss and a cloud of steam), F
# anywhere else climbs down. The heat builds up: after a while the fan has to
# go out and cool off, and a proper session ends with "С лёгким паром!".
# Steaming sweats the beer sway out faster.
#
# Nothing new goes over the network: a member steams when the room state says
# they are seated inside the hut, so every client shows them on the bench and
# lights the steam and the chimney smoke from the same rule.
const Loc = preload("res://scripts/ui/loc.gd")
const STOVE_REACH = 2.8
const FULL_SESSION = 20.0
# Heat rises to 1.0 in about 75 s on the bench, faster with every ladle.
const HEAT_RATE = 1.0 / 75.0
const LADLE_HEAT = 0.12
const COOL_RATE = 1.0 / 30.0
const LADLE_SECONDS = 1.5
# The beer sway fades this many times faster on the bench.
const SWEAT = 4.0

var game
var steaming = false
var session = 0.0
var heat = 0.0
var ladle_clock = 0.0

func room():
	return game.stage.biome.get("lake_sauna") if game.stage != null and game.stage.biome != null else null

func inside(pos: Vector3) -> bool:
	var sauna = room()
	return sauna != null and sauna.contains(pos)

func can_start() -> bool:
	return not steaming and not game.in_car and not game.seated and not game.injuries.down and game.beers < 30 \
		and game.drink_time < 0 and game.eat_time < 0 and game.placement_kind == "" and not game.cargo.held.has(game.chair_owner()) \
		and game.jump_height <= 0.01 and inside(game.walker)

func offers(items: Array, interaction) -> void:
	if can_start():
		interaction.offer(items, room().bench_point(), 0.8, 2.6, "sauna", "Париться")

# What F does on the bench: the stove when looking at it, otherwise climb down.
func seated_target(interaction) -> Dictionary:
	var items: Array = []
	interaction.offer(items, room().stones(), 0.45, STOVE_REACH, "sauna_ladle", "Поддать пару")
	var target = interaction.select_target(items)
	return target if not target.is_empty() else {"action": "stand", "label": Loc.t("Слезть с полка")}

func start() -> void:
	if not can_start():
		return
	var sauna = room()
	game.seat_exit = game.walker
	game.walker = sauna.seat()
	game.view_yaw = sauna.seat_yaw()
	game.view_pitch = -0.08
	game.seated = true
	steaming = true
	session = 0.0
	game.toast("F на каменку — поддать пару. F — слезть с полка.")

func ladle() -> void:
	if not steaming or ladle_clock > 0.0:
		return
	ladle_clock = LADLE_SECONDS
	heat = minf(1.0, heat + LADLE_HEAT)
	room().loyly()

# Called by player_motion.stand_up(), whatever made the fan get up.
func leave() -> void:
	if not steaming:
		return
	steaming = false
	if heat >= 1.0:
		game.toast("Жарко! Пора окунуться в озеро.")
	elif session >= FULL_SESSION:
		game.toast("С лёгким паром!")

# Every frame, on every stage (nothing to do without the sauna).
func update(delta: float) -> void:
	var sauna = room()
	if sauna == null:
		return
	ladle_clock = maxf(0.0, ladle_clock - delta)
	if steaming and not game.seated:
		steaming = false
	if steaming:
		session += delta
		heat = minf(1.0, heat + HEAT_RATE * delta)
		game.drunk_strength = maxf(0.0, game.drunk_strength - delta * (SWEAT - 1.0) / game.DRUNK_FADE_SECONDS)
		if heat >= 1.0:
			game.stand_up()
	else:
		heat = maxf(0.0, heat - COOL_RATE * delta)
	sauna.update(steaming or occupied_by_peer(), game.camera.global_position if game.camera != null and game.camera.is_inside_tree() else game.walker)

func occupied_by_peer() -> bool:
	for peer in game.room.peers.values():
		var state: Dictionary = peer.get("state", {})
		if bool(state.get("seated", false)) and not bool(state.get("in_car", true)) and state.get("pos") is Array and state.pos.size() == 3:
			if inside(Vector3(float(state.pos[0]), float(state.pos[1]), float(state.pos[2]))):
				return true
	return false
