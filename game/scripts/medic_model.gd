extends RefCounted
const Props = preload("res://scripts/props.gd")

static func create() -> Node3D:
	var avatar = Props.player_avatar(1)
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
		Props.box(upper.get_node(side), Vector3(0, -0.17, 0), Vector3(0.22, 0.36, 0.23), Color("e4efee"))
	return avatar

static func pose(medic: Dictionary, delta: float) -> void:
	var avatar: Node3D = medic.avatar
	var upper: Node3D = avatar.get_node("MedicalTorso")
	var treating = medic.state == "treating"
	upper.rotation.x = move_toward(upper.rotation.x, -1.05 if treating else 0.0, delta * 5.0)
	var stride = sin(float(medic.clock) * 8.0) * 0.45 if medic.moving else 0.0
	for side in ["Left", "Right"]:
		var sign = 1.0 if side == "Left" else -1.0
		avatar.get_node(side + "Leg").rotation.x = stride * sign
		upper.get_node(side + "Arm").rotation.x = 1.35 + sin(float(medic.clock) * 5.0) * 0.06 if treating else -stride * sign
	# A short visible step out/in at the door, while the feet remain grounded.
	if medic.state in ["exiting", "entering"]:
		var step = sin(clampf(float(medic.time) / 0.65, 0.0, 1.0) * PI) * 0.45
		avatar.get_node("LeftLeg").rotation.x = step
		avatar.get_node("RightLeg").rotation.x = -step
