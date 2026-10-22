extends "res://tests/harness.gd"

class SilentSocket extends RefCounted:
	var closed = false
	func poll() -> void: pass
	func get_ready_state() -> int: return 1
	func get_available_packet_count() -> int: return 0
	func get_current_outbound_buffered_amount() -> int: return 0
	func send_text(_text: String) -> int: return OK
	func close() -> void: closed = true

func _initialize() -> void:
	call_deferred("run")

func failure(room, socket: bool, status: int) -> void:
	if socket:
		room.transport._socket_message(JSON.stringify({"type": "error", "status": status, "error": "Recovery test error"}))
	else:
		room.transport.request_kind = "sync"
		room._response(HTTPRequest.RESULT_SUCCESS if status else HTTPRequest.RESULT_CANT_CONNECT, status, PackedStringArray(), JSON.stringify({"error": "Recovery test error"}).to_utf8_buffer())

func success(room, socket: bool) -> void:
	var reply = {"type": "reply", "id": 0, "players": [], "accepted": 0}
	if socket:
		room.transport._socket_message(JSON.stringify(reply))
	else:
		room._response(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(reply).to_utf8_buffer())

func outage(room, socket: bool) -> void:
	room.connected = true
	room.commands = [{"seq": 1, "action": "table"}]
	room.acknowledgements = ["guest:2"]
	room.prediction.pending.clear()
	room.prediction.pending.append({"seq": 3, "ticks": 1})
	var identity = [room.room_id, room.player_id, room.token]
	if socket:
		room.transport.socket_open = true
	for i in range(6):
		failure(room, socket, 500 if socket else 0)
	check(room.connected, "repeated %s failures preserve membership" % ("socket" if socket else "HTTP"))
	check(room.clock < 0 and room.transport.errors > 0, "transient failures back off syncs")
	check(not room.transport.socket_open, "server errors leave HTTP fallback available")
	check(room.commands.size() == 1 and room.acknowledgements == ["guest:2"] and room.prediction.pending.size() == 1, "outage preserves commands, acknowledgements and prediction")
	check([room.room_id, room.player_id, room.token] == identity, "outage preserves room identity")
	if not room.connected:
		return
	for seconds in [5, 15, 30]:
		room.transport.recovery_started_at = room.transport.now() - seconds
		failure(room, socket, 503)
		check(room.connected and room.clock >= -5.0, "%ds outage remains recoverable with capped backoff" % seconds)
	success(room, not socket)
	check(room.transport.recovery_started_at == -INF and room.transport.errors == 0, "success on either transport resets shared recovery episode")
	check(room.commands.size() == 1 and room.prediction.pending.size() == 1, "recovered reply retains unaccepted commands and prediction")
	failure(room, socket, 500)
	room.transport._socket_message(JSON.stringify({"type": "push", "players": [], "accepted": 0}))
	check(room.transport.recovery_started_at == -INF and room.transport.errors == 0, "successful socket push also resets recovery")
	failure(room, socket, 500)
	check(room.connected, "a later outage starts a fresh recovery episode")
	room.transport.recovery_started_at = room.transport.now() - 46.0
	failure(room, socket, 500)
	check(not room.connected and room.game.menu_text.text == "Recovery test error", "persistent outage ends after finite recovery window")

func stalled_socket(room) -> void:
	room.connected = true
	room.transport.reset_recovery()
	var socket = SilentSocket.new()
	room.transport.socket = socket
	room.transport.socket_open = true
	room.transport.socket_hello = true
	room.transport.poll(0.1)
	check(not socket.closed, "idle socket without outstanding sync does not time out")
	room.transport._send_socket({"token": room.token})
	if "socket_waiting_since" in room.transport:
		room.transport.socket_waiting_since = room.transport.now() - 9.0
	for i in range(40):
		room.transport._send_socket({"token": room.token})
	room.transport._socket_message('{"type":"reply","players":[],"accepted":0,"world":17}')
	for i in range(5):
		room.transport._socket_message('{"type":"push","players":[],"accepted":0}')
	room.transport.poll(0.1)
	check(socket.closed and not room.transport.socket_open, "unanswered sync falls back to HTTP despite continuous sends and incoming pushes")
	check(room.connected and room.transport.errors == 1 and room.clock < 0, "socket silence starts one bounded recovery episode")
	check(room.commands.size() == 1 and room.acknowledgements == ["guest:2"] and room.prediction.pending.size() == 1, "socket timeout preserves queued work")
	room.transport.poll(0.1)
	check(room.transport.errors == 1, "timed out socket reports failure only once")

