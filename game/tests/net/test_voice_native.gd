extends "res://tests/harness.gd"
# Native radio: the mesh rules of voice_native.gd on fake links (always), then
# real RallyVoiceLink connections carrying Opus through libdatachannel when the
# native/voice extension is installed (required with RFM_REQUIRE_NATIVE_VOICE=1).
const VoiceNative = preload("res://scripts/net/voice_native.gd")
const NetProtocol = preload("res://scripts/net/net_protocol.gd")

class FakeLink:
	extends RefCounted
	var offer := false
	var events: Array = []
	var remote := ""
	var closed := false
	var candidates: Array = []
	var sent: Array = []
	func initialize(_ice, as_offer: bool) -> int:
		offer = as_offer
		if offer:
			events.append({"type": "description", "sdp_type": "offer", "sdp": "v=0 offer"})
			events.append({"type": "candidate", "candidate": "candidate:1 1 udp 1 10.0.0.1 9 typ host", "mid": "audio"})
		return OK
	func set_remote_description(type: String, _sdp: String) -> int:
		remote = type
		if type == "offer":
			events.append({"type": "description", "sdp_type": "answer", "sdp": "v=0 answer"})
		events.append({"type": "state", "state": "connected"})
		return OK
	func add_ice_candidate(candidate: String, _mid: String) -> int:
		candidates.append(candidate)
		return OK
	func poll() -> Array:
		var out = events
		events = []
		return out
	func send_packet(packet: PackedByteArray) -> bool:
		sent.append(packet)
		return true
	func pull(frames: int, _rate: int, _volume: float, _cutoff: float, _noise: float) -> PackedVector2Array:
		var out = PackedVector2Array()
		out.resize(frames)
		return out
	func close() -> void:
		closed = true

var nodes: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func client(id: String, fake: bool = true) -> Node:
	var node = VoiceNative.new()
	if fake:
		node.link_factory = func(): return FakeLink.new()
		node.needs_extension = false
	node.audio_enabled = false
	root.add_child(node)
	nodes[id] = node
	return node

# Delivers queued signals the way the room server relays them.
func relay(rounds: int = 6) -> void:
	for i in range(rounds):
		var sent = 0
		for id in nodes:
			var node = nodes[id]
			node._poll_links()
			for envelope in node.tick([]).signals:
				sent += 1
				check(envelope.data.space == "voice" and str(envelope.data.session).length() >= 8, "signals carry the voice space and session")
				if nodes.has(envelope.to):
					nodes[envelope.to].on_signal(id, envelope.data)
		if sent == 0:
			return
		await process_frame

func run() -> void:
	await mesh_rules()
	await microphone_release()
	await real_links()
	await real_data_links()
	finish()

# The microphone bus comes with the project, so the radio never adds a bus
# while the mixer runs; the input closes a moment after the key is released.
func microphone_release() -> void:
	var bus = AudioServer.get_bus_index(VoiceNative.MIC_BUS)
	check(bus > 0 and AudioServer.get_bus_effect(bus, 0) is AudioEffectCapture, "the radio microphone bus ships in the bus layout")
	var count = AudioServer.bus_count
	var node = client("mic")
	node.audio_enabled = true
	node.encoder_factory = func(): return RefCounted.new()
	node.join({"localId": "mic", "session": "session-mic"})
	node.set_ptt(true)
	check(node.mic == "pending" and node.capture != null and node.mic_player != null, "pressing the key opens the microphone")
	check(AudioServer.bus_count == count, "opening the microphone adds no bus")
	node.set_ptt(true)
	node.set_ptt(false)
	node._pump_microphone()
	check(node.mic_player != null, "a short pause keeps the microphone open")
	node.released_at -= VoiceNative.MIC_HANG_MSEC + 1
	node._pump_microphone()
	check(node.mic == "idle" and node.mic_player == null and node.capture == null, "the microphone closes after the key is released")
	node.set_ptt(true)
	check(node.mic == "pending" and node.mic_player != null, "the next press opens it again")
	node.leave()
	await process_frame

