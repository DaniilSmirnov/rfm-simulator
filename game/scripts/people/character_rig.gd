extends RefCounted
# One pose for every person in the game: players seen by others, camp
# spectators, marshals and judges, the medic, villagers and casualties.
# Callers describe what the person is doing; the rig sets every joint each
# call, so nothing is left over from a previous action.
#   CharacterRig.pose(avatar, {"gait": 1, "time": clock, "arms": "drink", "lift": 0.7})
#
# Joints (from character_source.gd): Head, LeftArm/RightArm (shoulder) with
# LeftForearm/RightForearm (elbow), LeftLeg/RightLeg (hip) with
# LeftShin/RightShin (knee). The medic's arms and head sit on MedicalTorso.
# Hands are placed by two-bone IK at points chosen outside the body, so arms
# never pass through the torso or the head; elbows bend away from the body.
#
# Pose keys (all optional):
#   gait      0 stand, 1 walk, 2 run          time, seed  gait clock (s), per-person offset
#   airborne  jumping                          seat        seat height (m above the feet)
#   kneel     crouch low (medic)              ground      feet height; with seat/kneel
#                                                          the rig lowers the body onto it
#   arms      "", "eat", "drink", "carry", "shovel", "push", "cheer", "flag", "wave",
#             "clipboard", "treat", "throw", "pick", "lap", "limp", "relief"
#   lift      0..1 progress of eat/drink/throw/pick    look  head yaw (rad)
const KNEE = 0.33
const SHIN = 0.31
const UPPER_ARM = 0.22
const FOREARM = 0.28
const HIP_HEIGHT = 0.65
const PELVIS_BOTTOM = 0.55
const SHOULDER = Vector3(0.34, 1.29, 0.0)
# Thigh angle of the medic crouching beside a patient.
const CROUCH = 1.3
# Grip points and gestures in the shoulders' parent space (right hand; the
# left mirrors x). The mouth is just in front of the face.
const REST_HAND = Vector3(0.40, 0.81, -0.05)
const MOUTH = Vector3(0.07, 1.42, -0.42)
const CARRY_HAND = Vector3(0.30, 0.95, -0.40)
const PUSH_HAND = Vector3(0.25, 1.12, -0.62)
const CHEER_HAND = Vector3(0.50, 1.74, -0.16)
const FLAG_HAND = Vector3(0.40, 1.78, -0.08)
const CLIPBOARD_HAND = Vector3(0.12, 1.02, -0.40)
const TREAT_HAND = Vector3(0.20, 0.55, -0.50)
const LAP_HAND = Vector3(0.24, 0.84, -0.36)
const RELIEF_HAND = Vector3(0.10, 0.80, -0.27)
# Elbow directions: out, down and back from the shoulder-hand line.
const POLE_HANG = Vector3(0.45, 0.0, 1.0)
const POLE_LIFT = Vector3(0.75, -1.0, 0.2)
const POLE_OUT = Vector3(1.0, -0.3, 0.6)

static func joints(avatar: Node3D) -> Dictionary:
	if avatar.has_meta("rig_joints"):
		return avatar.get_meta("rig_joints")
	var torso = avatar.get_node_or_null("MedicalTorso")
	var body: Node3D = torso if torso != null else avatar
	var result = {"torso": torso, "head": body.get_node("Head"), "arms": [], "forearms": [], "legs": [], "shins": []}
	for side in ["Left", "Right"]:
		result.arms.append(body.get_node(side + "Arm"))
		result.forearms.append(body.get_node(side + "Arm/" + side + "Forearm"))
		result.legs.append(avatar.get_node(side + "Leg"))
		result.shins.append(avatar.get_node(side + "Leg/" + side + "Shin"))
	avatar.set_meta("rig_joints", result)
	return result

# The node a held item hangs from: it follows the hand.
static func hand(avatar: Node3D, side: String = "Right") -> Node3D:
	return joints(avatar).forearms[0 if side == "Left" else 1]

# Grip point of a hand in its forearm's space (where items are attached).
static func grip(drop: float = 0.0) -> Vector3:
	return Vector3(0, -FOREARM - drop, -0.03)

