extends Node
# Native radio backend (desktop, Android and iOS): one RallyVoiceLink from the
# native/voice GDExtension per other member, with the same mesh rules and
# signaling as web/voice-chat.js, so browser and native players hear each
# other. The microphone goes through AudioEffectCapture on a silent bus; each
# speaker plays through its own AudioStreamGenerator, coloured in C++.
const NetProtocol = preload("res://scripts/net/net_protocol.gd")

const MIC_BUS = "RadioMic"
# A lost offer or answer would leave a link waiting forever.
const DIAL_MSEC = 15000
# A member who reloaded never says bye: give a silent link a few seconds.
const LOST_MSEC = 5000
const FIRST_RETRY_MSEC = 1000
const RETRY_MSEC = 20000
const MAX_ATTEMPTS = 3
# No microphone frames this long after opening it means no usable input.
const MIC_TIMEOUT_MSEC = 2500
# The microphone closes this long after the key is released. An open input
# can switch Bluetooth headsets to their hands-free profile and keeps the
# driver capturing, so the game's own sound must not pay for it between
# transmissions.
const MIC_HANG_MSEC = 1500
const MAX_QUEUE = 128
const PLAYBACK_BUFFER = 0.1

# Tests swap in fakes; the game uses the extension classes.
var link_factory: Callable = func(): return ClassDB.instantiate("RallyVoiceLink")
var encoder_factory: Callable = func(): return ClassDB.instantiate("RallyVoiceEncoder")
var audio_enabled := true
# Tests with fake links run without the library.
var needs_extension := true

var joined := false
var local_id := ""
var session := ""
var ice_servers := PackedStringArray()
var members: Array = []
var peers: Dictionary = {}
var attempts: Dictionary = {}
var muted: Dictionary = {}
var outgoing: Array = []
var events: Array = []
var mic := "idle"
var pressed := false
var mic_opened_at := 0
var released_at := 0
var mic_player: AudioStreamPlayer
var capture: AudioEffectCapture
var encoder: RefCounted
var bands: Array = []

const LIBRARY_DIR = "res://addons/rally_voice/bin"

# The library for this platform ships inside the pack (see build-voice.mjs).
static func supported() -> bool:
	return not OS.has_feature("web") and (ClassDB.class_exists("RallyVoiceLink") or FileAccess.file_exists(LIBRARY_DIR.path_join(library_name())))

static func library_name() -> String:
	var arch = Engine.get_architecture_name()
	match OS.get_name():
		"Linux":
			return "librally_voice.linux.x86_64.so" if arch == "x86_64" else ""
		"Windows":
			return "librally_voice.windows.%s.dll" % ("x86_64" if arch == "x86_64" else "x86_32")
		"macOS":
			return "librally_voice.macos.universal.dylib"
		"Android":
			return "librally_voice.android.%s.so" % ("arm64" if arch == "arm64" else "arm32")
	return ""

# Loads the extension on first use: Godot cannot open a library inside the
# pack, so it is copied to user:// with a generated .gdextension next to it.
# iOS builds embed it in the app and load it at startup (build-desktop.mjs).
static func load_extension() -> bool:
	if ClassDB.class_exists("RallyVoiceLink"):
		return true
	var name = library_name()
	var source = LIBRARY_DIR.path_join(name)
	if name == "" or not FileAccess.file_exists(source):
		return false
	var bytes = FileAccess.get_file_as_bytes(source)
	# One folder per build of the library: an update never loads a stale copy.
	var dir = "user://rally_voice/%s" % FileAccess.get_md5(source).left(12)
	var target = dir.path_join(name)
	DirAccess.make_dir_recursive_absolute(dir)
	var existing = FileAccess.open(target, FileAccess.READ)
	var stale = existing == null or existing.get_length() != bytes.size()
	existing = null
	if stale:
		var file = FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			return false
		file.store_buffer(bytes)
		file.close()
	var feature = {"Linux": "linux.x86_64", "Windows": "windows", "macOS": "macos", "Android": "android"}.get(OS.get_name(), "")
	var config = FileAccess.open(dir.path_join("rally_voice.gdextension"), FileAccess.WRITE)
	if config == null:
		return false
	config.store_string("[configuration]\nentry_symbol = \"rally_voice_init\"\ncompatibility_minimum = \"4.4\"\n\n[libraries]\n%s = \"%s\"\n" % [feature, name])
	config.close()
	var status = GDExtensionManager.load_extension(dir.path_join("rally_voice.gdextension"))
	if status != GDExtensionManager.LOAD_STATUS_OK and status != GDExtensionManager.LOAD_STATUS_ALREADY_LOADED:
		push_warning("Radio extension did not load (%d)" % status)
	return ClassDB.class_exists("RallyVoiceLink")

