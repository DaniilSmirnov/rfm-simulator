extends Node
# Push-to-talk radio between the members of a room. Browser builds only: the
# audio itself is WebRTC in web/voice-chat.js, this node feeds it the roster,
# distances and the key, and relays its signaling over the room socket
# (`space: "voice"`). Native builds report the radio as unavailable until the
# native/voice extension carries audio.
const NetProtocol = preload("res://scripts/net/net_protocol.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Loc = preload("res://scripts/ui/loc.gd")

# Distances, the talking flags and signaling are exchanged ten times a second.
const TICK = 0.1
# Signals waiting for the socket; offers older than this are useless anyway.
const PENDING_TTL_MSEC = 10000
const MAX_PENDING = 64

var room: Node
var supported := false
var joined := false
var transmitting := false
var mic := "idle"
var connected_peers := 0
var pending: Array = []
var clock := 0.0
var label: Label

func setup(owner: Node) -> void:
	room = owner

func _ready() -> void:
	supported = OS.has_feature("web") and _eval("typeof RallyVoice === 'object' && typeof RTCPeerConnection === 'function'") == true

# The radio key and the touch button exist only where voice can work.
func available() -> bool:
	return supported and joined

# The key is held and the microphone is live: others hear us and see the pose.
func on_air() -> bool:
	return transmitting and mic == "ready"

func join() -> void:
	if not supported or room.player_id == "":
		return
	var session = ("%s-%s-%d" % [room.room_id, room.player_id, Time.get_ticks_msec()]).left(96)
	var options = {"localId": room.player_id, "session": session, "iceServers": NetProtocol.direct("ice_servers", [])}
	joined = _eval("RallyVoice.join(%s)" % JSON.stringify(options)) == true
	if joined:
		sync_members(room.members.keys())

# Says bye to every member while the socket is still open.
func leave() -> void:
	if not joined:
		return
	_set_ptt(false)
	_eval("RallyVoice.leave()")
	_tick()
	joined = false
	pending.clear()
	connected_peers = 0
	if label != null:
		label.hide()

func sync_members(ids: Array) -> void:
	if joined:
		_eval("RallyVoice.syncMembers(%s)" % JSON.stringify(ids))

func on_signal(from: String, data: Dictionary) -> void:
	if joined:
		_eval("RallyVoice.onSignal(%s,%s)" % [JSON.stringify(from), JSON.stringify(data)])

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
	_eval("RallyVoice.setPtt(%s)" % ("true" if value else "false"))

func _tick() -> void:
	var raw = _eval("RallyVoice.tick(%s)" % JSON.stringify(JSON.stringify(_levels())))
	var result = JSON.parse_string(str(raw)) if raw is String else null
	if result is Dictionary:
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
	if on_air():
		label.text = Loc.t("РАЦИЯ · В ЭФИРЕ")
	elif not names.is_empty():
		label.text = Loc.t("РАЦИЯ · %s") % ", ".join(names)
	label.visible = on_air() or not names.is_empty()

func _eval(code: String):
	if not OS.has_feature("web"):
		return null
	return JavaScriptBridge.eval(code, true)