func mesh_rules() -> void:
	var ids = ["a", "b", "c"]
	for id in ids:
		var node = client(id)
		node.sync_members(ids)
		check(node.join({"localId": id, "session": "session-" + id, "iceServers": ["stun:example.org:3478"]}), "%s joins the radio" % id)
	await relay()
	for id in ids:
		var node = nodes[id]
		check(node.connected_count() == 2, "%s is linked with both others" % id)
	check(nodes.a.peers.b.link.offer and not nodes.b.peers.a.link.offer, "the smaller id calls")
	check(nodes.b.peers.a.link.remote == "offer" and nodes.a.peers.b.link.remote == "answer", "offer and answer cross the relay")
	check(nodes.b.peers.a.link.candidates.size() == 1, "candidates reach the answering side")
	check(nodes.a.ice_servers == PackedStringArray(["stun:example.org:3478"]), "ICE servers come from the room options")
	# Push-to-talk sends only while the key is held and only to linked members.
	nodes.a.tick([{"id": "b", "distance": 320.0, "talking": true}])
	check(nodes.a.peers.b.distance == 320.0 and nodes.a.peers.b.talking, "levels reach the peer")
	check(VoiceNative.quality(nodes.a.bands, 5.0).level == 1 and VoiceNative.quality(nodes.a.bands, 600.0).level == 5, "distance bands come from net_protocol.json")
	check(VoiceNative.quality(nodes.a.bands, 600.0).volume < VoiceNative.quality(nodes.a.bands, 5.0).volume, "farther radios are quieter")
	nodes.a.audio_enabled = true
	nodes.a._pump_speakers()
	nodes.a.audio_enabled = false
	check(nodes.a.peers.b.player != null and nodes.a.peers.b.player.bus == &"Radio" and AudioServer.get_bus_index(VoiceNative.RADIO_BUS) > 0, "voices play through the radio's own bus")
	nodes.a.set_ptt(true)
	check(nodes.a.mic == "unavailable", "without audio input the radio stays receive-only")
	check(nodes.a.tick([]).events.any(func(e): return e.type == "mic"), "the microphone state is reported")
	# A refused offer from an unlisted member: the roster lags, an offer opens a link.
	var early = client("0")
	early.sync_members(["0", "a"])
	early.join({"localId": "0", "session": "session-0"})
	await relay()
	check(nodes.a.peers.has("0") and nodes.a.peers["0"].connected, "an offer from a member the roster does not list yet opens a link")
	nodes.b.on_signal("zz", {"space": "voice", "kind": "candidate", "session": "session-zz", "candidate": {}})
	check(not nodes.b.peers.has("zz"), "only an offer opens a link with an unlisted member")
	# Leaving says bye; the next roster no longer lists the member.
	nodes.c.leave()
	for id in ["a", "b"]:
		nodes[id].sync_members(["0", "a", "b"])
	var signals = nodes.c.tick([]).signals
	check(signals.size() == 2 and signals.all(func(s): return s.data.kind == "bye"), "leaving says bye to everyone")
	for envelope in signals:
		nodes[envelope.to].on_signal("c", envelope.data)
	check(not nodes.a.peers.has("c") and not nodes.b.peers.has("c"), "a bye drops the link")
	check(not "c" in nodes.a.members, "a late bye does not put the member back on the roster")
	nodes.erase("c")
	# A silent link is redialled after a short pause.
	var stale: Dictionary = nodes.a.peers.b
	stale.link.events.append({"type": "state", "state": "disconnected"})
	nodes.a._poll_links()
	stale.lost_at = Time.get_ticks_msec() - VoiceNative.LOST_MSEC - 1
	nodes.a._poll_links()
	check(not nodes.a.peers.has("b") and stale.link.closed, "a link silent for seconds is closed")
	await create_timer(VoiceNative.FIRST_RETRY_MSEC / 1000.0 + 0.2).timeout
	await relay()
	check(nodes.a.peers.has("b") and nodes.a.peers.b.connected and nodes.a.peers.b.link != stale.link, "the caller dials again after the first quick retry")
	# A reloaded member (new session) replaces the old link.
	var old_link = nodes.b.peers.a.link
	nodes.b.on_signal("a", {"space": "voice", "kind": "offer", "session": "session-a-reloaded", "description": {"type": "offer", "sdp": "v=0"}})
	check(nodes.b.peers.a.link != old_link and old_link.closed, "an offer with a new session restarts the link")
	nodes.a.peers.b.link.events.append({"type": "state", "state": "failed"})
	nodes.a._poll_links()
	check(not nodes.a.peers.has("b") and nodes.a.attempts.has("b"), "a failed link is dropped and counted")
	# Calls relayed before the callee's room socket opened were lost, and the
	# caller gave up. When the socket opens, the callee's bye makes it ring again.
	nodes.b._drop("a", false)
	nodes.a.attempts["b"] = {"count": VoiceNative.MAX_ATTEMPTS, "retry_at": 0}
	nodes.a.sync_members(nodes.a.members)
	check(not nodes.a.peers.has("b"), "a caller out of attempts stops dialling")
	nodes.b.ring_again()
	var byes = nodes.b.tick([]).signals.filter(func(s): return s.to == "a")
	check(byes.size() == 1 and byes[0].data.kind == "bye", "an opened socket asks members without a link to ring again")
	nodes.a.on_signal("b", byes[0].data)
	nodes.a.sync_members(nodes.a.members)
	await relay()
	check(nodes.a.peers.has("b") and nodes.a.peers.b.connected and nodes.b.peers.a.connected, "the caller rings again after the bye")
	for id in nodes:
		nodes[id].leave()
		nodes[id].queue_free()
	nodes.clear()

