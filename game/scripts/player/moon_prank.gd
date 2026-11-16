extends RefCounted
# The player's mooning (mooning.gd): look at a rally crew coming, press F, and
# the fan turns round, bends over and drops his trousers for a few seconds.
# The pilot looks and the car has a moment (decided by the host for every
# member, from the state's "moon"); friends see the pose behind the censor
# mosaic (peer_view.gd).
const DURATION = 3.5
const REACH = 45.0

var game
var active = false
var time_left = 0.0

func can_start() -> bool:
	return not active and game.playing and not game.in_car and not game.seated and not game.injuries.down and game.beers < game.COLLAPSE_BEERS \
		and game.drink_time < 0 and game.eat_time < 0 and game.placement_kind == "" and not game.cargo.held.has(game.chair_owner()) \
		and not game.player.relief.active and not game.player.repair.active()

# Offered on a crew still racing within reach.
func offers(items: Array, interaction) -> void:
	if not can_start():
		return
	for racer in game.racers:
		if racer.state == "racing" and str(racer.get("role", "racer")) == "racer" and is_instance_valid(racer.node):
			interaction.offer(items, racer.node.position + Vector3(0, 0.8, 0), 1.8, REACH, "moon", "Показать зад экипажу")

func start() -> void:
	if not can_start():
		return
	active = true
	time_left = DURATION
	game.toast("Получай, экипаж!")

func stop() -> void:
	active = false

# One frame of the local session. Returns true while the fan stands still.
func update(delta: float) -> bool:
	if not active:
		return false
	if game.in_car or game.seated or game.injuries.down or game.beers >= game.COLLAPSE_BEERS or game.drink_time >= 0 or game.eat_time >= 0:
		stop()
		return false
	time_left -= delta
	if time_left <= 0.0:
		stop()
		return false
	return true
