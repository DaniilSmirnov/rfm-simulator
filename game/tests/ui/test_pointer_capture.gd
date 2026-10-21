extends "res://tests/harness.gd"
# Desktop pointer lock: a lost lock pauses play, a free cursor never turns
# the camera, and a hint asks for a click while play runs unlocked.

func _initialize() -> void:
	call_deferred("run")

func motion(game, dx: float) -> void:
	var event = InputEventMouseMotion.new()
	event.relative = Vector2(dx, 0)
	game._unhandled_input(event)

# Join pressed in the menu captures at once; a room the host has just
# re-created answers 404 for its old ID. The menu gets its cursor back and
# the join can be retried without a restart.
func failed_join(game) -> void:
	var pointer = game.pointer
	var room = game.room
	room.ui.id_input.text = "0".repeat(room.NetProtocol.room_id_length())
	room.busy = true
	check(not pointer.stray(true), "the capture from the join button holds while the server answers")
	room.transport.request_kind = "join"
	room._response(HTTPRequest.RESULT_SUCCESS, 404, PackedStringArray(), JSON.stringify({"error": "Комната не найдена или закрыта."}).to_utf8_buffer())
	check(not room.connected and not game.playing and not room.busy, "a missing room leaves the player in the menu")
	check(room.ui.status.text.contains("новый ID"), "the error explains a re-created room has a new ID")
	check(not room.ui.join_button.disabled and not room.ui.create_button.disabled, "join and create can be pressed again")
	check(pointer.stray(true), "a capture left after the failed join is stray")
	pointer.update(true)
	check(not pointer.was_captured and not game.paused, "the menu frees the cursor without opening pause")
	game.loading_world = true
	check(not pointer.stray(true), "the capture holds while the stage loads")
	game.loading_world = false
	await process_frame

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	await failed_join(game)
	await game.start_game()
	var pointer = game.pointer
	check(game.playing and not game.paused and pointer.wanted(), "desktop play wants the pointer")
	pointer.update(true)
	check(not game.paused and not pointer.hint.visible, "locked pointer: play runs, no hint")
	pointer.update(false)
	check(game.paused and game.menu.visible and game.menu_title.text == "Пауза", "losing the lock (browser Esc, window switch) opens the pause menu")
	pointer.update(false)
	check(game.paused and not pointer.hint.visible, "no hint over the pause menu")
	game._menu_action()
	pointer.update(false)
	check(not game.paused, "a lock refused after Continue does not pause again")
	check(pointer.hint.visible, "unlocked play asks for a click")
	var yaw = game.view_yaw
	motion(game, 120)
	check(game.view_yaw == yaw, "a free cursor does not turn the camera")
	pointer.update(true)
	check(not pointer.hint.visible, "the hint goes once the pointer is locked")
	# Windows over play own the pointer: no pause and no hint under them.
	game._show_stage_safety_gate()
	pointer.update(false)
	check(not pointer.hint.visible and game.safety_gate != null and not game.menu.visible, "the safety memo frees the pointer without opening the pause menu")
	var gate = game.safety_gate
	gate.accepted.emit()
	gate.queue_free()
	game.die("Проверка")
	pointer.update(true)
	pointer.update(false)
	check(game.menu_title.text == "Выезд окончен" and not game.paused, "the result window is not replaced by pause")
	game.dead = false
	game.enable_mobile()
	game.paused = false
	game.menu.hide()
	pointer.update(true)
	pointer.update(false)
	check(not game.paused and not pointer.hint.visible, "touch play never pauses or asks for a click")
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	print("POINTER CAPTURE RESULT: %d checks, %d failures" % [checks, failures])
	finish()
