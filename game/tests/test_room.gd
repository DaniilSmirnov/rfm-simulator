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
	cmd.placement = {"pos": host.room.a(host.stage.clearings[0] + Vector3(0, 0, -2.5)), "yaw": 0}
	host.cargo.held["guest"] = {"kind": "table", "owner": "guest", "returning": false}
	host.room._apply_command(cmd)
	check(host.camp != null and host.car.position == car_before and host.in_car, "host executes guest placement and restores its player")
	guest.room.apply_world(host.room.world_state())
	check(guest.camp != null and guest.camp.position.distance_to(host.camp.position) < 0.02, "shared table has identical position")
	cmd.action = "chairs"
	cmd.placement.pos = host.room.a(host.camp.position + Vector3(-1.6, 0, 0.7))
	host.cargo.held["guest"] = {"kind": "chairs", "owner": "guest", "returning": false}
	host.room._apply_command(cmd)
	cmd.action = "grill"
	cmd.placement.pos = host.room.a(host.camp.position + Vector3(0.3, 0, -2.4))
	host.cargo.held["guest"] = {"kind": "grill", "owner": "guest", "returning": false}
	host.room._apply_command(cmd)
	host.cook_time = 19
	guest.room.apply_world(host.room.world_state())
	check(guest.has_chairs and guest.cooking and guest.cook_time == 19, "late world snapshot builds chairs and grill")
	host.in_car = false
	host.course.phase = "racing"
	host.spawn_racer("stuck")
	host.racers[0].state = "stranded"
	host.racers[0].node.position = host.stage.clearings[0]
	guest.room.apply_world(host.room.world_state())
	check(guest.racers.size() == 1 and guest.racers[0].variant == host.racers[0].variant, "rally model and state replicated")
	guest.room.apply_world(host.room.world_state())
	check(guest.racers.size() == 1, "repeated snapshot does not duplicate rally cars")
	var guest_state = {"pos": host.room.a(host.racers[0].node.position + host.Recovery.road_direction(host, host.racers[0]) * 3), "car": [170, 0, 0], "in_car": false, "tow": true, "heading": 0.0, "yaw": 0.0, "pitch": 0.0, "beer": 1.5}
	host.room._update_peers([{"id": "guest", "name": "Друг", "state": guest_state}])
	check(host.room.peers.size() == 1, "remote avatar and personal car created")
	host.room._process(0.1)
	check(host.room.peers.guest.avatar.visible, "remote walking avatar is visible")
	check(host.room.peers.guest.can.visible, "remote drinking animation shows beer can")
	host.stage.trees.clear()
	host.stage.rocks.clear()
	host.room.update_tow(3)
	check(host.tow_target != null and host.room.tow_owner == "guest" and host.tow_progress > 0, "guest holds rope on foot without its own car")
	guest_state.pos = host.room.a(host.racers[0].node.position + host.Recovery.road_direction(host, host.racers[0]) * 3)
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
	var drive_state = {"drive_enabled": true, "drive_inputs": [{"seq": 1, "ticks": 12, "throttle": 1.0, "steer": 0.0, "brake": false}], "pos": [999, 0, 0], "car": [999, 0, 0], "in_car": true, "heading": 0.0, "yaw": 0.0, "pitch": 0.0, "beer": -1.0}
	var driver = {"id": "driver", "name": "Driver", "slot": 1, "car_model": 0, "state_time": 10000, "state": drive_state.duplicate(true)}
	host.room._update_peers([driver])
	check(host.room.host_drives.driver.node.position.distance_to(host.stage.at(18)) < 2, "host initializes driving from trusted slot rather than claimed position")
	var solver = host.room.host_drives.driver
	driver.state = drive_state.duplicate(true)
	driver.state.drive_inputs.append({"seq": 2, "ticks": 12, "throttle": 1.0, "steer": 0.0, "brake": false})
	host.room._update_peers([driver])
	check(solver.ack == 2 and host.room.peers.driver.state.car == host.room.a(solver.node.position), "host render and contacts advance when queued input shares the same client timestamp")
	check(host.room.peers.driver.last_state_time == 10.0, "authoritative rendering does not refresh stale player activity")
	host.room._update_peers([])
	check(host.room.host_drives.is_empty(), "departed driver removes authoritative physics and budget")
	guest.room.prediction_enabled = true
	guest.room.prediction.reset(guest.car.position, guest.heading)
	var visual = guest.car.get_children().filter(func(child): return child is MeshInstance3D)[0]
	var original_visual = visual.transform
	var original_car = guest.car.transform
	guest.room.prediction.visual_offset = Vector3(0.5, 0.1, 0.4)
	guest.room.smooth_car_visuals()
	var once_visual = visual.transform
	guest.room.smooth_car_visuals()
	check(guest.car.transform == original_car and visual.transform.is_equal_approx(once_visual), "visual correction keeps physics root fixed and never accumulates between frames")
	check(visual.position.distance_to(original_visual.origin + guest.car.basis.inverse() * guest.room.prediction.visual_offset) < 0.00001, "car mesh receives the same world correction as the camera")
	guest.room.prediction.visual_offset = Vector3.ZERO
	guest.room.smooth_car_visuals()
	check(visual.transform.is_equal_approx(original_visual), "settled correction restores original model transform")
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
