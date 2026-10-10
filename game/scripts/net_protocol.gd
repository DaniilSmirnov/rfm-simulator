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

static func valid_room_id(id: String) -> bool:
	var pattern = RegEx.create_from_string(str(spec.get("room_id_pattern", "^[A-F0-9]{6}$")))
	return pattern.search(id) != null

static func room_id_length() -> int:
	return int(spec.get("room_id_length", 6))
