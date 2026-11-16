extends RefCounted
# Watching the northern lights (core/aurora.gd): while they glow, a fan on foot
# who looks up at the sky can press F to lean far back, head tipped up, and
# watch them. The view rises to the sky and sinks back with the body; any step,
# a jump or F again ends it, and so does the display fading out.
# Friends in a room see the pose: the replicated view pitch goes past what the
# mouse allows (game.gd, 1.1 rad) only while gazing, and peer_view.gd leans the
# avatar back by gaze_of(pitch).
const Loc = preload("res://scripts/ui/loc.gd")
# Looking at least this high up offers the action; the lights must be at least
# this bright.
const LOOK_UP = 0.45
const MIN_LEVEL = 0.25
# The view while gazing (rad above the horizon) and the highest pitch the
# mouse gives without gazing (game.gd).
const GAZE_PITCH = 1.2
const FREE_PITCH = 1.1
# Seconds to lean back fully, and how far the eyes sink and go back (m).
const EASE = 1.4
const EYE_DROP = 0.16
const EYE_BACK = 0.32

var game
var active = false
var lean = 0.0

func can_start() -> bool:
	return not active and game.sky_weather.aurora.level >= MIN_LEVEL and game.view_pitch >= LOOK_UP and not game.in_car and not game.seated \
		and not game.injuries.down and game.beers < game.COLLAPSE_BEERS and game.drink_time < 0 and game.eat_time < 0 and game.placement_kind == "" \
		and not game.player.relief.active and not game.player.moon.active and not game.player.repair.active() and game.jump_height <= 0.01 and not game.cargo.held.has(game.chair_owner())

# The sky itself is the target: offered when nothing nearer is in view.
func offer() -> Dictionary:
	return {"action": "stargaze", "label": Loc.t("Смотреть на сияние")} if can_start() else {}

func start() -> void:
	if can_start():
		active = true

# The free view takes over where the gaze left it, not with a jump.
func stop() -> void:
	if active:
		game.view_pitch = minf(pitch(), FREE_PITCH)
	active = false

# One frame on foot; true while the fan stands gazing.
func update(delta: float) -> bool:
	if active and (_moving() or game.in_car or game.seated or game.injuries.down or game.beers >= game.COLLAPSE_BEERS or game.drink_time >= 0 \
			or game.eat_time >= 0 or game.jump_height > 0.01 or game.sky_weather.aurora.level <= 0.0):
		stop()
	lean = move_toward(lean, 1.0 if active else 0.0, delta / EASE)
	return active

static func _moving() -> bool:
	return Vector2(Input.get_axis("left", "right"), Input.get_axis("forward", "back")).length() > 0.2 or Input.is_action_just_pressed("jump")

func amount() -> float:
	return smoothstep(0.0, 1.0, lean)

# The view pitch the camera uses and friends receive.
func pitch() -> float:
	return lerpf(game.view_pitch, GAZE_PITCH, amount())

# Eyes go down and back as the body arches.
func eye_offset() -> Vector3:
	var back = Vector3(sin(game.view_yaw), 0, cos(game.view_yaw))
	return (back * EYE_BACK + Vector3.DOWN * EYE_DROP) * amount()

func target() -> Dictionary:
	return {"action": "stargaze_stop", "label": Loc.t("Хватит смотреть")}

# How far a friend leans back, from the pitch they sent.
static func gaze_of(friend_pitch: float) -> float:
	return clampf((friend_pitch - FREE_PITCH - 0.01) / (GAZE_PITCH - FREE_PITCH - 0.01), 0.0, 1.0)
