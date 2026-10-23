extends Node
# Dedicated server: the game run headless on a host of ours, with no player of
# its own. It creates a room through the room server, simulates the stage as
# that room's host and stays invisible: guests do not draw it (room.gd
# _update_peers), and its walker and car wait under the map.
#   godot --headless --path game -- --dedicated --stage=3 [--room=A1B2C3] [--room-server=https://…] [--max-fps=60] [--idle-restart=300] [--crews=10] [--max-players=8]
# The room server lets only a holder of its DEDICATED_TOKEN create such a room
# (and pick its ID); the key is read from RALLY_DEDICATED_TOKEN, never from the
# command line, which other users of the host can read.
# The day stands still while the room is empty, so an empty server costs little
# and the first guest finds the day at its start. Once a day has begun and
# nobody has been in for --idle-restart seconds, the room starts over (a fresh
# day, the same fixed ID); so it does after a lost connection.
# Commands typed into the server's terminal (dedicated_console.gd) switch the
# stage, set the crews and the room size and hold the day; `help` lists them.
const NetProtocol = preload("res://scripts/net/net_protocol.gd")
const Console = preload("res://scripts/net/dedicated_console.gd")
const StageRegistry = preload("res://scripts/stages/stage_registry.gd")
const OFF_MAP = Vector3(0, -500, 0)
const RETRY_SECONDS = 10.0
const STATUS_SECONDS = 60.0
# A stage switch waits this long so the guests read why the room closes.
const SWITCH_SECONDS = 4.0
# Crews per pass: the service parks have a bay for ten (service_parks.gd KEYS).
const MAX_CREWS = 10
const HELP = [
	"Commands:",
	"status          the room, its stage, guests and crews",
	"stage N|id      switch the stage: the room starts over under the same ID, guests join again",
	"crews N         rally crews in each pass, 0-%d",
	"players N       guests let in, 1-%d (those already in stay)",
	"pause / resume  hold the day / let it go on",
	"restart         start the day over on the same stage",
]

static var _active = -1
# What the console changed: it outlives the scene reloads that start a room
# over. -1 takes the command line's value.
static var stage = -1
static var crews = -1
static var players = -1

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
	fields.max_players = max_players()
	return fields

static func max_players() -> int:
	if players < 0:
		players = clampi(int(option("max-players", str(NetProtocol.max_players()))), 1, NetProtocol.max_players())
	return players

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
# Held by the `pause` command; an empty room waits anyway.
var held = false
var switch_clock = -1.0

func _ready() -> void:
	room = get_parent()
	game = room.game
	Engine.max_fps = maxi(10, int(option("max-fps", "60")))
	if token().is_empty():
		push_warning("[RFM dedicated] RALLY_DEDICATED_TOKEN is empty: the room server will refuse the room")
	if stage < 0:
		stage = clampi(int(option("stage", "0")), 0, StageRegistry.count() - 1)
	if crews < 0:
		crews = clampi(int(option("crews", str(MAX_CREWS))), 0, MAX_CREWS)
	game.rally_crew_limit = crews
	Console.start()
	call_deferred("_connect")

func _connect() -> void:
	game.select_stage(stage)
	room.ui.name_input.text = option("name", "Сервер")
	room.connect_room("")

func _process(delta: float) -> void:
	for line in Console.take():
		command(line)
	if switch_clock >= 0.0:
		switch_clock -= delta
		if switch_clock < 0.0:
			restart()
			return
	if room.connected:
		joined = true
		retry = 0.0
		game.in_car = false
		game.walker = OFF_MAP
		game.car.position = OFF_MAP
		game.paused = held or room.peers.is_empty()
		idle = 0.0 if not room.peers.is_empty() else idle + delta
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
	if not room.connected:
		game.get_tree().reload_current_scene()
		return
	# The leave's answer reloads the scene (room._on_left), which starts a new room.
	room.leave()

# ---------------------------------------------------------------- console

func command(line: String) -> void:
	var words = line.split(" ", false)
	var arg = words[1] if words.size() > 1 else ""
	match words[0].to_lower():
		"help", "?":
			say("\n  ".join(HELP) % [MAX_CREWS, NetProtocol.max_players()])
		"status":
			say(status_line())
		"stage":
			switch_stage(arg)
		"crews":
			set_crews(arg)
		"players":
			set_players(arg)
		"pause":
			held = true
			game.toast("Сервер поставил день на паузу")
			say("paused")
		"resume":
			held = false
			game.toast("Сервер снял паузу")
			say("resumed" + (" (nobody in: the day waits for a guest)" if room.peers.is_empty() else ""))
		"restart":
			_announce_restart("starting the day over", "Сервер начинает день заново. Зайди снова по тому же ID через несколько секунд.")
		_:
			say("unknown command '%s'; help lists them" % words[0])

func switch_stage(arg: String) -> void:
	var index = StageRegistry.index_of(arg.to_lower())
	if index < 0 and arg.is_valid_int():
		index = int(arg)
	if index < 0 or index >= StageRegistry.count():
		var names = PackedStringArray()
		for i in range(StageRegistry.count()):
			names.append("%d %s" % [i, StageRegistry.entry(i).id])
		say("stage N|id, one of:\n  " + "\n  ".join(names))
		return
	if index == stage:
		say("the room is on stage %d %s already" % [index, StageRegistry.entry(index).id])
		return
	stage = index
	_announce_restart("switching to stage %d %s" % [index, StageRegistry.entry(index).id], "Сервер меняет СУ. Зайди снова по тому же ID через несколько секунд.")

# Guests read why the room closes (the notice travels with the snapshots, in
# their language) before it does.
func _announce_restart(text: String, notice: String) -> void:
	held = false
	if room.peers.is_empty():
		say(text + " now")
		restart()
		return
	game.toast(notice)
	switch_clock = SWITCH_SECONDS
	say("%s in %d s" % [text, int(SWITCH_SECONDS)])

func set_crews(arg: String) -> void:
	if not arg.is_valid_int() or int(arg) < 0 or int(arg) > MAX_CREWS:
		say("crews N, N from 0 to %d (now %d)" % [MAX_CREWS, crews])
		return
	crews = int(arg)
	game.rally_crew_limit = crews
	game.toast("Сервер изменил число экипажей")
	say("%d crews a pass (started in this pass: %d)" % [crews, game.rally_spawn_count])

func set_players(arg: String) -> void:
	if not arg.is_valid_int() or int(arg) < 1 or int(arg) > NetProtocol.max_players():
		say("players N, N from 1 to %d (now %d)" % [NetProtocol.max_players(), max_players()])
		return
	players = int(arg)
	say("up to %d guests (in the room: %d)" % [players, room.peers.size()])

func status_line() -> String:
	return "room=%s stage=%d %s guests=%d/%d crews=%d phase=%s pass=%d elapsed=%ds fps=%d%s" % [room.room_id, stage, StageRegistry.entry(stage).id, room.peers.size(), max_players(), crews, game.course.phase, game.course.pass_index, int(game.elapsed), Engine.get_frames_per_second(), " (pause)" if held else (" (waiting)" if game.paused else "")]

func say(text: String) -> void:
	print("[RFM dedicated] " + text)

func _status(delta: float) -> void:
	status_clock += delta
	if status_clock < STATUS_SECONDS:
		return
	status_clock = 0.0
	say(status_line())
