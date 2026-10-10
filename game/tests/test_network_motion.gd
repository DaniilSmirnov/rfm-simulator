extends "res://tests/harness.gd"
const Buffer = preload("res://scripts/snapshot_motion.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var buffer = Buffer.new()
	buffer.push(1, Vector3.ZERO, Vector3(0, deg_to_rad(179), 0))
	buffer.push(1.2, Vector3(2, 0, 0), Vector3(0, deg_to_rad(-179), 0))
	var pose = buffer.sample(1.1)
	check(absf(pose.position.x - 1) < 0.001, "interpolates between timestamped samples")
	check(absf(absf(pose.rotation.y) - PI) < 0.02, "rotation follows short path across yaw wrap")
	check(not buffer.push(1.2, Vector3(99, 0, 0), Vector3.ZERO) and not buffer.push(1.1, Vector3(99, 0, 0), Vector3.ZERO), "duplicates and reordered responses do not rewind movement")
	check(absf(buffer.sample(1.25).position.x - 2.5) < 0.001, "brief missing sample predicts constant velocity")
	check(absf(buffer.sample(20).position.x - 4.0) < 0.001, "lost connection stops prediction after 200 milliseconds")
	buffer.push(2, Vector3(100, 0, 0), Vector3.ZERO)
	check(buffer.samples.size() == 1 and buffer.sample(1).position.x == 100, "recovery teleport clears interpolation history")
	buffer.push(2.1, Vector3(101, 0, 0), Vector3.ZERO, true)
	check(buffer.samples.size() == 1, "entering or exiting car resets avatar history")
	var fast = Buffer.new()
	fast.max_speed = 12
	fast.push(0, Vector3.ZERO, Vector3.ZERO)
	fast.push(0.01, Vector3(20, 0, 0), Vector3.ZERO)
	check(fast.sample(1).position.x <= 22.41, "prediction velocity is bounded for noisy snapshots")
	var jittered = Buffer.new()
	var snapshots = []
	for i in range(61):
		var time = i * 0.1
		snapshots.append({"time": time, "arrival": time + [0.025, 0.06, 0.09, 0.03, 0.05][i % 5]})
	var index = 0
	var largest_step = 0.0
	var largest_error = 0.0
	var previous = Vector3.ZERO
	for frame in range(140):
		var time = frame / 24.0
		while index < snapshots.size() and snapshots[index].arrival <= time:
			var sample = snapshots[index]
			jittered.push(sample.time, Vector3(sample.time * 15, 0, 0), Vector3.ZERO)
			index += 1
		var rendered = jittered.sample(time - 0.18).position
		if frame > 20:
			largest_step = maxf(largest_step, rendered.distance_to(previous))
			largest_error = maxf(largest_error, absf(rendered.x - (time - 0.18) * 15))
		previous = rendered
	check(largest_step < 0.64 and largest_error < 0.01, "10 Hz snapshots with variable delays move continuously at 24 FPS")
	check(jittered.samples.size() <= Buffer.MAX_SAMPLES, "snapshot history remains bounded")
	var adaptive = Buffer.new()
	adaptive.push(0.0, Vector3.ZERO, Vector3.ZERO)
	adaptive.push(0.1, Vector3(1.0, 0, 0), Vector3.ZERO)
	check(adaptive.delay() <= 0.11, "stable 10 Hz transport uses roughly 100 ms buffer instead of 180 ms")
	var direct_rate = Buffer.new()
	for i in range(30):
		direct_rate.push(i * 0.05, Vector3(i * 0.5, 0, 0), Vector3.ZERO)
	check(direct_rate.delay() <= 0.07 and direct_rate.delay() >= 0.06, "a 20 Hz direct link keeps a 60 ms buffer")
	var before = adaptive.render(0.25).position.x
	adaptive.push(0.4, Vector3(4.0, 0, 0), Vector3.ZERO)
	check(adaptive.render(0.26).position.x >= before, "jitter-driven buffer increase never rewinds remote motion")
	check(adaptive.render(0.1).position.x >= before, "backward network clock correction never rewinds remote motion")
	check(adaptive.render(10, true).position.x == 4.0, "paused actors stop extrapolation")
	adaptive.push(0.5, Vector3(100, 0, 0), Vector3.ZERO, true)
	check(adaptive.render(0.5).position.x == 100, "teleport resets monotonic render timeline")
	for latency in [0.05, 0.10, 0.20]:
		var delayed = Buffer.new()
		var next_snapshot = 0
		var previous_render = 0.0
		var monotonic = true
		var finite_motion = true
		for frame in range(144):
			var now = frame / 24.0
			while next_snapshot * 0.1 + latency <= now:
				var sent = next_snapshot * 0.1
				delayed.push(sent, Vector3(sent * 15.0, 0, 0), Vector3.ZERO)
				next_snapshot += 1
			var rendered = delayed.render(now).position.x
			monotonic = monotonic and rendered >= previous_render - 0.001
			finite_motion = finite_motion and is_finite(rendered)
			previous_render = rendered
		check(monotonic and finite_motion, "remote motion stays continuous with %d ms latency" % int(latency * 1000))
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.start_game()
	game.room.connected = true
	game.room.is_host = false
	game.room.player_id = "guest"
	game.room.transport.request_kind = "sync"
	var own_position = game.car.position
	game.room._update_peers([{"id": "guest", "state": {"car": [900, 0, 0]}}])
	check(game.car.position == own_position, "own local prediction is not overwritten by delayed echo")
	var now = Time.get_ticks_usec() / 1000000.0
	game.room.transport.request_sent_at = now - 2.0
	game.room.update_server_clock((now + 100) * 1000)
	now = Time.get_ticks_usec() / 1000000.0
	game.room.transport.request_sent_at = now - 0.02
	game.room.update_server_clock((now + 100) * 1000)
	check(absf(game.room.transport.server_offset - 100.01) < 0.02, "fast response repairs clock calibrated by a slow first response")
	var offset_before = game.room.transport.server_offset
	now = Time.get_ticks_usec() / 1000000.0
	game.room.transport.request_sent_at = now - 1.5
	game.room.update_server_clock((now + 100) * 1000)
	check(game.room.transport.server_offset == offset_before, "slow outlier does not shift calibrated render clock")
	var world = game.room.world_state()
	world.elapsed = 10
	var stamp = Time.get_ticks_msec()
	var reply = {"accepted": 0, "players": [], "world": world, "world_time": stamp}
	game.room._response(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(reply).to_utf8_buffer())
	game.elapsed = 10.1
	game.room._response(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(reply).to_utf8_buffer())
	check(game.elapsed == 10.1, "duplicate cached world does not rewind guest timers")
	reply.world_time = stamp - 1
	game.room._response(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(reply).to_utf8_buffer())
	check(game.elapsed == 10.1, "older world snapshots are ignored")
	reply.world_time = stamp + 100
	reply.world.elapsed = 10.2
	game.room._response(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(reply).to_utf8_buffer())
	check(absf(game.elapsed - 10.2) < 0.001, "new world snapshot still applies shared state")
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	print("NETWORK MOTION RESULT: %d checks, %d failures" % [checks, failures])
	finish()
