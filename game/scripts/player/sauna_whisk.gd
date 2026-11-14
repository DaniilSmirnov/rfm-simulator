extends RefCounted
# Birch whisk (веник) in the lake sauna: inside the hut, F at a friend who is
# in there too (standing or on a bench) gives them a good whisking for a few
# seconds. The whisker's room state carries "venik" while it lasts, so every
# client swings a whisk in their hand; the friend's own client sees a whisker
# facing them within reach and feels it: a notice, a jolt and more heat.
const Furniture = preload("res://scripts/stages/finnish_forest/sauna_furniture.gd")
const REACH = 2.0
const SECONDS = 2.4
# A whisker this close and turned this much towards someone is whisking them.
const HIT_DISTANCE = 1.8
const HIT_FACING = 0.4
const HEAT = 0.1
const SWING_RATE = 12.0

var steam
var time_left = 0.0
var held: Node3D
var felt: Dictionary = {}

func whipping() -> bool:
	return time_left > 0.0

func can_start() -> bool:
	var game = steam.game
	return not whipping() and not game.in_car and not game.injuries.down and game.beers < 30 and game.drink_time < 0 and game.eat_time < 0 \
		and game.placement_kind == "" and not game.cargo.held.has(game.chair_owner()) and steam.inside(game.walker)

# Friends inside the sauna, aimed at by the body.
func offers(items: Array, interaction) -> void:
	if not can_start():
		return
	for peer in steam.game.room.peers.values():
		var pos = _pos(peer.get("state"))
		if pos != Vector3.INF and steam.inside(pos):
			interaction.offer(items, pos + Vector3(0, 0.9, 0), 0.55, REACH, "venik", "Попарить веником", str(peer.get("id", "")))

func start() -> void:
	if can_start():
		time_left = SECONDS

static func _pos(state) -> Vector3:
	if not state is Dictionary or bool(state.get("in_car", true)) or not state.get("pos") is Array or state.pos.size() != 3:
		return Vector3.INF
	return Vector3(float(state.pos[0]), float(state.pos[1]), float(state.pos[2]))

func update(delta: float) -> void:
	var game = steam.game
	time_left = maxf(0.0, time_left - delta)
	_show_held(game)
	var me = game.walker
	if game.in_car or not steam.inside(me):
		felt.clear()
		return
	for peer in game.room.peers.values():
		var id = str(peer.get("id", ""))
		var state = peer.get("state")
		var whisking = state is Dictionary and bool(state.get("venik", false)) and _facing(_pos(state), float(state.get("yaw", 0.0)), me)
		if whisking and not felt.get(id, false):
			game.toast("Тебя парят веником! Ух, хорошо!")
			steam.heat = minf(0.95, steam.heat + HEAT)
			game.impact_shake = maxf(game.impact_shake, 0.2)
		felt[id] = whisking

func _facing(from: Vector3, yaw: float, target: Vector3) -> bool:
	if from == Vector3.INF or not steam.inside(from):
		return false
	var to = Vector3(target.x - from.x, 0, target.z - from.z)
	if to.length() > HIT_DISTANCE or to.length() < 0.01:
		return to.length() < 0.01
	return Vector3(-sin(yaw), 0, -cos(yaw)).dot(to.normalized()) > HIT_FACING

# The own whisk, swinging in front of the camera.
func _show_held(game) -> void:
	if held == null:
		if not whipping() or game.camera == null:
			return
		held = Furniture.whisk(game.camera, Vector3(0.28, -0.32, -0.62), 0.0)
	held.visible = whipping()
	if held.visible:
		held.rotation.x = -0.9 + 0.8 * sin(Time.get_ticks_msec() / 1000.0 * SWING_RATE)

# A friend's whisk in their hand. True while they are whisking.
func draw_peer(peer: Dictionary, state: Dictionary) -> bool:
	var on = bool(state.get("venik", false)) and not state.in_car and peer.avatar.visible
	if on and not peer.has("venik"):
		peer.venik = Furniture.whisk(peer.arm, Vector3(0, -0.3, -0.05), PI)
	if peer.has("venik"):
		peer.venik.visible = on
	return on
