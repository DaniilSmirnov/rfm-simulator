extends Node
# Browser radio backend: the WebRTC mesh lives in web/voice-chat.js. Results
# come back as JSON strings because JavaScriptBridge.eval only returns
# primitives.

static func supported() -> bool:
	return OS.has_feature("web") and _eval("typeof RallyVoice === 'object' && typeof RTCPeerConnection === 'function'") == true

func join(options: Dictionary) -> bool:
	return _eval("RallyVoice.join(%s)" % JSON.stringify(options)) == true

func leave() -> void:
	_eval("RallyVoice.leave()")

func sync_members(ids: Array) -> void:
	_eval("RallyVoice.syncMembers(%s)" % JSON.stringify(ids))

func on_signal(from: String, data: Dictionary) -> void:
	_eval("RallyVoice.onSignal(%s,%s)" % [JSON.stringify(from), JSON.stringify(data)])

func set_ptt(value: bool) -> void:
	_eval("RallyVoice.setPtt(%s)" % ("true" if value else "false"))

# {signals, mic, events, connected} like the native backend.
func tick(levels: Array) -> Dictionary:
	var raw = _eval("RallyVoice.tick(%s)" % JSON.stringify(JSON.stringify(levels)))
	var result = JSON.parse_string(str(raw)) if raw is String else null
	return result if result is Dictionary else {}

static func _eval(code: String):
	if not OS.has_feature("web"):
		return null
	return JavaScriptBridge.eval(code, true)
