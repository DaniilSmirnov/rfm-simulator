extends "res://tests/harness.gd"

const Room = preload("res://scripts/room.gd")


func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	check(Room.default_server(true) == "", "browser never defaults to localhost")
	check(Room.default_server(false) == "http://127.0.0.1:8787", "native dev default preserved")
	var instance = Room.new()
	instance.server = "https://rally-test.example"
	instance.room_id = "AB12EF"
	check(instance.room_endpoint("create") == "https://rally-test.example/api/rooms", "create targets same-origin room API")
	check(instance.room_endpoint("join") == "https://rally-test.example/api/rooms/AB12EF/join", "join targets correct room")
	check(instance.room_endpoint("sync") == "https://rally-test.example/api/rooms/AB12EF/sync", "sync targets correct room")
	instance.free()
	print("ROOM_ORIGIN_UNIT_RESULT ", failures)
	finish()
