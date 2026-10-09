extends Node

# Actual browser/WASM regression for room creation routing.
# Test runner supplies a signed VK fixture and a 409 sentinel room API response.
func _ready() -> void:
	call_deferred("_verify")

func _verify() -> void:
	var game = load("res://main.tscn").instantiate()
	add_child(game)
	var deadline = Time.get_ticks_msec() + 15000
	while game.platform_service.profile.get("platform", "") != "vk" and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if game.platform_service.profile.get("platform", "") != "vk":
		push_error("ROOM_ORIGIN_FAIL: VK profile did not load")
		return
	var endpoint: String = game.room.room_endpoint("create")
	if not endpoint.begins_with("http") or not endpoint.ends_with("/api/rooms") or endpoint.contains("127.0.0.1:8787"):
		push_error("ROOM_ORIGIN_FAIL: wrong room endpoint " + endpoint)
		return
	game.room.connect_room("")
	deadline = Time.get_ticks_msec() + 15000
	while game.room.busy and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if game.room.lobby_status.text != "VK_ROOM_ORIGIN_PROBE_REJECTED":
		push_error("ROOM_ORIGIN_FAIL: request did not reach same-origin room API; status=" + game.room.lobby_status.text)
		return
	print("VK_ROOM_ORIGIN_PASS: Godot HTTPRequest reached same-origin /api/rooms using verified VK session")
