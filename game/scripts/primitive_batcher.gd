extends RefCounted
# Collapses authored box/cylinder props into spatially tiled MultiMeshes.
# Builders keep writing readable Props.box()/Props.cylinder() calls inside a
# temporary Node3D; collect() moves every primitive into a 64 m tile batch and
# frees the node, flush() uploads one MultiMesh per (primitive, tile).
const Props = preload("res://scripts/props.gd")
const TILE = 64.0

var prefix: String
var batches: Dictionary = {}
var meshes: Dictionary = {}

func _init(name_prefix: String = "VillageDetail_") -> void:
	prefix = name_prefix

# Register a custom unit mesh; MeshInstance3D children tagged with
# set_meta("batch_key", key) are then batched with their own scale.
func register_mesh(key: String, mesh: Mesh) -> void:
	meshes[key] = mesh

func has_mesh(key: String) -> bool:
	return meshes.has(key)

func collect(parent: Node3D, pose: Transform3D) -> void:
	for child in parent.get_children():
		if child.has_meta("unbatched") or child is CollisionObject3D:
			continue
		if child is MeshInstance3D:
			var key = ""
			var scale = Vector3.ONE
			if child.mesh is BoxMesh:
				key = "box"
				scale = child.mesh.size
				if not meshes.has(key):
					var unit = BoxMesh.new()
					unit.size = Vector3.ONE
					meshes[key] = unit
			elif child.mesh is CylinderMesh:
				var mesh: CylinderMesh = child.mesh
				var ratio = mesh.top_radius / maxf(mesh.bottom_radius, 0.001)
				key = "cylinder_%d_%d" % [mesh.radial_segments, int(ratio * 1000)]
				scale = Vector3(mesh.bottom_radius, mesh.height, mesh.bottom_radius)
				if not meshes.has(key):
					var unit = CylinderMesh.new()
					unit.bottom_radius = 1
					unit.top_radius = ratio
					unit.height = 1
					unit.radial_segments = mesh.radial_segments
					unit.rings = 1
					meshes[key] = unit
			elif child.has_meta("batch_key"):
				key = child.get_meta("batch_key")
			if key != "":
				var transform = pose * child.transform
				transform.basis = transform.basis * Basis.from_scale(scale)
				# Thin paving and trim never cast useful shadows; skip the shadow pass.
				add(key, transform, child.material_override.albedo_color, not (key == "box" and scale.y <= 0.12))
				child.free()
		elif child is Node3D:
			collect(child, pose * child.transform)

func add(key: String, transform: Transform3D, color: Color, casts_shadow: bool = true) -> void:
	var cell = Vector2i(floori(transform.origin.x / TILE), floori(transform.origin.z / TILE))
	var tile = "%s_%d_%d%s" % [key, cell.x, cell.y, "" if casts_shadow else "_no_shadow"]
	if not batches.has(tile):
		batches[tile] = {"key": key, "poses": [], "colors": [], "center": Vector3((cell.x + 0.5) * TILE, 0, (cell.y + 0.5) * TILE), "casts_shadow": casts_shadow}
	batches[tile].poses.append(transform)
	batches[tile].colors.append(color)

func flush(stage: Node3D) -> void:
	var material = Props.material(Color.WHITE)
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var titles = batches.keys()
	titles.sort()
	for title in titles:
		var data: Dictionary = batches[title]
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = meshes[data.key]
		mm.instance_count = data.poses.size()
		for i in range(data.poses.size()):
			var pose: Transform3D = data.poses[i]
			pose.origin -= data.center
			mm.set_instance_transform(i, pose)
			mm.set_instance_color(i, data.colors[i])
		var node = MultiMeshInstance3D.new()
		node.name = prefix + title
		stage.add_child(node)
		node.position = data.center
		node.multimesh = mm
		if stage.capture_bake_buffers:
			stage.BakedVillage.capture_instances(node, data.poses, data.colors, data.center)
		if not data.casts_shadow:
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.material_override = material
	batches.clear()
