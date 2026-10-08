extends SceneTree
var checks := 0
var failures := 0

func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.start_game()
	check(game.safety_gate == null, "headless fixture entry skips interactive safety gate")
	game._show_stage_safety_gate()
	await process_frame
	var gate = game.safety_gate
	check(game.paused and gate != null, "entering rally stage blocks gameplay")
	check(gate.accept_button.disabled, "acknowledgment is initially locked")
	check(gate.RULES.size() == 5 and gate.DANGERS.size() == 5 and gate.STAGE_GUIDES.size() == 3, "memo carries all RFM PWA rule sections")
	var press_count := 0
	gate.accepted.connect(func(): press_count += 1)
	gate._accept()
	check(press_count == 0 and game.paused, "cannot bypass unread memo with button handler")
	gate.scroll.scroll_vertical = 100000
	await process_frame
	gate._update_accept()
	check(not gate.accept_button.disabled, "reading to bottom unlocks acknowledgement")
	gate._accept()
	await process_frame
	check(press_count == 1 and not game.paused and game.safety_gate == null, "acknowledgement resumes gameplay and clears gate")
	print("STAGE SAFETY GATE RESULT: %d checks, %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
