extends SceneTree
# Native radio client for scripts/test-voice-interop.mjs: joins a room through
# voice_native.gd with real links and exchanges signaling with the test over
# TCP (one JSON object per line). Headless Godot has no microphone, so a
# "tone" command feeds a 440 Hz sine to the encoder as if the key were held,
# and inbound audio is measured straight from each link.
const VoiceNative = preload("res://scripts/net/voice_native.gd")

var tcp := StreamPeerTCP.new()
var buffer := ""
var voice: Node
var encoder: RefCounted
var tone := false
var phase := 0.0
var peak: Dictionary = {}
var connected_once := false

func _initialize() -> void:
	var options = {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			options[arg.substr(2, arg.find("=") - 2)] = arg.substr(arg.find("=") + 1)
	if not VoiceNative.load_extension():
		printerr("VOICE_INTEROP no native radio extension")
		quit(2)
		return
	voice = VoiceNative.new()
	voice.audio_enabled = false
	root.add_child(voice)
	voice.sync_members(str(options.get("members", "")).split(","))
	var id = str(options.get("id", "a"))
	if not voice.join({"localId": id, "session": "native-%s-session" % id, "iceServers": []}):
		printerr("VOICE_INTEROP join failed")
		quit(3)
		return
	encoder = ClassDB.instantiate("RallyVoiceEncoder")
	tcp.connect_to_host("127.0.0.1", int(options.get("port", "0")))

func send(message: Dictionary) -> void:
	tcp.put_data((JSON.stringify(message) + "\n").to_utf8_buffer())

func _process(delta: float) -> bool:
	tcp.poll()
	if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return false
	var available = tcp.get_available_bytes()
	if available > 0:
		buffer += tcp.get_utf8_string(available)
	while buffer.contains("\n"):
		var line = buffer.left(buffer.find("\n"))
		buffer = buffer.substr(buffer.find("\n") + 1)
		var message = JSON.parse_string(line)
		if message is Dictionary:
			handle(message)
	for envelope in voice.tick([]).signals:
		send({"type": "signal", "to": envelope.to, "data": envelope.data})
	var frames = clampi(int(delta * 48000.0), 1, 4800)
	if tone:
		var chunk = PackedVector2Array()
		chunk.resize(frames)
		for i in range(frames):
			var s = 0.4 * sin(phase)
			phase += TAU * 440.0 / 48000.0
			chunk[i] = Vector2(s, s)
		for packet in encoder.encode(chunk, 48000):
			for peer in voice.peers.values():
				if peer.connected:
					peer.link.send_packet(packet)
	for id in voice.peers:
		var peer = voice.peers[id]
		if peer.connected:
			var sum = 0.0
			var pulled: PackedVector2Array = peer.link.pull(frames, 48000, 1.0, 3400.0, 0.0)
			for f in pulled:
				sum += f.x * f.x
			peak[id] = maxf(float(peak.get(id, 0.0)), sqrt(sum / maxi(1, pulled.size())))
	return false

func handle(message: Dictionary) -> void:
	match str(message.get("type", "")):
		"signal":
			voice.on_signal(str(message.from), message.data)
		"tone":
			tone = message.get("on") == true
			if not tone:
				encoder.reset()
		"reset_peak":
			peak = {}
		"report":
			send({"type": "report", "connected": voice.connected_count(), "peak": peak,
				"states": voice.peers.keys().map(func(id): return "%s:%s" % [id, voice.peers[id].link.get_state()])})
		"quit":
			voice.leave()
			for envelope in voice.tick([]).signals:
				send({"type": "signal", "to": envelope.to, "data": envelope.data})
			quit()
