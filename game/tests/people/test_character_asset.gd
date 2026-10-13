extends "res://tests/harness.gd"
const Props = preload("res://scripts/core/props.gd")
const CharacterRig = preload("res://scripts/people/character_rig.gd")
func triangles(node: Node) -> int:
	var count = node.mesh.get_faces().size() / 3 if node is MeshInstance3D else 0
	for child in node.get_children():
		count += triangles(child)
	return count
func smooth_normals(mesh: Mesh) -> bool:
	for surface in range(mesh.get_surface_count()):
		var arrays = mesh.surface_get_arrays(surface)
		var normals = arrays[Mesh.ARRAY_NORMAL]
		var indices = arrays[Mesh.ARRAY_INDEX]
		var count = indices.size() if indices != null else normals.size()
		for i in range(0, count, 3):
			var a = indices[i] if indices != null else i
			var b = indices[i + 1] if indices != null else i + 1
			if normals[a].distance_to(normals[b]) > 0.05:
				return true
	return false

func _initialize() -> void:
	for i in range(4):
		var avatar = Props.player_avatar(i)
		check(avatar.has_node("Head") and avatar.has_node("LeftArm") and avatar.has_node("LeftLeg") and avatar.has_node("RightLeg"), "Animation pivots retained")
		check(avatar.has_node("RightArm/RightForearm/BeerCan") and avatar.has_node("RightArm/RightForearm/Skewer") and avatar.has_node("LeftLeg/LeftShin") and avatar.has_node("LeftArm/LeftForearm"), "Knee and elbow pivots; held food follows the hand")
		check(not avatar.get_node("RightArm/RightForearm/BeerCan").visible and not avatar.get_node("RightArm/RightForearm/Skewer").visible, "Held props start hidden")
		var count = triangles(avatar) - triangles(avatar.get_node("RightArm/RightForearm/BeerCan")) - triangles(avatar.get_node("RightArm/RightForearm/Skewer"))
		print("CHARACTER %d: %d body triangles" % [i, count])
		check(count > 0, "Imported character has body geometry")
		var head_mesh = avatar.get_node("Head").get_child(0).mesh
		check(smooth_normals(head_mesh), "GLB retains smooth shading on the head")
		# Body parts are flattened to one surface whose vertex colours keep the palette.
		var has_skin = false
		check(head_mesh.get_surface_count() == 1, "head is one draw call")
		for colour in head_mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]:
			# Vertex colours are stored as 8-bit channels.
			var skin = Color(Props.spectator_profile(i).skin)
			has_skin = has_skin or Vector3(colour.r - skin.r, colour.g - skin.g, colour.b - skin.b).length() < 0.01
		check(has_skin, "Original skin palette retained")
		var other = Props.player_avatar(i)
		check(avatar.get_node("Head").get_child(0).mesh == other.get_node("Head").get_child(0).mesh, "Instances share imported mesh resources")
		avatar.get_node("RightArm").rotation.x = 1.2
		check(is_zero_approx(other.get_node("RightArm").rotation.x), "Independent animation transforms")
		other.free()
		avatar.free()
	# Carried boxes are held in front (-Z) with both hands at the box sides.
	for kind in ["table", "chairs", "grill", "cauldron", "shovel"]:
		var carrier = Props.player_avatar(0)
		var box = Props.carried_gear(carrier, kind)
		CharacterRig.pose(carrier, {"arms": Props.carry_arms(kind)})
		var hands = [CharacterRig.grip_position(carrier, "Left"), CharacterRig.grip_position(carrier, "Right")]
		check(box.position.z < -0.3 and hands[0].z < -0.25 and hands[1].z < -0.25, "%s carried in front with both hands forward" % kind)
		if kind != "shovel":
			check(absf(hands[0].x) < 0.34 and absf(hands[1].x) < 0.34 and absf(hands[0].y - box.position.y) < 0.12 and absf(hands[0].z - box.position.z) < 0.08, "%s held between the hands at belly height" % kind)
		CharacterRig.pose(carrier)
		check(CharacterRig.grip_position(carrier, "Left").y < 0.9 and CharacterRig.grip_position(carrier, "Left").z > -0.15, "%s: arms drop when nothing is carried" % kind)
		carrier.free()
	finish()
