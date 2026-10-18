extends "res://tests/harness.gd"
# CharacterRig: every pose keeps hands and forearms out of the torso and the
# head, feet on the ground, a seated pelvis on the seat, and hands where the
# action needs them (mouth, box, flag up high).
const Props = preload("res://scripts/core/props.gd")
const CharacterRig = preload("res://scripts/people/character_rig.gd")
const MedicModel = preload("res://scripts/people/medic_model.gd")
const RadioModel = preload("res://scripts/people/radio_model.gd")

func _initialize() -> void:
	call_deferred("run")

# Inside the torso capsule (0.64 x 0.70 x 0.40 at y 1.03) or the head (0.60 x
# 0.84 x 0.52 at y 1.62), with a small margin for the shoulder joint itself.
func inside_body(point: Vector3) -> String:
	var torso = Vector3(point.x / 0.30, (point.y - 1.03) / 0.33, point.z / 0.19)
	if torso.length() < 0.92 and point.y < 1.24:
		return "torso"
	var head = Vector3(point.x / 0.28, (point.y - 1.62) / 0.40, point.z / 0.24)
	if head.length() < 0.95:
		return "head"
	return ""

# Points along both forearms and hands, in the avatar's space.
func limb_points(avatar: Node3D) -> Array:
	var result: Array = []
	var j = CharacterRig.joints(avatar)
	for i in range(2):
		var shoulder: Node3D = j.arms[i]
		var forearm: Node3D = j.forearms[i]
		var to_avatar: Transform3D = avatar.global_transform.affine_inverse() * forearm.global_transform
		for k in range(1, 7):
			result.append(to_avatar * Vector3(0, -0.36 * k / 6.0, -0.015))
	return result

func lowest_sole(avatar: Node3D) -> float:
	var j = CharacterRig.joints(avatar)
	var lowest = INF
	for shin in j.shins:
		var to_world: Transform3D = shin.global_transform
		for corner in [Vector3(0, -0.31, 0.10), Vector3(0, -0.31, -0.22)]:
			lowest = minf(lowest, (to_world * corner).y)
	return lowest

func check_clear(avatar: Node3D, name: String) -> void:
	var hit = ""
	for point in limb_points(avatar):
		hit = inside_body(point)
		if hit != "":
			break
	check(hit == "", "%s: hands and forearms stay out of the body (%s)" % [name, hit])

