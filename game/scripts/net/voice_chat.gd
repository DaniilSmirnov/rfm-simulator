extends Node
# Push-to-talk radio between the members of a room. The audio is WebRTC in a
# backend: web/voice-chat.js in the browser (voice_web.gd), the native/voice
# GDExtension on desktop and Android (voice_native.gd). This node feeds the
# backend the roster, distances and the key, and relays its signaling over the
# room socket (`space: "voice"`). Without either backend the radio is hidden.
const NetProtocol = preload("res://scripts/net/net_protocol.gd")
const VoiceWeb = preload("res://scripts/net/voice_web.gd")
const VoiceNative = preload("res://scripts/net/voice_native.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Loc = preload("res://scripts/ui/loc.gd")
const Dedicated = preload("res://scripts/net/dedicated.gd")

# Distances, the talking flags and signaling are exchanged ten times a second.
const TICK = 0.1
# Signals waiting for the socket; offers older than this are useless anyway.
const PENDING_TTL_MSEC = 10000
const MAX_PENDING = 64

var room: Node
var backend: Node
var supported := false
var joined := false
var transmitting := false
var mic := "idle"
var connected_peers := 0
var pending: Array = []
var clock := 0.0
var socket_was_open := false
var label: Label

func setup(owner: Node) -> void:
	room = owner

func _ready() -> void:
	if VoiceWeb.supported():
		backend = VoiceWeb.new()
	elif VoiceNative.supported():
		backend = VoiceNative.new()
	supported = backend != null
	if supported:
		backend.name = "Backend"
		add_child(backend)

# The radio key and the touch button exist only where voice can work.
func available() -> bool:
	return supported and joined

# The key is held and the microphone is live: others hear us and see the pose.
func on_air() -> bool:
	return transmitting and mic == "ready" and not cut_off()

# Radio links are set up over the room socket only: on HTTP no link can open,
# and links that are already up keep working.
func cut_off() -> bool:
	return not room.transport.socket_open and connected_peers == 0

func join() -> void:
	if not supported or room.player_id == "" or Dedicated.active():
		return
	var session = ("%s-%s-%d" % [room.room_id, room.player_id, Time.get_ticks_msec()]).left(96)
	var options = {"localId": room.player_id, "session": session, "iceServers": NetProtocol.direct("ice_servers", [])}
	joined = backend.join(options)
	socket_was_open = false
	if joined:
		sync_members(room.members.keys())

# Says bye to every member while the socket is still open.
func leave() -> void:
	if not joined:
		return
	_set_ptt(false)
	backend.leave()
	_tick()
	joined = false
	pending.clear()
	connected_peers = 0
	if label != null:
		label.hide()

func sync_members(ids: Array) -> void:
	if joined:
		backend.sync_members(ids)

func on_signal(from: String, data: Dictionary) -> void:
	if joined:
		backend.on_signal(from, data)

func _process(delta: float) -> void:
	if not joined:
		return
	var game = room.game
	_set_ptt(Input.is_action_pressed("radio") and room.connected and not game.paused and not game.dead and not game.finished)
	clock += delta
	if clock >= TICK:
		clock = 0.0
		_tick()

func _set_ptt(value: bool) -> void:
	if value == transmitting:
		return
	transmitting = value
	backend.set_ptt(value)

func _tick() -> void:
	var result: Dictionary = backend.tick(_levels())
	# The browser page answered that it has no voice (no WebRTC there).
	if result.get("joined", true) == false:
		_set_ptt(false)
		joined = false
		supported = false
		pending.clear()
		connected_peers = 0
		if label != null:
			label.hide()
		return
	# The room relays signals only to open sockets, so a call made while we
	# were still loading the stage was lost: ask everyone to ring again.
	var socket_open: bool = room.transport.socket_open
	if socket_open and not socket_was_open:
		pending.clear()
		backend.ring_again()
	socket_was_open = socket_open
	if not result.is_empty():
		connected_peers = int(result.get("connected", 0))
		for envelope in result.get("signals", []):
			if envelope is Dictionary and envelope.get("data") is Dictionary:
				pending.append({"to": str(envelope.get("to", "")), "data": envelope.data, "at": Time.get_ticks_msec()})
		for event in result.get("events", []):
			if event is Dictionary and event.get("type") == "mic":
				_mic_changed(str(event.get("value", "")))
	_flush()
	_update_label()

# What each other member sounds like here: distance and whether they transmit.
func _levels() -> Array:
	var list: Array = []
	var here: Vector3 = room.game.player_position()
	for peer in room.peers.values():
		if peer.state == null or peer.avatar == null:
			continue
		list.append({"id": str(peer.id), "distance": snappedf(here.distance_to(peer.avatar.position), 0.1), "talking": bool(peer.state.get("radio", false))})
	return list

func _flush() -> void:
	var now = Time.get_ticks_msec()
	pending = pending.filter(func(s): return now - int(s.at) < PENDING_TTL_MSEC).slice(-MAX_PENDING)
	while not pending.is_empty() and room.transport.send_signal(pending[0].to, pending[0].data):
		pending.pop_front()

func _mic_changed(value: String) -> void:
	mic = value
	if value == "denied":
		room.game.toast(Loc.t("Нет доступа к микрофону: рация работает только на приём."))
	elif value == "unavailable":
		room.game.toast(Loc.t("Микрофон не найден: рация работает только на приём."))

# "В ЭФИРЕ" while transmitting, otherwise who is talking right now.
func _update_label() -> void:
	if label == null:
		if room.game.hud == null or room.game.hud.top_box == null:
			return
		label = UiKit.label(room.game.hud.top_box, "", "muted")
		label.name = "RadioLine"
		label.add_theme_color_override("font_color", UiKit.HIGHLIGHT)
	var names: Array = []
	for peer in room.peers.values():
		if peer.state != null and bool(peer.state.get("radio", false)):
			names.append(str(room.members.get(str(peer.id), {}).get("name", "")))
	var no_link = transmitting and cut_off()
	if no_link:
		label.text = Loc.t("Плохая связь, голосовой чат не работает")
	elif on_air():
		label.text = Loc.t("РАЦИЯ · В ЭФИРЕ")
	elif not names.is_empty():
		label.text = Loc.t("РАЦИЯ · %s") % ", ".join(names)
	label.visible = no_link or on_air() or not names.is_empty()
