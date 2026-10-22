extends RefCounted
# Who drives a crew and how it goes wrong. Every competitor gets a class (a
# leader, the midfield or an amateur) that sets its pace, its skill (the
# assist in rally_driver.gd), how much it hangs the tail out and how often it
# errs. Zero cars are quick but tidy and never err.
#
# Mistakes are short spells the physics then plays out: braking late into a
# bend, a "moment" when the tail steps out, or a lapse that puts the car off
# into the ditch. A car that leaves the road goes through the usual departure
# and, unless it is stuck, drives back on (rally_rejoin.gd).

# Class shares of the field and their settings: pace range, assist (g), tail
# angle held at the limit (rad), slide caught past (rad), mistakes per km.
const CLASSES = {
	"leader": {"share": 0.2, "pace": Vector2(1.03, 1.07), "assist": 1.3, "drift": Vector2(0.35, 0.5), "max_slip": 0.5, "rate": 0.25},
	"midfield": {"share": 0.5, "pace": Vector2(0.97, 1.02), "assist": 1.0, "drift": Vector2(0.25, 0.5), "max_slip": 0.5, "rate": 0.6},
	"amateur": {"share": 0.3, "pace": Vector2(0.88, 0.95), "assist": 0.75, "drift": Vector2(0.15, 0.45), "max_slip": 0.6, "rate": 1.2},
}
const ZERO = {"pace": 1.0, "assist": 1.6, "drift": 0.2, "max_slip": 0.3, "rate": 0.0}
# What each mistake does while it lasts: seconds, speed carried over the plan,
# share of the assist left and a yaw kick (rad/s) at its start.
const KINDS = {
	"late_brake": {"time": 2.0, "over": 1.22, "assist": 0.5, "kick": 0.0},
	"moment": {"time": 0.7, "over": 1.05, "assist": 0.15, "kick": 1.4},
	"excursion": {"time": 1.6, "over": 1.3, "assist": 0.0, "kick": 0.6},
}
# How fast (rad/s²) a mistake's yaw kick builds up.
const KICK_RATE = 6.0
# A crew bound to crash or get stuck in front of the player makes its mistake
# this many metres before the spot; the old scripted departure still follows
# at the spot itself if the car is somehow still on the road.
const FOCUS_LEAD = 25.0
# Mistakes wait for a bend at least this sharp (rad over BEND_SPAN metres) and
# stay off the first metres of the stage.
const BEND = 0.25
const BEND_SPAN = 15.0
const CALM_START = 60.0

static func roll(id: int, salt: float) -> float:
	return fposmod(sin(id * 12.9898 + salt * 78.233) * 43758.5453, 1.0)

static func driver_class(id: int) -> String:
	var h = roll(id, 3.1)
	if h < CLASSES.leader.share:
		return "leader"
	return "midfield" if h < CLASSES.leader.share + CLASSES.midfield.share else "amateur"

# The driver of crew `id` ("racer" or "zero"): class, pace, assist, drift,
# max_slip and mistakes per km.
static func personality(id: int, role: String) -> Dictionary:
	if role == "zero":
		var zero = ZERO.duplicate()
		zero.class = "zero"
		return zero
	var name = driver_class(id)
	var c: Dictionary = CLASSES[name]
	return {"class": name, "pace": lerpf(c.pace.x, c.pace.y, roll(id, 5.7)), "assist": c.assist, "drift": lerpf(c.drift.x, c.drift.y, roll(id, 9.2)), "max_slip": c.max_slip, "rate": c.rate}

static func apply(racer: Dictionary) -> void:
	var driver = personality(int(racer.id), str(racer.get("role", "racer")))
	for key in ["class", "pace", "assist", "drift", "max_slip"]:
		racer[key] = driver[key]
	racer.mistake_rate = driver.rate
	racer.next_mistake = next_station(racer, float(racer.get("s", 0.0)))

# Mistakes come as a Poisson process along the road: the next one waits an
# exponential distance with mean 1000 / rate metres.
static func next_station(racer: Dictionary, s: float) -> float:
	var rate = float(racer.get("mistake_rate", 0.0))
	if rate <= 0.0:
		return INF
	var u = maxf(roll(int(racer.id), s + 0.37), 0.001)
	return s + maxf(CALM_START, -log(u) * 1000.0 / rate)

static func start(racer: Dictionary, kind: String, bend: float) -> void:
	var spec: Dictionary = KINDS[kind]
	# The tail steps out of the bend: the car rotates further into the turn.
	var kick = -signf(bend) * float(spec.kick) if bend != 0.0 else float(spec.kick)
	racer.mistake = {"kind": kind, "left": float(spec.time), "kick": kick}

# Called each frame before the driver acts. `bend` is the signed turn of the
# road ahead (rad over BEND_SPAN m, positive to the left). Returns the share
# of the planned speed the driver carries and sets racer.assist_share.
static func update(racer: Dictionary, s: float, bend: float, avoiding: bool, delta: float) -> float:
	var mistake: Dictionary = racer.get("mistake", {})
	if mistake.is_empty():
		var calm = avoiding or s < CALM_START
		var due = racer.get("kind", "pass") != "pass" and s >= float(racer.get("focus", INF)) - FOCUS_LEAD and not racer.get("focus_mistake", false)
		if due and not calm:
			racer.focus_mistake = true
			start(racer, "excursion", bend)
		elif not calm and s >= float(racer.get("next_mistake", INF)) and absf(bend) >= BEND:
			var h = roll(int(racer.id), s)
			start(racer, "excursion" if h < 0.15 else ("moment" if h < 0.6 else "late_brake"), bend)
			racer.next_mistake = next_station(racer, s)
		mistake = racer.get("mistake", {})
	if mistake.is_empty():
		racer.assist_share = 1.0
		return 1.0
	var spec: Dictionary = KINDS[mistake.kind]
	# The kick builds over a few frames rather than in one jump.
	var kick = clampf(float(mistake.kick), -KICK_RATE * delta, KICK_RATE * delta)
	racer.motion.handling.yaw_rate += kick
	mistake.kick = float(mistake.kick) - kick
	mistake.left = float(mistake.left) - delta
	if mistake.left <= 0.0:
		racer.erase("mistake")
	racer.assist_share = float(spec.assist)
	return float(spec.over)