func real_links() -> void:
	var present = VoiceNative.load_extension()
	if OS.get_environment("RFM_REQUIRE_NATIVE_VOICE") == "1":
		check(present, "the native radio extension is installed")
	if not present:
		print("SKIP: native radio extension not installed")
		return
	var a = ClassDB.instantiate("RallyVoiceLink")
	var b = ClassDB.instantiate("RallyVoiceLink")
	check(a.initialize(PackedStringArray(), true) == OK and b.initialize(PackedStringArray(), false) == OK, "native links initialize")
	var deadline = Time.get_ticks_msec() + 10000
	var offered = false
	while Time.get_ticks_msec() < deadline and not (a.get_state() == "connected" and b.get_state() == "connected"):
		for pair in [[a, b], [b, a]]:
			for event in pair[0].poll():
				if event.type == "description":
					offered = offered or event.sdp_type == "offer"
					check(event.sdp.contains("opus/48000"), "the %s carries Opus" % event.sdp_type)
					pair[1].set_remote_description(event.sdp_type, event.sdp)
				elif event.type == "candidate":
					pair[1].add_ice_candidate(event.candidate, event.mid)
				elif event.type == "error":
					check(false, "native link error: " + str(event.message))
		await create_timer(0.02).timeout
	check(offered and a.get_state() == "connected" and b.get_state() == "connected", "two native links connect over loopback")
	var encoder = ClassDB.instantiate("RallyVoiceEncoder")
	# Half a second of a 440 Hz tone, paced in 20 ms packets like a live mic.
	var phase = 0.0
	var loud = 0.0
	for frame in range(40):
		var chunk = PackedVector2Array()
		chunk.resize(960)
		for i in range(960):
			var s = 0.5 * sin(phase)
			phase += TAU * 440.0 / 48000.0
			chunk[i] = Vector2(s, s)
		for packet in encoder.encode(chunk, 48000):
			a.send_packet(packet)
		await create_timer(0.02).timeout
		if frame > 15:
			loud = maxf(loud, rms(b.pull(960, 48000, 1.0, 3400.0, 0.0)))
	check(b.get_received_packets() >= 30, "Opus packets arrive (%d)" % b.get_received_packets())
	check(loud > 0.1, "the tone is heard on the other side (rms %.3f)" % loud)
	check(encoder.get_level() > 0.2, "the encoder reports the input level")
	var far = 0.0
	for frame in range(12):
		var chunk = PackedVector2Array()
		chunk.resize(960)
		for i in range(960):
			var s = 0.5 * sin(phase)
			phase += TAU * 440.0 / 48000.0
			chunk[i] = Vector2(s, s)
		for packet in encoder.encode(chunk, 48000):
			a.send_packet(packet)
		await create_timer(0.02).timeout
		# The volume glides over ~10 ms: measure once it has settled.
		var level = rms(b.pull(960, 48000, 0.15, 1500.0, 0.0))
		if frame >= 4:
			far = maxf(far, level)
	check(far < loud * 0.4, "a far radio is quieter (%.3f vs %.3f)" % [far, loud])
	await create_timer(0.5).timeout
	b.pull(48000, 48000, 1.0, 3400.0, 0.0)
	check(rms(b.pull(960, 48000, 1.0, 3400.0, 0.0)) < 0.001, "silence after the key is released")
	var hiss = 0.0
	for i in range(5):
		hiss = maxf(hiss, rms(b.pull(960, 48000, 1.0, 3400.0, 0.1)))
	check(hiss > 0.005, "a talking far radio hisses (rms %.4f)" % hiss)
	# Resampling to the device rate keeps the tone.
	check(b.pull(441, 44100, 1.0, 3400.0, 0.0).size() == 441, "pull fills the requested frames at any mix rate")
	a.close()
	b.close()
	# The same mesh as above, on real links.
	for id in ["a", "b"]:
		var node = client(id, false)
		node.sync_members(["a", "b"])
		node.join({"localId": id, "session": "native-" + id, "iceServers": []})
	deadline = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline and not (nodes.a.connected_count() == 1 and nodes.b.connected_count() == 1):
		await relay(1)
		await create_timer(0.02).timeout
	check(nodes.a.connected_count() == 1 and nodes.b.connected_count() == 1, "the native mesh connects through relayed signals")
	for id in nodes:
		nodes[id].leave()

