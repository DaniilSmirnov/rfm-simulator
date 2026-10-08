extends RefCounted

# OBJ parts are kept separate for easy replacement in Godot's importer.
# Missing files return null so checkout builds remain playable until assets arrive.
const ASSET_ROOT = "res://models/cars/camping_hatchback/"
const PARTS = ["body", "glass", "trim", "lights", "wheels_metal", "wheels_rubber", "boat", "rack"]
const COLORS = {
	"body": Color("283f87"),
	"glass": Color("253d49"),
	"trim": Color("202b31"),
	"lights": Color("a6464a"),
	"wheels_metal": Color("899299"),
	"wheels_rubber": Color("181c20"),
	"boat": Color("59636d"),
	"rack": Color("3c3224"),
}

static func build() -> Node3D:
	for part in PARTS:
		if not ResourceLoader.exists(ASSET_ROOT + part + ".obj"):
			return null
	var root = Node3D.new()
	root.name = "PlayerCar_8"
	root.set_meta("model", "Походный хэтчбек")
	root.set_meta("variant", 8)
	root.set_meta("roof_cargo", "inflatable_boat")
	# The OBJ hatch starts behind the rear passenger seats, unlike the generic hatch template.
	root.set_meta("trunk_lid_start_z", 1.20)
	var details = Node3D.new()
	details.name = "CarModelDetails"
	root.add_child(details)
	var roof = Node3D.new()
	roof.name = "RoofHatchback"
	root.add_child(roof)
	for part in PARTS:
		var mesh: Mesh = load(ASSET_ROOT + part + ".obj")
		if mesh == null:
			root.free()
			return null
		var surface = MeshInstance3D.new()
		surface.name = "BodyShellHatchback" if part == "body" else "Camping_" + part
		surface.mesh = mesh
		# Source OBJ faces +Z, while gameplay expects vehicle forward along -Z.
		# Apply to each part before add_player_trunk() clips the rear hatch.
		surface.rotation.y = PI
		var mat = StandardMaterial3D.new()
		mat.albedo_color = COLORS[part]
		mat.metallic = 0.15 if part == "wheels_metal" else 0.0
		mat.roughness = 0.65
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		surface.material_override = mat
		# Rear glass, trim and lamps must be split together with the hatch panel.
		# add_player_trunk() only clips direct MeshInstance3D children.
		# Wheels and roof cargo stay static under CarModelDetails.
		if part in ["body", "glass", "trim", "lights"]:
			root.add_child(surface)
		else:
			details.add_child(surface)
	return root
