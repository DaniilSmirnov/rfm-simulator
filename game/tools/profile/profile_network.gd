extends SceneTree
# Multiplayer lag profile: a host and a guest in one process, joined by a
# simulated direct link (one-way latency + jitter), both running their real
# room code paths in real time. Prints what each side pays per packet and per
# frame, how far the guest's prediction is corrected, and how evenly remote
# cars move.
#   godot --headless --path game --script res://tools/profile/profile_network.gd -- <stage> [latency_ms] [jitter_ms] [seconds]
const PeerView = preload("res://scripts/net/peer_view.gd")
const NetProtocol = preload("res://scripts/net/net_protocol.gd")

var host
var guest
var latency = 0.04
var jitter = 0.02
var seconds = 10.0
var rng = RandomNumberGenerator.new()
# In-flight packets: {"at": seconds, "bytes": PackedByteArray}
var to_host: Array = []
var to_guest: Array = []
var stats: Dictionary = {}

func _initialize():
	call_deferred("run")

func add(key: String, value: float) -> void:
	if not stats.has(key):
		stats[key] = []
	stats[key].append(value)

func report(key: String, unit: String = "us") -> void:
	var samples: Array = stats.get(key, [])
	if samples.is_empty():
		print("NET_PROFILE ", key, " n=0")
		return
	samples.sort()
	var sum = 0.0
	for s in samples:
		sum += s
	print("NET_PROFILE %s n=%d avg_%s=%.1f p50=%.1f p95=%.1f max=%.1f" % [key, samples.size(), unit, sum / samples.size(), samples[samples.size() / 2], samples[int(samples.size() * 0.95)], samples[-1]])

func now() -> float:
	return Time.get_ticks_usec() / 1000000.0

func run():
	var args = OS.get_cmdline_user_args()
	var stage_index = int(args[0]) if args.size() > 0 else 0
	if args.size() > 1: latency = float(args[1]) / 1000.0
	if args.size() > 2: jitter = float(args[2]) / 1000.0
	if args.size() > 3: seconds = float(args[3])
	rng.seed = 7
	host = load("res://main.tscn").instantiate()
	guest = load("res://main.tscn").instantiate()
	root.add_child(host)
	# The guest gets its own physics space: in one world the two copies of
	# every stage prop and camp grill pushed each other apart (NaN grills,
	# props jittering forever).
	var guest_world = SubViewport.new()
	guest_world.own_world_3d = true
	root.add_child(guest_world)
	guest_world.add_child(guest)
	await process_frame
	for g in [host, guest]:
		g.set_process(false)
		g.room.set_process(false)
		g.select_stage(stage_index)
		g.rng.seed = 20261008
		await g.start_game()
	host.room.player_id = "host"
	guest.room.player_id = "guest"
	host.room.is_host = true
	host.room.connected = true
	guest.room.connected = true
	guest.room.prediction.coalesce = true
	for r in [host.room, guest.room]:
		r.host_id = "host"
		r.members = {"host": {"name": "host", "slot": 0, "car_model": 0, "character": 0}, "guest": {"name": "guest", "slot": 1, "car_model": 0, "character": 1}}
	host.room._update_peers([{"id": "guest", "name": "guest", "slot": 1, "car_model": 0, "character": 1, "state": null}])
	guest.room._update_peers([{"id": "host", "name": "host", "slot": 0, "car_model": 0, "character": 0, "state": null}])
	# The host's side of the simulated link: slow sections go out per link.
	host.room.direct.links["guest"] = {"pc": null, "channel": null, "open": true, "last_received": INF, "attempts": 0, "retry_at": INF}
	# Racing: eight crews on the stage, as in the CPU profile.
	host.course.phase = "racing"
	host.spawn_clock = 999.0
	for i in range(8):
		host.spawn_racer("pass")
		var racer = host.racers.back()
		racer.s = 20.0 + i * 70.0
		racer.node.position = host.race_at(racer.s)
	host.in_car = true
	guest.in_car = true
	print("NET_PROFILE setup stage=%d latency_ms=%d jitter_ms=%d seconds=%.0f spectators=%d people=%d" % [stage_index, latency * 1000, jitter * 1000, seconds, host.spectators.groups.size(), host.injuries.people().size()])
	await loop()
	breakdown()
	for key in stats.keys():
		report(key, "m" if key.begins_with("motion") or key.begins_with("correction") else ("B" if key.ends_with("bytes") else "us"))
	quit()

