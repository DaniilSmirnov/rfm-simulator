extends SceneTree
var checks = 0
var failures = 0

func check(condition: bool, title: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + title)
	else:
		print("PASS: " + title)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	check(scene.stage.points.size() == 211, "840m stage generated")
	check(scene.stage.clearings.size() == 4, "four spectator clearings")
check(scene.stage.rally_flags.size() == 3, "three Rally Fan Maps flags are placed")
	check(scene.stage.flag_positions.size() == 3, "flag positions are deterministic")
	for i in range(scene.stage.rally_flags.size()):
		var flag = scene.stage.rally_flags[i]
		check(flag.has_meta("rally_fan_maps_flag") and flag.get_meta("flag_index") == i, "flag %d carries the RFM marker" % (i + 1))
		check(flag.get_child_count() > 2, "flag %d has a pole and branded cloth" % (i + 1))
	check(scene.stage.trails.size() == 4, "each spectator clearing has a forest footpath")
	check(scene.stage.trees.size() > 900, "summer gravel stage has a dense forest")
	check(scene.stage.trail_distance(scene.stage.trails[0].points[2]) < 0.01, "footpath reaches the raised lookout")
	check(scene.stage.at(-20).is_equal_approx(scene.stage.at(0)), "road start clamped")
	check(scene.stage.at(9999).is_equal_approx(scene.stage.at(840)), "road end clamped")
	check(not scene.place_table(), "camp blocked while driving")
	scene.start_game()
	var start_position = scene.car.position
	Input.action_press("forward")
	scene._drive(0.2)
	Input.action_release("forward")
	check(scene.speed > 0 and scene.car.position.distance_to(start_position) > 0, "throttle moves car")
	Input.action_press("brake")
	scene._drive(0.3)
	Input.action_release("brake")
	check(is_zero_approx(scene.speed), "brake stops car")
	scene.speed = 7
	scene._toggle_car()
	check(scene.in_car, "cannot exit moving car")
	scene.speed = 0
	scene._toggle_car()
	check(not scene.in_car, "can exit stopped car")
	scene.walker = scene.stage.at(140)
	check(not scene.place_table(), "table blocked on stage")
	scene.walker = scene.stage.clearings[0]
	check(scene.place_table(), "free placement outside stage")
	check(not scene.place_table(), "no duplicate table")
	check(not scene.start_grill(), "grill needs chairs")
	check(scene.place_chairs(), "chairs installed")
	check(not scene.place_chairs(), "no duplicate chairs")
	check(scene.start_grill(), "grill starts")
	check(not scene.eat_meat(), "cannot eat uncooked meat")
	scene._update_cooking(40)
	check(scene.cook_time == 35, "cooking clamps at readiness")
	check(scene.eat_meat(), "ready meat can be eaten")
	check(not scene.eaten and scene.meat_prop != null, "food only counts after animated bites")
	scene._update_eating(scene.EAT_DURATION)
	check(scene.eaten and scene.meat_prop == null, "finished meal clears hand")
	check(scene.drink_beer(), "beer at camp")
	check(not scene.drink_beer(), "beer cannot be stacked during animation")
	check(scene.beers == 0 and scene.beer_prop != null, "beer starts with hand visible, count waits for sip")
	scene._update_drinking(0.7)
	check(scene.can_opened and scene.beer_prop.get_node("Opening").visible, "can opens during raise")
	scene._toggle_car()
	check(not scene.in_car, "cannot get in car with beer in hand")
	scene._update_drinking(1.2)
	check(scene.beers == 1 and scene.beer_timer > 0 and scene.beer_prop.rotation.x > 0.9, "sip tilts can and counts one beer")
	scene._update_drinking(0.3)
	check(scene.beers == 1, "sip is counted only once")
	scene._update_drinking(2.0)
	check(scene.beer_prop == null and scene.drink_time < 0, "hand lowers and clears after animation")
	check(not scene.drink_beer(), "beer cooldown after animation")
	scene.beer_timer = 0
	check(scene.drink_beer(), "next beer allowed after cooldown")
	scene.paused = true
	var paused_time = scene.drink_time
	scene._process(0.5)
	check(scene.drink_time == paused_time, "pause freezes drinking")
	scene.paused = false
	scene.die("test interruption")
	check(scene.beer_prop == null and scene.beers == 1, "death clears hand without counting unfinished beer")
	scene.dead = false
	scene.menu.hide()
	scene.beers = 3
	check(scene.drink_beer(), "beer remains available after third can")
	scene._cancel_drink()
	scene.beers = 1
	check(not scene.start_rally(), "manual rally shortcut cannot skip the countdown")
	scene.course.phase = "racing"
	scene.spawn_racer("stuck")
	var r = scene.racers[0]
	for i in range(4):
		scene.spawn_racer("pass")
	var model_names: Dictionary = {}
	var numbers: Dictionary = {}
	for racer in scene.racers:
		model_names[racer.node.get_meta("model")] = true
		numbers[racer.node.get_meta("number")] = true
	check(model_names.size() == 5 and numbers.size() == 5, "five sequential crews have distinct classic models and numbers")
	for i in range(4):
		var extra = scene.racers.pop_back()
		extra.node.queue_free()
	r.s = r.focus - 1
	scene._update_racers(0.1)
	check(r.state == "offroad", "stranding begins at spectator zone")
	scene._update_racers(1.2)
	check(r.state == "stranded", "car stranded off road")
	scene.car.position = r.node.position + Vector3(8, 0, 0)
	scene.walker = r.node.position + scene.Recovery.road_direction(scene, r) * 3
	scene.stage.trees.clear()
	scene.stage.rocks.clear()
	Input.action_press("tow")
	scene._update_tow(0.1)
	check(scene.tow_target != null, "tow attaches near stranded car")
	scene._update_tow(6)
	Input.action_release("tow")
	check(scene.helped == 1 and r.kind == "pass" and r.state == "racing", "tow releases crew to race")
	check(scene.rope_mesh == null, "tow rope cleared")
	# Collision with an actual moving car must end the run.
	scene.spawn_racer("pass")
	var moving = scene.racers[-1]
	scene.walker = scene.stage.at(moving.s + 2.7)
	scene._update_racers(0.1)
	check(scene.dead, "moving rally car collision kills spectator")
	# Victory is separate from death and includes complete picnic.
	scene.dead = false
	scene.passed = scene.RALLY_CREW_LIMIT
	scene._check_finish()
	check(not scene.finished, "ten crews cannot finish before closing police")
	scene.course.phase = "complete"
	scene._check_finish()
	check(scene.finished, "full picnic, ten crews and closing police complete demo")
	print("RESULT: %d checks, %d failures" % [checks, failures])
	await scene._shutdown_audio()
	scene.queue_free()
	await process_frame
	call_deferred("quit", 1 if failures else 0)
