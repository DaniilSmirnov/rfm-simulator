extends Node
signal completed(result: int, code: int, headers: PackedStringArray, body: PackedByteArray)
var http: HTTPRequest
var request_bytes = 0
var response_bytes = 0
var maximum_request_bytes = 0

func _ready() -> void:
	http = HTTPRequest.new()
	http.timeout = 8
	http.accept_gzip = not OS.has_feature("web")
	http.body_size_limit = 131072
	add_child(http)
	http.request_completed.connect(_completed)

func send(url: String, body: Dictionary) -> void:
	var encoded = JSON.stringify(body)
	request_bytes = encoded.to_utf8_buffer().size()
	maximum_request_bytes = maxi(maximum_request_bytes, request_bytes)
	var error = http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, encoded)
	if error != OK:
		completed.emit(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())

func _completed(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	response_bytes = body.size()
	completed.emit(result, code, headers, body)
