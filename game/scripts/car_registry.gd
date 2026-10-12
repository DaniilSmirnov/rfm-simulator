extends RefCounted
# The player fleet, read from res://data/cars.json. Each car is one record: its
# look (body proportions, lights, grille, trim), handling and trunk. The index
# of a car in the list is its content id (`variant`) in saves, rooms and the
# store catalog, so new cars are appended, never inserted.
const PATH = "res://data/cars.json"
# One speed range for every car in the game (player cars, rally crews, zero
# cars): the top speed is shared, cars differ only in how fast they reach it.
# A car's `zero_to_100` (s) sets its launch: full throttle accelerates at
# launch * (1 - (v / TOP_SPEED)^3), so it pulls hard at first and levels off
# at the top speed.
const TOP_SPEED = 220.0 / 3.6
const OFFROAD_SPEED = 7.0
const REVERSE_SPEED = 7.6
# ∫ dv / (1 - (v / TOP_SPEED)^3) from 0 to 100 km/h: seconds to 100 km/h at a
# launch of 1 m/s².
const LAUNCH_INTEGRAL = 28.4675
static var spec: Dictionary = _load()
static var cars: Array = _merge()

static func _load() -> Dictionary:
	var text = FileAccess.get_file_as_string(PATH)
	var data = JSON.parse_string(text) if text != "" else null
	if not data is Dictionary or not data.get("cars") is Array or data.cars.is_empty():
		push_error("Car registry is missing: " + PATH)
		return {"defaults": {}, "cars": [{"name": "Компактный седан", "color": "111a2b", "length": 4.26, "width": 1.70, "height": 1.50, "rear": 0.95, "glass": 0.36, "lights": "wide", "grille": 0.65, "shape": [-0.87, -0.40, 0.57, 1.07, 0.72, 0.77]}]}
	return data

static func _merge() -> Array:
	return merge_records(spec.get("defaults", {}), spec.cars)

# Every record with the shared defaults filled in; nested sections merge by
# key. Also used for the rally fleet (rally_car_model.gd).
static func merge_records(defaults: Dictionary, records: Array) -> Array:
	var result: Array = []
	for car in records:
		var merged: Dictionary = defaults.duplicate(true)
		for key in car:
			if car[key] is Dictionary and merged.get(key) is Dictionary:
				merged[key].merge(car[key], true)
			else:
				merged[key] = car[key]
		result.append(merged)
	return result

# Launch acceleration (m/s²) of a car that reaches 100 km/h in `seconds`.
static func launch(seconds: float) -> float:
	return LAUNCH_INTEGRAL / maxf(seconds, 0.5)

# Full-throttle acceleration (m/s²) at `speed` (m/s), zero at the top speed.
static func pull(launch_accel: float, speed: float) -> float:
	var ratio = clampf(absf(speed) / TOP_SPEED, 0.0, 1.0)
	return launch_accel * (1.0 - ratio * ratio * ratio)

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
