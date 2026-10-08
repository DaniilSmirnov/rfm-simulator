extends SceneTree
var checks = 0
var failures = 0
func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(title)
	else:
		print("PASS: " + title)
func _initialize() -> void:
	call_deferred("run")
func button(c: Control, action: String) -> Vector2:
	c._layout()
	for b in c.buttons:
		if b.action == action:
			return b.rect.get_center()
	if action in ["table", "chairs", "grill", "firewood", "cauldron", "flag", "recover", "eat_berries"]:
		c.gear_open = true
		c._layout()
		for b in c.buttons:
			if b.action == action:
				return b.rect.get_center()
	return Vector2(-1000, -1000)
func prepare_trunk(game) -> void:
	game.car.position = game.walker - Vector3(0, 0, 3)
	game.heading = 0
	game.cargo.opened[game.chair_owner()] = true

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	check(not game.mobile_mode, "desktop starts without touch overlay")
	game.enable_mobile()
	game.start_game()
	await process_frame
	var c = game.mobile_controls
	c.set_process(false)
	check(c.landscape() and game.get_window().content_scale_size == Vector2i(960, 540), "mobile uses a landscape canvas")
	check(not c.buttons.any(func(b): return b.action == "table"), "equipment is hidden behind the compact drawer")
	check(game.mobile_mode and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "mobile starts without pointer capture")
	var safe = Rect2(54, 120, 852, 390)
	var viewport_size = game.get_viewport().get_visible_rect().size
	var safe_payload = {"width": viewport_size.x, "height": viewport_size.y, "left": 54, "right": viewport_size.x - 906, "top": 120, "bottom": viewport_size.y - 510}
	game._mobile_safe_response(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(safe_payload).to_utf8_buffer())
	game._mobile_safe_response(HTTPRequest.RESULT_SUCCESS, 503, PackedStringArray(), "unavailable".to_utf8_buffer())
	check(game.mobile_safe_rect == safe, "browser viewport response maps to UI and failed responses preserve layout")
	c._process(0)
	await process_frame
	check(c.scale == Vector2.ONE and game.mobile_ui.scale == Vector2.ONE, "safe area never scales gameplay controls or HUD")
	for b in c.buttons:
		var screen_rect = Rect2(c.get_global_transform() * b.rect.position, b.rect.size * c.scale)
		check(safe.encloses(screen_rect), "VK buttons stay outside shell and system edges")
	check(safe.encloses(game.menu.get_global_rect()), "compact menu fits inside VK safe area")
	check(game.mobile_top.global_position.y >= safe.position.y and game.mobile_bottom.global_position.x >= safe.position.x, "HUD respects safe area origin")
	check(game.crosshair.get_global_rect().get_center().distance_to(game.get_viewport().get_visible_rect().size / 2) < 0.1, "aim stays at camera centre when safe area moves HUD")
	var touch = InputEventScreenTouch.new()
	touch.index = 21
	touch.pressed = true
	touch.position = c.get_global_transform() * button(c, "forward")
	c._input(touch)
	check(Input.is_action_pressed("forward"), "safe-area input hits the visible full-size pedal")
	touch.index = 22
	touch.position = Vector2(100, 20)
	c._input(touch)
	check(not c.fingers.has(22), "VK overlay band does not acquire a gameplay gesture")
	for pedal in ["forward", "brake"]:
		for b in c.buttons:
			if b.action == pedal:
				check(b.rect.size.x >= 88 and b.rect.size.y >= 112, "driving pedals have large touch targets")
	c._move_stick(c.stick_center + Vector2(62, 62))
	check(is_equal_approx(c.stick.x, 1.0) and is_zero_approx(c.stick.y), "driving steering uses only horizontal thumb motion")
	c.reset_input()
	c.touch_begin(27, button(c, "forward"))
	c.touch_begin(28, button(c, "gear"))
	check(not Input.is_action_pressed("forward") and c.fingers.is_empty(), "opening drawer releases held driving input")
	c.gear_open = true
	c._layout()
	var old_yaw = game.view_yaw
	c.touch_begin(25, c.gear_rect.position + Vector2(2, 2))
	c.touch_drag(25, c.gear_rect.position + Vector2(50, 2), Vector2(48, 0))
	check(not c.fingers.has(25) and game.view_yaw == old_yaw, "drawer padding never starts movement or camera gesture")
	c.touch_begin(26, Vector2(c.size.x * 0.75, 150))
	check(not c.gear_open and not c.fingers.has(26), "outside drawer tap closes it without camera capture")
	game.apply_mobile_safe_rect(Rect2(Vector2.ZERO, Vector2(960, 540)))
	c._process(0)
	check(not Input.is_action_pressed("forward") and c.fingers.is_empty(), "inset changes cancel held touches")
	c.touch_begin(1, button(c, "forward"))
	c.touch_begin(2, c.stick_center + Vector2(60, 0))
	check(Input.is_action_pressed("forward") and Input.is_action_pressed("right"), "gas and steering support multitouch")
	var look_point = Vector2(c.size.x * 0.6, 225)
	var drive_yaw = game.view_yaw
	var drive_pitch = game.view_pitch
	var drive_heading = game.heading
	c.touch_begin(3, look_point)
	c.touch_drag(3, look_point + Vector2(70, 50), Vector2(70, 50))
	check(game.view_yaw != drive_yaw and game.view_pitch != drive_pitch and game.heading == drive_heading and Input.is_action_pressed("forward") and Input.is_action_pressed("right"), "driver swipes horizontally and vertically while holding gas and steering")
	c.touch_begin(4, look_point + Vector2(-100, 0))
	var owned_yaw = game.view_yaw
	c.touch_drag(4, look_point, Vector2(100, 0))
	check(game.view_yaw == owned_yaw, "another finger cannot steal the active camera gesture")
	c.touch_end(4)
	c.touch_end(3)
	check(Input.is_action_pressed("forward") and Input.is_action_pressed("right"), "releasing camera finger preserves gas and steering")
	c.touch_end(2)
	check(Input.is_action_pressed("forward") and not Input.is_action_pressed("right"), "releasing steering preserves held gas")
	c.touch_drag(1, Vector2.ZERO, Vector2.ZERO)
	check(not Input.is_action_pressed("forward"), "sliding outside pedal releases gas")
	c.touch_drag(1, button(c, "forward"), Vector2.ZERO)
	check(Input.is_action_pressed("forward"), "sliding back onto pedal resumes gas")
	c.touch_end(1)
	check(not Input.is_action_pressed("forward"), "lifting pedal finger releases gas")
	var car_before = game.car.position
	game.car.position = Vector3(0, 40, 0)
	game.view_pitch = -0.12
	game._update_camera(1)
	var camera_height = game.camera.position.y
	var left_free = Vector2(c.size.x * 0.72, 190)
	c.touch_begin(5, left_free)
	c.touch_drag(5, left_free + Vector2(40, 80), Vector2(40, 80))
	game._update_camera(1)
	check(game.camera.position.y > camera_height + 0.5 and c.fingers.get(5, {}).get("kind", "") == "look", "right-side swipe changes actual third-person camera height")
	c.touch_end(5)
	game.car.position = car_before
	c.map_open = true
	c._process(0)
	var map_center = game.mobile_sidebar.get_global_rect().get_center()
	var map_yaw = game.view_yaw
	c.touch_begin(6, map_center)
	c.touch_drag(6, map_center + Vector2(80, 0), Vector2(80, 0))
	check(not c.fingers.has(6) and game.view_yaw == map_yaw, "open map consumes its area without rotating the camera")
	c.map_open = false
	c._process(0)
	c.touch_begin(7, look_point)
	game.paused = true
	var paused_yaw = game.view_yaw
	c.touch_drag(7, look_point + Vector2(80, 0), Vector2(80, 0))
	check(game.view_yaw == paused_yaw and c.fingers.is_empty(), "pause immediately cancels a camera drag")
	game.paused = false
	c.touch_begin(1, button(c, "interact"))
	c._process(0)
	check(not game.in_car, "touch exit switches to walking controls")
	c.touch_begin(1, c.stick_center + Vector2(0, -60))
	var yaw = game.view_yaw
	c.touch_begin(2, Vector2(c.size.x * 0.6, 225))
	c.touch_drag(2, Vector2(c.size.x * 0.6 + 50, 225), Vector2(50, 0))
	check(Input.is_action_pressed("forward") and game.view_yaw != yaw, "walking and swipe look work together")
	var crossing_yaw = game.view_yaw
	c.touch_drag(1, Vector2(c.size.x * 0.8, c.size.y * 0.5), Vector2(20, 0))
	check(c.fingers[1].kind == "stick" and game.view_yaw == crossing_yaw, "movement finger keeps its role when dragged into camera half")
	c.touch_end(2)
	check(Input.is_action_pressed("right"), "look finger release preserves movement")
	c.touch_drag(1, c.stick_center + Vector2(0, -60), Vector2.ZERO)
	c.touch_begin(3, button(c, "pause_demo"))
	c._process(0)
	check(game.paused and not Input.is_action_pressed("forward") and c.fingers.is_empty(), "pause clears held touches")
	game._menu_action()
	c._process(0)
	c.touch_begin(1, c.stick_center + Vector2(60, 0))
	c._notification(Control.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(not Input.is_action_pressed("right"), "focus loss releases movement")
	var floating_origin = Vector2(c.size.x * 0.30, c.size.y * 0.44)
	var fixed_yaw = game.view_yaw
	c.touch_begin(8, floating_origin)
	c.touch_drag(8, floating_origin + Vector2(-35, -45), Vector2(-35, -45))
	check(c.fingers[8].kind == "stick" and Input.is_action_pressed("left") and Input.is_action_pressed("forward") and game.view_yaw == fixed_yaw, "left half starts a floating movement stick without turning the camera")
	c.touch_end(8)
	c.touch_begin(8, c.stick_center)
	c.touch_drag(8, c.stick_center + Vector2(0, -60), Vector2(0, -60))
	c.touch_begin(9, button(c, "sprint"))
	c.touch_begin(10, look_point)
	check(Input.is_action_pressed("forward") and Input.is_action_pressed("sprint") and c.fingers[10].kind == "look", "sprint, movement and camera accept three independent fingers")
	c.touch_end(9)
	check(Input.is_action_pressed("forward") and not Input.is_action_pressed("sprint") and c.fingers.has(10), "releasing sprint preserves stick and camera")
	c.reset_input()
	var original_size = c.size
	c.size = Vector2(540, 960)
	c._process(0)
	c.touch_begin(11, Vector2(300, 500))
	check(not c.landscape() and c.buttons.is_empty() and c.fingers.is_empty(), "portrait mode refuses gameplay touches until rotated")
	c.size = original_size
	c._process(0)
	check(c.landscape() and not c.buttons.is_empty(), "rotation restores controls with no stuck actions")
	for b in c.buttons:
		check(Rect2(Vector2.ZERO, c.size).encloses(b.rect), "landscape button remains inside viewport")
	game.walker = game.stage.clearings[0]
	game.view_yaw = 0
	prepare_trunk(game)
	c.touch_begin(1, button(c, "table"))
	check(game.camp == null and game.placement_kind == "table", "touch placement starts with preview")
	c.touch_begin(1, button(c, "placement_rotate"))
	check(absf(game.placement_yaw - PI / 8) < 0.01, "touch rotates furniture preview")
	c.touch_begin(1, button(c, "placement_confirm"))
	check(game.camp != null and button(c, "chairs").x > 0, "camp button advances from table to chairs")
	game.walker = game.stage.clearings[0] + Vector3(-3, 0, 0)
	prepare_trunk(game)
	c.touch_begin(1, button(c, "chairs"))
	c.touch_begin(1, button(c, "placement_confirm"))
	check(game.has_chairs and button(c, "grill").x > 0, "camp button advances from chairs to grill")
	game.walker = game.stage.clearings[0] + Vector3(0, 0, -2)
	prepare_trunk(game)
	c.touch_begin(1, button(c, "grill"))
	c.touch_begin(1, button(c, "placement_confirm"))
	check(game.cooking and not c.buttons.any(func(b): return b.action in ["beer", "eat", "collect", "mount_mushroom", "eat_mushroom"]), "object interactions use a single contextual touch action")
	prepare_trunk(game)
	c.touch_begin(1, button(c, "table"))
	c.touch_begin(1, button(c, "placement_cancel"))
	check(game.placement_kind == "", "touch can cancel furniture placement")
	game.walker = game.cargo.point(game.cargo.poses()[game.chair_owner()])
	game.cargo.return_item(game.walker)
	game.car.position = game.stage.at(12)
	game.walker = game.camp.position + Vector3(0, 0, 2)
	game.walker.y = game.stage.ground(game.walker)
	game._update_camera(1)
	game.camera.look_at(game.camp.position + Vector3(0, 0.75, 0))
	c.touch_begin(1, button(c, "interact"))
	check(game.drink_time >= 0, "touch starts beer animation")
	c.touch_begin(2, c.stick_center + Vector2(60, 0))
	c.last_size = Vector2.ZERO
	c._process(0)
	check(c.fingers.is_empty() and not Input.is_action_pressed("right"), "resize reset clears touches")
	game._cancel_drink()
	game.in_car = false
	game.tow_target = Node3D.new()
	game.add_child(game.tow_target)
	c._process(0)
	c.touch_begin(4, button(c, "tow"))
	check(Input.is_action_pressed("tow"), "rope can be held on foot")
	c.touch_end(4)
	check(not Input.is_action_pressed("tow"), "lifting rope finger releases tow")
	game.in_car = true
	c._layout()
	check(not c.buttons.any(func(b): return b.action == "tow"), "driver has no rope button")
	game.dead = true
	c._process(0)
	check(not c.active() and c.buttons.is_empty(), "result screen disables touch gameplay")
	print("MOBILE RESULT: %d checks, %d failures" % [checks, failures])
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
