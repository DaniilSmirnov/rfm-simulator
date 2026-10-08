extends Node
# HTTPRequest is handled in the web shell; this URL never reaches the backend.
signal profile_ready(profile: Dictionary)
signal failed(message: String)
signal purchase_changed
signal invite_feedback(message: String)
var busy = false
var purchase_message = ""
var origin = ""
var profile: Dictionary = {}
var entitlements: Dictionary = {"mode": "unrestricted", "skus": []}
var catalog: Array = []
var invite_room = ""
var invite_busy = false
var invite_http: HTTPRequest
var http: HTTPRequest

func can_use(kind: String, index: int, guest: bool = false) -> bool:
	if entitlements.get("mode", "restricted") == "unrestricted":
		return true
	for product in catalog:
		if product.get("type") == kind and product.get("content_id") == index:
			return product.get("enabled", false) and (product.get("free", false) or product.get("sku") in entitlements.get("skus", []) or (kind == "stage" and guest))
	return false

func owns(kind: String, index: int) -> bool:
	var entry = product(kind, index)
	return entitlements.get("mode") == "restricted" and entry.get("sku", "") in entitlements.get("skus", [])

func _ready() -> void:
	if OS.has_feature("vk"):
		entitlements = {"mode": "restricted", "skus": []}
	if not OS.has_feature("web"):
		return
	http = HTTPRequest.new()
	http.timeout = 120.0
	http.accept_gzip = false
	http.body_size_limit = 16384
	add_child(http)
	http.request_completed.connect(_response)
	invite_http = HTTPRequest.new()
	invite_http.timeout = 30.0
	invite_http.accept_gzip = false
	invite_http.body_size_limit = 4096
	add_child(invite_http)
	invite_http.request_completed.connect(_invite_response)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--room-server="):
			origin = arg.trim_prefix("--room-server=").trim_suffix("/")
	_request("getBootstrap")

func product(kind: String, index: int) -> Dictionary:
	for entry in catalog:
		if entry.get("type") == kind and entry.get("content_id") == index:
			return entry
	return {}

func _request(method: String, sku: String = "") -> void:
	if busy or http == null:
		return
	busy = true
	purchase_message = "Ожидаем VK…" if method == "buy" else "Проверяем доступ…"
	purchase_changed.emit()
	var error = http.request(origin + "/__rally_platform", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify({"method": method, "sku": sku}))
	if error != OK:
		busy = false
		purchase_message = "Не удалось подключиться. Нажмите «Проверить покупку»."
		purchase_changed.emit()
		failed.emit("Не удалось запросить профиль платформы")

func buy(sku: String) -> void:
	_request("buy", sku)

func refresh_store() -> void:
	if profile.get("platform") == "vk":
		_request("refreshStore")

func invite_friend(id: String) -> void:
	if profile.get("platform", "") != "vk" or not OS.has_feature("web"):
		return
	if invite_busy:
		return
	if id.length() != 6 or not id.is_valid_hex_number():
		invite_feedback.emit("Не удалось определить ID комнаты.")
		return
	invite_busy = true
	invite_feedback.emit("Выбери друга в VK…")
	var payload = JSON.stringify({"method": "inviteFriend", "room_id": id.to_upper()})
	var err = invite_http.request(origin + "/__rally_platform", ["Content-Type: application/json"], HTTPClient.METHOD_POST, payload)
	if err != OK:
		invite_busy = false
		invite_feedback.emit("Не удалось открыть приглашение VK.")

func _invite_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	invite_busy = false
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not parsed is Dictionary:
		invite_feedback.emit(str(parsed.get("error", "Не удалось отправить приглашение.")) if parsed is Dictionary else "Не удалось отправить приглашение.")
		return
	if not parsed.get("result") is Dictionary:
		invite_feedback.emit("VK вернул некорректный ответ.")
		return
	match str(parsed.result.get("status", "")):
		"sent": invite_feedback.emit("Приглашение отправлено! Друг войдёт сразу в эту комнату.")
		"cancel": invite_feedback.emit("Приглашение отменено.")
		_: invite_feedback.emit("Не удалось отправить приглашение.")

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and not busy:
		refresh_store()

func _response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	busy = false
	var data = JSON.parse_string(body.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not data is Dictionary or not data.get("result") is Dictionary:
		purchase_message = "Не удалось проверить доступ. Нажмите «Проверить покупку»."
		purchase_changed.emit()
		failed.emit("Не удалось получить профиль платформы")
		return
	var bootstrap: Dictionary = data.result
	if not bootstrap.get("profile") is Dictionary or not bootstrap.get("entitlements") is Dictionary:
		purchase_message = "Ошибка проверки доступа."
		purchase_changed.emit()
		failed.emit("Некорректные права платформы")
		return
	profile = bootstrap.profile
	entitlements = bootstrap.entitlements
	catalog = bootstrap.get("catalog", [])
	invite_room = str(bootstrap.get("invite_room", ""))
	print("[RFM Platform] profile ", JSON.stringify(profile))
	print("[RFM Platform] access ", JSON.stringify({"mode": entitlements.get("mode"), "stage_1": can_use("stage", 0), "stage_2": can_use("stage", 1), "car_3": can_use("car", 2), "car_4": can_use("car", 3)}))
	purchase_message = ""
	match bootstrap.get("status", ""):
		"owned":
			if bootstrap.get("purchased_sku", "") in entitlements.get("skus", []):
				purchase_message = "Тестовая покупка подтверждена · контент открыт"
		"cancel": purchase_message = "Покупка отменена"
		"fail": purchase_message = "VK не завершил покупку"
		"pending": purchase_message = "Ждём подтверждения VK. Нажмите «Проверить покупку»."
	profile_ready.emit(profile)
	purchase_changed.emit()
