extends SceneTree
# Close-up sheet of every character pose, seen from the side and from the
# front three-quarters, to catch body parts passing through each other.
#   xvfb-run godot --path game --rendering-driver opengl3 \
#     --script res://tools/screenshots/export_character_poses.gd -- --out=/tmp/poses
# Writes <out>/<pose>_<view>.webp for players in a room, camp spectators,
# marshals, the medic and casualties.
const ScreenshotRig = preload("res://tools/screenshots/screenshot_rig.gd")
const PeerView = preload("res://scripts/net/peer_view.gd")
const Props = preload("res://scripts/core/props.gd")
const MedicModel = preload("res://scripts/people/medic_model.gd")
const CharacterRig = preload("res://scripts/people/character_rig.gd")

var rig
var game
var out = "res://../docs/screenshots/poses"
var last_spot := Vector3.ZERO
var spot = Vector3.ZERO
var slot = 0

func _initialize() -> void:
	call_deferred("run")

func arg(name: String, fallback: String) -> String:
	for value in OS.get_cmdline_user_args():
		if value.begins_with("--" + name + "="):
			return value.trim_prefix("--" + name + "=")
	return fallback

# A free, tree-less patch per pose: one every 7 m along the road.
func next_spot() -> Vector3:
	var point: Vector3 = game.stage.at(160.0 + slot * 7.0)
	slot += 1
	point.y = game.stage.ground(point)
	return point

func shoot(name: String, center: Vector3, yaw: float) -> void:
	var target = center + Vector3(0, 1.0, 0)
	var forward = Vector3(-sin(yaw), 0, -cos(yaw))
	var side = forward.cross(Vector3.UP)
	rig.aim(target + side * 3.6 + Vector3(0, 0.3, 0), target, 42.0)
	await rig.capture("%s/%s_side.webp" % [out, name], Vector2i(420, 420))
	rig.aim(target + (forward + side * 0.8).normalized() * 3.6 + Vector3(0, 0.7, 0), target, 42.0)
	await rig.capture("%s/%s_front.webp" % [out, name], Vector2i(420, 420))

# Head and hands from about a metre: held items in detail.
func closeup(name: String, center: Vector3, yaw: float) -> void:
	var target = center + Vector3(0, 1.4, 0)
	var forward = Vector3(-sin(yaw), 0, -cos(yaw))
	rig.aim(target + (forward + forward.cross(Vector3.UP) * 0.7).normalized() * 1.3 + Vector3(0, 0.15, 0), target, 40.0)
	await rig.capture("%s/%s.webp" % [out, name], Vector2i(420, 420))

func peer_state(pos: Vector3, extra: Dictionary) -> Dictionary:
	var state = {"in_car": false, "pos": [pos.x, pos.y, pos.z], "car": [pos.x + 30, pos.y, pos.z], "push": [0, 0, 0], "running": false, "airborne": false, "seated": false, "beers": 0, "eat": -1, "beer": -1, "food_kind": "meat", "food_species": "edible"}
	state.merge(extra, true)
	return state

func peer_pose(name: String, extra: Dictionary, clock: float = 0.3, carry: String = "") -> void:
	var pos = next_spot()
	var yaw = 0.4
	var id = "pose_%s" % name
	if extra.get("seated", false):
		var chair = Node3D.new()
		game.add_child(chair)
		Props.chair(chair, Vector3.ZERO)
		chair.position = pos
		chair.rotation.y = yaw
		var table = Node3D.new()
		game.add_child(table)
		Props.table(table)
		table.rotation.y = yaw
		table.position = pos + Vector3(-sin(yaw), 0, -cos(yaw)) * 0.95
	last_spot = pos
	var peer = PeerView.create(game, {"id": id, "name": name, "slot": slot % 4, "car_model": 0, "state": null})
	peer.state = peer_state(pos, extra)
	if carry != "":
		game.cargo.held[id] = {"owner": id, "kind": carry, "returning": false}
	for i in range(3):
		peer.avatar_motion.push(clock - 0.3 + i * 0.1, pos, Vector3(0, yaw, 0))
		peer.car_motion.push(clock - 0.3 + i * 0.1, pos + Vector3(30, 0, 0), Vector3.ZERO)
	# Eating and drinking advance from the reported start time.
	for i in range(int(extra.get("frames", 1))):
		PeerView.animate(game, peer, 1.0 / 30.0, clock, false, false)
	peer.label.hide()
	await shoot("peer_" + name, pos, yaw)

func spectator_pose(name: String, action: String, time: float) -> void:
	var person: Dictionary = game.spectators.people[0]
	var avatar: Node3D = person.avatar
	var pos = next_spot()
	avatar.position = pos
	avatar.rotation.y = 0.4
	person.can.visible = action == "beer"
	person.food.visible = action == "eat"
	var lift = 0.0
	if action == "eat":
		lift = Props.food_lift(time)
		person.food.rotation.x = -lift
		Props.pose_skewer(person.food, time)
	elif action == "beer":
		lift = smoothstep(0.8, 1.25, time) * (1.0 - smoothstep(2.5, 3.3, time))
		person.can.rotation.x = 0.35 * lift
	CharacterRig.pose(avatar, {"gait": 1 if action == "walk" else 0, "time": 0.25, "arms": {"eat": "eat", "beer": "drink", "cheer": "cheer", "push": "push"}.get(action, ""), "lift": lift, "wave": 0.3})
	await shoot("spectator_" + name, pos, 0.4)
	avatar.position = person.home