func _ready() -> void:
	bands = NetProtocol.spec.get("voice", {}).get("bands", [])

static func quality(bands_list: Array, distance: float) -> Dictionary:
	for i in range(bands_list.size()):
		var band: Dictionary = bands_list[i]
		if float(band.max) < 0 or distance <= float(band.max):
			return {"level": i + 1, "volume": float(band.volume), "noise": float(band.noise), "cutoff": float(band.cutoff)}
	return {"level": 1, "volume": 1.0, "noise": 0.0, "cutoff": 3400.0}

# ---------------------------------------------------------------- room

func join(options: Dictionary) -> bool:
	if joined:
		leave()
	if needs_extension and not load_extension():
		return false
	local_id = str(options.get("localId", ""))
	session = str(options.get("session", ""))
	ice_servers = PackedStringArray()
	for url in options.get("iceServers", []):
		ice_servers.append(str(url))
	attempts.clear()
	joined = local_id != "" and session.length() >= 8
	if joined:
		sync_members(members)
	return joined

func leave() -> void:
	set_ptt(false)
	for id in peers.keys():
		_drop(id, true)
	joined = false
	_close_mic()
	if mic != "denied" and mic != "unavailable":
		_set_mic("idle")

func sync_members(ids: Array) -> void:
	members = ids.map(func(id): return str(id)).filter(func(id): return id != "" and id != local_id)
	if not joined:
		return
	for id in peers.keys():
		if not id in members:
			_drop(id, true)
	# The member with the smaller id calls; the other waits for the offer.
	for id in members:
		if not peers.has(id) and local_id < id and _can_dial(id):
			_open(id, true)

func on_signal(from: String, data: Dictionary) -> void:
	var kind = str(data.get("kind", ""))
	if not joined or data.get("space") != "voice" or kind == "":
		return
	var id = str(from)
	if kind == "bye":
		_drop(id, false)
		# A bye from a member who is still listed asks for a fresh call.
		attempts.erase(id)
		return
	# The server only relays between members, so an unlisted offer is a newcomer.
	if not id in members:
		if kind != "offer":
			return
		members.append(id)
	var peer: Dictionary = peers.get(id, {})
	var remote_session = str(data.get("session", ""))
	if kind == "offer" and not peer.is_empty() and (peer.remote_session != "" and remote_session != peer.remote_session or peer.offering or local_id > id and peer.described and not peer.connected):
		# A reload starts over; two offers at once keep the polite side's peer.
		if peer.offering and local_id < id:
			return
		_drop(id, false)
		peer = {}
	if peer.is_empty():
		if kind != "offer":
			return
		peer = _open(id, false)
		if peer.is_empty():
			return
	var link = peer.link
	match kind:
		"offer", "answer":
			var description = data.get("description", {})
			if not description is Dictionary:
				return
			if kind == "offer":
				peer.remote_session = remote_session
			peer.offering = false
			if link.set_remote_description(str(description.get("type", kind)), str(description.get("sdp", ""))) != OK:
				_note_failure(id)
				_drop(id, false)
				return
			for candidate in peer.candidates:
				link.add_ice_candidate(candidate.candidate, candidate.mid)
			peer.candidates.clear()
			peer.described = true
		"candidate":
			var c = data.get("candidate", {})
			if not c is Dictionary:
				return
			var entry = {"candidate": str(c.get("candidate", "")), "mid": str(c.get("sdpMid", ""))}
			if peer.described:
				link.add_ice_candidate(entry.candidate, entry.mid)
			else:
				peer.candidates.append(entry)

