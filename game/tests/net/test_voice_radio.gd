extends "res://tests/harness.gd"
# The radio flag travels in the player state like the other pose flags, and a
# build without browser voice keeps the radio switched off.
const NetProtocol = preload("res://scripts/net/net_protocol.gd")
const VoiceChat = preload("res://scripts/net/voice_chat.gd")
const VoiceNative = preload("res://scripts/net/voice_native.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var base = {"pos": [0, 0, 0], "car": [1, 1, 1], "heading": 0, "yaw": 0, "pitch": 0, "in_car": false}
	check(NetProtocol.clean_state(base).radio == false, "the radio is off unless the state says so")
	check(NetProtocol.clean_state(base.merged({"radio": true})).radio == true, "a member on air keeps the radio flag")
	check(NetProtocol.clean_state(base.merged({"radio": true, "in_car": true})).radio == true, "talking from a car still shows who is on air")
	check(NetProtocol.clean_state(base.merged({"radio": "yes"})).radio == false, "only a boolean switches the radio on")
	var quiet = NetProtocol.compact_state(NetProtocol.clean_state(base))
	check(not quiet.has("radio"), "the direct link leaves the default radio flag out")
	var loud = NetProtocol.compact_state(NetProtocol.clean_state(base.merged({"radio": true})))
	check(loud.get("radio") == true and NetProtocol.expand_state(loud).radio == true, "the direct link carries the radio flag")
	check(NetProtocol.expand_state(quiet).radio == false, "a guest reads a missing radio flag as off")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/net_protocol.json"))
	check(data.has("voice") and int(data.voice.max_signal_bytes) > 0 and int(data.voice.signals_per_10s) > 0, "voice signaling has its own limits")
	var voice = VoiceChat.new()
	root.add_child(voice)
	await process_frame
	check(voice.supported == VoiceNative.supported(), "native builds offer the radio exactly when the native library ships")
	check(not voice.available(), "the radio is hidden until the room joins it")
	if not voice.supported:
		voice.join()
		voice.sync_members(["a", "b"])
		voice.on_signal("a", {"space": "voice", "kind": "offer"})
		voice.leave()
		check(not voice.joined and not voice.on_air(), "without a backend joining and leaving are no-ops")
	voice.free()
	finish()