# Where a guest's world packet goes: validation, reconciliation, each provider.
func breakdown() -> void:
	var Validation = load("res://scripts/net/world_validation.gd")
	var message = JSON.parse_string(JSON.stringify(host.room.direct.world_packet()))
	var world: Dictionary = message.world
	var room = guest.room
	for i in range(20):
		var t0 = Time.get_ticks_usec()
		Validation.valid(world)
		add("break_validate_once", Time.get_ticks_usec() - t0)
		var drive = world.get("driving", {}).get("guest", {})
		if not drive.is_empty():
			room.prediction.context = room.drive_context("guest")
			t0 = Time.get_ticks_usec()
			room.prediction.reconcile(drive, guest.stage, guest.selected_car)
			add("break_reconcile_%d_ticks" % room.prediction.backlog_ticks(), Time.get_ticks_usec() - t0)
		room.world_sync._ensure()
		for p in room.world_sync.providers:
			if p.section == "":
				t0 = Time.get_ticks_usec()
				p.apply.call(world, room.server_clock())
				add("break_apply_" + p.name, Time.get_ticks_usec() - t0)
		var solver = host.room.host_drives.get("guest")
		if solver != null:
			var inputs = []
			for k in range(10):
				inputs.append({"seq": solver.ack + 1 + k, "ticks": 4, "throttle": 1.0, "steer": 0.2, "brake": false})
			solver.context = host.room.drive_context("guest")
			t0 = Time.get_ticks_usec()
			solver.accept(inputs, host.stage, 0)
			add("break_host_step_40_ticks", Time.get_ticks_usec() - t0)
		for p in host.room.world_sync.providers:
			t0 = Time.get_ticks_usec()
			var part = p.snapshot.call()
			add("break_snapshot_" + p.name, Time.get_ticks_usec() - t0)
			add("break_snapshot_" + p.name + "_bytes", JSON.stringify(part).length())

func steer_input(t: float) -> void:
	Input.action_press("forward")
	var steer = sin(t * 0.7) * 0.6
	if steer > 0:
		Input.action_release("left")
		Input.action_press("right", steer)
	else:
		Input.action_release("right")
		Input.action_press("left", -steer)

func loop() -> void:
	var start = now()
	var last = start
	var guest_state_clock = 0.0
	var host_world_clock = 0.0
	var previous_view = {}
	var world_interval = 1.0 / float(NetProtocol.direct("world_rate", 20))
	var state_interval = 1.0 / float(NetProtocol.direct("state_rate", 30))
	while now() - start < seconds:
		await process_frame
		var t = now()
		var delta = minf(t - last, 0.1)
		last = t
		steer_input(t - start)
		# Host frame.
		var t0 = Time.get_ticks_usec()
		host._process(delta)
		add("host_game_process", Time.get_ticks_usec() - t0)
		host.room.transport.advance_view_clock(delta)
		while not to_host.is_empty() and to_host[0].at <= t:
			var bytes: PackedByteArray = to_host.pop_front().bytes
			t0 = Time.get_ticks_usec()
			host.room.direct._receive("guest", JSON.parse_string(bytes.get_string_from_utf8()))
			add("host_receive_guest_state", Time.get_ticks_usec() - t0)
		host_world_clock += delta
		if host_world_clock >= world_interval:
			host_world_clock = fmod(host_world_clock, world_interval)
			t0 = Time.get_ticks_usec()
			var parts = host.room.world_sync.current_parts()
			add("host_world_state_and_split", Time.get_ticks_usec() - t0)
			t0 = Time.get_ticks_usec()
			# What the link sends this guest: a delta against what it confirmed.
			var whole = host.room.direct.world_packet()
			host.room.world_sync._ensure()
			var current = host.room.direct.WorldDelta.parts(whole.world, host.room.world_sync.providers)
			var packet = host.room.direct.WorldDelta.packet(host.room.direct.links["guest"], whole, current, guest.room.a(guest.car.position))
			var bytes = JSON.stringify(packet).to_utf8_buffer()
			add("host_world_packet_total", Time.get_ticks_usec() - t0)
			add("whole_world_packet_bytes", JSON.stringify(whole).length())
			add("delta_crews_sent", packet.world.get("racers", []).size())
			add("world_packet_bytes", bytes.size())
			_queue(to_guest, t, bytes)
			if int((t - start) / NetProtocol.sync_interval()) != int((t - start - delta) / NetProtocol.sync_interval()):
				t0 = Time.get_ticks_usec()
				host.room.world_sync.refresh_cold()
				add("host_refresh_cold", Time.get_ticks_usec() - t0)
			for piece in host.room.direct.cold_messages("guest"):
				var piece_bytes = JSON.stringify(piece).to_utf8_buffer()
				add("cold_piece_bytes", piece_bytes.size())
				_queue(to_guest, t, piece_bytes)
			if int(t - start) != int(t - start - delta):
				add("host_membership_body_bytes", JSON.stringify(host.room.sync_body()).length())
		# Guest frame.
		t0 = Time.get_ticks_usec()
		guest._process(delta)
		add("guest_game_process", Time.get_ticks_usec() - t0)
		t0 = Time.get_ticks_usec()
		guest.room.transport.advance_view_clock(delta)
		guest.room._render_guest_world(delta)
		add("guest_render_world", Time.get_ticks_usec() - t0)
		while not to_guest.is_empty() and to_guest[0].at <= t:
			var bytes: PackedByteArray = to_guest.pop_front().bytes
			t0 = Time.get_ticks_usec()
			var message = JSON.parse_string(bytes.get_string_from_utf8())
			if message.t == "c":
				t0 = Time.get_ticks_usec()
				guest.room.direct._receive("host", message)
				add("guest_apply_cold_piece", Time.get_ticks_usec() - t0)
				continue
			add("guest_parse_world", Time.get_ticks_usec() - t0)
			_replay_reason(message)
			var pending = guest.room.prediction.pending.size()
			var ticks = guest.room.prediction.backlog_ticks()
			t0 = Time.get_ticks_usec()
			guest.room.direct._receive("host", message)
			add("guest_apply_world", Time.get_ticks_usec() - t0)
			add("guest_replayed_commands", pending)
			add("guest_replayed_ticks", ticks)
			if guest.room.prediction.active:
				add("correction_after_reconcile", guest.room.prediction.visual_offset.length())
		guest_state_clock += delta
		if guest_state_clock >= state_interval and guest.room.prediction_enabled:
			guest_state_clock = fmod(guest_state_clock, state_interval)
			t0 = Time.get_ticks_usec()
			var bytes = JSON.stringify({"t": "s", "state": NetProtocol.outgoing_state(guest.room.local_state()), "cr": guest.room.world_sync.cold_revs, "wa": guest.room.direct.world_ack()}).to_utf8_buffer()
			guest.room.prediction.seal()
			add("guest_state_packet", Time.get_ticks_usec() - t0)
			add("guest_state_bytes", bytes.size())
			_queue(to_host, t, bytes)
		t0 = Time.get_ticks_usec()
		var context = guest.room.drive_context("guest")
		add("drive_context", Time.get_ticks_usec() - t0)
		add("drive_context_contacts", context.contacts.size())
		# How remote cars move on each screen, against how they really move.
		_watch("motion_host_sees_guest", host, "guest", guest.car.position if guest.room.prediction.active else null, previous_view, delta)
		_watch("motion_guest_sees_host", guest, "host", host.car.position, previous_view, delta)
	for action in ["forward", "left", "right"]:
		Input.action_release(action)