static func pose(avatar: Node3D, p: Dictionary = {}) -> void:
	var j = joints(avatar)
	var gait = int(p.get("gait", 0))
	var angle = float(p.get("time", 0.0)) * (13.0 if gait == 2 else 8.0) + float(p.get("seed", 0.0))
	var swing = sin(angle) if gait > 0 else 0.0
	_legs(avatar, j, p, gait, angle)
	_arms(j, p, gait, swing)
	var head: Node3D = j.head
	var lift = float(p.get("lift", 0.0))
	head.rotation = Vector3(0.18 * lift if p.get("arms", "") in ["eat", "drink"] else (-0.35 * lift if p.get("arms", "") == "pick" else 0.0), float(p.get("look", 0.0)), 0.0)
	if j.torso != null:
		j.torso.rotation.x = -0.45 if p.get("kneel", false) else 0.0

# Root lowering for a seat or a kneel, relative to the feet.
static func body_drop(p: Dictionary) -> float:
	if float(p.get("seat", -1.0)) >= 0.0:
		return float(p.seat) - PELVIS_BOTTOM
	if p.get("kneel", false):
		return SHIN + KNEE * cos(CROUCH) - HIP_HEIGHT
	return 0.0

static func _legs(avatar: Node3D, j: Dictionary, p: Dictionary, gait: int, angle: float) -> void:
	var drop = body_drop(p)
	if p.has("ground") and (float(p.get("seat", -1.0)) >= 0.0 or p.get("kneel", false)):
		avatar.position.y = float(p.ground) + drop
	for i in range(2):
		var sign = 1.0 if i == 0 else -1.0
		var hip = 0.0
		var knee = -0.04
		if float(p.get("seat", -1.0)) >= 0.0:
			# Thighs on the seat, shins down to the ground.
			var hip_height = HIP_HEIGHT + drop
			hip = acos(clampf((hip_height - SHIN) / KNEE, -1.0, 1.0))
			hip = clampf(hip, 1.25, 1.75)
			knee = -hip
		elif p.get("kneel", false):
			# Crouched low beside the patient, both feet flat on the ground.
			# (A knee on the ground would push the toes into it: the feet have
			# no ankle joint.)
			hip = CROUCH + (0.05 if i == 0 else -0.05)
			knee = -hip
		elif p.get("airborne", false):
			hip = 0.55 if i == 0 else 0.15
			knee = -0.95 if i == 0 else -0.55
		elif p.get("arms", "") == "limp":
			hip = 0.12 * sign
			knee = -0.25
		elif gait > 0:
			hip = sin(angle) * sign * (0.62 if gait == 2 else 0.4)
			# The knee folds while the leg swings through, straightens to land.
			knee = -(0.05 + (1.05 if gait == 2 else 0.6) * maxf(0.0, cos(angle) * sign))
		j.legs[i].rotation = Vector3(hip, 0, 0)
		j.shins[i].rotation = Vector3(knee, 0, 0)