# Our room socket has just opened: calls relayed before it were lost. Every
# link that is not up starts over, and a bye makes the other side call again.
func ring_again() -> void:
	if not joined:
		return
	for id in members:
		if peers.has(id) and peers[id].connected:
			continue
		_drop(id, false)
		attempts.erase(id)
		_send(id, {"kind": "bye"})

# ---------------------------------------------------------------- links

func _open(id: String, initiator: bool) -> Dictionary:
	var link = link_factory.call()
	if link == null or link.initialize(ice_servers, initiator) != OK:
		_note_failure(id)
		return {}
	var peer = {"id": id, "link": link, "offering": initiator, "described": false, "candidates": [], "remote_session": "",
		"opened_at": Time.get_ticks_msec(), "connected": false, "distance": 9999.0, "talking": false, "player": null}
	peers[id] = peer
	return peer

func _drop(id: String, notify: bool) -> void:
	var peer: Dictionary = peers.get(id, {})
	if peer.is_empty():
		return
	if notify:
		_send(id, {"kind": "bye"})
	peers.erase(id)
	peer.link.close()
	if peer.player != null:
		peer.player.queue_free()

func _note_failure(id: String) -> void:
	var entry: Dictionary = attempts.get(id, {"count": 0, "retry_at": 0})
	entry.count += 1
	entry.retry_at = Time.get_ticks_msec() + (FIRST_RETRY_MSEC if entry.count == 1 else RETRY_MSEC)
	attempts[id] = entry

func _can_dial(id: String) -> bool:
	var entry: Dictionary = attempts.get(id, {})
	return entry.is_empty() or (int(entry.count) < MAX_ATTEMPTS and Time.get_ticks_msec() >= int(entry.retry_at))

func _send(to: String, data: Dictionary) -> void:
	if outgoing.size() >= MAX_QUEUE:
		outgoing.pop_front()
	var envelope = data.duplicate()
	envelope.space = "voice"
	envelope.session = session
	outgoing.append({"to": to, "data": envelope})

# Link events become signals, connection state drives redials.
func _poll_links() -> void:
	var now = Time.get_ticks_msec()
	for id in peers.keys():
		var peer: Dictionary = peers[id]
		for event in peer.link.poll():
			match str(event.get("type", "")):
				"description":
					_send(id, {"kind": str(event.sdp_type), "description": {"type": str(event.sdp_type), "sdp": str(event.sdp)}})
				"candidate":
					_send(id, {"kind": "candidate", "candidate": {"candidate": str(event.candidate), "sdpMid": str(event.mid), "sdpMLineIndex": 0}})
				"state":
					_state_changed(id, peer, str(event.state), now)
				"error":
					events.append({"type": "error", "stage": "native", "message": str(event.get("message", ""))})
		if not peers.has(id):
			continue
		# "lost_at" exists only while a connected link is silent.
		if not peer.connected and now - int(peer.opened_at) > DIAL_MSEC or peer.has("lost_at") and now - int(peer.lost_at) > LOST_MSEC:
			_drop(id, false)
			_note_failure(id)

func _state_changed(id: String, peer: Dictionary, state: String, now: int) -> void:
	match state:
		"connected":
			peer.connected = true
			peer.erase("lost_at")
			attempts.erase(id)
		"disconnected":
			peer.lost_at = now
		"failed", "closed":
			_drop(id, false)
			_note_failure(id)

func connected_count() -> int:
	return peers.values().filter(func(p): return p.connected).size()

# ---------------------------------------------------------------- microphone

func set_ptt(value: bool) -> void:
	pressed = value and joined
	if pressed and mic == "idle":
		_open_mic()
	if not pressed:
		released_at = Time.get_ticks_msec()
		if encoder != null:
			encoder.reset()

func _open_mic() -> void:
	_set_mic("pending")
	if OS.get_name() == "Android" and not "android.permission.RECORD_AUDIO" in OS.get_granted_permissions():
		if not get_tree().on_request_permissions_result.is_connected(_on_permission):
			get_tree().on_request_permissions_result.connect(_on_permission)
		# True means it was already granted; otherwise the answer comes as a signal.
		if not OS.request_permission("android.permission.RECORD_AUDIO"):
			return
	_start_capture()

func _on_permission(permission: String, granted: bool) -> void:
	if permission != "android.permission.RECORD_AUDIO" or mic != "pending":
		return
	if granted:
		_start_capture()
	else:
		_set_mic("denied")

