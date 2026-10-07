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
	stage.free()
	print("DRIVE PREDICTION RESULT: %d failures" % failures)
	quit(1 if failures else 0)
