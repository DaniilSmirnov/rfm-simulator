extends Node
# HTTPRequest is handled in the web shell; this URL never reaches the backend.
signal profile_ready(profile: Dictionary)
signal failed(message: String)
var profile: Dictionary = {}
var entitlements: Dictionary = {"mode": "unrestricted", "skus": []}
var catalog: Array = []
var http: HTTPRequest

func can_use(kind: String, index: int, guest: bool = false) -> bool:
	if entitlements.get("mode", "restricted") == "unrestricted":
		return true
	for product in catalog:
		if product.get("type") == kind and product.get("content_id") == index:
			return product.get("enabled", false) and (product.get("free", false) or product.get("sku") in entitlements.get("skus", []) or (kind == "stage" and guest))
	return false

func _ready() -> void:
	if OS.has_feature("vk"):
		entitlements = {"mode": "restricted", "skus": []}
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
	var error = http.request(origin + "/__rally_platform", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify({"method": "getBootstrap"}))
	if error != OK:
		failed.emit("Не удалось запросить профиль платформы")

func _response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var data = JSON.parse_string(body.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not data is Dictionary or not data.get("result") is Dictionary:
		failed.emit("Не удалось получить профиль платформы")
		return
	var bootstrap: Dictionary = data.result
	if not bootstrap.get("profile") is Dictionary or not bootstrap.get("entitlements") is Dictionary:
		failed.emit("Некорректные права платформы")
		return
	profile = bootstrap.profile
	entitlements = bootstrap.entitlements
	catalog = bootstrap.get("catalog", [])
	print("[RFM Platform] profile ", JSON.stringify(profile))
	print("[RFM Platform] access ", JSON.stringify({"mode": entitlements.get("mode"), "stage_1": can_use("stage", 0), "stage_2": can_use("stage", 1), "car_3": can_use("car", 2), "car_4": can_use("car", 3)}))
	profile_ready.emit(profile)
