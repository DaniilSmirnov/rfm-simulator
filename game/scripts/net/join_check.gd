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
		active = false
		print("ROOM_JOIN_CHECK linked ", room.host_id)
		room._joined(data)
		return true
	var reason = problem()
	if reason != "":
		fail(reason)
	return true

# Why the link cannot come, or "" while it still may.
func problem() -> String:
	if not room.direct.enabled:
		return "Эта версия игры не умеет соединяться с хозяином комнаты напрямую. Обнови игру."
	if not room.transport.socket_enabled:
		return "Сеть не пропускает соединение с сервером комнаты. Попробуй другую сеть, например мобильный интернет."
	if waited <= room.LINK_GIVE_UP:
		return ""
	if room.host_id == "":
		return "Хозяин комнаты не отвечает. Попроси его вернуться в игру и попробуй снова."
	return "Не удалось соединиться с хозяином комнаты напрямую: сеть одного из вас не пропускает такое соединение. Попробуй другую сеть, например мобильный интернет."

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
