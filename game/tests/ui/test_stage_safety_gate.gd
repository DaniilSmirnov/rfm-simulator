extends "res://tests/harness.gd"


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
	await process_frame
	check(game.paused and gate != null, "entering rally stage blocks gameplay")
	check(gate.accept_button.disabled, "acknowledgment is initially locked")
	check(gate.WHERE_TO_STAND.size() == 4 and gate.ALLOWED.size() == 4 and gate.FORBIDDEN.size() == 5, "memo only covers safe viewing locations, allowed and forbidden actions")
	check(gate.panel.anchor_right == 1.0 and gate.panel.anchor_bottom == 1.0, "safety memo covers the complete viewport")
	check(gate.scroll.size_flags_horizontal == Control.SIZE_EXPAND_FILL, "safety memo scroll occupies viewport")
	check(gate.MAX_READING_WIDTH == 760.0 and gate.content_margins != null, "memo has a centered max-width reading column")
	check(gate.button_margins != null and gate.button_margins.get_theme_constant("margin_left") == gate.content_margins.get_theme_constant("margin_left"), "acceptance button aligns with text column")
	check(gate.outer.get_theme_constant("margin_bottom") >= 12, "action footer maintains a minimum bottom safe gutter")
	var original_size = gate.panel.size
	gate.panel.size = Vector2(1440, 900)
	gate._update_layout()
	check(gate.content_margins.get_theme_constant("margin_left") >= 300, "desktop reading column has generous side whitespace")
	gate.panel.size = Vector2(390, 844)
	gate._update_layout()
	check(gate.content_margins.get_theme_constant("margin_left") >= 20, "mobile retains readable horizontal padding")
	gate.panel.size = original_size
	gate._update_layout()
	await process_frame
	await process_frame
	var viewport_size = game.get_viewport().get_visible_rect().size
	game._mobile_safe_response(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify({"width":viewport_size.x/2, "height":viewport_size.y/2, "left":22, "top":8, "right":22, "bottom":10}).to_utf8_buffer())
	check(gate.outer.get_theme_constant("margin_left") == 44 and gate.outer.get_theme_constant("margin_top") == 16 and gate.outer.get_theme_constant("margin_right") == 44 and gate.outer.get_theme_constant("margin_bottom") == 32, "mini browser viewport transport updates safety insets in stretched UI units")
	game._mobile_safe_response(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify({"width":viewport_size.x, "height":viewport_size.y, "left":0, "top":0, "right":0, "bottom":0}).to_utf8_buffer())
	await process_frame
	await process_frame
	gate.panel.size = Vector2(1440, 4000)
	gate._update_layout()
	await process_frame
	await process_frame
	gate._update_accept()
	check(not gate.accept_button.disabled, "memo fitting entirely on screen does not require impossible scrolling")
	gate.panel.size = original_size
	gate._update_layout()
	await process_frame
	await process_frame
	gate._update_accept()
	var press_count := [0]
	gate.accepted.connect(func(): press_count[0] += 1)
	gate._accept()
	check(press_count[0] == 0 and game.paused, "cannot bypass unread memo with button handler")
	gate.scroll.scroll_vertical = 100000
	await process_frame
	gate._update_accept()
	check(not gate.accept_button.disabled, "reading to bottom unlocks acknowledgement")
	gate._accept()
	await process_frame
	check(press_count[0] == 1 and not game.paused and game.safety_gate == null, "acknowledgement resumes gameplay and clears gate")
	print("STAGE SAFETY GATE RESULT: %d checks, %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	finish()
