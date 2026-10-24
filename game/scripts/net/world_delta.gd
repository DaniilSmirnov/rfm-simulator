extends RefCounted
# The hot world as per-guest deltas (direct_link.gd "w").
#
# The host splits the hot world by provider ("parts") and sends a part only
# while the guest has not confirmed a packet with its current value: a guest's
# state packets name the newest world it applied ("wa"), and a part that
# changed after that rides every packet until then. The channel drops and
# reorders packets, so nothing waits for a resend, and a whole world goes every
# FULL_EVERY in case a guest lost what it held.
#
# Rally crews are tracked one by one; a crew farther than FAR from the guest
# is refreshed at most every FAR_INTERVAL and sent at most FAR_SENDS times. The packet names the parts it
# carries ("parts") and every crew on the stage ("crews"), so a part that
# became empty and a crew that left are both said.

const FULL_EVERY = 2.0
const FAR = 150.0
const FAR_INTERVAL = 0.5
const FAR_SENDS = 2

# Host, once a tick: each hot provider's part of `hot` with its hash (the
# engine's deep hash: equal values hash alike, like the JSON they become). The
# crews hash on their own; the racers part's hash covers the rest and the ids.
static func parts(hot: Dictionary, providers: Array) -> Dictionary:
	var result = {}
	for p in providers:
		if p.section != "":
			continue
		var part = {}
		for key in p.keys:
			if hot.has(key):
				part[key] = hot[key]
		if p.name != "racers":
			result[p.name] = {"part": part, "hash": part.hash()}
			continue
		var crews = {}
		var ids = []
		for entry in part.get("racers", []):
			crews[key(entry.id)] = {"entry": entry, "hash": entry.hash()}
			ids.append(entry.id)
		var rest = part.duplicate()
		rest.erase("racers")
		result[p.name] = {"part": rest, "hash": [rest, ids].hash(), "crews": crews, "ids": ids}
	return result

# Host: the "w" message for one link from the full `message` (world_packet())
# and this tick's `current` parts. `guest_pos` is where the guest is (null:
# unknown, every crew counts as near). The link keeps what was sent ("delta").
static func packet(link: Dictionary, message: Dictionary, current: Dictionary, guest_pos) -> Dictionary:
	var now_ms = int(message.time)
	if not link.has("delta") or now_ms < float(link.delta.full_at):
		link.delta = {"full_at": -INF, "parts": {}, "crews": {}}
	var state: Dictionary = link.delta
	var acked = int(link.get("acked", -1))
	var full = now_ms - float(state.full_at) >= FULL_EVERY * 1000.0
	if full:
		state.full_at = now_ms
	var world = {}
	var names = []
	for name in current:
		var c: Dictionary = current[name]
		var tracked = state.parts.get(name)
		if tracked == null or tracked.hash != c.hash:
			tracked = {"hash": c.hash, "at": now_ms}
			state.parts[name] = tracked
		if not c.has("crews"):
			if full or int(tracked.at) > acked:
				names.append(name)
				world.merge(c.part, true)
			continue
		var crews: Array = _crews(state, c, now_ms, acked, full, guest_pos)
		if full or int(tracked.at) > acked or not crews.is_empty():
			names.append(name)
			world.merge(c.part, true)
			world.racers = crews
	var result = message.duplicate()
	result.world = world
	result.parts = names
	if names.has("racers"):
		result.crews = current.racers.ids
	if full:
		result.full = true
	return result

static func _crews(state: Dictionary, c: Dictionary, now_ms: int, acked: int, full: bool, guest_pos) -> Array:
	var sending = []
	var known: Dictionary = state.crews
	for id in known.keys():
		if not c.crews.has(id):
			known.erase(id)
	for id in c.crews:
		var crew: Dictionary = c.crews[id]
		var tracked = known.get(id)
		var far = guest_pos is Array and guest_pos.size() == 3 and _distance(crew.entry.pos, guest_pos) > FAR
		if tracked == null or (tracked.hash != crew.hash and (not far or now_ms - int(tracked.at) >= FAR_INTERVAL * 1000.0)):
			tracked = {"hash": crew.hash, "at": now_ms, "sent": 0}
			known[id] = tracked
		# A far crew's refresh goes FAR_SENDS times at most: one that got lost
		# waits for the next refresh, half a second later.
		if full or (int(tracked.at) > acked and (not far or int(tracked.sent) < FAR_SENDS)):
			tracked.sent = int(tracked.sent) + 1
			sending.append(crew.entry)
	return sending

# A crew id as a dictionary key: 3 and 3.0 (from JSON) are the same crew.
static func key(id) -> String:
	return str(int(id)) if (id is float or id is int) and float(id) == floorf(float(id)) else str(id)

static func _distance(a: Array, b: Array) -> float:
	return Vector3(float(a[0]), float(a[1]), float(a[2])).distance_to(Vector3(float(b[0]), float(b[1]), float(b[2])))

# Guest: whether a "w" message's delta fields are well formed. A message
# without "parts" is a whole world.
static func valid(message: Dictionary) -> bool:
	if not message.has("parts"):
		return true
	if not message.parts is Array or message.parts.size() > 64:
		return false
	for name in message.parts:
		if not name is String:
			return false
	if message.parts.has("racers") and not (message.get("crews") is Array and message.crews.size() <= 256):
		return false
	return true

# Guest: merges a "w" message into `base` (what it holds, by provider) and
# returns the whole hot world, the providers that changed (null: all) and the
# crews that arrived (null: all).
static func merge(base: Dictionary, message: Dictionary, providers: Array) -> Dictionary:
	var world: Dictionary = message.world
	if not message.has("parts"):
		base.clear()
		return {"world": world, "changed": null, "crews": null}
	if message.get("full", false) == true or base.is_empty():
		base.parts = {}
		base.crews = {}
	var changed = {}
	var fresh = {}
	for p in providers:
		if p.section != "" or not message.parts.has(p.name):
			continue
		var part = {}
		for key in p.keys:
			if world.has(key):
				part[key] = world[key]
		if p.name == "racers":
			part.racers = _merge_crews(base, part.get("racers", []), message.crews, fresh)
		base.parts[p.name] = part
		changed[p.name] = true
	var merged = {}
	for name in base.parts:
		merged.merge(base.parts[name], true)
	return {"world": merged, "changed": changed, "crews": fresh}

static func _merge_crews(base: Dictionary, arrived: Array, ids: Array, fresh: Dictionary) -> Array:
	for entry in arrived:
		if entry is Dictionary and entry.has("id"):
			base.crews[key(entry.id)] = entry
			fresh[key(entry.id)] = true
	var kept = {}
	var result = []
	for id in ids:
		var entry = base.crews.get(key(id))
		if entry != null:
			kept[key(id)] = entry
			result.append(entry)
	base.crews = kept
	return result
