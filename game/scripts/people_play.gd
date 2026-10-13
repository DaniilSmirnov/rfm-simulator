extends RefCounted
# Playful falls share injury poses/replication, but never dispatch an ambulance.
# Car casualties keep their existing medical recovery rules.
const HEAD = 1.5
const REACH = 2.5
const HELP_SECONDS = 1.0
var _owner: WeakRef
var injuries:
	get:
		return _owner.get_ref() if _owner != null else null
	set(value):
		_owner = weakref(value)
var previous: Dictionary = {}
var grips: Dictionary = {}

func grabbed(key: String) -> bool:
	for grip in grips.values():
		if grip.key == key:
			return true
	return false

# Swept feet crossing the shoulders from above, never a side bump or ascent.
func landing(actor: String, start: Vector3, end: Vector3) -> bool:
	if not injuries.authority() or injuries.is_down(actor) or end.y >= start.y:
		return false
	for person in injuries.people():
		if person.key == actor or injuries.is_down(person.key):
			continue
		var top: float = person.pos.y + HEAD
		if start.y < top or end.y > top:
			continue
		var at = start.lerp(end, (start.y - top) / (start.y - end.y))
		if Vector2(at.x - person.pos.x, at.z - person.pos.z).length() <= 0.48:
			return injuries.knock(person.key, person.pos, Vector3.ZERO, start, true)
	return false

func stand(key: String) -> bool:
	if not injuries.authority():
		return false
	var r: Dictionary = injuries.records.get(key, {})
	if not r.get("play", false) or r.get("phase", "") != "lying":
		return false
	injuries._stand(key, r)
	if key.begins_with("player:"):
		# Keep one healthy limp snapshot so guests receive the final position.
		r.limp = 0.1
		if key == injuries.local_key():
			injuries.limp = 0.0
			injuries.game.toast("Ты снова на ногах.")
	for id in grips.keys():
		if grips[id].key == key:
			grips.erase(id)
	return true

func nearest(pos: Vector3, actor: String = "") -> String:
	var best = REACH
	var found = ""
	var source: Dictionary = injuries.records if injuries.authority() else injuries.targets
	for key in source:
		var r: Dictionary = source[key]
		if key == actor or r.get("phase", "") != "lying":
			continue
		var at: Vector3 = r.pos if injuries.authority() else injuries.game.room.v(r.pos)
		var distance = pos.distance_to(at)
		if distance < best:
			best = distance
			found = key
	return found

func update(players: Dictionary, delta: float) -> Dictionary:
	var occupied: Dictionary = {}
	if not injuries.authority():
		return occupied
	var game = injuries.game
	for id in grips.keys():
		if not players.has(id):
			grips.erase(id)
	for id in previous.keys():
		if not players.has(id):
			previous.erase(id)
	for raw_id in players:
		var id = str(raw_id)
		var p: Dictionary = players[raw_id]
		var pos: Vector3 = game.room.v(p.pos)
		var actor = "player:" + id
		if previous.has(id) and not p.get("in_car", true) and not p.get("seated", false):
			var before: Dictionary = previous[id]
			if before.airborne and before.pos.distance_to(pos) < 5.0:
				landing(actor, before.pos, pos)
		previous[id] = {"pos": pos, "airborne": p.get("airborne", false)}
		if not p.get("tow", false) or p.get("in_car", true) or p.get("seated", false) or p.get("airborne", false) or int(p.get("beers", 0)) >= 30 or injuries.is_down(actor) or game.cargo.held.has(id):
			grips.erase(id)
			continue
		if not grips.has(id):
			var key = nearest(pos, actor)
			if key == "" or grabbed(key):
				continue
			grips[id] = {"key": key, "help": 0.0, "last": pos}
		var grip: Dictionary = grips[id]
		var r: Dictionary = injuries.records.get(grip.key, {})
		if r.get("phase", "") != "lying" or pos.distance_to(r.pos) > REACH + 1.0:
			grips.erase(id)
			continue
		occupied[id] = true
		var moving = pos.distance_to(grip.last) > 0.002 or game.room.v(p.get("push", [0, 0, 0])).length() > 0.1
		grip.last = pos
		if moving:
			grip.help = 0.0
			var offset: Vector3 = pos - r.pos
			offset.y = 0.0
			var next: Vector3 = r.pos + offset.normalized() * minf(maxf(0.0, offset.length() - 0.9), 4.0 * delta)
			next = injuries._clear_spot(next, r.pos)
			next.y = game.stage.ground(next) + 0.25
			if game.stage.solids.hit(r.pos, next, 0.35).is_empty() and game.stage.rock_hit(r.pos, next, 0.35).is_empty() and game.stage.obstacle_hit(r.pos, next, 0.35, true) < 0:
				r.pos = next
				r.station = game.race_station(next)
				if not r.get("play", false):
					injuries._retarget_all()
				r.time = 0.0
				injuries._pose(grip.key, r.pos, r.rot, 1.0)
		elif r.get("play", false):
			grip.help += delta
			if grip.help >= HELP_SECONDS:
				stand(grip.key)
	return occupied