func run() -> void:
	var avatar = Props.player_avatar(0)
	root.add_child(avatar)
	var poses = {
		"stand": {}, "walk": {"gait": 1}, "run": {"gait": 2}, "jump": {"airborne": true},
		"eat": {"arms": "eat", "lift": 1.0}, "drink": {"arms": "drink", "lift": 1.0},
		"carry": {"arms": "carry"}, "shovel": {"arms": "shovel"}, "push": {"arms": "push"},
		"cheer": {"arms": "cheer"}, "flag": {"arms": "flag"}, "wave": {"arms": "wave"},
		"clipboard": {"arms": "clipboard"}, "throw": {"arms": "throw", "lift": 1.0},
		"throw_back": {"arms": "throw", "lift": 0.0}, "pick": {"arms": "pick", "lift": 1.0},
		"lap": {"arms": "lap", "seat": Props.CHAIR_SEAT}, "limp": {"arms": "limp"}, "radio": {"arms": "radio", "lift": 1.0}, "radio_half": {"arms": "radio", "lift": 0.5},
	}
	for name in poses:
		for phase in [0.0, 0.2, 0.4, 0.6]:
			var p: Dictionary = poses[name].duplicate()
			p.time = phase
			p.wave = phase
			CharacterRig.pose(avatar, p)
			check_clear(avatar, "%s @%.1f" % [name, phase])
	# Hands land where the action needs them.
	CharacterRig.pose(avatar, {"arms": "eat", "lift": 1.0})
	check(CharacterRig.grip_position(avatar).distance_to(CharacterRig.MOUTH) < 0.05, "eating brings the hand to the mouth")
	CharacterRig.pose(avatar, {"arms": "radio", "lift": 1.0})
	check(CharacterRig.grip_position(avatar).distance_to(CharacterRig.MOUTH) < 0.12, "the radio is held at the mouth")
	var radio = RadioModel.attach_to_hand(CharacterRig.hand(avatar), CharacterRig.grip())
	radio.show()
	RadioModel.hold_upright(radio, avatar, 1.0)
	var tip: Vector3 = avatar.global_transform.affine_inverse() * radio.get_node("Antenna").global_position
	check(tip.y > CharacterRig.MOUTH.y and tip.distance_to(CharacterRig.MOUTH) < 0.3, "the raised radio stands upright beside the face (antenna at %s)" % tip)
	check(inside_body(avatar.global_transform.affine_inverse() * radio.get_node("Body").global_position) == "", "the radio body stays outside the head and torso")
	var up: Vector3 = avatar.global_basis.inverse() * radio.global_basis.y.normalized()
	check(up.y > 0.95, "the raised radio stands upright (up %s)" % up)
	var grip_point: Vector3 = avatar.global_transform.affine_inverse() * (CharacterRig.hand(avatar).global_transform * radio.get_meta("grip"))
	var body_point: Vector3 = avatar.global_transform.affine_inverse() * radio.get_node("Body").global_position
	check(grip_point.distance_to(body_point) < 0.06, "the hand holds the radio around its middle")
	CharacterRig.pose(avatar, {"arms": "radio", "lift": 0.0})
	check(CharacterRig.grip_position(avatar).y < 0.95, "without lift the radio hand hangs at rest")
	radio.free()
	CharacterRig.pose(avatar, {"arms": "flag"})
	check(CharacterRig.grip_position(avatar).y > 1.72, "the flag hand is raised to the top of the head")
	CharacterRig.pose(avatar, {"gait": 1, "time": 0.2})
	var left = CharacterRig.grip_position(avatar, "Left")
	var right = CharacterRig.grip_position(avatar, "Right")
	check(absf(left.z - right.z) > 0.15 and signf(left.z - right.z) == signf(avatar.get_node("LeftLeg").rotation.x), "walking swings each arm against its leg")
	# Standing and walking: feet on the ground.
	for name in ["stand", "walk", "run"]:
		CharacterRig.pose(avatar, poses[name])
		# The rear toe dips a few centimetres while rolling off: there is no ankle.
		check(lowest_sole(avatar) > -0.09 and lowest_sole(avatar) < 0.06, "%s: soles at ground level (%.3f)" % [name, lowest_sole(avatar)])
	# Seated on the camp chair: pelvis on the seat, feet down, knees bent.
	avatar.position = Vector3.ZERO
	CharacterRig.pose(avatar, {"seat": Props.CHAIR_SEAT, "ground": 0.0})
	var pelvis_bottom = avatar.position.y + CharacterRig.PELVIS_BOTTOM
	check(absf(pelvis_bottom - Props.CHAIR_SEAT) < 0.01, "seated pelvis rests on the chair seat")
	check(lowest_sole(avatar) > -0.03 and lowest_sole(avatar) < 0.08, "seated feet reach the ground (%.3f)" % lowest_sole(avatar))
	check(avatar.get_node("LeftLeg/LeftShin").rotation.x < -1.0, "seated knees are bent")
	# Each call sets every joint: nothing remains from the previous action.
	CharacterRig.pose(avatar, {"arms": "cheer"})
	CharacterRig.pose(avatar)
	check(CharacterRig.grip_position(avatar).y < 0.9, "a plain pose drops raised arms")
	avatar.free()
	# The medic crouches beside the patient, feet flat on the ground.
	var medic = MedicModel.create()
	root.add_child(medic)
	MedicModel.pose({"avatar": medic, "state": "treating", "clock": 0.0, "moving": false, "time": 0.0}, 0.1)
	check(lowest_sole(medic) > -0.06 and lowest_sole(medic) < 0.12, "crouching medic keeps the feet on the ground (%.3f)" % lowest_sole(medic))
	var hip: Vector3 = medic.get_node("RightLeg").global_position
	check(hip.y < 0.45 and medic.get_node("RightLeg/RightShin").rotation.x < -1.0, "the medic crouches low with bent knees (hip %.2f m)" % hip.y)
	MedicModel.pose({"avatar": medic, "state": "walking", "clock": 0.3, "moving": true, "time": 0.0}, 0.1)
	check(absf(medic.position.y) < 0.001, "the medic stands up again at ground level")
	medic.free()
	print("CHARACTER RIG RESULT: %d checks, %d failures" % [checks, failures])
	finish()
