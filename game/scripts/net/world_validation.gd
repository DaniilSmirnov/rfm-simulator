extends RefCounted
# Wire shapes are shared with the Worker; validation precedes all world mutation.
static var types: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_schema.json")).types

# One packet passes through several appliers (direct link, room, prediction,
# providers) that each check it. While a checked world is being applied, the
# room marks it trusted so the nested checks do not walk it again.
static var _trusted = null

static func valid(world) -> bool:
	if world != null and is_same(world, _trusted):
		return true
	return _bounded(world, [32768]) and _matches(world, "world")

# Marks a world that valid() accepted for the duration of its application;
# trust(null) ends it.
static func trust(world) -> void:
	_trusted = world

static func _usable(world: Dictionary) -> bool:
	if not world is Dictionary or world.size() > 96: return false
	for key in world:
		if not (key is String or key is StringName) or key.length() > 32 or key.is_empty(): return false
		for character in str(key):
			if not "abcdefghijklmnopqrstuvwxyz_".contains(character): return false
	if world.get("cooking", false) and world.get("grill_pose") == null and world.get("camp") == null: return false
	if world.get("notice_time", 0) > 0 and not world.has("notice"): return false
	var cooking: Dictionary = world.get("camp_cooking", {})
	return not cooking.get("pot", false) or not cooking.has("pot_pos") or cooking.pot_pos.size() == 3

static func _bounded(value, budget: Array, depth: int = 0) -> bool:
	budget[0] -= 1
	if budget[0] < 0 or depth > 12: return false
	if value == null or value is bool: return true
	if value is int or value is float: return is_finite(float(value)) and absf(float(value)) <= 9007199254740991.0
	if value is String or value is StringName: return value.length() <= 4096
	if value is Array:
		if value.size() > 20000: return false
		for item in value:
			if not _bounded(item, budget, depth + 1): return false
		return true
	if not value is Dictionary or value.size() > 2048: return false
	for key in value:
		if not (key is String or key is StringName) or key.length() > 128 or not _bounded(value[key], budget, depth + 1): return false
	return true

static func _matches(value, shape) -> bool:
	if shape is String:
		match shape:
			"null": return value == null
			"bool": return value is bool
			"string": return value is String or value is StringName
			"int": return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value))
			"number", "coordinate": return (value is int or value is float) and is_finite(float(value)) and (shape != "coordinate" or absf(float(value)) < 100000.0)
		return _matches(value, types[shape]) and (shape != "world" or _usable(value))
	if shape is Array:
		if not value is Array or value.size() != shape.size(): return false
		for i in range(shape.size()):
			if not _matches(value[i], shape[i]): return false
		return true
	if shape.has("one"):
		for option in shape.one:
			if _matches(value, option): return true
		return false
	if shape.has("array"):
		if not value is Array or value.size() > shape.max: return false
		for item in value:
			if not _matches(item, shape.array): return false
		return true
	if not value is Dictionary: return false
	if shape.has("map"):
		if value.size() > shape.max: return false
		for item in value.values():
			if not _matches(item, shape.map): return false
		return true
	if shape.get("empty", false) and value.is_empty(): return true
	for key in shape.get("required", []):
		if not value.has(key): return false
	for key in shape.fields:
		if value.has(key) and not _matches(value[key], shape.fields[key]): return false
	return true
