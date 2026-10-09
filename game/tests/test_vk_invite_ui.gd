extends SceneTree

var failures = 0

func check(ok: bool, description: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + description)
	if not ok:
		failures += 1

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	check(game.invite_button != null and game.invite_button.text == "ПРИГЛАСИТЬ ДРУЗЕЙ", "VK invitation control is created in stage pause menu")
	check(not game.invite_button.visible, "invitation stays hidden in main menu")
	game.playing = true
	game.platform_service.profile = {"platform": "standalone"}
	game._update_invite_button()
	check(not game.invite_button.visible, "standalone never shows VK invitation button")
	game.platform_service.profile = {"platform": "vk-prototype"}
	game._update_invite_button()
	check(not game.invite_button.visible, "prototype is not treated as authenticated VK")
	game.platform_service.profile = {"platform": "vk", "verified": true}
	game._update_invite_button()
	check(game.invite_button.visible, "authenticated VK stage shows invitation button")
	# Exercise the actual Button.pressed connection, not just button visibility.
	game.room.busy = true
	game.invite_button.pressed.emit()
	check(game.invite_status.visible and game.invite_status.text.contains("Подожди"), "press shows a visible status instead of silently returning while room is busy")
	game.room.busy = false
	game.invite_after_room_create = true
	game.invite_button.disabled = true
	game.room.request_kind = "create"
	game.room._response(HTTPRequest.RESULT_SUCCESS, 409, PackedStringArray(), JSON.stringify({"error": "Комната недоступна"}).to_utf8_buffer())
	check(not game.invite_after_room_create and not game.invite_button.disabled and game.invite_status.visible and game.invite_status.text.contains("Комната недоступна"), "failed room creation displays the server error and permits retry")
	game.dead = true
	game._update_invite_button()
	check(not game.invite_button.visible, "invitation hidden after death")
	game.dead = false
	game.finished = true
	game._update_invite_button()
	check(not game.invite_button.visible, "invitation hidden after stage completion")
	game.finished = false
	game.playing = false
	game.platform_service.invite_room = "BAD!!"
	game._join_invited_room()
	check(not game.room.connected and not game.room.busy and game.platform_service.invite_room.is_empty(), "invalid launch request is ignored before room network call")
	var chair = Node3D.new()
	chair.set_meta("gear_owner", "local")
	game.add_child(chair)
	game.personal_chairs["local"] = chair
	var flag = Node3D.new()
	flag.set_meta("gear_owner", "local")
	game.add_child(flag)
	game.personal_flags["local"] = [flag]
	game.foraging.inventories["local"] = {"berries": 3, "mushrooms": 1, "mushroom_types": ["edible"]}
	game.foraging.effects["local"] = {"serial": 1}
	game.cargo.held["local"] = {"owner": "local", "kind": "table", "returning": false}
	game.cargo.opened["local"] = true
	game.room.player_id = "vk_host_123"
	game.room._adopt_local_host_state()
	check(game.personal_chairs.has("vk_host_123") and not game.personal_chairs.has("local"), "solo chair ownership moves to the room host")
	check(game.personal_flags.has("vk_host_123") and not game.personal_flags.has("local"), "solo flags retain ownership")
	check(chair.get_meta("gear_owner", "") == "vk_host_123" and flag.get_meta("gear_owner", "") == "vk_host_123", "deployed objects retain their new network owner")
	check(game.foraging.inventories.has("vk_host_123") and not game.foraging.inventories.has("local"), "foraged mushrooms and berries are preserved")
	check(game.foraging.effects.has("vk_host_123") and not game.foraging.effects.has("local"), "active mushroom effects preserve player identity")
	check(game.cargo.held.has("vk_host_123") and not game.cargo.held.has("local") and game.cargo.held["vk_host_123"].owner == "vk_host_123", "carried cargo stays with its owner")
	check(game.cargo.opened.has("vk_host_123") and not game.cargo.opened.has("local"), "existing trunk state follows host")
	game.queue_free()
	await process_frame
	print("VK INVITE UI RESULT: %d failures" % failures)
	quit(1 if failures else 0)
