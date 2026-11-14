extends "res://tests/harness.gd"
# The lake sauna on "Финский лес": people walk in up the steps, sit on the
# upper bench facing the road window, throw water on the stones, heat up and
# have to leave; friends in the room light the steam and chimney smoke.

func _initialize() -> void:
	call_deferred("run")

func face(game, target: Vector3) -> void:
	var height = 1.45 if game.seated else 1.72
	game.camera.position = game.walker + Vector3(0, height, 0)
	game.camera.look_at(target)
	game.view_yaw = game.camera.rotation.y
	game.view_pitch = game.camera.rotation.x

func walk_to(game, target: Vector3, seconds: float) -> void:
	for i in range(int(seconds * 30.0)):
		var to = target - game.walker
		to.y = 0
		if to.length() < 0.15:
			break
		game.view_yaw = atan2(-to.x, -to.z)
		game.player.walk(1.0 / 30.0)
	Input.action_release("forward")

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.select_stage(4)
	await game.start_game()
	game.in_car = false
	var stage = game.stage
	var steam = game.player.sauna
	var sauna = steam.room()
	check(sauna != null and stage.get_node_or_null("LakeSaunaInterior") != null, "the Finnish forest sauna is a room with an interior")

	# --- The window faces the road and nothing blocks the view.
	var window = sauna.window_center()
	var door = sauna.at(Vector3(0, sauna.FLOOR + 1.0, sauna.HALF.y))
	check(stage.road_distance(window) + 3.0 < stage.road_distance(door), "the window is in the wall facing the road (%.1f m vs door %.1f m)" % [stage.road_distance(window), stage.road_distance(door)])
	var eye = sauna.seat() + Vector3(0, 1.45, 0)
	var clear_views = 0
	# Crews come from lower stations: the window shows them approach and pass.
	for ds in [-15.0, -10.0, -5.0, 0.0, 2.0]:
		var road = stage.at(stage.road_s(window) + ds) + Vector3(0, 1.0, 0)
		var blocked = stage.obstacle_hit(eye, road, 0.05, true) >= 0 or not stage.rock_hit(eye, road, 0.05).is_empty() or not stage.solids.hit(eye, road, 0.05, false, Vector3.ZERO).is_empty()
		for k in range(1, 20):
			var p = eye.lerp(road, k / 20.0)
			blocked = blocked or p.y < stage.ground(p) - 0.05
		if not blocked:
			clear_views += 1
	check(clear_views >= 4, "from the bench the road is seen through the window (%d of 5 sight lines)" % clear_views)

	# --- Walking in: up the steps, through the door, onto the floor.
	var outside = sauna.at(Vector3(0, 0, sauna.HALF.y + 2.6))
	game.walker = Vector3(outside.x, stage.ground(outside), outside.z)
	Input.action_press("forward")
	walk_to(game, sauna.at(Vector3(0, 0, sauna.HALF.y + 0.2)), 4.0)
	Input.action_press("forward")
	walk_to(game, sauna.at(Vector3(0.3, 0, 0.2)), 4.0)
	var floor_y = sauna.at(Vector3(0, sauna.FLOOR, 0)).y
	check(steam.inside(game.walker) and absf(game.walker.y - floor_y) < 0.05, "a fan walks up the steps and into the sauna (inside %s, feet %.2f, floor %.2f)" % [steam.inside(game.walker), game.walker.y, floor_y])
	var wall_probe = game.walker
	Input.action_press("forward")
	walk_to(game, sauna.at(Vector3(0.3, 0, -3.0)), 2.0)
	check(steam.inside(game.walker) and game.walker.distance_to(wall_probe) > 0.5, "the road wall stops the walker inside the room")

	# --- Sitting on the bench.
	game.walker = sauna.at(Vector3(-0.4, sauna.FLOOR, 0.2))
	game.beers = 6
	game.drunk_strength = 1.0
	face(game, sauna.bench_point())
	var target = game.interaction.current()
	check(target.get("action", "") == "sauna" and target.get("label", "") == "Париться", "the bench offers to steam")
	game.interaction.activate()
	check(game.seated and steam.steaming and game.walker.distance_to(sauna.seat()) < 0.01, "the fan sits on the upper bench")
	var forward = Vector3(-sin(game.view_yaw), 0, -cos(game.view_yaw))
	var to_window = (window - game.walker)
	to_window.y = 0
	check(forward.dot(to_window.normalized()) > 0.95, "sitting down turns the view to the road window")
	check(game.walking_intent() == Vector3.ZERO and not game.jump(), "the steamer stays on the bench")
	face(game, sauna.stones())
	target = game.interaction.current()
	check(target.get("action", "") == "sauna_ladle" and target.get("label", "") == "Поддать пару", "looking at the stove offers to throw water")
	var heat = steam.heat
	game.interaction.activate()
	check(steam.heat > heat + 0.1 and sauna.cloud.emitting, "water on the stones heats the room and makes a cloud of steam")
	game.interaction.activate()
	check(steam.heat < heat + 0.2, "the ladle needs a moment between throws")
	face(game, window)
	check(game.interaction.current().get("action", "") == "stand", "looking elsewhere offers to climb down")
	for i in range(30):
		game.player.update_intoxication(1.0 / 30.0)
	check(sauna.smoke.emitting and sauna.steam.emitting and sauna.lamp.visible, "steam inside and smoke from the chimney while someone steams")
	check(game.drunk_strength < 1.0 - 3.0 / game.DRUNK_FADE_SECONDS, "steaming sweats the beer sway out faster (%.3f)" % game.drunk_strength)

	# --- A full session, then climbing down onto the floor.
	for i in range(20 * 10):
		game.player.update_intoxication(0.1)
	game.interaction.activate()
	check(not game.seated and not steam.steaming and game.toast_label.text == "С лёгким паром!", "a full session ends with С лёгким паром!")
	check(steam.inside(game.walker) and absf(game.walker.y - floor_y) < 0.05, "climbing down puts the fan back on the sauna floor")
	for i in range(60 * 10):
		game.player.update_intoxication(0.1)
	check(not sauna.smoke.emitting, "the chimney stops smoking when nobody steams")

	# --- Too long on the bench sends the fan out.
	steam.heat = 0.0
	face(game, sauna.bench_point())
	game.interaction.activate()
	for i in range(90 * 10):
		game.player.update_intoxication(0.1)
		if not game.seated:
			break
	check(not game.seated and game.toast_label.text == "Жарко! Пора окунуться в озеро.", "too much heat sends the fan to the lake")

	# --- A friend steaming lights the steam for everyone.
	game.room.peers["friend"] = {"state": {"seated": true, "in_car": false, "pos": [sauna.seat().x, sauna.seat().y, sauna.seat().z]}}
	game.player.update_intoxication(0.1)
	check(sauna.smoke.emitting, "a friend seated on the bench steams for every client")
	game.room.peers["friend"].state.seated = false
	game.player.update_intoxication(0.1)
	check(not sauna.smoke.emitting, "a friend standing up stops it")
	game.room.peers.erase("friend")

	# --- The second bench, opposite: its own seats facing the window.
	game.walker = sauna.at(Vector3(0.3, sauna.FLOOR, 0.2))
	face(game, sauna.bench_point(1.0))
	target = game.interaction.current()
	check(target.get("action", "") == "sauna" and float(target.get("value", 0.0)) == 1.0, "the opposite bench offers to steam too")
	game.interaction.activate()
	check(game.seated and game.walker.distance_to(sauna.seat(2)) < 0.01, "the fan sits on the opposite bench")
	game.stand_up()
	var friend_seat = sauna.seat(2)
	game.room.peers["friend"] = {"id": "friend", "state": {"seated": true, "in_car": false, "pos": [friend_seat.x, friend_seat.y, friend_seat.z]}}
	check(steam.free_seat(1.0) == 3, "a friend's seat is taken: the next one on that bench is offered")

	# --- Birch whisk: whisking a friend, and being whisked.
	game.walker = sauna.at(Vector3(0.4, sauna.FLOOR, -0.6))
	face(game, friend_seat + Vector3(0, 0.9, 0))
	target = game.interaction.current()
	check(target.get("action", "") == "venik" and target.get("label", "") == "Попарить веником", "a friend in the sauna can be whisked")
	game.interaction.activate()
	check(steam.whisk.whipping() and game.room.local_state().get("venik", false), "whisking goes into the room state")
	game.player.update_intoxication(0.1)
	check(steam.whisk.held != null and steam.whisk.held.visible, "the whisk swings in the hand")
	for i in range(30):
		game.player.update_intoxication(0.1)
	check(not steam.whisk.whipping() and not steam.whisk.held.visible, "a whisking lasts a few seconds")
	var me = game.walker
	var whisker = me + Vector3(0, 0, 1.0)
	game.room.peers["friend"].state = {"seated": false, "in_car": false, "venik": true, "pos": [whisker.x, whisker.y, whisker.z], "yaw": 0.0}
	steam.heat = 0.0
	var before = steam.heat
	game.player.update_intoxication(0.05)
	check(game.toast_label.text == "Тебя парят веником! Ух, хорошо!" and steam.heat > before + 0.05, "a friend whisking you is felt: notice and heat")
	game.room.peers["friend"].state.yaw = PI
	game.player.update_intoxication(0.05)
	check(not steam.whisk.felt.get("friend", true), "a whisker turned away misses")
	game.room.peers.erase("friend")

	# --- Outside nobody is offered to steam.
	game.walker = sauna.at(Vector3(0, 0, sauna.HALF.y + 2.6))
	game.walker.y = stage.ground(game.walker)
	face(game, sauna.bench_point())
	check(game.interaction.current().get("action", "") != "sauna", "the bench is not offered from outside")
	finish()
