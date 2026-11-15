extends RefCounted
# Window glass with a room behind it, for every building window a player can
# look into. The room is not geometry: shaders/window_room.gdshader traces
# the view ray into a box room (walls, floor, ceiling) past flat furniture
# cards, so the parallax is right from any angle, at one quad per window.
# Kinds pick the room: a Provençal home, a shop with stocked shelves (accent =
# the goods), an izba with its stove and red corner, a chalet, a machine cab,
# a church with candles and an iconostasis, a winery hall with barrels and
# vats, a café, an office.
#
#   WindowRooms.pane(parent, centre, Vector2(0.8, 1.3), Vector3.FORWARD, "home", {"drop": 1.3})
#
# A pane is its own MeshInstance3D (meta META) until a builder merges them:
# MeshMerge.bake() folds a building's panes into one "WindowRooms" mesh and
# the village batcher (primitive_batcher.gd) one mesh per 64 m tile.
# At night sky_weather.gd sets the shader global window_night: lit rooms
# (a chance per room, `lit`) glow warm, the others go dark.
const SHADER = preload("res://shaders/window_room.gdshader")
const KINDS = {"home": 0, "shop": 1, "izba": 2, "chalet": 3, "cab": 4, "church": 5, "hall": 6, "cafe": 7, "office": 8}
const META = "window_room"
const NAME = "WindowRooms"
const NIGHT = &"window_night"
# How far a merged street of windows is drawn (m).
const RANGE = 420.0
static var _material: ShaderMaterial

static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	return _material

# Day 0 .. night 1 for every room window.
static func set_night(amount: float) -> void:
	RenderingServer.global_shader_parameter_set(NIGHT, amount)

# A pane `size` wide and high centred at `centre` in `parent`, its outside
# facing `outward` (horizontal). Options: drop (m from the centre down to the
# room's floor, default 1.3), accent (Color), lit (night chance 0..1, 1 also
# lights it by day), seed (0..1, default from the parent and position).
static func pane(parent: Node3D, centre: Vector3, size: Vector2, outward: Vector3, kind: String, options: Dictionary = {}) -> MeshInstance3D:
	var normal = Vector3(outward.x, 0, outward.z).normalized()
	var right = Vector3.UP.cross(normal)
	var seed = float(options.get("seed", float(posmod(hash("%s:%.2f:%.2f:%.2f" % [parent.name, centre.x, centre.y, centre.z]), 997)) / 997.0))
	var data = _arrays()
	_quad(data, centre, right, normal, size * 0.5, KINDS.get(kind, 0), clampf(seed, 0.0, 0.999), float(options.get("drop", 1.3)), options.get("accent", Color("c7553f")), float(options.get("lit", 0.4)))
	var node = MeshInstance3D.new()
	node.name = "WindowRoom"
	node.mesh = _commit(data)
	node.material_override = material()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.set_meta(META, true)
	parent.add_child(node)
	return node

static func is_pane(node: Node) -> bool:
	return node is MeshInstance3D and node.has_meta(META)

# Folds every pane under `root` into one mesh named NAME in root space;
# returns it (null when there are none).
static func merge(root: Node3D) -> MeshInstance3D:
	var data = _arrays()
	var panes: Array = []
	_gather(root, root, Transform3D.IDENTITY, data, panes)
	if panes.is_empty():
		return null
	for node in panes:
		node.get_parent().remove_child(node)
		node.free()
	var merged = MeshInstance3D.new()
	merged.name = NAME
	merged.mesh = _commit(data)
	merged.material_override = material()
	merged.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	merged.visibility_range_end = RANGE
	merged.set_meta("unbatched", true)
	merged.set_meta("perch_ignore", true)
	root.add_child(merged)
	return merged

# Adds one pane (already a MeshInstance3D with META) to `data` at `pose`.
static func append(data: Dictionary, node: MeshInstance3D, pose: Transform3D) -> void:
	var arrays = node.mesh.surface_get_arrays(0)
	var base = data.vertex.size()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	for i in range(vertices.size()):
		data.vertex.append(pose * vertices[i])
		data.normal.append((pose.basis * normals[i]).normalized())
		var t = (pose.basis * Vector3(tangents[i * 4], tangents[i * 4 + 1], tangents[i * 4 + 2])).normalized()
		data.tangent.append_array(PackedFloat32Array([t.x, t.y, t.z, tangents[i * 4 + 3]]))
	data.color.append_array(arrays[Mesh.ARRAY_COLOR])
	data.uv.append_array(arrays[Mesh.ARRAY_TEX_UV])
	data.uv2.append_array(arrays[Mesh.ARRAY_TEX_UV2])
	for index in arrays[Mesh.ARRAY_INDEX]:
		data.index.append(base + index)

static func new_arrays() -> Dictionary:
	return _arrays()

static func commit(data: Dictionary) -> ArrayMesh:
	return _commit(data)

static func _gather(node: Node, root: Node3D, xform: Transform3D, data: Dictionary, panes: Array) -> void:
	for child in node.get_children():
		if not child is Node3D:
			continue
		var local: Transform3D = xform * child.transform
		if is_pane(child):
			append(data, child, local)
			panes.append(child)
		else:
			_gather(child, root, local, data, panes)

static func _arrays() -> Dictionary:
	return {"vertex": PackedVector3Array(), "normal": PackedVector3Array(), "tangent": PackedFloat32Array(),
		"color": PackedColorArray(), "uv": PackedVector2Array(), "uv2": PackedVector2Array(), "index": PackedInt32Array()}

static func _quad(data: Dictionary, centre: Vector3, right: Vector3, normal: Vector3, half: Vector2, kind: int, seed: float, drop: float, accent: Color, lit: float) -> void:
	var base = data.vertex.size()
	var info = Vector2(kind + seed, 1000.0 * roundf(half.x * 100.0) + clampf(roundf(drop * 100.0), 0.0, 999.0))
	var tint = Color(accent.r, accent.g, accent.b, clampf(lit, 0.0, 1.0))
	# Top left, top right, bottom right, bottom left as seen from outside:
	# clockwise, Godot's front face.
	for corner in [Vector2(-1, 1), Vector2(1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var offset = Vector2(corner.x * half.x, corner.y * half.y)
		data.vertex.append(centre + right * offset.x + Vector3.UP * offset.y)
		data.normal.append(normal)
		data.tangent.append_array(PackedFloat32Array([right.x, right.y, right.z, 1.0]))
		data.color.append(tint)
		data.uv.append(offset)
		data.uv2.append(info)
	data.index.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))

static func _commit(data: Dictionary) -> ArrayMesh:
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data.vertex
	arrays[Mesh.ARRAY_NORMAL] = data.normal
	arrays[Mesh.ARRAY_TANGENT] = data.tangent
	arrays[Mesh.ARRAY_COLOR] = data.color
	arrays[Mesh.ARRAY_TEX_UV] = data.uv
	arrays[Mesh.ARRAY_TEX_UV2] = data.uv2
	arrays[Mesh.ARRAY_INDEX] = data.index
	var mesh = ArrayMesh.new()
	if not data.vertex.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
