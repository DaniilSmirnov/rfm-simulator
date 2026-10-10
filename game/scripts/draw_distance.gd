extends RefCounted
# Local rendering preference; the simulation and room snapshots are unaffected.
const NEAR = 0
const MEDIUM = 1
const FAR = 2
const LABELS = ["Близко", "Средне", "Далеко"]
# Sun shadow reach (m) and cascade count per mode. Every shadow caster is drawn
# once more per cascade, so phones (MEDIUM by default) use two short ones.
const SHADOW_DISTANCE = [50.0, 70.0, 120.0]
const SHADOW_SPLITS = [2, 2, 4]
var mode = FAR
var has_saved_choice = false
var settings_path = "user://draw_distance.json"

func load_settings(is_mobile: bool = false) -> void:
	has_saved_choice = false
	apply_device_default(is_mobile)
	if not FileAccess.file_exists(settings_path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(settings_path))
	if data is Dictionary and data.get("mode") is float and data.mode == int(data.mode) and data.mode >= NEAR and data.mode <= FAR:
		mode = int(data.mode)
		has_saved_choice = true

func apply_device_default(is_mobile: bool) -> void:
	if not has_saved_choice:
		mode = MEDIUM if is_mobile else FAR

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
	# Record authored ranges once, so repeated switches never compound the scale.
	for node in world.find_children("*", "GeometryInstance3D", true, false):
		if not node.has_meta("draw_distance_base_end"):
			node.set_meta("draw_distance_base_end", node.visibility_range_end)
			node.set_meta("draw_distance_base_margin", node.visibility_range_end_margin)
		var scale = 0.7 if mode == NEAR else (0.0 if mode == FAR else 1.0)
		node.visibility_range_end = float(node.get_meta("draw_distance_base_end")) * scale
		node.visibility_range_end_margin = float(node.get_meta("draw_distance_base_margin")) * scale

func apply_shadows(sun: DirectionalLight3D) -> void:
	sun.directional_shadow_max_distance = SHADOW_DISTANCE[mode]
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if SHADOW_SPLITS[mode] == 4 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
