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

# Imported wheels are one OBJ mesh. Split its triangles into four wheel pivots,
# preserving metal/rubber materials while allowing independent rotation.
static func _wheel_parts(parent: Node3D, mesh: Mesh, part: String, color: Color) -> void:
	for surface_index in range(mesh.get_surface_count()):
		var source = MeshDataTool.new()
		if source.create_from_surface(mesh, surface_index) != OK:
			continue
		var groups: Dictionary = {}
		for face_index in range(source.get_face_count()):
			var vertices: Array = []
			for point in range(3):
				vertices.append(source.get_vertex(source.get_face_vertex(face_index, point)))
			var midpoint: Vector3 = (vertices[0] + vertices[1] + vertices[2]) / 3.0
			var key = ("%d_%d" % [1 if midpoint.x >= 0 else -1, 1 if midpoint.z >= 0 else -1])
			if not groups.has(key):
				groups[key] = []
			groups[key].append_array(vertices)
		for key in groups:
			var vertices: Array = groups[key]
			var low: Vector3 = vertices[0]
			var high: Vector3 = vertices[0]
			for vertex in vertices:
				low = low.min(vertex)
				high = high.max(vertex)
			var pivot = (low + high) * 0.5
			var builder = SurfaceTool.new()
			builder.begin(Mesh.PRIMITIVE_TRIANGLES)
			for vertex in vertices:
				builder.add_vertex(vertex - pivot)
			builder.generate_normals()
			var wheel = MeshInstance3D.new()
			wheel.name = "Camping_%s_%s" % [part, key]
			wheel.mesh = builder.commit()
			wheel.position = pivot
			wheel.rotation.y = PI
			var mat = StandardMaterial3D.new()
			mat.albedo_color = color
			mat.roughness = 0.65
			mat.metallic = 0.15 if part == "wheels_metal" else 0.0
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			wheel.material_override = mat
			wheel.set_meta("rolling_wheel_radius", maxf((high.y - low.y) * 0.5, 0.1))
			wheel.set_meta("rolling_wheel_axis", Vector3.RIGHT)
			parent.add_child(wheel)

static func build() -> Node3D:
	for part in PARTS:
		if not ResourceLoader.exists(ASSET_ROOT + part + ".obj"):
			return null
	var root = Node3D.new()
	root.name = "PlayerCar_8"
	root.set_meta("model", "Походный хэтчбек")
	root.set_meta("variant", 8)
	root.set_meta("roof_cargo", "inflatable_boat")
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
		if part in ["wheels_metal", "wheels_rubber"]:
			_wheel_parts(details, mesh, part, COLORS[part])
			continue
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
