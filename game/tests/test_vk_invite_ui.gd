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
	game.queue_free()
	await process_frame
	print("VK INVITE UI RESULT: %d failures" % failures)
	quit(1 if failures else 0)
