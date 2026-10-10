extends "res://tests/harness.gd"

const Transport = preload("res://scripts/room_transport.gd")


func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	check(Transport.default_server(true) == "", "browser never defaults to localhost")
	check(Transport.default_server(false) == "http://127.0.0.1:8787", "native dev default preserved")
	var instance = Transport.new()
	instance.server = "https://rally-test.example"
	check(instance.endpoint("create", "AB12EF") == "https://rally-test.example/api/rooms", "create targets same-origin room API")
	check(instance.endpoint("join", "AB12EF") == "https://rally-test.example/api/rooms/AB12EF/join", "join targets correct room")
	check(instance.endpoint("sync", "AB12EF") == "https://rally-test.example/api/rooms/AB12EF/sync", "sync targets correct room")
	instance.free()
	print("ROOM_ORIGIN_UNIT_RESULT ", failures)
	finish()
