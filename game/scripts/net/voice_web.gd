extends Node
# Browser radio backend: the WebRTC mesh lives in web/voice-chat.js. The mini
# Web engine has no JavaScript bridge, so calls are batched into a same-origin
# request that web/platform/transport.js answers inside the page; it never
# reaches the network. Replies come back a frame or two later: tick() hands
# over what arrived since the previous tick.
const PATH = "/__rally_voice"
const MAX_BODY = 262144

var origin := ""
var http: HTTPRequest
var calls: Array = []
var busy := false
# What the room asked for last; a reply that disagrees means no browser voice.
var want_joined := false
var lost := false
var signals: Array = []
var events: Array = []
var connected := 0

# Whether the page really has voice is only known from the first reply.
static func supported() -> bool:
	return OS.has_feature("web")

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--room-server="):
			origin = arg.trim_prefix("--room-server=").trim_suffix("/")
	http = HTTPRequest.new()
	http.timeout = 5.0
	http.accept_gzip = false
	http.body_size_limit = MAX_BODY
	add_child(http)
	http.request_completed.connect(_response)

func join(options: Dictionary) -> bool:
	want_joined = true
	lost = false
	_call(["join", options])
	return true

func leave() -> void:
	want_joined = false
	_call(["leave"])

func sync_members(ids: Array) -> void:
	_call(["syncMembers", ids])

func on_signal(from: String, data: Dictionary) -> void:
	_call(["onSignal", from, data])

func ring_again() -> void:
	_call(["ringAgain"])

func set_ptt(value: bool) -> void:
	_call(["setPtt", value])

# {signals, events, connected} like the native backend; joined is false once
# the page turned out to have no voice.
func tick(levels: Array) -> Dictionary:
	_call(["tick", levels])
	var result = {"signals": signals, "events": events, "connected": connected}
	if lost:
		result.joined = false
	signals = []
	events = []
	return result

func _call(call: Array) -> void:
	calls.append(call)
	_flush()

func _process(_delta: float) -> void:
	_flush()

func _flush() -> void:
	if busy or calls.is_empty() or http == null:
		return
	var body = JSON.stringify({"calls": calls})
	calls = []
	busy = http.request(origin + PATH, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body) == OK
	if not busy:
		_failed()

func _response(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
	busy = false
	var data = JSON.parse_string(bytes.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else null
	if not data is Dictionary:
		_failed()
		return
	for reply in data.get("results", []):
		if reply is Dictionary:
			signals.append_array(reply.get("signals", []))
			events.append_array(reply.get("events", []))
			connected = int(reply.get("connected", connected))
	# Only a reply to every call so far shows the page's final answer.
	if want_joined and calls.is_empty() and data.get("joined") == false:
		lost = true
	_flush()

func _failed() -> void:
	if want_joined:
		lost = true