func marshal_pose(name: String, action: String) -> void:
	var person: Dictionary = game.stage.officials.people[0]
	var avatar: Node3D = person.avatar
	var pos = next_spot()
	last_spot = pos
	avatar.position = pos
	avatar.rotation.y = 0.4
	var flag: Node3D = CharacterRig.hand(avatar).get_node("RedFlag")
	flag.visible = action == "flag"
	CharacterRig.pose(avatar, {"arms": {"flag": "flag", "push": "push"}.get(action, ""), "wave": 0.3})
	await shoot("marshal_" + name, pos, 0.4)

func medic_pose(name: String, state: String, moving: bool) -> void:
	var avatar = MedicModel.create()
	game.add_child(avatar)
	var pos = next_spot()
	avatar.position = pos
	avatar.rotation.y = 0.4
	var medic = {"avatar": avatar, "state": state, "clock": 0.35, "moving": moving, "time": 0.3}
	for i in range(30):
		MedicModel.pose(medic, 1.0 / 30.0)
	await shoot("medic_" + name, pos, 0.4)

func casualty_pose(name: String, rot: Vector3) -> void:
	var avatar = Props.player_avatar(2)
	game.add_child(avatar)
	var pos = next_spot()
	avatar.position = pos + Vector3(0, 0.25, 0)
	avatar.rotation = rot
	CharacterRig.pose(avatar, {"arms": "limp"})
	await shoot("casualty_" + name, pos, 0.4)

# Villagers: on a bench of the given seat height, or standing (seat < 0).
func bench_pose(name: String, seat: float, arms: String) -> void:
	var avatar = Props.player_avatar(3)
	game.add_child(avatar)
	var pos = next_spot()
	avatar.position = pos
	avatar.rotation.y = 0.4
	if seat > 0.0:
		var bench = Node3D.new()
		game.add_child(bench)
		bench.position = pos
		bench.rotation.y = 0.4
		Props.box(bench, Vector3(0, seat - 0.025, 0.02), Vector3(1.2, 0.05, 0.42), Color("4f6b55"))
		CharacterRig.pose(avatar, {"seat": seat, "ground": pos.y, "arms": arms, "lift": 0.8})
	else:
		CharacterRig.pose(avatar, {"arms": arms, "lift": 0.8, "wave": 0.3})
	await shoot("village_" + name, pos, 0.4)

func run() -> void:
	out = arg("out", out)
	DirAccess.make_dir_recursive_absolute(out)
	rig = ScreenshotRig.new(self, "POSES")
	game = rig.open_stage(int(arg("stage", "0")))
	await peer_pose("idle", {})
	await peer_pose("walk", {"push": [1, 0, 0]}, 0.1)
	await peer_pose("run", {"push": [1, 0, 0], "running": true}, 0.1)
	await peer_pose("jump", {"airborne": true})
	await peer_pose("seated", {"seated": true})
	await peer_pose("seated_drink", {"seated": true, "beer": 1.6, "frames": 2})
	await peer_pose("eat", {"eat": 1.4, "frames": 2})
	await peer_pose("drink", {"beer": 1.6, "frames": 2})
	await peer_pose("carry_box", {}, 0.3, "table")
	await peer_pose("carry_shovel", {}, 0.3, "shovel")
	await peer_pose("collapsed", {"beers": 30, "frames": 40})
	await peer_pose("radio", {"radio": true, "frames": 10})
	await closeup("peer_radio_closeup", last_spot, 0.4)
	await peer_pose("radio_raising", {"radio": true, "frames": 3})
	await peer_pose("radio_walk", {"radio": true, "push": [1, 0, 0], "frames": 10}, 0.1)
	await spectator_pose("eat", "eat", 1.4)
	await spectator_pose("beer", "beer", 1.6)
	await spectator_pose("cheer", "cheer", 0.0)
	await spectator_pose("push", "push", 0.0)
	await spectator_pose("walk", "walk", 0.0)
	await marshal_pose("watch", "watch")
	await closeup("marshal_radio_closeup", last_spot, 0.4)
	await marshal_pose("flag", "flag")
	await marshal_pose("push", "push")
	await medic_pose("walk", "walking", true)
	await medic_pose("treat", "treating", false)
	await casualty_pose("lying", Vector3(0, 0, PI / 2))
	await bench_pose("bench_sit", 0.485, "lap")
	await bench_pose("cafe_sip", 0.47, "drink")
	await bench_pose("pick", -1.0, "pick")
	await bench_pose("throw", -1.0, "throw")
	await bench_pose("wave", -1.0, "wave")
	rig.close()
