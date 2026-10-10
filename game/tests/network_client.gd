extends Node
# Drives the real Room HTTP client; only controls and observations are test-specific.
var game
var role = "host"
var join_id = ""
var control: HTTPRequest
var last_command = -1
var poll_clock = 0.0
var report_clock = 0.0
func _ready() -> void:
	# Browser transport tests keep real physics, without two software-rendered forests.
	if OS.has_feature("web"):
		RenderingServer.render_loop_enabled = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--network-role="): role = arg.trim_prefix("--network-role=")
		if arg.begins_with("--network-room="): join_id = arg.trim_prefix("--network-room=")
	last_command = int(ProjectSettings.get_setting("network_test/last_" + role, -1))
	game = load("res://main.tscn").instantiate()
	add_child(game)
	control = HTTPRequest.new()
	add_child(control)
	control.request_completed.connect(on_control)
	game.room.ui.name_input.text = role
	game.room.connect_room(join_id)
func _process(delta: float) -> void:
	poll_clock += delta
	report_clock += delta
	if poll_clock >= 0.2 and control.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
		poll_clock = 0
		control.request(game.room.transport.server + "/test/control?role=" + role)
	if report_clock >= 0.2:
		report_clock = 0
		var p = game.room.prediction
		var sample = {"role": role, "connected": game.room.connected, "room": game.room.room_id, "player": game.room.player_id, "enabled": game.room.prediction_enabled, "active": p.active, "ack": p.ack, "seq": p.seq, "pending": p.pending.size(), "pos": game.room.a(game.car.position), "speed": game.speed, "condition": game.condition, "dead": game.dead, "paused": game.paused, "world_paused": game.room.world_paused, "in_car": game.in_car, "driving": {}}
		for id in game.room.host_drives:
			sample.driving[id] = game.room.host_drives[id].snapshot()
		sample.safe_area_ready = game.mobile_safe_rect.has_area()
		sample.direct = game.room.direct.open_links().size()
		sample.direct_healthy = not game.room.is_host and game.room.direct.healthy(game.room.host_id)
		print("NETWORK_SAMPLE ", JSON.stringify(sample))
func on_control(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if code != 200: return
	var command = JSON.parse_string(body.get_string_from_utf8())
	if not command is Dictionary or int(command.id) == last_command: return
	last_command = int(command.id)
	ProjectSettings.set_setting("network_test/last_" + role, last_command)
	for action in ["forward", "left", "right", "brake", "back"]:
		Input.action_release(action)
	match command.action:
		"forward":
			game.paused = false
			Input.action_press("forward")
		"brake": Input.action_press("brake")
		"pause": game.paused = true
		"resume": game.paused = false
		"recover": game.room.recover_drive()
		"exit", "enter": game._toggle_car()
		"rejoin": game.room.leave()
