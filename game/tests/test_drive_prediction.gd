extends SceneTree
const Predictor = preload("res://scripts/drive_prediction.gd")
const Stage = preload("res://scripts/stage.gd")
var failures = 0
func check(ok: bool, title: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + title)
	if not ok: failures += 1
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var stage = Stage.new()
	var client = Predictor.new()
	var host = Predictor.new()
	client.reset(stage.at(12), 0)
	host.reset(stage.at(12), 0)
	for i in range(30):
		client.predict(5, 1.0, 0.3, false, stage, 0)
	var predicted = client.node.position
	host.accept(client.pending.slice(0, 10), stage, 0)
	client.reconcile(host.snapshot(), stage, 0)
	check(client.node.position.distance_to(predicted) < 0.00001, "replay restores exact predicted physics after partial acknowledgement")
	check(client.pending.size() == 20 and client.ack == 10, "only acknowledged inputs are removed")
	host.accept(client.pending, stage, 0)
	var once = host.node.position
	host.accept(client.pending, stage, 0)
	check(host.node.position == once and host.ack == 30, "resent commands are never applied twice")
	client.reconcile(host.snapshot(), stage, 0)
	check(client.pending.is_empty() and client.node.position.distance_to(host.node.position) < 0.00001, "all input converges to host result")
	var stale = host.snapshot()
	stale.ack = 1
	stale.pos = [999, 0, 0]
	client.reconcile(stale, stage, 0)
	check(client.node.position == host.node.position, "old acknowledgement cannot rewind client")
	host.accept([{"seq": 32, "ticks": 5, "throttle": 1.0, "steer": 0.0, "brake": false}], stage, 0)
	check(host.ack == 30, "a missing command is not skipped")
	for i in range(120):
		client.predict(5, 1.0, 0.0, false, stage, 0)
	check(client.pending.size() == Predictor.LIMIT, "disconnection backlog stays bounded")
	client.reset(stage.at(12), 0)
	host.reset(stage.at(12), 0)
	for i in range(8):
		client.predict(12, 1, 0.1, false, stage, 0)
	check(host.accept(client.pending, stage, 0, 25) == 24 and host.ack == 2, "host enforces tick budget without dropping a command")
	host.accept(client.pending, stage, 0, 72)
	client.reconcile(host.snapshot(), stage, 0)
	check(client.pending.is_empty(), "budget-delayed commands eventually drain")
	# A missing packet and an older reply are independent of simulation order.
	for model in range(10):
		client.reset(stage.at(100), 0)
		host.reset(stage.at(100), 0)
		for i in range(100):
			client.predict(2, 1 if i < 60 else -1, 0.2 if i < 70 else -0.5, i > 85, stage, model)
			if i % 13 == 0:
				host.accept(client.pending, stage, model)
				client.reconcile(host.snapshot(), stage, model)
		host.accept(client.pending, stage, model)
		client.reconcile(host.snapshot(), stage, model)
		check(client.node.position.distance_to(host.node.position) < 0.00001 and client.motion.velocity.distance_to(host.motion.velocity) < 0.00001, "delayed throttle, reverse, steering and braking converge for model %d" % model)
	client.node.position += Vector3(1, 0, 0)
	var rendered = client.node.position
	client.reconcile(host.snapshot(), stage, 9)
	check((client.node.position + client.visual_offset).distance_to(rendered) < 0.00001, "small reconciliation preserves visible position")
	client.node.position += Vector3(20, 0, 0)
	client.reconcile(host.snapshot(), stage, 9)
	check(client.visual_offset == Vector3.ZERO, "large correction snaps without a long visual trail")
	client.reset(stage.at(12) + Vector3(12, 0, 0), 0)
	host.reset(client.node.position, 0)
	client.predict(1, 0, 0, false, stage, 0, true)
	host.accept(client.pending, stage, 0)
	client.reconcile(host.snapshot(), stage, 0)
	check(stage.road_distance(client.node.position) < 0.1 and client.node.position.distance_to(host.node.position) < 0.00001, "recovery is a numbered command and survives resend")
	client.reset(stage.at(12), 0)
	client.motion.velocity = Vector3(0, 0, -12)
	client.context = {"contacts": [{"position": client.node.position + Vector3(0, 0, -1)}]}
	client.predict(1, 0, 0, false, stage, 0)
	check(client.condition < 100 and client.motion.velocity.z > 0, "dynamic car contact blocks and damages predicted car")
	var event_count = client.events.size()
	var state = client.snapshot()
	state.ack = 0
	client.reconcile(state, stage, 0)
	check(client.events.size() == event_count, "replay never repeats collision effects")
	client.reset(stage.at(12), 0)
	check(client.condition == 100 and client.pending.is_empty() and client.events.is_empty(), "new session clears damage and queued effects")
	client.motion.velocity = Vector3(0, 0, -12)
	stage.rocks.append({"pos": client.node.position + Vector3(0, 0, -1.2), "radius": 0.5, "height": 4.0})
	client.predict(1, 1, 0, false, stage, 0)
	check(client.condition < 100 and client.impact_timer > 0, "rock impact applies damage and cooldown")
	stage.rocks.clear()
	client.reset(stage.at(12), 0)
	client.motion.velocity = Vector3(0, 0, -12)
	stage.trees.append(client.node.position + Vector3(0, 0, -1))
	client.predict(1, 1, 0, false, stage, 0)
	check(client.events.any(func(e): return e.kind == "tree") and client.condition < 100, "tree collision emits falling-tree event and damage")
	stage.trees.clear()
	client.reset(stage.at(12), 0)
	client.motion.velocity = Vector3(0, 0, -12)
	client.context = {"contacts": [{"position": client.node.position + Vector3(0, 0, -1), "person": true}]}
	client.predict(1, 1, 0, false, stage, 0)
	check(client.events.any(func(e): return e.kind == "person"), "fast contact with a walking participant reports host fatal collision")
	var village = Stage.new(2)
	root.add_child(village)
	village.build()
	var lamp = village.city.lamps[0].body
	var center = village.city._relative_pose(lamp).origin
	var start = center + Vector3(1.05, 0, 0)
	start.y = village.ground(start)
	client.reset(start, PI / 2)
	client.motion.velocity = Vector3(-20, 0, 0)
	client.predict(2, 1, 0, false, village, 0)
	check(client.events.any(func(e): return e.kind == "city" and e.hit.kind == "lamp") and client.condition < 100, "village lamp contact emits destruction and applies damage")
	var blocked_recovery = client.node.position
	client.context = {"racing": true}
	client.predict(1, 0, 0, true, village, 0, true)
	check(client.recovery_ack == 0 and client.node.position.distance_to(blocked_recovery) < 1, "recovery is rejected during a rally")
	village.free()
	stage.free()
	print("DRIVE PREDICTION RESULT: %d failures" % failures)
	quit(1 if failures else 0)
