extends "res://tests/harness.gd"
const Props = preload("res://scripts/core/props.gd")
const FallenTrees = preload("res://scripts/stages/fallen_trees.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var taxi = Props.rally_car(5)
	var parts: Dictionary = taxi.get_meta("baked_parts", {})
	check(taxi.get_meta("number") == 65 and parts.has("TrunkTaxi"), "reference rally 2107 has number 65 and taxi checker")
	var sign: Vector3 = parts.TrunkTaxi.get_center() if parts.has("TrunkTaxi") else Vector3.ZERO
	check(sign.z > 1.4 and sign.y < 1.4, "taxi checker is on trunk, below roof")
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
	check(not game.drink_beer(), "collapsed player cannot restart the timer by drinking")
	game._cancel_drink()
	game._update_hud()
	check(game.sobriety_panel.visible and game.sobriety_bar.value == 0 and game.sober_remaining == 180, "collapse starts a visible three-minute recovery bar")
	game._update_sobriety(60)
	game._update_hud()
	check(game.sober_remaining == 120 and game.sobriety_bar.value == 60, "recovery bar advances with elapsed gameplay")
	game.paused = true
	game._process(30)
	check(game.sober_remaining == 120, "local pause freezes recovery")
	game.paused = false
	game.room.connected = true
	game.room.is_host = false
	game.room.world_paused = true
	game._update_sobriety(30)
	check(game.sober_remaining == 120, "host pause freezes a guest's recovery")
	game.room.world_paused = false
	game.room.connected = false
	game._update_sobriety(119.9)
	check(game.beers == 30 and game.sober_remaining > 0, "player stays down before three minutes")
	game._update_sobriety(0.1)
	game._update_camera(0.1)
	game._update_hud()
	check(game.beers == 0 and game.sober_remaining == 0 and game.drunk_strength == 0 and game.collapse_time == 0 and not game.sobriety_panel.visible and game.camera.position.y > game.walker.y + 1.5, "after three minutes player is sober and standing")
	position_before = game.walker
	Input.action_press("forward")
	game._walk(0.1)
	Input.action_release("forward")
	check(game.walker.distance_to(position_before) > 0.05, "walking is available again after recovery")
	check(game.drink_beer(), "beer becomes available again after recovery")
	game._cancel_drink()
	game.walker = game.car.position + Vector3(0, 0, 2.5)
	game._toggle_car()
	check(game.in_car, "recovered player can enter car for the end of the outing")
	game.in_car = false
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
	remote.beers = 0
	game.room._update_peers([{"id": "friend", "slot": 1, "name": "Друг", "state": remote}])
	game.room._process(0.8)
	check(absf(game.room.peers.friend.avatar.rotation.z) < 0.01, "friends see the recovered avatar stand up")
	var person = game.room.v(remote.pos)
	game.speed = 2
	check(game.contact_blocked(person + Vector3(-3, 0, 0), person + Vector3(-1, 0, 0), true) and not game.dead, "slow vehicle contact stops without killing pedestrian")
	# A fast car throws the friend (injuries.gd) instead of ending the outing.
	game.injuries.vehicle_sweep(person + Vector3(-3, 0, 0), person + Vector3(-1, 0, 0), Vector3(12, 0, 0), game.injuries.PLAYER_CAR_SPEED)
	check(game.injuries.is_down("player:friend") and not game.dead, "fast personal car throws the friend down")
	check(not game.contact_blocked(person + Vector3(-3, 0, 0), person + Vector3(-1, 0, 0), true), "cars pass a friend lying on the ground")
	game.injuries.records.clear()
	game.dead = false
	game.menu.hide()
	var index = 0
	var tree = game.stage.trees[index]
	check(game.stage.obstacle_hit(tree + Vector3(-3, 0, 0), tree + Vector3(3, 0, 0), 0.5) == index, "swept tree collision does not tunnel")
	check(game.stage.fell(index, Vector3.RIGHT) and not game.stage.fell(index, Vector3.RIGHT), "tree falls exactly once")
	game.stage.update_fallen(2)
	var tip: Vector3 = tree + game.stage.fallen[index].basis * Vector3.UP * game.stage.forest_data[index].height * 0.64
	check(absf(game.stage.fallen[index].basis.y.y) < 0.7 and absf(tip.y - game.stage.ground(tip)) < 0.3, "fallen trunk lies along the ground")
	var midpoint = tree + Vector3.RIGHT * game.stage.forest_data[index].height * 0.32
	check(game.stage.obstacle_hit(midpoint + Vector3(0, 0, -1), midpoint, 0.3) >= 0, "fallen log remains a collision obstacle")
	var final_basis = game.stage.fallen[index].basis
	game.stage.update_fallen(1)
	check(game.stage.fallen[index].basis == final_basis, "settled trees retain final collision basis")
	game.stage.apply_trees([[2, PI, PI * 0.5, 1.3]], game.stage.fallen)
	check(is_equal_approx(game.stage.fallen[2].basis.y.y, cos(game.stage.fallen[2].lie)) and game.stage.fallen[2].rendered_age == 1.3, "late completed tree snapshot renders the trunk lying down")
	var snapshot_basis = game.stage.fallen[2].basis
	game.stage.apply_trees([[2, PI * 0.5, PI * 0.5, 1.3]], game.stage.fallen)
	check(game.stage.fallen[2].basis != snapshot_basis, "completed tree snapshot direction change refreshes transform")
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
	# Past FallenTrees.LIMIT the host stands the oldest far tree back up; the
	# compact snapshot keeps the trees section small, and guests follow.
	for i in range(game.stage.trees.size()):
		if game.stage.fallen.size() >= FallenTrees.LIMIT + 40: break
		game.stage.fell(i, Vector3.RIGHT)
	game.stage.update_fallen(2)
	var bytes = JSON.stringify(game.stage.tree_snapshot()).length()
	check(game.stage.fallen.size() == FallenTrees.LIMIT + 40 and bytes < game.stage.fallen.size() * 32, "felled tree entries stay compact (%d bytes for %d trees)" % [bytes, game.stage.fallen.size()])
	var players = {"local": {"pos": game.room.a(game.player_position())}}
	var before: Array = game.stage.fallen.keys()
	for i in range(80):
		FallenTrees.recycle(game, players)
	var raised = before.filter(func(i): return not game.stage.fallen.has(i))
	check(game.stage.fallen.size() == FallenTrees.LIMIT and raised.size() == 40, "host keeps at most the limit of felled trees")
	var near_player = raised.filter(func(i): return Vector2(game.stage.trees[i].x, game.stage.trees[i].z).distance_to(Vector2(game.player_position().x, game.player_position().z)) <= FallenTrees.RAISE_CLEARANCE)
	check(near_player.is_empty(), "only trees out of the players' sight stand back up")
	var standing: Vector3 = game.stage.trees[raised[0]]
	check(game.stage.obstacle_hit(standing + Vector3(-2, 0, 0), standing + Vector3(2, 0, 0), 0.3) == raised[0], "a tree stood back up blocks on its stump again")
	guest.room.apply_world(game.room.world_state())
	check(guest.stage.fallen.size() == FallenTrees.LIMIT and not guest.stage.fallen.has(raised[0]), "guests stand the same trees back up")
	guest.stage.fell(raised[1], Vector3.LEFT)
	guest.tree_requests[raised[1]] = Vector3.LEFT
	guest.room.apply_world(game.room.world_state())
	check(guest.stage.fallen.has(raised[1]), "a guest's own unconfirmed fall survives a host snapshot")
	for scene in [game, guest]:
		await scene._shutdown_audio()
		scene.queue_free()
	await process_frame
	print("PARTY RESULT: %d checks, %d failures" % [checks, failures])
	finish()
