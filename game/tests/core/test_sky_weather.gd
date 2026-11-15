extends "res://tests/harness.gd"
# Time of day and weather (scripts/core/sky_weather.gd): the stage card tiles
# and their previews,
# which weather each stage allows (rain without snow, snow on snowy stages),
# the sky they draw, headlights at night, grip, the weather sound and the room
# snapshot guests apply.
const CarLamps = preload("res://scripts/cars/car_lamps.gd")
const SkyWeather = preload("res://scripts/core/sky_weather.gd")
const StageRegistry = preload("res://scripts/stages/stage_registry.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	check_rules()
	check_looks()
	var game = load("res://main.tscn").instantiate()
	game.defer_world = true
	root.add_child(game)
	await process_frame
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	var sky = game.sky_weather
	var ui = game.lobby_ui
	check(sky.daytime == "day" and sky.weather == "sun", "a stage starts in daylight and sun")
	var tiles: Dictionary = ui.conditions.tiles
	check(ui.conditions.get_parent() == ui.images[1], "the tiles sit on the stage preview")
	check(tiles.rain.icon.resource_path.ends_with("weather_rain.svg"), "a summer stage offers rain")
	check(ui.images[1].texture.resource_path == "res://textures/previews/stage_%d.webp" % game.selected_stage, "day and sun show the stage's usual preview")
	tiles.rain.pressed.emit()
	check(ui.images[1].texture.resource_path == SkyWeather.preview_path(game.selected_stage, "day", "rain"), "the preview shows the stage in the rain")
	check(sky.weather == "rain" and game.get_node_or_null("Weather") != null, "rain picked on the card falls")
	var forest_point = game.stage.at(100)
	check(is_equal_approx(game.stage.grip(forest_point), game.stage.biome.grip(forest_point) * SkyWeather.GRIP.rain) and SkyWeather.GRIP.rain < 1.0, "rain makes the road slippery")
	game.playing = true
	game.soundscape._update_weather()
	check(game.soundscape.weather_audio.stream == load("res://audio/rain.wav"), "rain is heard while playing")
	game.playing = false
	game.soundscape._update_weather()
	check(game.soundscape.weather_audio.stream == null, "the menu stays quiet")
	tiles.night.pressed.emit()
	check(sky.daytime == "night" and ui.images[1].texture.resource_path == SkyWeather.preview_path(game.selected_stage, "night", "rain"), "night picked on the card")
	check(game.world_environment.environment.ambient_light_energy < 0.35 and game.sunlight.light_energy < 0.3, "night dims the ambient light and the sun becomes a moon")
	check(game.car.get_node_or_null("Headlights") is SpotLight3D, "the car has its headlights on at night")
	var rally = game.Props.rally_car(0)
	game.add_child(rally)
	var parked = game.Props.player_car(1)
	game.add_child(parked)
	# Far from the player or next to them, every car shows the same lights.
	rally.position = Vector3(0, 0, 600)
	sky._update_headlights()
	check(parked.get_node("LampGlow").visible and rally.get_node("LampGlow").visible, "every car's head and tail lamps glow at night")
	check(rally.get_node_or_null("LampGlow/LampBeams") is MeshInstance3D and parked.get_node_or_null("LampGlow/LampBeams") is MeshInstance3D, "every car throws its beams ahead at night, near the player or far away")
	check(rally.get_node_or_null("Headlights") == null and parked.get_node_or_null("Headlights") == null, "no real light hops between the cars around the player")
	check_lamp_positions(game)
	tiles.sun.pressed.emit()
	check(sky.weather == "sun" and game.get_node_or_null("Weather") == null, "the sky clears")
	# Rain picked, then a snowy stage: the weather turns to sun, snow becomes possible.
	tiles.rain.pressed.emit()
	var winter = StageRegistry.index_of("winter")
	game.select_stage(winter)
	check(sky.weather == "sun" and ui.conditions.weather == "sun", "rain turns to sun on a snowy stage")
	check(tiles.rain.icon.resource_path.ends_with("weather_snow.svg"), "a snowy stage offers snow in place of rain")
	tiles.rain.pressed.emit()
	check(sky.weather == "snow" and game.get_node_or_null("Weather") is GPUParticles3D, "snow falls on a snowy stage")
	check(game.world_environment.environment.fog_density >= SkyWeather.FOG_DENSITY.snow, "snowfall thickens the fog")
	check(is_equal_approx(game.stage.weather_grip, SkyWeather.GRIP.snow) and SkyWeather.GRIP.snow < 1.0, "fresh snow takes some grip")
	# The room: the host's conditions reach a guest's sky.
	var shared = sky.snapshot()
	check(shared == {"time": "night", "weather": "snow"}, "the snapshot carries time and weather")
	sky.apply_snapshot({"time": "day", "weather": "fog"})
	check(sky.daytime == "day" and sky.weather == "fog" and game.car.get_node_or_null("Headlights") == null, "a guest takes the host's conditions; headlights go off in the day")
	check(not parked.get_node("LampGlow").visible and not rally.get_node("LampGlow").visible, "the lamps stop glowing in the day")
	check(game.stage.weather_grip == 1.0, "fog leaves the grip alone")
	ui.refresh()
	check(ui.conditions.time == "day" and ui.conditions.weather == "fog", "the tiles show the room's conditions")
	sky.apply_snapshot({"time": "noon", "weather": "rain"})
	check(sky.daytime == "day" and sky.weather == "sun", "unknown or unfitting values fall back to day and sun")
	await check_night_lights(game)
	var validation = load("res://scripts/net/world_validation.gd")
	check(validation.valid({"sky": shared}) and not validation.valid({"sky": {"time": 1}}), "the world schema checks the sky section")
	game.queue_free()
	await process_frame
	finish()

# Every kind of car has headlamps at its nose, and its beams and its own
# SpotLight3D start there, not inside or on top of the body.
func check_lamp_positions(game) -> void:
	var cars = [game.Props.rally_car(0), game.Props.course_car("police"), game.Props.course_car("ambulance"), game.Props.course_car("zero", 1)]
	for variant in range(game.Props.PLAYER_MODELS.size()):
		# The helicopter has no headlamps to light.
		if str(game.Props.PLAYER_MODELS[variant].model) != "helicopter":
			cars.append(game.Props.player_car(variant))
	for car in cars:
		var bounds: AABB = load("res://scripts/cars/car_hitbox.gd").bounds(car)
		var lamp: Vector3 = car.get_meta("head_lamp", Vector3.INF)
		var beams = car.get_node_or_null("LampGlow/LampBeams")
		check(lamp != Vector3.INF and beams != null, "%s has headlamps that throw beams" % car.name)
		if lamp == Vector3.INF or beams == null:
			car.free()
			continue
		check(lamp.z < bounds.position.z + 0.6 and lamp.y < bounds.end.y * 0.75, "%s headlamps sit at the nose, low on the front (%s in %s)" % [car.name, lamp, bounds])
		var beam_box: AABB = beams.mesh.get_aabb()
		check(beam_box.position.z < bounds.position.z - 5.0 and beam_box.end.z <= lamp.z + 0.05, "%s beams shine ahead of the car" % car.name)
		var light = SkyWeather.headlights(car)
		check(light.position.z < bounds.position.z and absf(light.position.y - lamp.y) < 0.01, "%s headlight sits ahead of its own lamps" % car.name)
		light.free()
		# A walker meets the car's body only: the lit beams are no wall or floor.
		var Perches = load("res://scripts/player/perches.gd")
		root.add_child(car)
		CarLamps.set_lit(car, false)
		var dark: Dictionary = Perches.field(car, car.global_transform)
		CarLamps.set_lit(car, true)
		var lit: Dictionary = Perches.field(car, car.global_transform)
		# The lit lenses stand a few millimetres proud of the body; a beam would
		# reach metres ahead.
		var grown = Vector2(lit.get("size", Vector2i.ZERO) - dark.get("size", Vector2i.ZERO)) * Perches.CELL
		check(not dark.is_empty() and lit.origin.distance_to(dark.origin) < 0.25 and grown.length() < 0.25, "%s beams can be walked through (%s)" % [car.name, grown])
		car.free()

func check_rules() -> void:
	check(SkyWeather.fits("rain", false) == "rain" and SkyWeather.fits("rain", true) == "sun", "rain only without snow")
	check(SkyWeather.fits("snow", true) == "snow" and SkyWeather.fits("snow", false) == "sun", "snow only on snowy stages")
	for kind in ["sun", "fog"]:
		check(SkyWeather.fits(kind, true) == kind and SkyWeather.fits(kind, false) == kind, "%s fits every stage" % kind)

func check_looks() -> void:
	for i in range(StageRegistry.count()):
		var day = SkyWeather.look(i, "day", "sun")
		check(day.environment == StageRegistry.section(i, "environment") and day.sun == StageRegistry.section(i, "sun"), "day and sun keep the stage's own sky (%d)" % i)
		var night = SkyWeather.look(i, "night", "sun")
		check(Color(night.environment.sky_top).get_luminance() < 0.1 and float(night.sun.energy) < float(day.sun.energy), "night is dark (%d)" % i)
		var fog = SkyWeather.look(i, "day", "fog")
		check(float(fog.environment.fog_density) > 0.015, "fog closes in (%d)" % i)
		var rain = SkyWeather.look(i, "day", "rain")
		check(float(rain.sun.energy) < float(day.sun.energy) and float(rain.environment.fog_density) > float(day.environment.fog_density), "rain is overcast (%d)" % i)
		# The stage card has a picture of every combination: rain or snow, not both.
		var missing = []
		for time in SkyWeather.DAYTIMES:
			for kind in ["sun", "fog"]:
				if not ResourceLoader.exists(SkyWeather.preview_path(i, time, kind)):
					missing.append(time + " " + kind)
			if ResourceLoader.exists(SkyWeather.preview_path(i, time, "rain")) == ResourceLoader.exists(SkyWeather.preview_path(i, time, "snow")):
				missing.append(time + " rain or snow")
		check(missing.is_empty(), "the stage card has a preview of every condition (%d) %s" % [i, missing])

# Campfires, lit grills and roof beacons light up at night, the nearest within
# the budget; by day the lights go.
func check_night_lights(game) -> void:
	var NightLights = load("res://scripts/core/night_lights.gd")
	var at = game.stage.at(300)
	var fire = game.Props.campfire(game)
	fire.position = at
	var police = game.Props.course_car("police")
	game.add_child(police)
	police.position = at + Vector3(8, 0, 0)
	var judges = game.Props.judges_car()
	game.add_child(judges)
	judges.position = at + Vector3(-8, 0, 0)
	var grill = load("res://scripts/camp/grill_model.gd").build(game)
	grill.position = at + Vector3(0, 0, 6)
	load("res://scripts/camp/grill_model.gd").set_fire(grill, 1.0, 1.0)
	var far_fire = game.Props.campfire(game)
	far_fire.position = at + Vector3(0, 0, 400)
	var lights = NightLights.new()
	lights.update(self, false, at, 0.5)
	check(fire.get_node_or_null(NightLights.LIGHT_NAME) == null, "no fire light by day")
	lights.update(self, true, at, 0.5)
	check(fire.get_node_or_null(NightLights.LIGHT_NAME) is OmniLight3D, "a campfire lights up at night")
	check(grill.get_node("GrillFire").get_node_or_null(NightLights.LIGHT_NAME) is OmniLight3D, "a lit grill glows at night")
	check(police.get_node("BeaconBlue").get_node_or_null(NightLights.LIGHT_NAME) is OmniLight3D and police.get_node("BeaconRed").get_node_or_null(NightLights.LIGHT_NAME) is OmniLight3D, "police beacons light up at night")
	var amber = judges.find_child("AmberBeacon", true, false)
	check(amber != null and amber.get_node_or_null(NightLights.LIGHT_NAME) is OmniLight3D, "the judges' amber beacon lights up at night")
	check(far_fire.get_node_or_null(NightLights.LIGHT_NAME) == null, "a fire far from the camera stays unlit")
	for i in range(NightLights.BUDGET.fire + 2):
		var extra = game.Props.campfire(game)
		extra.position = at + Vector3(i * 0.5, 0, -20)
	lights.update(self, true, at, 0.5)
	var lit = 0
	for node in get_nodes_in_group(NightLights.GROUP):
		if node.get_meta("night_light") in ["fire", "grill"] and node.get_node_or_null(NightLights.LIGHT_NAME) != null:
			lit += 1
	check(lit == NightLights.BUDGET.fire, "only the nearest fires are lit (%d)" % lit)
	lights.update(self, false, at, 0.5)
	await process_frame
	check(fire.get_node_or_null(NightLights.LIGHT_NAME) == null and police.get_node("BeaconBlue").get_node_or_null(NightLights.LIGHT_NAME) == null, "the lights go out by day")
