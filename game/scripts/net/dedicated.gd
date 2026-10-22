extends Node
# Dedicated server: the game run headless on a host of ours, with no player of
# its own. It creates a room through the room server, simulates the stage as
# that room's host and stays invisible: guests do not draw it (room.gd
# _update_peers), and its walker and car wait under the map.
#   godot --headless --path game -- --dedicated --stage=3 [--room=A1B2C3] [--room-server=https://…] [--max-fps=60] [--idle-restart=300]
# The room server lets only a holder of its DEDICATED_TOKEN create such a room
# (and pick its ID); the key is read from RALLY_DEDICATED_TOKEN, never from the
# command line, which other users of the host can read.
# The day stands still while the room is empty, so an empty server costs little
# and the first guest finds the day at its start. Once a day has begun and
# nobody has been in for --idle-restart seconds, the room starts over (a fresh
# day, the same fixed ID); so it does after a lost connection.
const NetProtocol = preload("res://scripts/net/net_protocol.gd")
const OFF_MAP = Vector3(0, -500, 0)
const RETRY_SECONDS = 10.0
const STATUS_SECONDS = 60.0

static var _active = -1

static func active() -> bool:
	if _active < 0:
		_active = 1 if "--dedicated" in OS.get_cmdline_user_args() else 0
	return _active == 1

static func option(key: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % key):
			return arg.get_slice("=", 1)
	return fallback

static func token() -> String:
	return OS.get_environment("RALLY_DEDICATED_TOKEN")

# What a create request adds: the mark, and the room ID to take, if any.
static func create_fields() -> Dictionary:
	var fields = {"dedicated": true}
	var id = option("room", "").to_upper()
	if NetProtocol.valid_room_id(id):
		fields.room = id
	return fields

# Where the world around players comes to life (rally crews, villagers): at the
# longest-standing guest, or the start of the stage while nobody is there.
static func focus(game) -> Vector3:
	for id in game.room.peers:
		var state = game.room.peers[id].state
		if state != null:
			return game.room.v(state.pos)
	return game.stage.at(45)

var game: Node
var room: Node
var idle = 0.0
var retry = 0.0
var status_clock = 0.0
var joined = false

func _ready() -> void:
	room = get_parent()
	game = room.game
	Engine.max_fps = maxi(10, int(option("max-fps", "60")))
	if token().is_empty():
		push_warning("[RFM dedicated] RALLY_DEDICATED_TOKEN is empty: the room server will refuse the room")
	call_deferred("_connect")

func _connect() -> void:
	game.select_stage(int(option("stage", "0")))
	room.ui.name_input.text = option("name", "Сервер")
	room.connect_room("")

func _process(delta: float) -> void:
	if room.connected:
		joined = true
		retry = 0.0
		game.in_car = false
		game.walker = OFF_MAP
		game.car.position = OFF_MAP
		game.paused = room.peers.is_empty()
		idle = 0.0 if not game.paused else idle + delta
		var limit = float(option("idle-restart", "300"))
		if limit > 0 and idle > limit and game.elapsed > 0:
			print("[RFM dedicated] nobody for %d s: starting the room over" % int(idle))
			restart()
		_status(delta)
	elif not room.busy and not game.loading_world:
		retry += delta
		if retry >= RETRY_SECONDS:
			retry = 0.0
			if joined or game.playing:
				print("[RFM dedicated] room lost: starting over")
				game.get_tree().reload_current_scene()
			else:
				print("[RFM dedicated] creating the room again")
				room.connect_room("")

func restart() -> void:
	set_process(false)
	# The leave's answer reloads the scene (room._on_left), which starts a new room.
	room.leave()

func _status(delta: float) -> void:
	status_clock += delta
	if status_clock < STATUS_SECONDS:
		return
	status_clock = 0.0
	print("[RFM dedicated] room=%s guests=%d phase=%s elapsed=%ds fps=%d%s" % [room.room_id, room.peers.size(), game.course.phase, int(game.elapsed), Engine.get_frames_per_second(), " (waiting)" if game.paused else ""])