func resumed_outage(room) -> void:
	room.connected = true
	room.transport.reset_recovery()
	failure(room, false, 500)
	room.transport.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	room.transport.recovery_started_at = room.transport.now() - 65.0
	if "suspended_at" in room.transport:
		room.transport.suspended_at = room.transport.now() - 60.0
	failure(room, false, 500)
	check(room.connected, "background callbacks do not consume suspended recovery time")
	room.transport.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	failure(room, false, 500)
	check(room.connected, "suspended time does not exhaust active recovery budget on resume")
	room.transport.recovery_started_at = room.transport.now() - 46.0
	failure(room, false, 500)
	check(not room.connected, "active outage still expires after a resume")

func correlated_reply(room) -> void:
	room.connected = true
	var socket = SilentSocket.new()
	room.transport.socket = socket
	room.transport.socket_open = true
	room.transport.socket_hello = true
	room.transport._send_socket({"token": room.token})
	var id = room.transport.message_id
	room.transport.socket_waiting_since = room.transport.now() - 9.0
	var reply = {"type": "reply", "id": id + 1, "players": [], "accepted": 0}
	room.transport._socket_message(JSON.stringify(reply))
	check(room.transport.socket_waiting_since != -INF, "uncorrelated reply cannot acknowledge an outstanding sync")
	reply.id = id
	room.transport._socket_message(JSON.stringify(reply))
	check(room.transport.socket_waiting_since == -INF, "correlated reply clears outstanding sync watchdog")
	room.transport.poll(0.1)
	check(not socket.closed, "acknowledged sync does not trigger stale socket timeout")
	room.transport.close_socket()

func malformed_socket_numbers(room) -> void:
	room.connected = true
	room.transport.reset_recovery()
	failure(room, false, 500)
	for extra in [{"id": {}}, {"id": 1, "server_time": []}]:
		var reply = {"type": "reply", "id": 0, "players": [], "accepted": 0}
		reply.merge(extra, true)
		room.transport.message_times[1] = room.transport.now()
		room.transport._socket_message(JSON.stringify(reply))
		check(room.transport.errors == 1, "malformed numeric socket fields cannot reset recovery")

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.start_game()
	var room = game.room
	room.room_id = "ABC123"
	room.player_id = "guest"
	room.token = "same-token"
	room.transport.socket_enabled = false
	outage(room, false)
	room.transport.reset_recovery()
	outage(room, true)
	stalled_socket(room)
	correlated_reply(room)
	malformed_socket_numbers(room)
	resumed_outage(room)
	for socket in [false, true]:
		for status in [400, 413, 401, 404, 410]:
			room.connected = true
			room.transport.errors = 0
			failure(room, socket, status)
			check(not room.connected and game.menu_text.text == "Recovery test error", "%s %d is a visible terminal failure" % ["socket" if socket else "HTTP", status])
		# One host sync the server refuses (too large, malformed) is not fatal.
		room.is_host = true
		for status in [413, 400]:
			room.connected = true
			room.transport.reset_recovery()
			room.world_sync.server_cold_revs = {"trees": 1}
			failure(room, socket, status)
			check(room.connected and room.world_sync.server_cold_revs.is_empty(), "%s host sync refused with %d keeps the room and resends cold sections" % ["socket" if socket else "HTTP", status])
		for i in range(room.transport.MAX_REFUSED_SYNCS):
			failure(room, socket, 413)
		check(not room.connected, "%s host gives up after repeated refused syncs" % ("socket" if socket else "HTTP"))
		room.is_host = false
		room.connected = true
		room.transport.reset_recovery()
		failure(room, socket, 429)
		check(room.connected and room.transport.errors == 0 and room.transport.recovery_started_at == -INF and room.clock <= -1, "rate limiting backs off without a transport failure")
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	print("ROOM_RECOVERY RESULT: %d checks, %d failures" % [checks, failures])
	finish()
