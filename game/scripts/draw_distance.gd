extends RefCounted
# Local graphics preference; the simulation and room snapshots are unaffected.
# Modes keep their saved numbers (LOW was added last); ORDER is how the menu
# lists them, from cheapest to richest.
const NEAR = 0
const MEDIUM = 1
const FAR = 2
const LOW = 3
const ORDER = [LOW, NEAR, MEDIUM, FAR]
const LABELS = ["Близко", "Средне", "Далеко", "Минимум"]
# Sun shadow reach (m) and cascade count per mode. Every shadow caster is drawn
# once more per cascade, so phones (MEDIUM by default) use two short ones and
# LOW has none.
const SHADOW_DISTANCE = [50.0, 70.0, 120.0, 0.0]
const SHADOW_SPLITS = [2, 2, 4, 0]
# Authored visibility ranges are multiplied by this; 0 removes them (FAR).
const RANGE_SCALE = [0.7, 1.0, 0.0, 0.45]
# Share of the window resolution the 3D scene is drawn at (UI stays sharp).
const RENDER_SCALE = [1.0, 1.0, 1.0, 0.6]
# Auto quality: below this average frame rate (over WATCH_SECONDS, after
# WARMUP_SECONDS of play) the game steps one mode down, unless the player
# picked a mode themselves.
const SLOW_FPS = 20.0
const WATCH_SECONDS = 3.0
const WARMUP_SECONDS = 4.0
var mode = FAR
var has_saved_choice = false
var settings_path = "user://draw_distance.json"
# The browser draws WebGL without the graphics card (--gpu-software).
var software = false
var _watch_time = 0.0
var _watch_frames = 0
var _played = 0.0
var _warned = false

func load_settings(is_mobile: bool = false) -> void:
	has_saved_choice = false
	software = "--gpu-software" in OS.get_cmdline_user_args()
	apply_device_default(is_mobile)
	if not FileAccess.file_exists(settings_path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(settings_path))
	if data is Dictionary and data.get("mode") is float and data.mode == int(data.mode) and data.mode >= NEAR and data.mode <= LOW:
		mode = int(data.mode)
		has_saved_choice = true

func apply_device_default(is_mobile: bool) -> void:
	if not has_saved_choice:
		mode = LOW if software else (MEDIUM if is_mobile else FAR)

func save_settings() -> Error:
	has_saved_choice = true
	var file = FileAccess.open(settings_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"mode": mode}))
	return OK

func apply(world: Node) -> void:
	var host = world.get_parent() if world != null else null
	if host != null:
		for light in host.get_children():
			if light is DirectionalLight3D:
				apply_shadows(light)
		if host.is_inside_tree():
			var viewport = host.get_viewport()
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			viewport.scaling_3d_scale = RENDER_SCALE[mode]
	# Record authored ranges once, so repeated switches never compound the scale.
	for node in world.find_children("*", "GeometryInstance3D", true, false):
		if not node.has_meta("draw_distance_base_end"):
			node.set_meta("draw_distance_base_end", node.visibility_range_end)
			node.set_meta("draw_distance_base_margin", node.visibility_range_end_margin)
		var scale: float = RANGE_SCALE[mode]
		node.visibility_range_end = float(node.get_meta("draw_distance_base_end")) * scale
		node.visibility_range_end_margin = float(node.get_meta("draw_distance_base_margin")) * scale

func apply_shadows(sun: DirectionalLight3D) -> void:
	sun.shadow_enabled = SHADOW_SPLITS[mode] > 0
	if not sun.shadow_enabled:
		return
	sun.directional_shadow_max_distance = SHADOW_DISTANCE[mode]
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if SHADOW_SPLITS[mode] == 4 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS

# The next cheaper mode, or -1 at the bottom.
func cheaper(from: int) -> int:
	var index = ORDER.find(from)
	return ORDER[index - 1] if index > 0 else -1

# Called every frame while playing. Returns a message for the player when the
# quality was lowered (or should be), otherwise "".
func watch(delta: float) -> String:
	if software and not _warned:
		_warned = true
		return "Браузер рисует игру без видеокарты, поэтому графика на минимуме. Включите аппаратное ускорение в настройках браузера и обновите видеодрайвер."
	_played += delta
	if _played < WARMUP_SECONDS or mode == LOW:
		return ""
	_watch_time += delta
	_watch_frames += 1
	if _watch_time < WATCH_SECONDS:
		return ""
	var fps = _watch_frames / _watch_time
	_watch_time = 0.0
	_watch_frames = 0
	if fps >= SLOW_FPS:
		return ""
	if has_saved_choice:
		if _warned:
			return ""
		_warned = true
		return "Игра идёт медленно (%d FPS). Попробуйте графику «Минимум» в паузе (Esc)." % int(fps)
	mode = cheaper(mode)
	_played = 0.0
	return "Игра шла медленно (%d FPS) — графика снижена до «%s». Изменить можно в паузе (Esc)." % [int(fps), LABELS[mode]]
