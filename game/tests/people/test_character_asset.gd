extends "res://tests/harness.gd"
const Props = preload("res://scripts/core/props.gd")
const CharacterRig = preload("res://scripts/people/character_rig.gd")
const StageRegistry = preload("res://scripts/stages/stage_registry.gd")
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

func has_colour(mesh: Mesh, hex: String) -> bool:
	var wanted = Color(hex)
	var colours = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	if colours == null:
		# A single-colour part keeps its imported material.
		colours = [mesh.surface_get_material(0).albedo_color]
	for colour in colours:
		# Vertex colours are stored as 8-bit channels.
		if Vector3(colour.r - wanted.r, colour.g - wanted.g, colour.b - wanted.b).length() < 0.01:
			return true
	return false

# The baked body part that turns with a pivot (its own mesh, not its children's).
func body(pivot: Node) -> Mesh:
	return pivot.find_children("*", "MeshInstance3D", false, false)[0].mesh

# Snowy stages dress everyone for winter; the same look keeps its face and name.
func check_outfits() -> void:
	for index in range(StageRegistry.count()):
		var biome = StageRegistry.make_biome(index)
		check(biome.outfit() == ("winter" if biome.has_snow() else ""), "%s: outfit follows the snow" % StageRegistry.entry(index).id)
	for i in range(Props.SPECTATOR_MODELS.size()):
		var summer = Props.player_avatar(i)
		var winter = Props.player_avatar(i, "winter")
		var look = Props.spectator_profile(i, "winter")
		check(winter.get_meta("outfit") == "winter" and summer.get_meta("outfit") == "" and winter.get_meta("model") == summer.get_meta("model"), "Winter look %d keeps its name" % i)
		check(winter.has_node("RightArm/RightForearm/BeerCan") and winter.has_node("LeftLeg/LeftShin") and winter.has_node("Head"), "Winter look %d keeps the rig pivots" % i)
		var head: Mesh = body(winter.get_node("Head"))
		check(head != body(summer.get_node("Head")) and has_colour(head, look.skin) and has_colour(head, look.hat_color), "Winter look %d: same face under a warm hat" % i)
		check(has_colour(body(winter.get_node("RightArm/RightForearm")), look.gloves), "Winter look %d wears mittens" % i)
		check(not has_colour(body(winter.get_node("LeftLeg")), look.skin), "Winter look %d: no bare legs" % i)
		summer.free()
		winter.free()
	var hand = Props.beer_hand(0, "winter")
	check(hand.get_child(1).material_override.albedo_color.is_equal_approx(Color(Props.spectator_profile(0, "winter").gloves)), "First-person hand wears the mitten")
	hand.free()
	var marshal = Props.course_official("marshal", 0, "winter")
	check(marshal.get_meta("outfit") == "winter" and marshal.has_node("SafetyVest"), "Marshal wears the vest over the winter jacket")
	marshal.free()

func _initialize() -> void:
	check_outfits()
	for i in range(Props.SPECTATOR_MODELS.size()):
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
