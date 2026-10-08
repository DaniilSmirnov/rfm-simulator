extends RefCounted
const VERSION = 1
static var schema: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_protocol.json"))

static func validate(world: Variant, legacy: bool = true) -> String:
	var old = world is Dictionary and not world.has("world_protocol")
	if old and not legacy:
		return "world.world_protocol"
	var error = _check(world, schema.definitions.world, "world", old)
	if error != "":
		return error
	if world.get("cooking", false) and world.get("grill_pose") == null and world.get("camp") == null:
		return "world.grill_pose"
	var pot: Dictionary = world.get("camp_cooking", {})
	if pot.get("fire", false) and not pot.has("pos"):
		return "world.camp_cooking.pos"
	if pot.get("pot", false) and pot.get("pot_pos", []).size() != 3:
		return "world.camp_cooking.pot_pos"
	return ""

static func _check(value: Variant, rule: Dictionary, path: String, old: bool, depth: int = 0) -> String:
	if depth > 12:
		return path
	match rule.type:
		"anyOf":
			for option in rule.rules:
				if _check(value, option, path, old, depth + 1) == "": return ""
			return path
		"ref": return _check(value, schema.definitions[rule.name], path, old, depth + 1)
		"nullable": return "" if value == null else _check(value, rule.items, path, old, depth + 1)
		"enum":
			for option in rule.values:
				if (option is float or option is int) and (value is float or value is int):
					if float(option) == float(value): return ""
				elif typeof(option) == typeof(value) and option == value: return ""
			return path
		"number", "integer":
			if not (value is int or value is float) or not is_finite(float(value)) or value < rule.min or value > rule.max:
				return path
			return path if rule.type == "integer" and float(value) != floor(float(value)) else ""
		"boolean": return "" if value is bool else path
		"string": return "" if value is String and value.length() <= rule.max else path
		"array":
			if not value is Array or value.size() > rule.max or value.size() < rule.get("min", 0):
				return path
			for index in range(value.size()):
				var error = _check(value[index], rule.items, "%s[%d]" % [path, index], old, depth + 1)
				if error != "": return error
			return ""
	if not value is Dictionary or value.size() > rule.max:
		return path
	if rule.type == "object":
		for key in rule.required:
			if not (old and path == "world") and not value.has(key): return path + "." + key
		for key in value:
			if not rule.fields.has(key):
				if not old: return path + "." + str(key)
				continue
			var error = _check(value[key], rule.fields[key], path + "." + str(key), old, depth + 1)
			if error != "": return error
	else:
		for key in value:
			if str(key).length() > 256: return path
			var error = _check(value[key], rule.items, path + "." + str(key), old, depth + 1)
			if error != "": return error
	return ""
