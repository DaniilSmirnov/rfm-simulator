extends SceneTree
var failures = 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.room.set_process(false)
	game.start_game()
	var map = game.minimap
	map.size = Vector2(280, 400)
	game.in_car = true
	for i in range(4):
		game.heading = i * PI / 2
		check(map.player_direction().is_equal_approx([Vector2.UP, Vector2.LEFT, Vector2.DOWN, Vector2.RIGHT][i]), "car indicator cardinal direction %d" % i)
	game.in_car = false
	game.heading = PI
	game.view_yaw = 0
	check(map.player_direction().is_equal_approx(Vector2.UP), "walking indicator follows view instead of parked car")
	game.view_yaw = 0.7
	var forward = Vector3(-sin(game.view_yaw), 0, -cos(game.view_yaw))
	check(map.player_direction().is_equal_approx((map.project(forward) - map.project(Vector3.ZERO)).normalized()), "indicator uses actual nonuniform map projection")
	game.walker = Vector3(10000, 0, -10000)
	check(Rect2(Vector2.ONE * 12, map.size - Vector2.ONE * 24).has_point(map.player_marker_position() - Vector2(0.001, -0.001)), "off-map marker stays inside map")
	game._update_hud()
	check(game.quest_label.text.begins_with("[ ] Выбрать место для лагеря"), "driving or walking alone does not select camp location")
	game.walker = game.stage.clearings[0]
	check(game.place_table(game.walker), "table can establish camp")
	game.stage.clearings.clear()
	game._update_hud()
	check(game.quest_label.text.begins_with("[x] Выбрать место для лагеря"), "camp establishes location without clearing selection or distance")
	check(not game.room.world_state().has("clearing"), "world snapshot no longer selects a clearing")
	check(not game.room.submit("random_spot"), "removed clearing command cannot be submitted")
	game.enable_mobile()
	game.mobile_controls.gear_open = true
	game.mobile_controls._layout()
	for button in game.mobile_controls.buttons:
		check(button.action != "random_spot", "mobile menu has no clearing selection")
	game.in_car = true
	game._update_hud()
	check(not "ПОЛЯНА" in game.info_label.text, "mobile HUD does not show obsolete clearing distance")
	await game._shutdown_audio()
	game.free()
	print("MINIMAP_AND_CAMP failures=", failures)
	quit(1 if failures else 0)
