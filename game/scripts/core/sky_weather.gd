extends Node
# Time of day and weather on the stage: the sky, fog, ambient light and sun of
# data/stages.json, changed by the conditions picked on the stage card, plus
# falling rain or snow around the camera, headlights, fires and beacons at
# night (night_lights.gd) and the grip
# rain and snow take off the road (stage.weather_grip; the sound is in
# soundscape.gd).
# Rain falls only on stages without snow, snow only on snowy ones
# (stage.has_snow); sun and fog fit every stage. In a room the host's
# conditions are the room's: they reach guests as the "sky" world section.
const StageRegistry = preload("res://scripts/stages/stage_registry.gd")
const DAYTIMES = ["day", "night"]
const DAYTIME_LABELS = ["День", "Ночь"]
const WEATHERS = ["sun", "rain", "fog", "snow"]
const WEATHER_LABELS = ["Солнце", "Дождь", "Туман", "Снег"]
# Overcast sky of each wet or grey weather; the stage's own colours are mixed
# in by SKY_MIX so a canyon stays warmer than a winter pass.
const OVERCAST = {
	"rain": {"sky_top": "626c76", "sky_horizon": "9aa1a6", "ground_bottom": "4c5250", "ground_horizon": "9aa1a6", "ambient": "a3a8ab", "fog": "858d93"},
	"fog": {"sky_top": "a9b0b3", "sky_horizon": "c3c8c8", "ground_bottom": "8c918e", "ground_horizon": "c3c8c8", "ambient": "b8bcbb", "fog": "bfc4c4"},
	"snow": {"sky_top": "98a4b0", "sky_horizon": "d5dbe1", "ground_bottom": "a5adb5", "ground_horizon": "d5dbe1", "ambient": "c8d1db", "fog": "ccd3da"},
}
const SKY_MIX = 0.8
# Fog density and the sun's share of its stage energy per weather.
const FOG_DENSITY = {"sun": 0.0, "rain": 0.006, "fog": 0.022, "snow": 0.008}
const SUN_SHARE = {"sun": 1.0, "rain": 0.35, "fog": 0.45, "snow": 0.5}
const AMBIENT_ENERGY = {"sun": 0.0, "rain": 0.44, "fog": 0.46, "snow": 0.46}
# Night: a dark blue sky, a dim cold moon in place of the sun, fog that
# fades to the night sky instead of glowing on the horizon.
const NIGHT = {"sky_top": "070d1c", "sky_horizon": "1d2840", "ground_bottom": "0a0e14", "ground_horizon": "1d2840", "ambient": "5d6f9c", "fog": "141c2c"}
const NIGHT_AMBIENT_ENERGY = 0.3
const MOON = {"rotation": [-52, 140, 0], "color": "9fb4e0", "energy": 0.32}
# Falling particles: how many (full and cheap drawing), box around the camera
# (m), fall speed (m/s) and how long each one lives (s).
const FALL = {
	"rain": {"amount": 3000, "cheap": 1200, "box": Vector3(26, 1, 26), "height": 14.0, "speed": 19.0, "life": 1.0, "size": Vector2(0.03, 0.8), "color": Color(0.8, 0.85, 0.92, 0.5)},
	"snow": {"amount": 4000, "cheap": 1500, "box": Vector3(26, 1, 26), "height": 11.0, "speed": 1.6, "life": 7.5, "size": Vector2(0.13, 0.13), "color": Color(1, 1, 1, 0.95)},
}
const HEADLIGHT_RANGE = 60.0
# Grip the weather leaves on every surface (stage.weather_grip): a wet road,
# fresh snow over the packed snow and ice. Fog and night change only the view.
const GRIP = {"sun": 1.0, "rain": 0.8, "fog": 1.0, "snow": 0.85}
# The stage card shows the stage under the picked conditions: day and sun is
# its usual preview, every other combination a capture of the same view
# (tools/screenshots/condition_previews.gd).
const PREVIEW_DIR = "res://textures/previews/conditions"

var game: Node3D
var daytime = "day"
var weather = "sun"
var environment: WorldEnvironment
var sun: DirectionalLight3D
var fall: GPUParticles3D
var _last_camera = Vector3.INF
var _drift = Vector3.ZERO
# Campfires, grills and beacons that light their surroundings at night.
var night_lights = preload("res://scripts/core/night_lights.gd").new()

static func night_or_day(value) -> String:
	return str(value) if str(value) in DAYTIMES else "day"

