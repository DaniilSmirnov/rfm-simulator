extends "res://tests/harness.gd"
const Validation = preload("res://scripts/net/world_validation.gd")

class ReplyProbe:
	extends RefCounted
	var connected = true
	var is_host = false
	var failures = 0
	func _on_failure(_kind, _code, _message, _data): failures += 1
	func _on_reply(_kind, _data): pass

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/world_snapshots.json"))
	for sample in fixtures.valid:
		check(Validation.valid(sample.world), "accepts " + sample.name)
	for sample in fixtures.invalid:
		check(not Validation.valid(sample.world), "rejects " + sample.name)
	check(not Validation.valid({"camp": [0, INF, 0]}), "rejects non-finite native values")
	var transport = load("res://scripts/net/room_transport.gd").new()
	var probe = ReplyProbe.new()
	transport.room = probe
	transport.request_kind = "sync"
	transport.errors = 2
	var reply = {"players": [], "accepted": 0, "world": {"driving": 17}}
	transport.handle_http(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(reply).to_utf8_buffer())
	check(probe.failures == 1 and transport.errors == 2, "malformed HTTP world never clears transport failures")
	reply.type = "reply"
	transport._socket_message(JSON.stringify(reply))
	check(probe.failures == 2 and transport.errors == 2, "malformed socket world never clears transport failures")
	transport.free()
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.start_game()
	var full: Dictionary = game.room.world_state()
	check(Validation.valid(full), "accepts the complete actual game world")
	game.passed = 3
	for sample in fixtures.invalid:
		var bad: Dictionary = sample.world.duplicate(true)
		bad.passed = 99
		game.room.apply_world(bad)
		check(game.passed == 3, "invalid world is atomic: " + sample.name)
	game.room.connected = true
	game.room.is_host = false
	game.room.host_id = "host"
	var before: float = game.room.authority_stamp
	game.room._guest_world({"driving": 17}, 99999, [], true)
	check(game.room.authority_stamp == before, "invalid authority never advances the accepted timestamp")
	game.room.direct._receive("host", {"t": "w", "time": 99999, "world": {"passed": 99}, "players": [{"id": "guest", "state": {"pos": [0, 1, 2], "heading": 0, "yaw": 0, "pitch": 0, "in_car": true, "tilt": []}}]})
	check(game.passed == 3 and game.room.authority_stamp == before, "malformed direct compact state cannot partially apply the world")
	var packet = {"t": "w", "time": "bad", "world": {"passed": 99}, "players": []}
	game.room.direct._receive("host", packet)
	check(game.passed == 3 and game.room.authority_stamp == before, "invalid direct time cannot partially apply the world")
	packet.time = 1000000000000
	packet.players = [{"id": "guest", "state_time": [], "state": {"pos": [0, 1, 2], "heading": 0, "yaw": 0, "pitch": 0, "in_car": true}}]
	game.room.direct._receive("host", packet)
	check(game.passed == 3 and game.room.authority_stamp == before, "invalid direct member time cannot partially apply the world")
	var compact = {"pos": [0, 1, 2], "heading": 0, "yaw": 0, "pitch": 0, "in_car": false, "push": [], "stand": "car:host", "stand_at": []}
	var entry = game.room.direct._full_entry({"id": "guest", "state": compact})
	check(entry.state.push == [0.0, 0.0, 0.0] and entry.state.stand == "", "direct state normalizes malformed optional tuples")
	game.room.world_sync.apply_cold({"cold": {"camp": {"camp": [1], "passed": 99}}}, 1)
	check(game.passed == 3, "invalid cold state is discarded before providers apply")
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	finish()
