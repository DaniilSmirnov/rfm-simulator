extends RefCounted
# Draw-call reduction for props built from many small primitives. Every
# MeshInstance3D is one draw call per pass (and again per shadow split), so a
# car of 80 boxes costs 80+ calls. bake() folds the static, plain-coloured
# meshes and Label3D captions under a root into one vertex-coloured mesh:
#
#   MeshMerge.bake(car, "rally:6")  # cache key: identical props share the result
#
# Left alone (they move, toggle or glow on their own): rolling wheels, nodes
# marked set_meta("unbatched", true), names in `keep` with their subtrees,
# hidden subtrees, emissive or textured materials, billboards. The original
# baked nodes are freed; their names and bounds stay in the root's
# "baked_parts" meta (name -> AABB in root space) and the captions in
# "baked_text", for tests and tools.
# flatten() does the same for one multi-material mesh (imported characters),
# sharing the result between all instances of that mesh.
const BlockText = preload("res://scripts/block_text.gd")
const CACHE_LIMIT = 192
const KEEP = ["TrunkHinge", "TrunkBoxes"]
static var _cache: Dictionary = {}
static var _flat: Dictionary = {}
static var _materials: Dictionary = {}

# Material for a merged surface; one per (double-sided, roughness, metallic).
static func material(double_sided: bool, roughness: float, metallic: float) -> StandardMaterial3D:
	var key = Vector3(1.0 if double_sided else 0.0, roughness, metallic)
	if not _materials.has(key):
		var mat = StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = roughness
		mat.metallic = metallic
		if double_sided:
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[key] = mat
	return _materials[key]

static func bake(root: Node3D, cache_key: String = "", keep: Array = KEEP, name: String = "Baked") -> MeshInstance3D:
	var parts: Array = []
	_collect(root, root, Transform3D.IDENTITY, keep, parts)
	if parts.is_empty():
		return null
	var mesh: ArrayMesh
	var bounds: Dictionary
	var texts: Array
	if cache_key != "" and _cache.has(cache_key):
		mesh = _cache[cache_key].mesh
		bounds = _cache[cache_key].bounds
		texts = _cache[cache_key].texts
	else:
		var groups: Dictionary = {}
		bounds = {}
		texts = []
		for part in parts:
			_append(groups, part)
			var node: Node = part.node
			if node is Label3D:
				texts.append(node.text)
			if not str(node.name).begins_with("@") and part.node is MeshInstance3D and part.node.mesh != null:
				var box: AABB = part.xform * part.node.mesh.get_aabb()
				bounds[str(node.name)] = bounds[str(node.name)].merge(box) if bounds.has(str(node.name)) else box
		mesh = _commit(groups)
		if cache_key != "" and _cache.size() < CACHE_LIMIT:
			_cache[cache_key] = {"mesh": mesh, "bounds": bounds, "texts": texts}
	var baked = MeshInstance3D.new()
	baked.name = name
	baked.mesh = mesh
	root.add_child(baked)
	root.set_meta("baked_parts", bounds)
	root.set_meta("baked_text", texts)
	_remove(parts)
	return baked

# One surface with vertex colours instead of one per material; shared by
# every instance of the same source mesh.
static func flatten(node: MeshInstance3D) -> void:
	if node.mesh == null or node.mesh.get_surface_count() < 2:
		return
	var key = node.mesh.get_rid()
	if not _flat.has(key):
		var groups: Dictionary = {}
		_append(groups, {"node": node, "xform": Transform3D.IDENTITY})
		_flat[key] = _commit(groups)
	node.mesh = _flat[key]
	node.material_override = null

static func _collect(node: Node, root: Node3D, xform: Transform3D, keep: Array, parts: Array) -> void:
	for child in node.get_children():
		if not child is Node3D or not child.visible or str(child.name) in keep:
			continue
		if child.has_meta("rolling_wheel_radius") or child.has_meta("unbatched") or child is CollisionObject3D:
			continue
		var local: Transform3D = xform * child.transform
		if child is MeshInstance3D and _plain(child):
			parts.append({"node": child, "xform": local})
		elif child is Label3D and child.billboard == BaseMaterial3D.BILLBOARD_DISABLED:
			parts.append({"node": child, "xform": local})
		_collect(child, root, local, keep, parts)