# The weather a stage keeps: rain turns to sun on snowy stages, snow on the rest.
static func fits(value, snowy: bool) -> String:
	var name = str(value)
	if not name in WEATHERS or (name == "rain" and snowy) or (name == "snow" and not snowy):
		return "sun"
	return name

static func allowed(name: String, snowy: bool) -> bool:
	return fits(name, snowy) == name

static func preview_path(stage_index: int, time: String, kind: String) -> String:
	if time == "day" and kind == "sun":
		return "res://textures/previews/stage_%d.webp" % stage_index
	return "%s/stage_%d_%s_%s.webp" % [PREVIEW_DIR, stage_index, time, kind]

# Sky, fog, ambient and sun of stage `variant` under the given conditions:
# {"environment": {...}, "sun": {...}} with the stages.json fields.
static func look(variant: int, time: String, kind: String) -> Dictionary:
	var env: Dictionary = StageRegistry.section(variant, "environment").duplicate()
	var light: Dictionary = StageRegistry.section(variant, "sun").duplicate()
	if OVERCAST.has(kind):
		for key in OVERCAST[kind]:
			env[key] = Color(env[key]).lerp(Color(OVERCAST[kind][key]), SKY_MIX).to_html(false)
		env.fog_density = maxf(float(env.fog_density), FOG_DENSITY[kind])
		env.ambient_energy = AMBIENT_ENERGY[kind]
		env.fog_sky_affect = 1.0
		env.erase("sky_curve")
		light.energy = float(light.energy) * SUN_SHARE[kind]
	if time == "night":
		var grey = Color(env.fog).get_luminance()
		for key in NIGHT:
			env[key] = NIGHT[key]
		# Snow and fog stay lighter than the night sky: they catch the moon.
		if kind in ["fog", "snow"]:
			env.fog = Color(NIGHT.fog).lerp(Color(grey, grey, grey), 0.25).to_html(false)
		env.ambient_energy = NIGHT_AMBIENT_ENERGY
		light = MOON.duplicate()
		light.energy = float(MOON.energy) * (1.0 if kind == "sun" else 0.6)
	return {"environment": env, "sun": light}

func setup(owner: Node3D) -> void:
	game = owner
	name = "SkyWeather"

func snowy() -> bool:
	return game.stage != null and game.stage.has_snow

# Changes the conditions; the weather is fitted to the current stage.
func set_conditions(time, kind) -> void:
	var new_time = night_or_day(time)
	var new_weather = fits(kind, snowy())
	if new_time == daytime and new_weather == weather and environment != null:
		return
	daytime = new_time
	weather = new_weather
	rebuild()

# Rebuilt for every stage: its sky differs and the weather may no longer fit.
func rebuild() -> void:
	weather = fits(weather, snowy())
	if environment != null:
		environment.free()
		sun.free()
	if fall != null:
		fall.free()
		fall = null
	if game.stage != null:
		game.stage.weather_grip = GRIP[weather]
	var current = look(game.stage.variant if game.stage != null else 0, daytime, weather)
	environment = _environment(current.environment)
	game.add_child(environment)
	sun = _sun(current.sun)
	game.add_child(sun)
	game.world_environment = environment
	game.sunlight = sun
	if FALL.has(weather):
		fall = _fall(FALL[weather])
		game.add_child(fall)
	_last_camera = Vector3.INF
	_update_headlights()

func _environment(look_env: Dictionary) -> WorldEnvironment:
	var world = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky = Sky.new()
	var sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(look_env.sky_top)
	sky_mat.sky_horizon_color = Color(look_env.sky_horizon)
	sky_mat.ground_bottom_color = Color(look_env.ground_bottom)
	sky_mat.ground_horizon_color = Color(look_env.ground_horizon)
	if look_env.has("sky_curve"):
		sky_mat.sky_curve = float(look_env.sky_curve)
	if daytime == "night" or weather != "sun":
		# No bright sun disc in an overcast or night sky.
		sky_mat.sun_angle_max = 0.0
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(look_env.ambient)
	env.ambient_light_energy = float(look_env.ambient_energy)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = Color(look_env.fog)
	env.fog_density = float(look_env.fog_density)
	if look_env.has("fog_sky_affect"):
		env.fog_sky_affect = float(look_env.fog_sky_affect)
	world.environment = env
	return world

