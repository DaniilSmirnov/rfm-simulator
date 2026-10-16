extends Node
class_name RallyVoiceChat
var room: Node
var transmitting := false
var backend := "unavailable"
var native_peer: RefCounted
func setup(owner: Node) -> void: room = owner
func enable() -> void:
	if backend == "web":
		JavaScriptBridge.eval("RallyVoice && RallyVoice.attach({session:'%s'}).enable()" % room.player_id, true)
	elif backend == "native-voice" and native_peer != null:
		native_peer.start(room.player_id, "radio-session", "[]")
func _ready() -> void:
	backend = "web" if OS.has_feature("web") else ("native-webrtc" if ClassDB.class_exists("WebRTCPeerConnection") else "unavailable")
	if not OS.has_feature("web") and ClassDB.class_exists("RallyVoicePeer"):
		backend = "native-voice"
		native_peer = ClassDB.instantiate("RallyVoicePeer")
func _process(_delta: float) -> void:
	if backend == "unavailable" or room == null or not room.connected: return
	if backend != "web":
		if backend == "native-voice" and native_peer != null:
			# Signaling and microphone/Opus transport stay inside the extension.
			pass
		return
	var queued = JavaScriptBridge.eval("RallyVoice && RallyVoice.drainSignals ? RallyVoice.drainSignals() : []", true)
	if queued is Array:
		for envelope in queued:
			if envelope is Dictionary and envelope.has("to") and envelope.has("data"): room.transport.send_signal(str(envelope.to), envelope.data)
		set_ptt(Input.is_action_pressed("radio") and not room.game.paused and not room.game.dead and not room.game.finished)
func set_ptt(value: bool) -> void:
	if transmitting == value or backend == "unavailable": return
	transmitting = value
	if backend == "web": JavaScriptBridge.eval("RallyVoice && RallyVoice.state.enabled && RallyVoice.attach({}).setPtt(%s)" % ("true" if value else "false"), true)
	elif backend == "native-voice" and native_peer != null: native_peer.set_push_to_talk(value)
func on_signal(from: String, data: Dictionary) -> void:
	if OS.has_feature("web"): JavaScriptBridge.eval("RallyVoice && RallyVoice.onSignal(%s,%s)" % [JSON.stringify(from), JSON.stringify(data)], true)

func sync_members(ids: Array) -> void:
	if backend == "web":
		JavaScriptBridge.eval("RallyVoice && RallyVoice.syncMembers(%s,%s)" % [JSON.stringify(room.player_id), JSON.stringify(ids)], true)

func set_distance(id: String, distance: float) -> void:
	if backend == "web":
		JavaScriptBridge.eval("RallyVoice && RallyVoice.state.enabled && RallyVoice.attach({}).setDistance(%s,%s)" % [JSON.stringify(id), distance], true)
