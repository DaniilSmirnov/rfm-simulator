extends RefCounted
# A guest checks its direct link to the host before it loads the stage. The
# room server only lets it in; the game itself goes over the link
# (direct_link.gd), so a guest that cannot reach the host hears so on the
# entry panel instead of after the load, inside a world it cannot play.
#   1. The join reply: the guest opens the room socket, which carries the
#      connection setup, and waits in the menu. It sends no syncs: the host's
#      own syncs push the membership, and with it the host to call.
#   2. The link opens: room._joined() loads the stage as before.
#   3. No link within room.LINK_GIVE_UP: the guest leaves the room and the
#      entry panel says why.
# While the stage loads the socket and the link keep being drained, so the
# link is still fresh when the guest enters (direct_link.gd drops the world
# until then).
var room
var data: Dictionary = {}
var active = false
var waited = 0.0

# A join or create reply. A host has nobody to check and enters at once.
func start(owner_room, reply: Dictionary) -> void:
	room = owner_room
	room.direct.set_relays(reply.get("ice", []))
	if reply.get("host", false) == true:
		room._joined(reply)
		return
	data = reply
	active = true
	waited = 0.0
	room.player_id = str(reply.player)
	room.token = str(reply.token)
	room.is_host = false
	room.host_id = ""
	room.connected = true
	room.ui.status.text = "Проверяем связь с хозяином комнаты…"
	room.transport.open_socket(str(reply.get("socket", "")))
	print("ROOM_JOIN_CHECK ", room.room_id)

# Once per room frame. True: the room skips the rest of its frame.
func update(delta: float) -> bool:
	if not active:
		if room != null and room.game.loading_world and room.is_guest():
			room.transport.poll(delta)
			room.direct.poll()
		return false
	room.transport.poll(delta)
	if not active:
		return true
	room.direct.poll()
	waited += delta
	if room.direct.links.get(room.host_id, {}).get("open", false):
		linked()
		return true
	var reason = problem()
	if reason != "":
		room.direct.report(room.host_id, "failed", reason, waited)
		fail(REASONS[reason])
	return true

# The link to the host is open: the guest loads the stage.
func linked() -> void:
	active = false
	print("ROOM_JOIN_CHECK linked ", room.host_id)
	room.direct.report(room.host_id, "linked", "", waited)
	room._joined(data)

# What the entry panel says for each reason the link cannot come.
const REASONS = {
	"no_webrtc": "Эта версия игры не умеет соединяться с хозяином комнаты напрямую. Обнови игру.",
	"no_socket": "Сеть не пропускает соединение с сервером комнаты. Попробуй другую сеть, например мобильный интернет.",
	"host_silent": "Хозяин комнаты не отвечает. Попроси его вернуться в игру и попробуй снова.",
	"blocked": "Не удалось соединиться с хозяином комнаты напрямую: сеть одного из вас не пропускает такое соединение. Попробуй другую сеть, например мобильный интернет.",
}

# Why the link cannot come (a REASONS key), or "" while it still may.
func problem() -> String:
	if not room.direct.enabled:
		return "no_webrtc"
	if not room.transport.socket_enabled:
		return "no_socket"
	if waited <= room.LINK_GIVE_UP:
		return ""
	return "host_silent" if room.host_id == "" else "blocked"

# Leaves the room during the check and says why on the entry panel.
# False when no check is running.
func fail(message: String) -> bool:
	if not active:
		return false
	active = false
	room.transport.abandon(room.room_id, room.token)
	room.connected = false
	room.direct.close_all()
	room.transport.close_socket()
	room.host_id = ""
	room.members.clear()
	room.ui.status.text = message
	room.ui.set_entry_enabled(true)
	room.game.lobby_ui.refresh()
	print("ROOM_JOIN_CHECK failed: ", message)
	return true
