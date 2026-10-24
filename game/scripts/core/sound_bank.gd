extends RefCounted
# Sound files of res://audio by name. scripts/generate-sounds.mjs renders most
# of them (engines, tyres, doors, steps…); each stream loads once and every
# player node shares it.
static var streams: Dictionary = {}

static func stream(sound: String) -> AudioStream:
	if not streams.has(sound):
		streams[sound] = load("res://audio/%s.wav" % sound)
	return streams[sound]

# Every file up front, while the game sets up. The Web build plays them as
# WebAudio samples, and the first play of each decodes and uploads it: done
# here, a car coming into earshot does not stall a frame.
static func warm() -> void:
	for file in DirAccess.get_files_at("res://audio"):
		if not file.ends_with(".wav.import"):
			continue
		var loaded = stream(file.trim_suffix(".wav.import"))
		if OS.has_feature("web") and loaded != null and not AudioServer.is_stream_registered_as_sample(loaded):
			AudioServer.register_stream_as_sample(loaded)

# On the Web, unpausing a sample (Godot 4.4 SampleNode) starts it again on a
# new source even when it was not paused, and the old source keeps looping
# unheard forever: written every frame, that piled up hundreds of sources a
# second. So the flag is written only when it changes.
static func set_paused(node: Node, paused: bool) -> void:
	if node.stream_paused != paused:
		node.stream_paused = paused

# One of the numbered takes `sound-1` … `sound-count`.
static func take(sound: String, count: int, rng: RandomNumberGenerator) -> AudioStream:
	return stream("%s-%d" % [sound, rng.randi_range(1, count)])

# Every game sound plays on the Sounds bus, so the general volume slider moves
# it and leaves the radio (its own bus, default_bus_layout.tres) alone.
const BUS = &"Sounds"

static func player(parent: Node, volume_db: float, sound: String = "") -> AudioStreamPlayer:
	var node = AudioStreamPlayer.new()
	node.bus = BUS
	node.volume_db = volume_db
	if sound != "":
		node.stream = stream(sound)
	parent.add_child(node)
	return node

# A sound in the world: `unit` metres to fall off by half, silent past `reach`.
static func spatial(parent: Node, volume_db: float, unit: float, reach: float, sound: String = "") -> AudioStreamPlayer3D:
	var node = AudioStreamPlayer3D.new()
	node.bus = BUS
	node.volume_db = volume_db
	node.unit_size = unit
	node.max_distance = reach
	if sound != "":
		node.stream = stream(sound)
	parent.add_child(node)
	return node
