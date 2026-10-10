extends RefCounted
# Packed geometry stays spatially partitioned. Only mutable MultiMeshes are
# uploaded once per scene; immutable meshes and materials retain shared resources.
const SCHEMA = 4
const SOURCES = ["stage", "stage_solids", "primitive_batcher", "village_stage", "village_layout", "village_architecture", "village_landscape", "village_farmland", "props", "village_interiors", "church_bell"]
const STAGE_FIELDS = ["woodland_details", "collectibles", "collectible_parts", "rocks", "trees", "forest_data", "detail_tree_groups", "detail_tree_visuals", "forest_layers", "forest_chunk_slots", "forest_chunk_centers"]

static func fingerprint() -> String:
	var input = "village:%d" % SCHEMA
	for source in SOURCES:
		input += FileAccess.get_sha256("res://scripts/%s.gd" % source)
	var files = DirAccess.get_files_at("res://models/nature")
	files.sort()
	for file in files:
		if not file.ends_with(".import"):
			input += file + FileAccess.get_sha256("res://models/nature/" + file)
	return input.sha256_text()


static func capture_instances(node: MultiMeshInstance3D, poses: Array, colors: Array, center: Vector3) -> void:
	# The headless/dummy renderer does not retain MultiMesh buffers. Capture the
	# actual generated transforms before upload so CI bakes the same geometry.
	var buffer = PackedFloat32Array()
	buffer.resize(poses.size() * 16)
	for i in range(poses.size()):
		var pose: Transform3D = poses[i]
		pose.origin -= center
		var b = pose.basis
		var p = pose.origin
		var c: Color = colors[i]
		var values = [b.x.x, b.y.x, b.z.x, p.x, b.x.y, b.y.y, b.z.y, p.y, b.x.z, b.y.z, b.z.z, p.z, c.r, c.g, c.b, c.a]
		for j in range(16):
			buffer[i * 16 + j] = values[j]
	node.set_meta("baked_instances", buffer)

static func _encode(value, root: Node, multimeshes: Dictionary):
	if value is Node:
		return {"_baked_node": root.get_path_to(value)}
	if value is MultiMesh:
		return {"_baked_multimesh": multimeshes[value.get_instance_id()]}
	if value is Array:
		var result = []
		for item in value:
			result.append(_encode(item, root, multimeshes))
		return result
	if value is Dictionary:
		var result = {}
		for key in value:
			result[key] = _encode(value[key], root, multimeshes)
		return result
	return value

static func _decode(value, root: Node):
	if value is Dictionary:
		if value.has("_baked_node"):
			return root.get_node(value._baked_node)
		if value.has("_baked_multimesh"):
			return root.get_node(value._baked_multimesh).multimesh
		var result = {}
		for key in value:
			result[key] = _decode(value[key], root)
		return result
	if value is Array:
		var result = []
		for item in value:
			result.append(_decode(item, root))
		return result
	return value

static func _restore(node: Node, fields: Dictionary, root: Node) -> void:
	for field in fields:
		var value = _decode(fields[field], root)
		var current = node.get(field)
		if current is Array and value is Array:
			# Keep declared element types, e.g. Array[Dictionary]/Array[Vector3].
			current.assign(value)
		else:
			node.set(field, value)

static func _script_fields(node: Node, root: Node, multimeshes: Dictionary) -> Dictionary:
	var fields = {}
	for property in node.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.name not in ["stage", "collision_cells", "moving_obstacle_ids", "indexed_obstacle_count"]:
			fields[property.name] = _encode(node.get(property.name), root, multimeshes)
	return fields

static func _own_children(node: Node, root: Node, multimeshes: Dictionary) -> void:
	for index in range(node.get_child_count()):
		var child = node.get_child(index)
		# Runtime-generated @ names are not stable PackedScene paths.
		if str(child.name).begins_with("@"):
			child.name = "Baked_%s_%d" % [child.get_class(), index]
		child.owner = root
		if child is MultiMeshInstance3D:
			multimeshes[child.multimesh.get_instance_id()] = root.get_path_to(child)
		_own_children(child, root, multimeshes)