static func _arms(j: Dictionary, p: Dictionary, gait: int, swing: float) -> void:
	var mode = str(p.get("arms", ""))
	var lift = clampf(float(p.get("lift", 0.0)), 0.0, 1.0)
	var wave = float(p.get("wave", 0.0))
	for i in range(2):
		var side = -1.0 if i == 0 else 1.0
		var right = i == 1
		var rest = REST_HAND
		if gait > 0:
			# Arms swing against the leg on the same side.
			var amount = (0.30 if gait == 2 else 0.20) * swing * (1.0 if right else -1.0)
			rest = REST_HAND + Vector3(0, absf(amount) * 0.5 + (0.12 if gait == 2 else 0.0), -amount)
		elif p.get("airborne", false):
			rest = Vector3(0.52, 1.05, -0.18)
		var target = rest
		var pole = POLE_HANG
		match mode:
			"eat", "drink":
				if right:
					var mouth = MOUTH + (Vector3(0, -0.04, 0) if mode == "drink" else Vector3.ZERO)
					target = rest.lerp(mouth, smoothstep(0.0, 1.0, lift))
					pole = POLE_LIFT
			"lap":
				target = LAP_HAND
				pole = POLE_LIFT
			"carry":
				target = CARRY_HAND
				pole = POLE_OUT
			"shovel":
				target = Vector3(0.24, 1.05, -0.30) if right else Vector3(0.04, 0.82, -0.58)
				pole = POLE_OUT
			"push":
				target = PUSH_HAND
				pole = POLE_OUT
			"cheer":
				target = CHEER_HAND + Vector3(sin(wave * 8.0 + i) * 0.08, 0, 0)
				pole = POLE_OUT
			"flag", "wave":
				if right:
					target = FLAG_HAND + Vector3(sin(wave * 6.0) * 0.22, 0, 0)
					pole = POLE_OUT
			"clipboard":
				if right:
					target = CLIPBOARD_HAND
					pole = POLE_LIFT
			"treat":
				target = TREAT_HAND + Vector3(0, sin(wave * 5.0 + i) * 0.03, 0)
				pole = POLE_OUT
			"throw":
				if right:
					target = Vector3(0.36, 0.78, 0.32).lerp(Vector3(0.34, 1.35, -0.55), lift)
			"pick":
				target = rest.lerp(Vector3(0.26, 0.86, -0.55) if right else Vector3(0.30, 1.0, -0.42), lift if right else 1.0 - lift)
				pole = POLE_LIFT
			"limp":
				target = Vector3(0.52, 0.95, -0.12)
				pole = POLE_OUT
			"relief":
				target = RELIEF_HAND
				pole = POLE_OUT
		# Targets are written for a shoulder at its usual place on an upright
		# body; a shoulder mounted elsewhere (the medic's leaning torso) moves them along.
		var shoulder_shift: Vector3 = j.arms[i].position - Vector3(SHOULDER.x * side, SHOULDER.y, SHOULDER.z)
		reach(j.arms[i], j.forearms[i], Vector3(target.x * side, target.y, target.z) + shoulder_shift, Vector3(pole.x * side, pole.y, pole.z))

# Two-bone IK: turn the shoulder and bend the elbow so the grip lands on
# `target` (shoulder-parent space), the elbow bending towards `pole`.
static func reach(shoulder: Node3D, forearm: Node3D, target: Vector3, pole: Vector3) -> void:
	var origin: Vector3 = shoulder.position
	var offset = target - origin
	var distance = clampf(offset.length(), 0.1, UPPER_ARM + FOREARM - 0.002)
	var direction = offset.normalized() if offset.length() > 0.001 else Vector3.DOWN
	var bend = pole.normalized() - direction * pole.normalized().dot(direction)
	if bend.length() < 0.01:
		bend = Vector3.BACK - direction * direction.z
	bend = bend.normalized()
	var shoulder_angle = acos(clampf((UPPER_ARM * UPPER_ARM + distance * distance - FOREARM * FOREARM) / (2.0 * UPPER_ARM * distance), -1.0, 1.0))
	var upper = direction * cos(shoulder_angle) + bend * sin(shoulder_angle)
	var elbow = origin + upper * UPPER_ARM
	var lower = (origin + direction * distance - elbow).normalized()
	var back = -(lower - upper * lower.dot(upper))
	back = back.normalized() if back.length() > 0.001 else bend
	var y_axis = -upper
	shoulder.basis = Basis(y_axis.cross(back), y_axis, back)
	var elbow_angle = acos(clampf((UPPER_ARM * UPPER_ARM + FOREARM * FOREARM - distance * distance) / (2.0 * UPPER_ARM * FOREARM), -1.0, 1.0))
	forearm.rotation = Vector3(PI - elbow_angle, 0, 0)

# Where a grip actually is, in the shoulders' parent space (for tests).
static func grip_position(avatar: Node3D, side: String = "Right") -> Vector3:
	var j = joints(avatar)
	var i = 0 if side == "Left" else 1
	var shoulder: Node3D = j.arms[i]
	var forearm: Node3D = j.forearms[i]
	return shoulder.transform * (forearm.transform * grip())