# Whether this packet will make the guest replay its input, and the first
# field that differs from the prediction when it does.
func _replay_reason(message) -> void:
	var p = guest.room.prediction
	if not message is Dictionary or not message.get("world") is Dictionary or not p.active:
		return
	var drive = message.world.get("driving", {}).get("guest", {})
	if drive.is_empty() or int(drive.ack) < p.ack:
		return
	var later = p.pending.filter(func(c): return int(c.seq) > int(drive.ack))
	var expected = p.snapshot() if later.is_empty() else p.predicted.get(int(drive.ack))
	var replay = expected == null or not p.matches(expected, drive)
	add("guest_replay_share", 1.0 if replay else 0.0)
	if replay and expected != null:
		for key in drive:
			if key != "ack" and str(drive[key]) != str(expected.get(key)) and not p.matches(expected.merged({key: drive[key]}, true), expected):
				add("replay_field_" + key, 1.0)
				break

func _queue(queue: Array, t: float, bytes: PackedByteArray) -> void:
	# Unordered channel: each packet takes its own latency; the queue is kept
	# sorted by arrival so a late packet can be overtaken.
	var at = t + latency + rng.randf() * jitter
	var entry = {"at": at, "bytes": bytes}
	var i = queue.size()
	while i > 0 and queue[i - 1].at > at:
		i -= 1
	queue.insert(i, entry)

# Per frame: the rendered step versus the true step of the same car. A smooth
# view moves like the real car shifted in time, so the step error stays small.
func _watch(key: String, viewer, id: String, truth, previous: Dictionary, delta: float) -> void:
	if truth == null or not viewer.room.peers.has(id):
		return
	var peer = viewer.room.peers[id]
	if peer.car_motion.samples.size() < 2:
		return
	var rendered: Vector3 = peer.car_motion.render(viewer.room.server_clock()).position
	var last = previous.get(key)
	if last != null:
		var shown = rendered.distance_to(last.rendered) / delta
		var real = (truth as Vector3).distance_to(last.truth) / delta
		add(key + "_speed_error", absf(shown - real))
		add(key + "_lag", rendered.distance_to(truth))
	previous[key] = {"rendered": rendered, "truth": truth}
