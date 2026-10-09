extends SceneTree
const Props = preload("res://scripts/props.gd")
var failed = false
func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
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
		for i in range(0, indices.size(), 3):
			if normals[indices[i]].distance_to(normals[indices[i + 1]]) > 0.05:
				return true
	return false

func _initialize() -> void:
	for i in range(4):
		var avatar = Props.player_avatar(i)
		check(avatar.has_node("Head") and avatar.has_node("LeftArm") and avatar.has_node("LeftLeg") and avatar.has_node("RightLeg"), "Animation pivots retained")
		check(avatar.has_node("RightArm/BeerCan") and avatar.has_node("RightArm/Skewer"), "Multiplayer food attachment paths retained")
		check(not avatar.get_node("RightArm/BeerCan").visible and not avatar.get_node("RightArm/Skewer").visible, "Held props start hidden")
		var count = triangles(avatar) - triangles(avatar.get_node("RightArm/BeerCan")) - triangles(avatar.get_node("RightArm/Skewer"))
		print("CHARACTER %d: %d body triangles" % [i, count])
		check(count > 0, "Imported character has body geometry")
		var head_mesh = avatar.get_node("Head").get_child(0).mesh
		check(smooth_normals(head_mesh), "GLB retains smooth shading on the head")
		var has_skin = false
		for surface in range(head_mesh.get_surface_count()):
			has_skin = has_skin or head_mesh.surface_get_material(surface).albedo_color.is_equal_approx(Color(Props.spectator_profile(i).skin))
		check(has_skin, "Original skin palette retained")
		var other = Props.player_avatar(i)
		check(avatar.get_node("Head").get_child(0).mesh == other.get_node("Head").get_child(0).mesh, "Instances share imported mesh resources")
		avatar.get_node("RightArm").rotation.x = 1.2
		check(is_zero_approx(other.get_node("RightArm").rotation.x), "Independent animation transforms")
		other.free()
		avatar.free()
	# Carried boxes are held in front (-Z) with both hands reaching forward to them.
	for kind in ["table", "chairs", "grill", "cauldron", "shovel"]:
		var carrier = Props.player_avatar(0)
		var box = Props.carried_gear(carrier, kind)
		Props.pose_carry(carrier, kind, true)
		var hands: Array = []
		for side in ["LeftArm", "RightArm"]:
			var arm: Node3D = carrier.get_node(side)
			hands.append(arm.transform * Vector3(0, -0.6, 0))
		check(box.position.z < -0.3 and hands[0].z < -0.3 and hands[1].z < -0.3, "%s carried in front with both hands forward" % kind)
		if kind != "shovel":
			check(absf(hands[0].x) < 0.34 and absf(hands[1].x) < 0.34 and absf(hands[0].y - box.position.y) < 0.2, "%s held between the hands at belly height" % kind)
		Props.pose_carry(carrier, kind, false)
		check(carrier.get_node("LeftArm").rotation.is_zero_approx(), "%s: left arm drops when nothing is carried" % kind)
		carrier.free()
	quit(1 if failed else 0)
