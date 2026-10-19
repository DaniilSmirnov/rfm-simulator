extends RefCounted
const Props = preload("res://scripts/core/props.gd")
const CharacterRig = preload("res://scripts/people/character_rig.gd")

static func create(outfit: String = "") -> Node3D:
	var avatar = Props.player_avatar(1, outfit)
	avatar.name = "AmbulanceMedic"
	# Keep feet on the ground: the torso bends about the hips, not the ankles.
	var upper = Node3D.new()
	upper.name = "MedicalTorso"
	avatar.add_child(upper)
	upper.owner = avatar
	upper.position.y = 0.83
	for child in avatar.get_children():
		if child != upper and child is Node3D and child.name not in ["LeftLeg", "RightLeg"]:
			var pos: Vector3 = child.position
			child.owner = null
			child.reparent(upper, false)
			child.position = pos - upper.position
	var coat = Node3D.new()
	upper.add_child(coat)
	coat.position.y = -0.83
	Props.box(coat, Vector3(0, 1.1, 0), Vector3(0.67, 0.58, 0.53), Color("e4efee"))
	for z in [-0.274, 0.274]:
		Props.box(coat, Vector3(0, 1.19, z), Vector3(0.19, 0.055, 0.012), Color("d93742"))
		Props.box(coat, Vector3(0, 1.19, z), Vector3(0.055, 0.19, 0.014), Color("d93742"))
	for side in ["LeftArm", "RightArm"]:
		Props.box(upper.get_node(side), Vector3(0, -0.10, 0), Vector3(0.22, 0.26, 0.23), Color("e4efee"))
	return avatar

# Treating: down on one knee beside the patient, hands at the wound.
static func pose(medic: Dictionary, _delta: float) -> void:
	var avatar: Node3D = medic.avatar
	var treating = medic.state == "treating"
	var stepping = medic.state in ["exiting", "entering"]
	var pose = {"gait": 1 if medic.moving or stepping else 0, "time": float(medic.clock), "arms": "treat" if treating else "", "wave": float(medic.clock), "kneel": treating}
	if treating:
		pose.ground = avatar.position.y if not avatar.has_meta("ground") else float(avatar.get_meta("ground"))
		avatar.set_meta("ground", pose.ground)
	elif avatar.has_meta("ground"):
		avatar.position.y = float(avatar.get_meta("ground"))
		avatar.remove_meta("ground")
	CharacterRig.pose(avatar, pose)