# Untextured, non-emissive, opaque StandardMaterial3D on every surface.
static func _plain(node: MeshInstance3D) -> bool:
	if node.mesh == null or node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
		return false
	for surface in range(node.mesh.get_surface_count()):
		var mat = _surface_material(node, surface)
		if mat != null and not mat is StandardMaterial3D:
			return false
		if mat != null and (mat.albedo_texture != null or mat.emission_enabled or mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED):
			return false
	return true

static func _surface_material(node: MeshInstance3D, surface: int) -> Material:
	if node.material_override != null:
		return node.material_override
	var override = node.get_surface_override_material(surface)
	return override if override != null else node.mesh.surface_get_material(surface)

static func _append(groups: Dictionary, part: Dictionary) -> void:
	var node: Node3D = part.node
	var xform: Transform3D = part.xform
	if node is Label3D:
		var target = _group(groups, false, 0.95, 0.0)
		var basis = xform.basis
		var normal = (basis * Vector3.BACK).normalized()
		for vertex in BlockText.triangles(node.text, BlockText.label_pixel(node)):
			target.v.append(xform * vertex)
			target.n.append(normal)
			target.c.append(node.modulate)
		return
	var mesh: Mesh = node.mesh
	var normal_basis = xform.basis.inverse().transposed()
	for surface in range(mesh.get_surface_count()):
		var mat = _surface_material(node, surface) as StandardMaterial3D
		var albedo = mat.albedo_color if mat != null else Color.WHITE
		var double_sided = mat != null and mat.cull_mode == BaseMaterial3D.CULL_DISABLED
		var target = _group(groups, double_sided, snappedf(mat.roughness if mat != null else 1.0, 0.25), snappedf(mat.metallic if mat != null else 0.0, 0.25))
		var arrays = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals = arrays[Mesh.ARRAY_NORMAL]
		var colors = arrays[Mesh.ARRAY_COLOR] if mat != null and mat.vertex_color_use_as_albedo else null
		var indices = arrays[Mesh.ARRAY_INDEX]
		var count = indices.size() if indices != null and indices.size() > 0 else vertices.size()
		for k in range(count):
			var i = indices[k] if indices != null and indices.size() > 0 else k
			target.v.append(xform * vertices[i])
			target.n.append((normal_basis * normals[i]).normalized() if normals != null and normals.size() > i else Vector3.UP)
			target.c.append(albedo * colors[i] if colors != null and colors.size() > i else albedo)

static func _group(groups: Dictionary, double_sided: bool, roughness: float, metallic: float) -> Dictionary:
	var key = Vector3(1.0 if double_sided else 0.0, roughness, metallic)
	if not groups.has(key):
		groups[key] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(), "material": material(double_sided, roughness, metallic)}
	return groups[key]

static func _commit(groups: Dictionary) -> ArrayMesh:
	var mesh = ArrayMesh.new()
	for key in groups:
		var group: Dictionary = groups[key]
		if group.v.is_empty():
			continue
		var arrays = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = group.v
		arrays[Mesh.ARRAY_NORMAL] = group.n
		arrays[Mesh.ARRAY_COLOR] = group.c
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, group.material)
	return mesh

# Free baked nodes. A node that still holds something unbaked (a wheel, a
# beacon, a hinge) stays as a plain transform with its mesh removed.
static func _remove(parts: Array) -> void:
	var baked: Dictionary = {}
	for part in parts:
		baked[part.node] = true
	for i in range(parts.size() - 1, -1, -1):
		var node: Node3D = parts[i].node
		if _all_baked(node, baked):
			node.get_parent().remove_child(node)
			node.free()
		elif node is MeshInstance3D:
			node.mesh = null
		else:
			node.text = ""

static func _all_baked(node: Node, baked: Dictionary) -> bool:
	for child in node.get_children():
		if not baked.has(child) or not _all_baked(child, baked):
			return false
	return true
