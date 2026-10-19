extends RefCounted
# Sound files of res://audio by name. scripts/generate-sounds.mjs renders most
# of them (engines, tyres, doors, steps…); each stream loads once and every
# player node shares it.
static var streams: Dictionary = {}

static func stream(sound: String) -> AudioStream:
	if not streams.has(sound):
		streams[sound] = load("res://audio/%s.wav" % sound)
	return streams[sound]

# One of the numbered takes `sound-1` … `sound-count`.
static func take(sound: String, count: int, rng: RandomNumberGenerator) -> AudioStream:
	return stream("%s-%d" % [sound, rng.randi_range(1, count)])

static func player(parent: Node, volume_db: float, sound: String = "") -> AudioStreamPlayer:
	var node = AudioStreamPlayer.new()
	node.volume_db = volume_db
	if sound != "":
		node.stream = stream(sound)
	parent.add_child(node)
	return node

# A sound in the world: `unit` metres to fall off by half, silent past `reach`.
static func spatial(parent: Node, volume_db: float, unit: float, reach: float, sound: String = "") -> AudioStreamPlayer3D:
	var node = AudioStreamPlayer3D.new()
	node.volume_db = volume_db
	node.unit_size = unit
	node.max_distance = reach
	if sound != "":
		node.stream = stream(sound)
	parent.add_child(node)
	return node
