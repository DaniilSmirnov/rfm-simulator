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
func _initialize() -> void:
	for i in range(4):
		var avatar = Props.player_avatar(i)
		check(avatar.has_node("Head") and avatar.has_node("LeftArm") and avatar.has_node("LeftLeg") and avatar.has_node("RightLeg"), "Animation pivots retained")
		check(avatar.has_node("RightArm/BeerCan") and avatar.has_node("RightArm/Skewer"), "Multiplayer food attachment paths retained")
		check(not avatar.get_node("RightArm/BeerCan").visible and not avatar.get_node("RightArm/Skewer").visible, "Held props start hidden")
		var count = triangles(avatar) - triangles(avatar.get_node("RightArm/BeerCan")) - triangles(avatar.get_node("RightArm/Skewer"))
		print("CHARACTER %d: %d body triangles" % [i, count])
		check(count <= 1500, "Low polygon budget")
		var other = Props.player_avatar(i)
		check(avatar.get_node("Head").get_child(0).mesh == other.get_node("Head").get_child(0).mesh, "Instances share imported mesh resources")
		avatar.get_node("RightArm").rotation.x = 1.2
		check(is_zero_approx(other.get_node("RightArm").rotation.x), "Independent animation transforms")
		other.free()
		avatar.free()
	quit(1 if failed else 0)
