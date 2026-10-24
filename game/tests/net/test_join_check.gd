extends "res://tests/harness.gd"
# A guest checks its direct link to the host before it loads the stage
# (join_check.gd): it waits in the menu, enters once the link opens, and stays
# in the menu with a reason when the link cannot come.
const DirectTest = preload("res://tests/net/test_direct_link.gd")

func _initialize() -> void:
	call_deferred("run")

func connect_links(host, guest) -> void:
	for pair in [[host, guest, "guest", "host"], [guest, host, "host", "guest"]]:
		var from = pair[0]
		var to = pair[1]
		var own_id: String = pair[3]
		from.room.direct.enabled = true
		from.room.direct.connection_factory = func(): return DirectTest.FakeConnection.new()
		from.room.direct.signal_sender = func(target: String, data: Dictionary) -> bool:
			if target != pair[2]:
				return false
			to.room.direct.on_signal(own_id, data.duplicate(true))
			return true
		from.room.transport.socket_open = true

func reply(player: String) -> Dictionary:
	return {"player": player, "token": "token-" + player, "host": false, "name": player, "slot": 1, "car_model": 0, "character": 0, "stage": 0, "socket": ""}

func join(guest, player: String) -> void:
	guest.room.room_id = "ABC123"
	guest.room.transport.request_kind = "join"
	guest.room._on_reply("join", reply(player))

func run() -> void:
	var host = load("res://main.tscn").instantiate()
	var guest = load("res://main.tscn").instantiate()
	var other = load("res://main.tscn").instantiate()
	for g in [host, guest, other]:
		root.add_child(g)
	await process_frame
	for g in [host, guest, other]:
		g.set_process(false)
		g.room.set_process(false)
	host.start_game()
	host.room.player_id = "host"
	host.room.host_id = "host"
	host.room.is_host = true
	host.room.connected = true
	connect_links(host, guest)
	var players = [{"id": "host", "name": "Хозяин", "slot": 0, "car_model": 0, "state": host.room.local_state(), "state_time": 0},
		{"id": "guest", "name": "Гость", "slot": 1, "car_model": 0, "state": null, "state_time": 0}]
	host.room._update_members(players)
	host.room._update_peers(players)

	# The join reply: the guest stays in the menu and checks the link.
	join(guest, "guest")
	guest.room.transport.socket_open = true  # the socket's hello
	var check_ = guest.room.join_check
	check(check_.active and guest.room.connected and not guest.playing and not guest.loading_world, "after the join reply the guest waits in the menu")
	check(guest.room.ui.status.text == "Проверяем связь с хозяином комнаты…", "the entry panel says the link is being checked")
	guest.room.ui.id_input.text = "ABC123"
	guest.lobby_ui.refresh()
	check(guest.room.ui.join_button.disabled and guest.room.ui.create_button.disabled, "the entry buttons stay off during the check")
	guest.start_game()
	check(not guest.playing and not guest.loading_world, "the solo start waits for the check")
	guest.room.join_check.update(0.1)
	check(check_.active and guest.room.direct.links.is_empty(), "without the membership there is nobody to call yet")
	# The host's sync pushes the membership: the guest calls the host.
	guest.room._apply_sync({"host": "host", "players": players, "accepted": 0})
	check(guest.room.host_id == "host" and guest.room.direct.links.has("host"), "the pushed membership names the host and the guest calls it")
	check(guest.room.peers.is_empty(), "a guest still in the menu draws nobody")
	host.room.direct.poll()
	host.course.phase = "racing"
	host.spawn_racer()
	host.room.direct._send(1.0)
	check(guest.room.join_check.update(0.1), "the room skips its frame while the check runs")
	check(not check_.active and (guest.loading_world or guest.playing), "an open link starts the stage load")
	check(guest.racers.is_empty() and guest.room.last_world_time < 0, "the world that came before the stage is dropped")
	var waited = 0
	while check_.active == false and not guest.playing and waited < 3000:
		host.room.direct._send(0.05)
		guest.room.join_check.update(0.016)
		await process_frame
		waited += 1
	check(guest.playing and guest.room.connected and not guest.dead, "the guest enters the stage")
	check(guest.room.direct.healthy("host"), "the link kept being drained during the load and is still fresh")
	host.room.direct.still_sent_at = -INF  # a still world goes at 5/s only
	host.room.direct._send(1.0)
	guest.room.direct.poll()
	check(guest.racers.size() == 1 and guest.racers[0].id == host.racers[0].id, "once playing the guest takes the host's world")

	# Failures keep the player in the menu, with a reason on the entry panel.
	other.room.direct.enabled = false
	join(other, "other")
	other.room.join_check.update(0.1)
	check(not other.room.connected and not other.room.join_check.active and not other.dead and not other.playing, "a build without direct links leaves the room at once")
	check(other.room.ui.status.text == "Эта версия игры не умеет соединяться с хозяином комнаты напрямую. Обнови игру.", "the reason: no direct link in this build")
	other.room.ui.id_input.text = "ABC123"
	other.lobby_ui.refresh()
	check(not other.room.ui.join_button.disabled, "the player can try again")

	other.room.direct.enabled = true
	other.room.direct.connection_factory = func(): return DirectTest.FakeConnection.new()
	other.room.direct.signal_sender = func(_target: String, _data: Dictionary) -> bool: return false
	join(other, "other")
	other.room.transport.socket_open = true
	other.room.join_check.update(other.room.LINK_GIVE_UP + 1.0)
	check(not other.room.connected and other.room.ui.status.text == "Хозяин комнаты не отвечает. Попроси его вернуться в игру и попробуй снова.", "a host that never shows up is named as the reason")

	join(other, "other")
	other.room.transport.socket_open = true
	other.room._apply_sync({"host": "host", "players": players, "accepted": 0})
	var link: Dictionary = other.room.direct.links.get("host", {})
	check(not link.is_empty() and link.pc != null, "the guest calls the host")
	link.started -= 60.0
	other.room.join_check.update(0.1)
	var retry = other.room.direct.links.get("host", {})
	check(other.room.join_check.active and retry.pc == null and float(retry.retry_at) - other.room.direct.now() <= 1.01, "a failed attempt during the check is retried within a second")
	other.room.join_check.update(other.room.LINK_GIVE_UP + 1.0)
	check(not other.room.connected and other.room.direct.links.is_empty() and not other.dead, "no link within the time limit: the guest leaves the room")
	check(other.room.ui.status.text.begins_with("Не удалось соединиться с хозяином комнаты напрямую"), "the reason: the networks block the direct link")

	other.room.transport.socket_enabled = false
	join(other, "other")
	other.room.join_check.update(0.1)
	check(not other.room.connected and other.room.ui.status.text.begins_with("Сеть не пропускает соединение с сервером комнаты"), "a network without the room socket cannot set the link up")
	other.room.transport.socket_enabled = true

	join(other, "other")
	other.room._on_failure("sync", 410, "Создатель вышел. Комната закрыта.", null)
	check(not other.room.connected and not other.dead and other.menu_title.text != "Комната закрыта" and other.room.ui.status.text == "Создатель вышел. Комната закрыта.", "a room closed during the check is reported on the entry panel")

	print("JOIN CHECK RESULT: %d checks, %d failures" % [checks, failures])
	for g in [host, guest, other]:
		g.queue_free()
	await process_frame
	finish()