# The room's direct link on native builds: the same extension, through the
# adapter that direct_link.gd uses in place of Godot's WebRTC.
func real_data_links() -> void:
	var DirectNative = load("res://scripts/net/direct_native.gd")
	var guest = DirectNative.create()
	var host = DirectNative.create()
	if guest == null or host == null:
		if OS.get_environment("RFM_REQUIRE_NATIVE_VOICE") == "1":
			check(false, "the native direct link is available")
		print("SKIP: native direct link not available")
		return
	var channels = []
	for pc in [guest, host]:
		pc.initialize({"iceServers": []})
		channels.append(pc.create_data_channel("fast", {"negotiated": true, "id": 1, "ordered": false, "maxRetransmits": 0}))
	guest.session_description_created.connect(func(type, sdp): host.set_remote_description(type, sdp))
	host.session_description_created.connect(func(type, sdp): guest.set_remote_description(type, sdp))
	guest.ice_candidate_created.connect(func(media, index, name): host.add_ice_candidate(media, index, name))
	host.ice_candidate_created.connect(func(media, index, name): guest.add_ice_candidate(media, index, name))
	check(guest.create_offer() == OK, "the guest offers a native direct link")
	var deadline = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline and not channels.all(func(c): return c.get_ready_state() == 1):
		guest.poll()
		host.poll()
		await create_timer(0.02).timeout
	check(channels.all(func(c): return c.get_ready_state() == 1) and guest.get_connection_state() == 2, "two native direct links open over loopback")
	var world = JSON.stringify({"t": "w", "time": 1, "world": {}, "players": []}).to_utf8_buffer()
	check(channels[1].put_packet(world) == OK and channels[0].put_packet("{\"t\":\"s\"}".to_utf8_buffer()) == OK, "both sides send")
	deadline = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline and not (channels[0].get_available_packet_count() > 0 and channels[1].get_available_packet_count() > 0):
		guest.poll()
		host.poll()
		await create_timer(0.02).timeout
	check(channels[0].get_available_packet_count() == 1 and channels[0].get_packet() == world, "the world packet arrives unchanged")
	check(channels[1].get_available_packet_count() == 1 and channels[1].get_packet().get_string_from_utf8() == "{\"t\":\"s\"}", "the guest state arrives")
	channels[0].close()
	host.close()
	check(guest.get_connection_state() == 5 and channels[0].get_ready_state() == 3, "a closed native link reports closed")

func rms(frames: PackedVector2Array) -> float:
	if frames.is_empty():
		return 0.0
	var sum = 0.0
	for f in frames:
		sum += f.x * f.x
	return sqrt(sum / frames.size())
