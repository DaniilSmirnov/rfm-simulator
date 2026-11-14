extends RefCounted
# Lamps that light up at night. Models mark their headlamp and tail-lamp
# meshes (mark()); Props.bake_car() copies the marked meshes, a hair proud of
# the body, into one hidden unshaded mesh per car ("LampGlow", shared by
# identical cars). At night sky_weather.gd shows it on every car in GROUP, so
# a lit car costs one extra draw call and no light; only the nearest cars also
# get a headlight beam (SkyWeather.headlights()).
const MeshMerge = preload("res://scripts/core/mesh_merge.gd")
const GROUP = &"car_lamps"
const NODE = "LampGlow"
const COLORS = {"head": Color("fff4d8"), "tail": Color("ff2f22")}
const PROUD = 0.006 # towards the viewer, so the copy never shares a depth with the lens
static var _material: StandardMaterial3D

static func mark(node: Node3D, kind: String) -> Node3D:
	node.set_meta("lamp", kind)
	return node

# Call before the car's own bake: the glow node stays hidden, so the body bake
# leaves it alone.
static func build(car: Node3D, cache_key: String) -> void:
	var glow = Node3D.new()
	glow.name = NODE
	_copy(car, car, Transform3D.IDENTITY, glow)
	if glow.get_child_count() == 0:
		glow.free()
		return
	car.add_child(glow)
	var mesh = MeshMerge.bake(glow, cache_key + ":glow", [], "LampGlowMesh")
	mesh.material_override = material()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.hide()
	car.add_to_group(GROUP)

static func _copy(node: Node, car: Node3D, xform: Transform3D, glow: Node3D) -> void:
	for child in node.get_children():
		if not child is Node3D or not child.visible:
			continue
		var local: Transform3D = xform * child.transform
		if child is MeshInstance3D and child.mesh != null and child.has_meta("lamp"):
			var kind = str(child.get_meta("lamp"))
			var copy = MeshInstance3D.new()
			copy.mesh = child.mesh
			copy.transform = local
			# Panels built in car space sit at the origin: judge by the mesh itself.
			copy.position.z += -PROUD if (local * child.mesh.get_aabb()).get_center().z < 0.0 else PROUD
			var paint = StandardMaterial3D.new()
			paint.albedo_color = COLORS.get(kind, COLORS.head)
			copy.material_override = paint
			glow.add_child(copy)
		_copy(child, car, local, glow)

static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.vertex_color_use_as_albedo = true
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _material

static func set_lit(car: Node3D, lit: bool) -> void:
	var glow = car.get_node_or_null(NODE)
	if glow != null:
		glow.visible = lit
