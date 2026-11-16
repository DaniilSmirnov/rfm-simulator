extends RefCounted
# Mooning a rally crew, after a real marshal on the 2017 Solway Coast Rally who
# showed his backside to a passing crew (and got six months and a £1000 fine
# for it). A fan turns his back to the road, bends over and drops his
# trousers, a censor mosaic over the result (CharacterRig "moon"). The pilot
# of a crew driving at him looks, and the car has a "moment" (the tail steps
# out, rally_mistakes.gd); every crew falls for each fan only once.
#
# Camp spectators who are pranksters do it now and then instead of cheering
# (spectators.gd); a player does it by looking at an approaching crew and
# pressing F (moon_prank.gd). The host checks both every frame (scare()).
const RallyDriver = preload("res://scripts/traffic/rally_driver.gd")
const Mistakes = preload("res://scripts/traffic/rally_mistakes.gd")
# A fan is seen from this far (m), and only in front of the car.
const REACH = 22.0
const AHEAD = 3.0
# One in PRANKSTERS camp spectators moons, at about half the crews.
const PRANKSTERS = 4
const CHANCE = 0.5
# Seconds a camp prankster stays bent over before he stands up and cheers.
const TIME = 4.0

# Whether camp spectator `id` moons the crew `racer_id` driving past.
static func prankster(id: int, variant: int, racer_id: int) -> bool:
	return posmod(id * 7 + variant * 3, PRANKSTERS) == 0 and Mistakes.roll(id, racer_id + 0.5) < CHANCE

# Host only. `mooners` are {"key", "pos"} of everyone mooning right now.
# Returns the {"key", "racer"} pairs that scared a crew this frame.
static func scare(game, mooners: Array) -> Array:
	var scared: Array = []
	if mooners.is_empty():
		return scared
	for racer in game.racers:
		if racer.state != "racing" or str(racer.get("role", "racer")) != "racer" or not RallyDriver.applies(racer) or not racer.get("mistake", {}).is_empty() or not is_instance_valid(racer.node):
			continue
		var node: Node3D = racer.node
		var forward: Vector3 = -node.basis.z
		var right: Vector3 = node.basis.x
		var seen: Dictionary = racer.get("mooned", {})
		for mooner in mooners:
			if seen.has(mooner.key):
				continue
			var offset: Vector3 = mooner.pos - node.position
			offset.y = 0.0
			if offset.length() > REACH or offset.dot(forward) < AHEAD:
				continue
			seen[mooner.key] = true
			racer.mooned = seen
			# The pilot looks towards the fan: the tail steps out the other way.
			Mistakes.start(racer, "moment", 1.0 if offset.dot(right) < 0.0 else -1.0)
			scared.append({"key": mooner.key, "racer": racer})
			break
	return scared

# Players mooning right now: this one and room friends whose state says so.
static func players(game) -> Array:
	var result: Array = []
	if game.room == null or game.player == null:
		return result # still being built
	if game.player.moon.active:
		result.append({"key": game.injuries.local_key(), "pos": game.walker})
	for peer in game.room.peers.values():
		var state = peer.get("state")
		if state is Dictionary and bool(state.get("moon", false)) and not bool(state.get("in_car", false)) and peer.has("avatar"):
			result.append({"key": "player:%s" % peer.id, "pos": peer.avatar.position})
	return result
