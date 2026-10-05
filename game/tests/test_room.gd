extends SceneTree
var checks = 0
var failures = 0
func check(ok: bool, name: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(name)
	else:
		print("PASS: " + name)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var host = load("res://main.tscn").instantiate()
	var guest = load("res://main.tscn").instantiate()
	root.add_child(host)
	root.add_child(guest)
	await process_frame
	for g in [host, guest]:
		g.set_process(false)
		g.room.set_process(false)
		g.start_game()
		host.room.player_id = "host"
		guest.room.player_id = "guest"
	host.room.is_host = true
	guest.room.is_host = false
	host.room.connected = true
	guest.room.connected = true
	check(guest.room.submit("table") and guest.camp == null, "guest camp action queues without changing local world")
	check(not guest.room.submit("beer"), "beer animation remains local")
	var cmd = {"id": "guest:1", "action": "table", "state": {"in_car": false, "pos": host.room.a(host.stage.clearings[0]), "car": host.room.a(guest.car.position), "yaw": 0.0}}
	var car_before = host.car.position
	host.room._apply_command(cmd)
	check(host.camp != null and host.car.position == car_before and host.in_car, "host executes guest placement and restores its player")
	guest.room.apply_world(host.room.world_state())
	check(guest.camp != null and guest.camp.position.distance_to(host.camp.position) < 0.02, "shared table has identical position")
	cmd.action = "chairs"
	host.room._apply_command(cmd)
	cmd.action = "grill"
	host.room._apply_command(cmd)
	host.cook_time = 19
	guest.room.apply_world(host.room.world_state())
	check(guest.has_chairs and guest.cooking and guest.cook_time == 19, "late world snapshot builds chairs and grill")
	host.in_car = false
	host.spawn_racer("stuck")
	host.racers[0].state = "stranded"
	host.racers[0].node.position = host.stage.clearings[0]
	guest.room.apply_world(host.room.world_state())
	check(guest.racers.size() == 1 and guest.racers[0].variant == host.racers[0].variant, "rally model and state replicated")
	guest.room.apply_world(host.room.world_state())
	check(guest.racers.size() == 1, "repeated snapshot does not duplicate rally cars")
	var guest_state = {"pos": host.room.a(host.stage.clearings[0]), "car": host.room.a(host.stage.clearings[0] + Vector3(0, 0, 12)), "in_car": false, "tow": true, "heading": 0.0, "yaw": 0.0, "pitch": 0.0, "beer": 1.5}
	host.room._update_peers([{"id": "guest", "name": "Друг", "state": guest_state}])
	check(host.room.peers.size() == 1, "remote avatar and personal car created")
	host.room._process(0.1)
	check(host.room.peers.guest.avatar.visible, "remote walking avatar is visible")
	check(host.room.peers.guest.can.visible, "remote drinking animation shows beer can")
	host.room.update_tow(3)
	check(host.tow_target != null and host.room.tow_owner == "guest" and host.tow_progress > 0, "guest holds rope using its own car")
	host.room.update_tow(3.1)
	check(host.helped == 1 and host.racers[0].state == "racing", "guest tow frees shared rally crew")
	host.racers[0].node.rotation = Vector3(0.15, 0.2, -0.18)
	host._update_stones(0.1)
	host.stone_impact("guest")
	guest.room.apply_world(host.room.world_state())
	await create_timer(0.4).timeout
	guest.room._process(0.1)
	check(guest.stones.size() == host.stones.size() and guest.stones.size() > 0, "shared gravel is replicated")
	check(absf(guest.racers[0].node.rotation.z + 0.18) < 0.02, "rally suspension roll replicated")
	var condition_after_hit = guest.condition
	guest.impact_shake = 0
	guest.room.apply_world(host.room.world_state())
	check(guest.condition == condition_after_hit and guest.impact_shake == 0, "repeated impact snapshot does not apply damage twice")
	host.paused = true
	guest.room.apply_world(host.room.world_state())
	check(guest.room.world_paused, "host pause replicated")
	guest.enable_mobile()
	var controls = guest.mobile_controls
	controls._layout()
	controls.touch_begin(9, controls.stick_center + Vector2(60, 0))
	check(not Input.is_action_pressed("right"), "host pause blocks guest mobile movement")
	var pause_found = false
	for button in controls.buttons:
		if button.action == "pause_demo":
			controls.touch_begin(10, button.rect.get_center())
			pause_found = true
			break
	check(pause_found and guest.paused and guest.menu.visible, "guest can still open pause and leave while host paused")
	guest.paused = false
	host.paused = false
	host.racers[0].node.queue_free()
	host.racers.clear()
	guest.room.apply_world(host.room.world_state())
	check(guest.racers.is_empty(), "removed rally car disappears from guest")
	host.room._update_peers([])
	check(host.room.peers.is_empty(), "departed player nodes removed")
	host.dead = true
	host.menu_title.text = "Общий выезд окончен"
	guest.room.apply_world(host.room.world_state())
	check(guest.dead and guest.menu.visible, "shared result reaches guest")
	guest.room.disconnect_room("Хозяин вышел")
	check(not guest.room.connected and guest.paused and guest.dead, "disconnect blocks further local play")
	print("ROOM RESULT: %d checks, %d failures" % [checks, failures])
	for g in [host, guest]:
		await g._shutdown_audio()
		g.queue_free()
	await process_frame
	quit(1 if failures else 0)
