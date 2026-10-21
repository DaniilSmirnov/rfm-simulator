extends "res://tests/harness.gd"
const Buffer = preload("res://scripts/net/snapshot_motion.gd")
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
	# Cars are shown where they are now: dead reckoning ahead of the newest
	# sample, with new samples blended in instead of jumping.
	var circle = func(t: float) -> Vector3: return Vector3(sin(t * 0.5) * 40.0, 0, cos(t * 0.5) * 40.0)
	var heading = func(t: float) -> float: return wrapf(t * 0.5 - PI / 2, -PI, PI)
	for latency in [0.04, 0.12]:
		var ahead = Buffer.new()
		ahead.predictive = true
		var behind_buffer = Buffer.new()
		var next_sample = 0
		var worst_ahead = 0.0
		var worst_behind = 0.0
		var worst_step = 0.0
		var last_shown = Vector3.ZERO
		var jitter_rng = RandomNumberGenerator.new()
		jitter_rng.seed = 7
		var arrivals = []
		for i in range(200):
			arrivals.append(i * 0.05 + latency + jitter_rng.randf() * latency * 0.5)
		for frame in range(400):
			var now = frame / 60.0
			while next_sample < arrivals.size() and arrivals[next_sample] <= now:
				var sent = next_sample * 0.05
				ahead.push(sent, circle.call(sent), Vector3(0, heading.call(sent), 0))
				behind_buffer.push(sent, circle.call(sent), Vector3(0, heading.call(sent), 0))
				next_sample += 1
			var shown = ahead.render(now).position
			if frame > 60:
				worst_ahead = maxf(worst_ahead, shown.distance_to(circle.call(now)))
				worst_behind = maxf(worst_behind, behind_buffer.render(now).position.distance_to(circle.call(now)))
				worst_step = maxf(worst_step, shown.distance_to(last_shown))
			last_shown = shown
		check(worst_ahead < 0.15 and worst_ahead < worst_behind * 0.2, "a car turning at 20 m/s is shown where it is now with %d ms latency (%.2f m off, %.2f m behind before)" % [int(latency * 1000), worst_ahead, worst_behind])
		check(worst_step < 0.5, "predicted car moves continuously with %d ms latency" % int(latency * 1000))
	var braking = Buffer.new()
	braking.predictive = true
	var largest_jump = 0.0
	var shown_before = Vector3.ZERO
	for frame in range(120):
		var now = frame / 60.0
		if frame % 3 == 0:
			var sent = now - 0.1
			if sent >= 0:
				braking.push(sent, Vector3(minf(sent, 1.0) * 20.0, 0, 0), Vector3.ZERO)
		var shown = braking.render(now).position
		if frame > 12:
			largest_jump = maxf(largest_jump, shown.distance_to(shown_before))
		shown_before = shown
	check(largest_jump < 0.6, "a sudden stop is blended in, not snapped (largest frame step %.2f m)" % largest_jump)
	check(absf(braking.render(5.0).position.x - 20.0) < 0.05, "a stopped car settles where it stopped")
	var known = Buffer.new()
	known.predictive = true
	known.push(0.0, Vector3.ZERO, Vector3.ZERO, false, Vector3(0, 0, -10))
	check(known.render(0.1).position.distance_to(Vector3(0, 0, -1)) < 0.001, "a velocity sent by the host is used from the first sample")
	check(known.render(5.0).position.z >= -10.0 * Buffer.MAX_LEAD - 0.001, "a lost connection stops prediction after the lead limit")
	check(known.render(6.0, true).position == Vector3.ZERO and known.correction_position == Vector3.ZERO, "paused cars show the last sample")
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
	# A guest car driven on the host is stamped by its simulated ticks, so
	# input bursts that arrive with jitter still give evenly spaced samples.
	var Prediction = load("res://scripts/net/drive_prediction.gd")
	var rng = RandomNumberGenerator.new()
	rng.seed = 3
	var stamp_time = 100.0 - Prediction.STAMP_LAG
	var worst_spacing = 0.0
	var behind = true
	for i in range(1, 300):
		var arrival = 100.0 + i / 30.0 + rng.randf() * 0.04
		var next_stamp = Prediction.stamp(stamp_time, 4, arrival)
		if i > 1:
			worst_spacing = maxf(worst_spacing, absf((next_stamp - stamp_time) - 4.0 / 120.0))
		behind = behind and next_stamp <= arrival and next_stamp > arrival - 0.25
		stamp_time = next_stamp
	check(worst_spacing <= Prediction.STAMP_DRIFT + 0.0001, "jittered input bursts keep simulation stamps evenly spaced")
	check(behind, "simulation stamps stay just behind the arrival clock")
	check(Prediction.stamp(stamp_time, 0, stamp_time + 5.0) == stamp_time + 5.0 - Prediction.STAMP_LAG, "a stall resets the stamp to the clock")
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	print("NETWORK MOTION RESULT: %d checks, %d failures" % [checks, failures])
	finish()
