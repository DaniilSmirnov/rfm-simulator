extends RefCounted
# See-through window glass for cars and houses. One shared material: a light
# blue-green tint that keeps most of what is behind it visible and catches a
# sun highlight. Glass casts no shadow, so daylight and night lights reach the
# interior behind it; the mesh stays out of MeshMerge bakes (transparent).
const TINT = Color(0.46, 0.58, 0.64, 0.16)
static var _material: StandardMaterial3D

static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.albedo_color = TINT
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.roughness = 0.06
		_material.metallic_specular = 0.9
		# Shells are not consistently wound: draw both sides. Every layer has
		# the same colour, so the blend order does not matter.
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _material

# Turns a mesh into glass and returns it.
static func glaze(node: MeshInstance3D) -> MeshInstance3D:
	node.material_override = material()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

static func is_glass(node: Node) -> bool:
	return node is MeshInstance3D and node.material_override == _material and _material != null
