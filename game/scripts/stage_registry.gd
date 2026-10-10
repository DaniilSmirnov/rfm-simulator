extends RefCounted
# The list of special stages, read from res://data/stages.json. Everything that
# needs "which stages exist" asks here: the menu, Stage.new(), previews, tests.
# Each entry names a biome script (stage_biome.gd subclass) and the stage's
# look: sky, sun, loading caption, minimap tint and what berries are called.
const PATH = "res://data/stages.json"
static var spec: Dictionary = _load()

static func _load() -> Dictionary:
	var text = FileAccess.get_file_as_string(PATH)
	var data = JSON.parse_string(text) if text != "" else null
	if not data is Dictionary or not data.get("stages") is Array or data.stages.is_empty():
		push_error("Stage registry is missing: " + PATH)
		return {"defaults": {}, "stages": [{"id": "forest", "title": "Лесной перевал", "subtitle": "гравий", "biome": "res://scripts/forest_pass.gd"}]}
	return data

static func count() -> int:
	return spec.stages.size()

static func entry(index: int) -> Dictionary:
	return spec.stages[clampi(index, 0, count() - 1)]

# Menu caption, "Title · subtitle".
static func caption(index: int) -> String:
	var e = entry(index)
	return "%s · %s" % [e.title, e.subtitle]

static func captions() -> Array:
	var result: Array = []
	for i in range(count()):
		result.append(caption(i))
	return result

static func index_of(id: String) -> int:
	for i in range(count()):
		if spec.stages[i].id == id:
			return i
	return -1

# A presentation value of the stage, falling back to the shared defaults.
static func value(index: int, key: String):
	var e = entry(index)
	return e[key] if e.has(key) else spec.get("defaults", {}).get(key)

# Merged dictionary values (environment, sun): stage keys over the defaults.
static func section(index: int, key: String) -> Dictionary:
	var result: Dictionary = spec.get("defaults", {}).get(key, {}).duplicate()
	result.merge(entry(index).get(key, {}), true)
	return result

static func make_biome(index: int):
	var script: Script = load(str(entry(index).biome))
	return script.new()
