extends Node
# HTTPRequest is handled in the web shell; this URL never reaches the backend.
signal profile_ready(profile: Dictionary)
signal failed(message: String)
var profile: Dictionary = {}
var http: HTTPRequest

func _ready() -> void:
	if not OS.has_feature("web"):
		return
	http = HTTPRequest.new()
	http.timeout = 15.0
	http.accept_gzip = false
	http.body_size_limit = 4096
	add_child(http)
	http.request_completed.connect(_response)
	var origin = ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--room-server="):
			origin = arg.trim_prefix("--room-server=").trim_suffix("/")
	var error = http.request(origin + "/__rally_platform", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify({"method": "getProfile"}))
	if error != OK:
		failed.emit("Не удалось запросить профиль платформы")

func _response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var data = JSON.parse_string(body.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not data is Dictionary or not data.get("result") is Dictionary:
		failed.emit("Не удалось получить профиль платформы")
		return
	profile = data.result
	print("[RFM Platform] profile ", JSON.stringify(profile))
	profile_ready.emit(profile)