static func save(stage: Node3D, path: String) -> Error:
	# Bake before any gameplay state changes; officials are rebuilt at runtime.
	stage.rocks = stage.rocks.filter(func(rock): return not rock.get("official", false))
	stage.officials.free()
	stage.officials = null
	# Village life is local animation, rebuilt from the baked anchors on load.
	if stage.life != null:
		stage.life.root.free()
		stage.life = null
	var asset = Node3D.new()
	asset.name = "VillageAsset"
	for child in stage.get_children():
		stage.remove_child(child)
		asset.add_child(child)
	var multimeshes = {}
	_own_children(asset, asset, multimeshes)
	var state = {}
	for field in STAGE_FIELDS:
		state[field] = _encode(stage.get(field), asset, multimeshes)
	asset.set_meta("baked_schema", SCHEMA)
	asset.set_meta("source_fingerprint", fingerprint())
	asset.set_meta("stage_state", state)
	asset.set_meta("solids_path", asset.get_path_to(stage.solids))
	asset.set_meta("solids_state", _script_fields(stage.solids, asset, multimeshes))
	asset.set_meta("bell_state", _script_fields(stage.solids.bell, asset, multimeshes))
	asset.set_meta("village_anchors", _encode(stage.village.anchors, asset, multimeshes))
	asset.set_meta("village_counts", stage.village.counts.duplicate())
	var instance_data = {}
	for node in asset.find_children("*", "MultiMeshInstance3D", true, false):
		if not node.has_meta("baked_instances"):
			asset.free()
			return ERR_INVALID_DATA
		instance_data[asset.get_path_to(node)] = {"mesh": node.multimesh.mesh, "buffer": node.get_meta("baked_instances"), "count": node.multimesh.instance_count}
		node.remove_meta("baked_instances")
		node.multimesh = null
	asset.set_meta("instance_data", instance_data)
	var packed = PackedScene.new()
	var error = packed.pack(asset)
	if error == OK:
		error = ResourceSaver.save(packed, path, ResourceSaver.FLAG_COMPRESS)
	asset.free()
	return error

static func _clear_owners(node: Node) -> void:
	for child in node.get_children():
		_clear_owners(child)
		child.owner = null

static func _apply(stage: Node3D, packed: PackedScene) -> bool:
	if packed == null:
		return false
	var asset = packed.instantiate()
	if asset.get_meta("baked_schema", -1) != SCHEMA or (OS.has_feature("editor") and asset.get_meta("source_fingerprint", "") != fingerprint()):
		asset.free()
		return false
	var instance_data: Dictionary = asset.get_meta("instance_data")
	for path in instance_data:
		var data: Dictionary = instance_data[path]
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = data.mesh
		mm.instance_count = data.count
		mm.buffer = data.buffer
		var node = asset.get_node(path)
		node.multimesh = mm
		if stage.capture_bake_buffers:
			node.set_meta("baked_instances", data.buffer)
	# The baked solids replace the empty component created with the stage.
	if stage.solids != null:
		stage.remove_child(stage.solids)
		stage.solids.free()
	stage.solids = asset.get_node(asset.get_meta("solids_path"))
	_restore(stage, asset.get_meta("stage_state"), asset)
	_restore(stage.solids, asset.get_meta("solids_state"), asset)
	_restore(stage.solids.bell, asset.get_meta("bell_state"), asset)
	stage.solids.stage = stage
	stage.village.anchors = _decode(asset.get_meta("village_anchors"), asset)
	stage.village.counts = asset.get_meta("village_counts", {}).duplicate()
	_clear_owners(asset)
	for child in asset.get_children():
		asset.remove_child(child)
		stage.add_child(child)
	asset.free()
	stage.solids.index()
	stage._rebuild_tree_index()
	stage.loaded_baked = true
	return true

static func load_into(stage: Node3D, path: String) -> bool:
	if not ResourceLoader.exists(path):
		return false
	return _apply(stage, ResourceLoader.load(path, "PackedScene"))

static func load_into_async(stage: Node3D, path: String, progress: Callable) -> bool:
	var error = ResourceLoader.load_threaded_request(path, "PackedScene")
	if error != OK:
		return load_into(stage, path)
	var status = ResourceLoader.load_threaded_get_status(path)
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		var amount = []
		ResourceLoader.load_threaded_get_status(path, amount)
		await progress.call("Загрузка спецучастка", int(amount[0] * 55) if not amount.is_empty() else 0)
		status = ResourceLoader.load_threaded_get_status(path)
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		return false
	await progress.call("Подготовка объектов", 55)
	return _apply(stage, ResourceLoader.load_threaded_get(path))
