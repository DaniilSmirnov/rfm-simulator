extends RefCounted
# The stage card's preview under every time of day and weather the stage
# offers: the same camera as its day-and-sun preview (stage_<N>.webp),
# re-rendered under each other combination into
# SkyWeather.preview_path(N, time, weather). The preview tools switch to it
# with `-- --conditions` and then skip their other captures; one command runs
# them all: node scripts/export-condition-previews.mjs
const SkyWeather = preload("res://scripts/core/sky_weather.gd")
const QUALITY = 0.8
const SETTLE_FRAMES = 8
# Rain lives a second: at the few frames a second of software rendering it
# would fall through the picture between two frames.
const TIME_SCALE = 0.05

static func requested() -> bool:
	return "--conditions" in OS.get_cmdline_user_args()

# The stage index of a stage card preview path, or -1 for any other capture.
static func stage_of(path: String) -> int:
	var name = path.get_file().get_basename()
	if not path.begins_with("res://textures/previews/") or not name.begins_with("stage_"):
		return -1
	return name.trim_prefix("stage_").to_int()

static func capture_all(tree: SceneTree, game: Node, viewport: SubViewport, stage_index: int) -> void:
	var sky = game.sky_weather
	var camera = viewport.get_camera_3d()
	# Rain, snow and the lit fires follow the game camera: put it at the shot.
	if game.camera != null:
		game.camera.global_transform = camera.global_transform
	DirAccess.make_dir_recursive_absolute(SkyWeather.PREVIEW_DIR)
	Engine.time_scale = TIME_SCALE
	for time in SkyWeather.DAYTIMES:
		for weather in SkyWeather.WEATHERS:
			if (time == "day" and weather == "sun") or not SkyWeather.allowed(weather, sky.snowy()):
				continue
			sky.set_conditions(time, weather)
			viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			for frame in range(SETTLE_FRAMES):
				await tree.process_frame
			await RenderingServer.frame_post_draw
			var path = SkyWeather.preview_path(stage_index, time, weather)
			var error = viewport.get_texture().get_image().save_webp(path, false, QUALITY)
			print("CONDITION_PREVIEW ", path, " ", "ok" if error == OK else "error %d" % error)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	Engine.time_scale = 1.0
	sky.set_conditions("day", "sun")
