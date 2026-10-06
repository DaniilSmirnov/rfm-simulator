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
	check(game.mobile_mode and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "mobile starts without pointer capture")
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
	var left_free = Vector2(c.size.x * 0.18, 225)
	c.touch_begin(5, left_free)
	c.touch_drag(5, left_free + Vector2(40, 80), Vector2(40, 80))
	game._update_camera(1)
	check(game.camera.position.y > camera_height + 0.5 and c.fingers.get(5, {}).get("kind", "") == "look", "free left-side swipe changes actual third-person camera height")
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
	c.touch_end(2)
	check(Input.is_action_pressed("forward"), "look finger release preserves walking")
	c.touch_begin(3, button(c, "pause_demo"))
	c._process(0)
	check(game.paused and not Input.is_action_pressed("forward") and c.fingers.is_empty(), "pause clears held touches")
	game._menu_action()
	c._process(0)
	c.touch_begin(1, c.stick_center + Vector2(60, 0))
	c._notification(Control.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(not Input.is_action_pressed("right"), "focus loss releases movement")
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
