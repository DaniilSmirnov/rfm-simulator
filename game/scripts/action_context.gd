extends RefCounted
# Who an action is performed for. The local player acts with their own state;
# when the host runs a guest's command it passes this context instead of
# temporarily overwriting the host's own walker, car and seat.
var owner = ""
var pos = Vector3.ZERO
var car = Vector3.ZERO
var heading = 0.0
var yaw = 0.0
var in_car = false
var beers = 0
var speed = 0.0
var variant = 0

static func from_command(c: Dictionary, actor: String, car_variant: int):
	var context = new()
	var state: Dictionary = c.get("state", {})
	context.owner = actor
	context.pos = _vec(state.get("pos", [0, 0, 0]))
	context.car = _vec(state.get("car", [0, 0, 0]))
	context.heading = float(state.get("heading", 0.0))
	context.yaw = float(state.get("yaw", 0.0))
	context.in_car = bool(state.get("in_car", false))
	context.beers = int(state.get("beers", 0))
	context.speed = float(state.get("speed", 0.0))
	context.variant = car_variant
	return context

static func _vec(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])

# Where the actor is: in the car or on foot.
func position() -> Vector3:
	return car if in_car else pos

# The trunk/cargo system keys its own context by owner and car pose.
func cargo_context(host_car: Vector3) -> Dictionary:
	return {"owner": owner, "car": car, "heading": heading, "variant": variant, "host_car": host_car, "speed": speed}
