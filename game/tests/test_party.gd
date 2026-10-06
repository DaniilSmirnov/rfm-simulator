extends SceneTree
const Props = preload("res://scripts/props.gd")
var failures = 0
var checks = 0
func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(title)
	else:
		print("PASS: " + title)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var taxi = Props.rally_car(5)
	check(taxi.get_meta("number") == 65 and taxi.has_node("TrunkTaxi"), "reference rally 2107 has number 65 and taxi checker")
	check(taxi.get_node("TrunkTaxi").position.z > 1.4 and taxi.get_node("TrunkTaxi").position.y < 1.4, "taxi checker is on trunk, below roof")
	taxi.free()
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.start_game()
	game.in_car = false
	game.walker = game.stage.clearings[0]
	game.place_table()
	game.place_chairs()
	game.start_grill()
	game.beers = 1
	game.drink_beer()
	game._update_drinking(1.9)
	game._cancel_drink()
	check(game.drunk_strength == 0, "first two beers do not sway the camera")
	game.beer_timer = 0
	game.drink_beer()
	game._update_drinking(1.9)
	game._cancel_drink()
	game._process(0.1)
	check(game.drunk_strength > 0 and absf(game.camera.rotation.z) < deg_to_rad(3.0), "third sip starts bounded gentle sway")
	var mild = game.drunk_strength
	game._update_intoxication(10)
	check(game.drunk_strength < mild, "beer sway gradually fades without further sips")
	game.drunk_strength = 1.0
	var sway_bounded = true
	for frame in range(240):
		game._update_intoxication(1.0 / 24.0)
		game._update_camera(1.0 / 24.0)
		sway_bounded = sway_bounded and absf(game.camera.rotation.z) <= deg_to_rad(3.01)
	check(sway_bounded, "sway never rotates the screen fully")
	game._update_intoxication(60)
	game._update_camera(0.1)
	check(game.drunk_strength == 0 and is_zero_approx(game.camera.rotation.z), "beer sway ends completely after a minute")
	game.drunk_strength = 0.5
	game.paused = true
	var phase = game.drunk_phase
	var strength = game.drunk_strength
	game._process(0.5)
	check(game.drunk_phase == phase and game.drunk_strength == strength, "pause freezes intoxication")
	game.paused = false
	game.beers = 29
	game.beer_timer = 0
	check(game.drink_beer(), "no hard limit on beer")
	game._update_drinking(1.9)
	check(game.beers == 30, "thirtieth sip counted once")
	var position_before = game.walker
	Input.action_press("forward")
	game._walk(1)
	Input.action_release("forward")
	check(game.walker == position_before, "thirtieth beer disables walking")
	game._update_camera(1.0)
	check(game.camera.position.y < game.walker.y + 0.5, "collapsed view lies near ground")
	game._cancel_drink()
	game.beer_timer = 0
	check(game.drink_beer(), "beer remains available even after thirty")
	game._cancel_drink()
	game.beers = 0
	game.walker = game.car.position + Vector3(0, 0, 2.5)
	check(game.contact_blocked(game.walker, game.car.position, false), "walker cannot pass through parked car")
	var remote = game.room.local_state()
	remote.pos = game.room.a(game.stage.clearings[0])
	remote.car = game.room.a(game.stage.clearings[0] + Vector3(10, 0, 0))
	remote.in_car = false
	remote.beers = 30
	game.room.connected = true
	game.room.is_host = true
	game.room.busy = true
	game.room._update_peers([{"id": "friend", "slot": 1, "name": "Друг", "state": remote}])
	game.room._process(0.8)
	check(absf(game.room.peers.friend.avatar.rotation.z - PI / 2) < 0.01, "friends see collapsed avatar")
	var person = game.room.v(remote.pos)
	game.speed = 2
	check(game.contact_blocked(person + Vector3(-3, 0, 0), person + Vector3(-1, 0, 0), true) and not game.dead, "slow vehicle contact stops without killing pedestrian")
	game.speed = 12
	game.contact_blocked(person + Vector3(-3, 0, 0), person + Vector3(-1, 0, 0), true)
	check(game.dead, "fast personal car impact ends shared outing")
	game.dead = false
	game.menu.hide()
	var index = 0
	var tree = game.stage.trees[index]
	check(game.stage.obstacle_hit(tree + Vector3(-3, 0, 0), tree + Vector3(3, 0, 0), 0.5) == index, "swept tree collision does not tunnel")
	check(game.stage.fell(index, Vector3.RIGHT) and not game.stage.fell(index, Vector3.RIGHT), "tree falls exactly once")
	game.stage.update_fallen(2)
	check(absf(game.stage.fallen[index].basis.y.y) < 0.01, "fallen trunk transform stays horizontal")
	var midpoint = tree + Vector3.RIGHT * game.stage.forest_data[index].height * 0.32
	check(game.stage.obstacle_hit(midpoint + Vector3(0, 0, -1), midpoint, 0.3) >= 0, "fallen log remains a collision obstacle")
	var remote_tree = game.stage.trees[1]
	remote.car = game.room.a(remote_tree + Vector3(0, 0, 1))
	remote.speed = 10
	remote.trees = [{"id": 1, "dir": [1, 0, 0]}]
	game.room._update_peers([{"id": "friend", "slot": 1, "name": "Друг", "state": remote}])
	game.room.check_remote_collisions()
	check(game.stage.fallen.has(1), "host validates friend's tree impact")
	var guest = load("res://main.tscn").instantiate()
	root.add_child(guest)
	await process_frame
	guest.set_process(false)
	guest.room.set_process(false)
	guest.start_game()
	guest.room.apply_world(game.room.world_state())
	check(guest.stage.fallen.has(index) and guest.stage.fallen[index].age == 1.3, "late join receives fully fallen tree")
	guest.room.apply_world(game.room.world_state())
	check(guest.stage.fallen.size() == game.stage.fallen.size(), "repeated snapshot does not duplicate fallen trees")
	for scene in [game, guest]:
		await scene._shutdown_audio()
		scene.queue_free()
	await process_frame
	print("PARTY RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
