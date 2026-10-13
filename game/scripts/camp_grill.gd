extends RefCounted
# The player's grill, from cold iron to a skewer in hand. It comes out of the
# trunk empty and unlit: light it (F), wait for the flames to burn down to
# coals, lay out the skewers and wait for the meat. Mushrooms go on the same
# grate whenever a slot is free. `meat_time` is the meat's own clock and stays
# below zero while the grate holds no skewers.
const Props = preload("res://scripts/props.gd")
const GrillModel = preload("res://scripts/grill_model.gd")
const Loc = preload("res://scripts/loc.gd")
const COALS_SECONDS = 20.0
const MEAT_SECONDS = 35.0
const REACH = 4.0

var game
var lit = false
var fire_time = 0.0
var meat_time = -1.0
var servings = 0

func reset() -> void:
	lit = false
	fire_time = 0.0
	meat_time = -1.0
	servings = 0
	Props.set_grill_servings(game.grill, 0)

func coals() -> bool:
	return lit and fire_time >= COALS_SECONDS

func loaded() -> bool:
	return meat_time >= 0.0 and servings > 0

func ready() -> bool:
	return loaded() and meat_time >= MEAT_SECONDS

# none, unlit, flaring, coals (hot and empty), cooking, ready.
func phase() -> String:
	if game.grill == null:
		return "none"
	if not lit:
		return "unlit"
	if not coals():
		return "flaring"
	if not loaded():
		return "coals"
	return "ready" if ready() else "cooking"

func mushroom_count() -> int:
	return game.foraging.skewers.get("-1", []).size()

func free_slots() -> int:
	if game.grill == null:
		return 0
	return maxi(0, Props.FOOD_PORTIONS - servings - mushroom_count())

func _can_act() -> bool:
	return game.playing and not game.actor_in_car() and not game.paused and not game.dead and not game.finished \
		and game.actor_beers() < 30 and not game.packing.active() and not game.cargo.held.has(game.cargo.actor())

func near() -> bool:
	return game.grill != null and game.actor_position().distance_to(game.grill.position) <= REACH

func can_light() -> bool:
	return game.grill != null and not lit and _can_act() and near()

func light() -> bool:
	if not can_light():
		return false
	if game.room.submit("light_grill"):
		return true
	lit = true
	fire_time = 0.0
	if game.soundscape != null:
		game.soundscape.placement()
	game.toast("Мангал разожжён. Дождись, пока угли прогорят.")
	return true

func can_load() -> bool:
	return phase() == "coals" and free_slots() > 0 and _can_act() and near()

func load_meat() -> bool:
	if not can_load():
		return false
	if game.room.submit("load_meat"):
		return true
	servings = free_slots()
	meat_time = 0.0
	Props.set_grill_servings(game.grill, servings)
	game.toast(Loc.t("Шампуры на углях. Шашлык будет готов через %d секунд.") % int(MEAT_SECONDS))
	return true

# One skewer leaves the grate; an empty grate goes back to bare coals so the
# next batch can be laid out.
func take_serving() -> bool:
	if not ready():
		return false
	servings -= 1
	Props.set_grill_servings(game.grill, servings)
	if servings <= 0:
		meat_time = -1.0
	return true

func update(delta: float) -> void:
	if game.grill == null:
		return
	if lit and fire_time < COALS_SECONDS:
		fire_time = minf(COALS_SECONDS, fire_time + delta)
		if fire_time >= COALS_SECONDS:
			game.toast("Угли прогорели. Выложи шампуры: F у мангала.")
	if loaded() and meat_time < MEAT_SECONDS:
		meat_time = minf(MEAT_SECONDS, meat_time + delta)
		if meat_time >= MEAT_SECONDS:
			game.toast("Шашлык готов! Подойди к мангалу и нажми F.")

# Flames climb as the wood catches and sink as it turns to coals.
func flame_height() -> float:
	if not lit or fire_time >= COALS_SECONDS:
		return 0.0
	return clampf(smoothstep(0.0, 2.0, fire_time) - smoothstep(COALS_SECONDS * 0.6, COALS_SECONDS, fire_time), 0.0, 1.0)

func animate(visual_time: float) -> void:
	if game.grill == null:
		return
	GrillModel.set_fire(game.grill, clampf(fire_time / 3.0, 0.0, 1.0) if lit else 0.0, flame_height(), visual_time)
	if game.smoke != null:
		game.smoke.emitting = lit

# How far along the current wait is: the coals burning through, or the meat.
func progress() -> float:
	match phase():
		"flaring":
			return fire_time / COALS_SECONDS
		"cooking":
			return meat_time / MEAT_SECONDS
	return 0.0

# One line for the HUD: cold, burning down, waiting for skewers or roasting.
func status(short: bool) -> String:
	match phase():
		"unlit":
			return Loc.t("НЕТ ОГНЯ") if short else Loc.t("МАНГАЛ НЕ РАЗОЖЖЁН")
		"flaring":
			return Loc.t("УГЛИ %d%%") % int(progress() * 100)
		"coals":
			return Loc.t("УГЛИ ГОТОВЫ") if short else Loc.t("УГЛИ ГОТОВЫ · ВЫЛОЖИ ШАМПУРЫ")
		"cooking":
			return Loc.t("ШАШЛЫК %d%%") % int(progress() * 100)
		"ready":
			return Loc.t("ШАШЛЫК ГОТОВ")
	return Loc.t("БЕЗ МАНГАЛА") if short else Loc.t("МАНГАЛ НЕ ПОСТАВЛЕН")

func snapshot() -> Dictionary:
	return {"lit": lit, "fire": snappedf(fire_time, 0.01)}

func apply_snapshot(data: Dictionary) -> void:
	lit = bool(data.get("lit", false))
	fire_time = clampf(float(data.get("fire", 0.0)), 0.0, COALS_SECONDS)
