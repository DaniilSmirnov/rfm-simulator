extends Node
# Native DOM input is focused directly by a touch, without an asynchronous bridge.
var field: LineEdit
var http: HTTPRequest
var revision = 0
func _ready() -> void:
	http = HTTPRequest.new()
	http.accept_gzip = false
	http.timeout = 3
	add_child(http)
	http.request_completed.connect(_response)
	var timer = Timer.new()
	timer.wait_time = 0.3
	timer.timeout.connect(_sync)
	add_child(timer)
	timer.start()
	_sync()
func _sync() -> void:
	if http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	var rect = field.get_global_rect()
	var size = field.get_viewport_rect().size
	var payload = {"visible": get_parent().game.mobile_mode and field.is_visible_in_tree() and field.editable, "text": field.text, "revision": revision,
		"rect": [rect.position.x / size.x, rect.position.y / size.y, rect.size.x / size.x, rect.size.y / size.y]}
	http.request(get_parent().server + "/__rally_room_input", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(payload))
func _response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or int(data.get("revision", 0)) <= revision:
		return
	revision = int(data.revision)
	field.text = str(data.get("text", "")).to_upper().substr(0, 6)
	field.text_changed.emit(field.text)