func _start_capture() -> void:
	if not audio_enabled or not ProjectSettings.get_setting("audio/driver/enable_input", false):
		_set_mic("unavailable")
		return
	encoder = encoder_factory.call()
	# The bus ships in default_bus_layout.tres: AudioServer.add_bus() changes
	# the bus list without locking the mixer, so adding it mid-game races the
	# audio thread. Its capture effect runs before the -80 dB fader: we never
	# hear ourselves.
	var bus = AudioServer.get_bus_index(MIC_BUS)
	if bus < 0 or AudioServer.get_bus_effect_count(bus) == 0 or not AudioServer.get_bus_effect(bus, 0) is AudioEffectCapture:
		push_warning("Radio microphone bus is missing from the bus layout")
		_set_mic("unavailable")
		return
	capture = AudioServer.get_bus_effect(bus, 0)
	capture.clear_buffer()
	mic_player = AudioStreamPlayer.new()
	mic_player.name = "RadioMicrophone"
	mic_player.stream = AudioStreamMicrophone.new()
	mic_player.bus = MIC_BUS
	add_child(mic_player)
	mic_player.play()
	mic_opened_at = Time.get_ticks_msec()

func _close_mic() -> void:
	if mic_player != null:
		mic_player.stop()
		mic_player.queue_free()
		mic_player = null
	capture = null
	encoder = null

func _set_mic(value: String) -> void:
	if mic == value:
		return
	mic = value
	events.append({"type": "mic", "value": value})

# Drains the microphone every frame; while the key is held it is sent to everyone.
func _pump_microphone() -> void:
	if capture == null:
		return
	if not pressed and Time.get_ticks_msec() - released_at > MIC_HANG_MSEC:
		_close_mic()
		_set_mic("idle")
		return
	var available = capture.get_frames_available()
	if available <= 0:
		if mic == "pending" and Time.get_ticks_msec() - mic_opened_at > MIC_TIMEOUT_MSEC:
			_close_mic()
			_set_mic("denied" if AudioServer.get_input_device_list().size() > 0 else "unavailable")
		return
	if mic == "pending":
		_set_mic("ready")
	var frames: PackedVector2Array = capture.get_buffer(available)
	if not pressed or encoder == null:
		return
	for packet in encoder.encode(frames, int(AudioServer.get_mix_rate())):
		for peer in peers.values():
			if peer.connected:
				peer.link.send_packet(packet)

# ---------------------------------------------------------------- speakers

func _pump_speakers() -> void:
	if not audio_enabled:
		return
	var rate = int(AudioServer.get_mix_rate())
	for peer in peers.values():
		if not peer.connected:
			continue
		if peer.player == null:
			var generator = AudioStreamGenerator.new()
			generator.mix_rate = rate
			generator.buffer_length = PLAYBACK_BUFFER
			var player = AudioStreamPlayer.new()
			player.name = "Radio_%s" % peer.id
			player.stream = generator
			add_child(player)
			player.play()
			peer.player = player
		var playback: AudioStreamGeneratorPlayback = peer.player.get_stream_playback()
		if playback == null:
			continue
		var frames = playback.get_frames_available()
		if frames <= 0:
			continue
		var q = quality(bands, float(peer.distance))
		var silent = muted.has(peer.id)
		playback.push_buffer(peer.link.pull(frames, rate, 0.0 if silent else q.volume, q.cutoff, 0.0 if silent or not peer.talking else q.noise * 0.25))

func mute(id: String, value: bool = true) -> void:
	if value:
		muted[id] = true
	else:
		muted.erase(id)

func _process(_delta: float) -> void:
	if not joined:
		return
	_poll_links()
	_pump_microphone()
	_pump_speakers()

# {signals, mic, events, connected} like web/voice-chat.js.
func tick(levels: Array) -> Dictionary:
	for entry in levels:
		var peer: Dictionary = peers.get(str(entry.get("id", "")), {})
		if not peer.is_empty():
			peer.distance = float(entry.get("distance", 0.0))
			peer.talking = entry.get("talking") == true
	sync_members(members)
	var result = {"signals": outgoing, "mic": mic, "events": events, "connected": connected_count()}
	outgoing = []
	events = []
	return result
