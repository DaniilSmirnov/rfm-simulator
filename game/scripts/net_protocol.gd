extends RefCounted
# Room protocol constants, read from res://data/net_protocol.json. The Worker
# imports the same file, so the client and the server cannot drift apart.
const PATH = "res://data/net_protocol.json"
static var spec: Dictionary = _load()

static func _load() -> Dictionary:
	var text = FileAccess.get_file_as_string(PATH)
	var data = JSON.parse_string(text) if text != "" else null
	if not data is Dictionary:
		push_error("Room protocol is missing: " + PATH)
		return {"protocol_version": 0, "max_players": 8, "actions": [], "limits": {}, "durations": {}}
	return data

static func version() -> int:
	return int(spec.get("protocol_version", 0))

static func max_players() -> int:
	return int(spec.get("max_players", 8))

static func actions() -> Array:
	return spec.get("actions", [])

static func limit(name: String) -> int:
	return int(spec.get("limits", {}).get(name, 0))

static func duration(name: String) -> float:
	return float(spec.get("durations", {}).get(name, 0.0))

static func sync_interval() -> float:
	return float(spec.get("sync_interval", 0.1))

static func max_message_bytes() -> int:
	return int(spec.get("max_message_bytes", 65536))

static func name_input_length() -> int:
	return int(spec.get("name_input_length", 24))

# The Web template is built without the RegEx module, so the id is checked
# against the alphabet character by character.
static func valid_room_id(id: String) -> bool:
	if id.length() != room_id_length():
		return false
	var alphabet = str(spec.get("room_id_alphabet", "0123456789ABCDEF"))
	for character in id:
		if not alphabet.contains(character):
			return false
	return true

# Direct (WebRTC) link settings, see "direct" in net_protocol.json.
static func direct(key: String, fallback = null):
	return spec.get("direct", {}).get(key, fallback)

static func room_id_length() -> int:
	return int(spec.get("room_id_length", 6))

# ---------------------------------------------------------------- player state

static func _vec(value) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for n in value:
		if not (n is float or n is int) or not is_finite(float(n)) or absf(float(n)) >= 3000.0:
			return false
	return true

static func _number(value) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and absf(float(value)) < 100000.0

static func _requests(value, id_limit: int) -> Array:
	var result: Array = []
	if not value is Array:
		return result
	for request in value.slice(0, limit("object_requests_per_sync")):
		if request is Dictionary and _number(request.get("id")) and int(request.id) >= 0 and int(request.id) < id_limit and _vec(request.get("dir")):
			result.append({"id": int(request.id), "dir": request.dir})
	return result

# A member's state as the server accepts it (server/room-core.mjs, sync): the
# host applies the same checks to states that arrive over a direct link.
# Returns null for a malformed state.
static func clean_state(s):
	if not s is Dictionary or not _vec(s.get("pos")) or not _vec(s.get("car")) or not _number(s.get("heading")) or not _number(s.get("yaw")) or not _number(s.get("pitch")) or not s.get("in_car") is bool:
		return null
	var inputs: Array = []
	var raw_inputs = s.get("drive_inputs", [])
	if raw_inputs is Array:
		for c in raw_inputs.slice(0, limit("drive_inputs_per_sync")):
			if not c is Dictionary or not _number(c.get("seq")) or int(c.seq) <= 0 or not _number(c.get("ticks")) or int(c.ticks) < 1 or int(c.ticks) > limit("ticks_per_input"):
				continue
			if not _number(c.get("throttle")) or absf(float(c.throttle)) > 1.0 or not _number(c.get("steer")) or absf(float(c.steer)) > 1.0 or not c.get("brake") is bool:
				continue
			var command = {"seq": int(c.seq), "ticks": int(c.ticks), "throttle": float(c.throttle), "steer": float(c.steer), "brake": c.brake}
			if c.get("recover") == true:
				command.recover = true
			inputs.append(command)
	var in_car: bool = s.in_car
	var seated = s.get("seated") == true and not in_car
	var push = [0.0, 0.0, 0.0]
	if _vec(s.get("push")):
		push = [clampf(float(s.push[0]), -1, 1), 0.0, clampf(float(s.push[2]), -1, 1)]
	return {"drive_enabled": s.get("drive_enabled") == true, "drive_inputs": inputs, "pos": s.pos, "car": s.car, "heading": float(s.heading),
		"tilt": s.tilt if _vec(s.get("tilt")) else [0, s.heading, 0], "yaw": float(s.yaw), "pitch": float(s.pitch), "in_car": in_car,
		"tow": s.get("tow") == true and not in_car, "push": push, "speed": clampf(float(s.speed), -50, 50) if _number(s.get("speed")) else 0.0,
		"beers": clampi(int(s.beers), 0, 100000) if _number(s.get("beers")) else 0,
		"trees": _requests(s.get("trees"), 20000), "lamps": _requests(s.get("lamps"), 512),
		"seated": seated, "running": s.get("running") == true and not in_car and not seated, "airborne": s.get("airborne") == true and not in_car and not seated,
		"food_species": s.food_species if str(s.get("food_species", "")) in ["edible", "fly_agaric", "toadstool"] else "edible",
		"food_kind": s.food_kind if str(s.get("food_kind", "")) in ["meat", "mushroom", "berries", "plov"] else "meat",
		"eat": clampf(float(s.eat), -1, duration("eat")) if _number(s.get("eat")) else -1.0,
		"beer": clampf(float(s.get("beer", 0)), -1, duration("drink")) if _number(s.get("beer")) else 0.0}
