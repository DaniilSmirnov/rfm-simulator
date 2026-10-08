extends SceneTree
const Protocol = preload("res://scripts/world_protocol.gd")
const Session = preload("res://scripts/session_state.gd")
const Actor = preload("res://scripts/actor_context.gd")
const Prediction = preload("res://scripts/drive_prediction.gd")
var failures = 0

class FlatStage:
	extends RefCounted
	const LENGTH = 1000
	var urban = false
	var fallen = {}
	func at(s): return Vector3(0, 0, -s)
	func road_s(p): return -p.z
	func direction(_s): return Vector3.FORWARD
	func road_distance(p): return absf(p.x)
	func grip(_p): return 0.8
	func ground(_p): return 0.0
	func rock_hit(_a, _b, _radius): return {}
	func obstacle_hit(_a, _b, _radius, _escape): return -1

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var session = Session.new()
	check(not session.simulating(), "menu cannot simulate")
	session.loading = true
	check(not session.playing, "loading cannot play")
	session.loading = false
	session.playing = true
	session.set_pause("local", true)
	session.set_pause("host", true)
	session.set_pause("local", false)
	check(not session.can_act(), "closing local pause cannot resume a paused host")
	session.set_pause("host", false)
	check(session.can_act(), "resuming all pause causes restores play")
	session.dead = true
	check(not session.can_act() and session.playing, "terminal state retains result view but cannot act")
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/world_v1.json"))
	check(Protocol.validate(world, false) == "", "shared protocol fixture accepted in Godot")
	for field in ["elapsed", "paused", "world_protocol"]:
		var broken = world.duplicate(true)
		broken.erase(field)
		check(Protocol.validate(broken, false) != "", "missing required world field rejected")
	var bad = world.duplicate(true)
	bad.driving = []
	check(Protocol.validate(bad) != "", "nested collection type rejected")
	bad = world.duplicate(true)
	bad.elapsed = NAN
	check(Protocol.validate(bad) != "", "nonfinite world number rejected")
	bad = world.duplicate(true)
	bad.world_protocol = 2
	check(Protocol.validate(bad) != "", "unsupported protocol rejected")
	var command = {"player": "guest", "state": {"pos": [1,2,3], "car": [4,5,6], "in_car": false, "yaw": 0.5, "beers": 2}}
	var actor = Actor.from_command(command, 3)
	command.state.pos[0] = 90
	check(actor.position == Vector3(1,2,3) and actor.owner == "guest" and actor.variant == 3, "actor copies identity and position without retaining mutable command arrays")
	var stage = FlatStage.new()
	var single = Prediction.new()
	var batched = Prediction.new()
	single.reset(Vector3(0,0,-12), 0)
	batched.reset(Vector3(0,0,-12), 0)
	for tick in range(120):
		single.step({"ticks":1,"throttle":1,"steer":0.2,"brake":false}, stage, 0)
	for batch in range(10):
		batched.step({"ticks":12,"throttle":1,"steer":0.2,"brake":false}, stage, 0)
	check(single.node.transform.is_equal_approx(batched.node.transform) and single.motion.velocity.is_equal_approx(batched.motion.velocity), "fixed driving simulation is independent of render/input batching")
	print("ARCHITECTURE failures=", failures)
	quit(1 if failures else 0)
