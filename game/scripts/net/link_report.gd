extends RefCounted
# Tells the room server how a direct link ended, so how often links fail,
# on which networks, and whether a TURN relay carried them can be counted
# (server/link-report.mjs writes it to the Worker log). Sent once:
#   linked  the guest's link to the host opened during the join check;
#   failed  the join check gave up (reason: why, as in join_check.gd);
#   lost    a link that was open went quiet for good (room.gd).
# The candidate types say what each side could offer: host (own address),
# srflx (address seen through STUN), relay (a TURN relay). "pair" is the
# pair the link actually uses, where the platform can tell (native builds).

const Dedicated = preload("res://scripts/net/dedicated.gd")

const TYPES = ["host", "srflx", "prflx", "relay"]

# The candidate types in an SDP or a trickled candidate ("... typ srflx ...").
# No RegEx: the module is off in the web template.
static func candidate_types(text: String) -> Array:
	var types: Array = []
	var parts = text.split(" typ ")
	for i in range(1, parts.size()):
		var type = parts[i].replace("\r", " ").replace("\n", " ").get_slice(" ", 0)
		if type in TYPES and not type in types:
			types.append(type)
	return types

static func platform() -> String:
	if OS.has_feature("web"):
		return "web"
	return {"macOS": "macos", "Windows": "windows", "Linux": "linux", "Android": "android", "iOS": "ios"}.get(OS.get_name(), "other")

static func body(room, direct, id: String, result: String, reason: String, waited: float) -> Dictionary:
	var seen: Dictionary = direct.candidates.get(id, {"local": {}, "remote": {}})
	var link: Dictionary = direct.links.get(id, {})
	var pair = ""
	if link.get("pc") != null and link.pc.has_method("get_selected_pair"):
		pair = str(link.pc.get_selected_pair())
	var relays = direct.relay_ice.filter(func(server): return str(server.get("urls", [])).contains("turn"))
	return {"result": result, "reason": reason, "room": str(room.room_id), "role": "host" if room.is_host else "guest", "platform": platform(), "waited": snappedf(waited, 0.1), "attempts": int(link.get("attempts", 0)), "relays": relays.size(), "local": seen.local.keys(), "remote": seen.remote.keys(), "pair": pair}

# Sends the report and returns it ({} when nothing goes: a dedicated host).
static func send(room, direct, id: String, result: String, reason: String, waited: float) -> Dictionary:
	if room == null or room.transport == null or Dedicated.active():
		return {}
	var data = body(room, direct, id, result, reason, waited)
	print("ROOM_LINK_REPORT ", JSON.stringify(data))
	room.transport.post_once("/api/telemetry/link", data)
	return data