func _sun(light: Dictionary) -> DirectionalLight3D:
	var node = DirectionalLight3D.new()
	node.rotation_degrees = Vector3(light.rotation[0], light.rotation[1], light.rotation[2])
	node.light_color = Color(light.color)
	node.light_energy = float(light.energy)
	node.shadow_enabled = true
	game.draw_distance.apply_shadows(node)
	return node

# Rain streaks or snowflakes in a box over the camera; the box follows the
# camera (and runs ahead of it while driving), the drops stay in the world.
func _fall(spec: Dictionary) -> GPUParticles3D:
	var node = GPUParticles3D.new()
	node.name = "Weather"
	var cheap = game.mobile_mode or game.draw_distance.mode == game.draw_distance.LOW
	node.amount = int(spec.cheap if cheap else spec.amount)
	node.lifetime = float(spec.life)
	node.preprocess = float(spec.life)
	node.local_coords = false
	node.fixed_fps = 0
	node.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 50, 80))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = spec.box * 0.5
	process.direction = Vector3.DOWN
	process.spread = 4.0 if spec.speed > 5.0 else 25.0
	process.initial_velocity_min = spec.speed * 0.85
	process.initial_velocity_max = spec.speed * 1.15
	process.gravity = Vector3(0, -2.0, 0) if spec.speed > 5.0 else Vector3(0, -0.15, 0)
	node.process_material = process
	var mesh = QuadMesh.new()
	mesh.size = spec.size
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = spec.color if daytime == "day" else spec.color.darkened(0.55)
	# Rain streaks stay upright; flakes face the camera.
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y if spec.speed > 5.0 else BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if spec.speed <= 5.0:
		mat.albedo_texture = _flake()
	mesh.material = mat
	node.draw_pass_1 = mesh
	node.position = _fall_origin(spec)
	return node

# A soft round flake: white in the middle, clear at the edge.
static func _flake() -> GradientTexture2D:
	var gradient = Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var texture = GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 16
	texture.height = 16
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture

func _fall_origin(spec: Dictionary) -> Vector3:
	var camera: Camera3D = game.camera
	var at = camera.global_position if camera != null and camera.is_inside_tree() else Vector3.ZERO
	return at + _drift + Vector3(0, spec.height, 0)

func _process(delta: float) -> void:
	if game == null:
		return
	if fall != null and game.camera != null and game.camera.is_inside_tree():
		var at = game.camera.global_position
		if _last_camera != Vector3.INF and delta > 0.0:
			# Lead the box by how far the camera moves while a drop falls,
			# so a car at speed drives into falling rain, not out of it.
			var spec: Dictionary = FALL[weather]
			var lead = (at - _last_camera) / delta * minf(float(spec.life) * 0.6, 2.0)
			lead.y = 0
			_drift = _drift.lerp(lead.limit_length(30.0), minf(1.0, delta * 3.0))
		_last_camera = at
		fall.position = _fall_origin(FALL[weather])
	_update_headlights()
	var camera: Camera3D = game.camera
	if camera != null and camera.is_inside_tree():
		night_lights.update(get_tree(), daytime == "night", camera.global_position, delta)

# Cars on the stage switch their lights on at night: the player's and those
# of the other room members.
func _update_headlights() -> void:
	var cars: Array = []
	if game.car != null and is_instance_valid(game.car):
		cars.append(game.car)
	if game.room != null:
		for peer in game.room.peers.values():
			if peer is Dictionary and peer.get("car") is Node3D and is_instance_valid(peer.car):
				cars.append(peer.car)
	for car in cars:
		var lights = car.get_node_or_null("Headlights")
		if daytime == "night" and lights == null and car.is_inside_tree():
			car.add_child(headlights())
		elif daytime != "night" and lights != null:
			lights.free()

static func headlights() -> SpotLight3D:
	var light = SpotLight3D.new()
	light.name = "Headlights"
	light.position = Vector3(0, 0.75, -2.3)
	light.rotation_degrees = Vector3(-7, 0, 0)
	light.light_color = Color("fff2d6")
	light.light_energy = 9.0
	light.spot_range = HEADLIGHT_RANGE
	light.spot_angle = 38.0
	light.spot_attenuation = 0.5
	light.shadow_enabled = false
	return light

# ---------------------------------------------------------------- room

func snapshot() -> Dictionary:
	return {"time": daytime, "weather": weather}

func apply_snapshot(data) -> void:
	if data is Dictionary:
		set_conditions(data.get("time", "day"), data.get("weather", "sun"))
