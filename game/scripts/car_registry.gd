extends RefCounted
# The player fleet, read from res://data/cars.json. Each car is one record: its
# look (body proportions, lights, grille, trim), handling and trunk. The index
# of a car in the list is its content id (`variant`) in saves, rooms and the
# store catalog, so new cars are appended, never inserted.
const PATH = "res://data/cars.json"
static var spec: Dictionary = _load()
static var cars: Array = _merge()

static func _load() -> Dictionary:
	var text = FileAccess.get_file_as_string(PATH)
	var data = JSON.parse_string(text) if text != "" else null
	if not data is Dictionary or not data.get("cars") is Array or data.cars.is_empty():
		push_error("Car registry is missing: " + PATH)
		return {"defaults": {}, "cars": [{"name": "Компактный седан", "color": "111a2b", "length": 4.26, "width": 1.70, "height": 1.50, "rear": 0.95, "glass": 0.36, "lights": "wide", "grille": 0.65, "shape": [-0.87, -0.40, 0.57, 1.07, 0.72, 0.77]}]}
	return data

# Every car with the shared defaults filled in; nested sections merge by key.
static func _merge() -> Array:
	var defaults: Dictionary = spec.get("defaults", {})
	var result: Array = []
	for car in spec.cars:
		var merged: Dictionary = defaults.duplicate(true)
		for key in car:
			if car[key] is Dictionary and merged.get(key) is Dictionary:
				merged[key].merge(car[key], true)
			else:
				merged[key] = car[key]
		result.append(merged)
	return result

static func count() -> int:
	return cars.size()

static func car(variant: int) -> Dictionary:
	return cars[posmod(variant, cars.size())]

# Share of drive torque sent to the rear axle.
static func rear_bias(variant: int) -> float:
	match str(car(variant).handling.drive):
		"rear":
			return 1.0
		"all":
			return 0.5
	return 0.0
