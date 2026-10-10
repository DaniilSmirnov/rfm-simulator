extends SceneTree
# Render load of one stage during a race, from the chase camera:
#   xvfb-run godot --rendering-driver opengl3 --path game --script res://tools/profile_render.gd -- <stage> [near|medium|far] [noshadow]
# Prints RenderingServer draw calls / objects / primitives (60-frame mean)
# and which subtrees own the visible surfaces, so a regression points at its
# source. Needs a real renderer; numbers from a software GL are for comparing
# before/after, not device frame rates. See docs/RENDER_PERFORMANCE.md.
const MODES = {"near": 0, "medium": 1, "far": 2}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args = OS.get_cmdline_user_args()
	var stage_index = int(args[0]) if args.size() > 0 else 0
	var distance = args[1] if args.size() > 1 else "medium"
	root.size = Vector2i(1280, 720)
	var game = load("res://main.tscn").instantiate()
	game.defer_world = false
	root.add_child(game)
	await process_frame
	game.room.set_process(false)
	game.select_stage(stage_index)
	game.rng.seed = 20261008
	await game.start_game()
	game.draw_distance.mode = MODES.get(distance, 1)
	game.draw_distance.apply(game.stage)
	if "noshadow" in args:
		game.sunlight.shadow_enabled = false
	game.course.phase = "racing"
	game.spawn_clock = 999.0
	for i in range(8):
		game.spawn_racer("pass")
		var racer = game.racers.back()
		racer.s = 120.0 + i * 25.0
		racer.node.position = game.race_at(racer.s)
	for frame in range(40):
		await process_frame
	var keys = {
		"draw_calls": RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME,
		"objects": RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME,
		"primitives": RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME,
	}
	var sums = {}
	for key in keys:
		sums[key] = 0
	for frame in range(60):
		await process_frame
		for key in keys:
			sums[key] += RenderingServer.get_rendering_info(keys[key])
	var line = "RENDER_PROFILE stage=%d mode=%s" % [stage_index, distance]
	for key in keys:
		line += " %s=%d" % [key, sums[key] / 60]
	print(line)
	print("RENDER_OWNERS " + _owners(game))
	if "census" in args:
		_census(game)
	quit()

# Visible surfaces in the camera frustum, grouped by the first two named
# ancestors (one surface is roughly one draw call per pass).
func _owners(game: Node) -> String:
	var camera: Camera3D = game.camera
	var planes = camera.get_frustum()
	var owners: Dictionary = {}
	for node in game.find_children("*", "GeometryInstance3D", true, false):
		if not node.is_visible_in_tree():
			continue
		var box: AABB = node.global_transform * node.get_aabb()
		var inside = true
		for plane in planes:
			if plane.distance_to(box.get_support(-plane.normal)) > 0:
				inside = false
				break
		var reach = camera.global_position.distance_to(box.get_center())
		if not inside or (node.visibility_range_end > 0 and reach > node.visibility_range_end + node.visibility_range_end_margin):
			continue
		var surfaces = 1
		if node is MeshInstance3D and node.mesh != null:
			surfaces = node.mesh.get_surface_count()
		elif node is MultiMeshInstance3D and node.multimesh != null and node.multimesh.mesh != null:
			surfaces = node.multimesh.mesh.get_surface_count()
		var names: Array = []
		for part in str(game.get_path_to(node)).split("/"):
			if not part.begins_with("@"):
				names.append(part.rstrip("0123456789_"))
			if names.size() == 2:
				break
		var key = "/".join(names) if not names.is_empty() else "%s<%s>" % [node.get_parent().name.rstrip("0123456789_").replace("@", ""), node.mesh.get_class() if node is MeshInstance3D and node.mesh != null else node.get_class()]
		owners[key] = owners.get(key, 0) + surfaces
	var order = owners.keys()
	order.sort_custom(func(a, b): return owners[a] > owners[b])
	var text = ""
	for key in order.slice(0, 16):
		text += "%s:%d " % [key, owners[key]]
	return text.strip_edges()

# Every visible geometry node regardless of the camera, by owner (debugging).
func _census(game: Node) -> void:
	var total = 0
	var owners: Dictionary = {}
	for node in game.get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		if not node.is_visible_in_tree():
			continue
		total += 1
		var key = str(node.get_parent().name).rstrip("0123456789_").replace("@", "") + "/" + node.get_class()
		owners[key] = owners.get(key, 0) + 1
	var order = owners.keys()
	order.sort_custom(func(a, b): return owners[a] > owners[b])
	var text = "RENDER_CENSUS total=%d" % total
	for key in order.slice(0, 20):
		text += " %s:%d" % [key, owners[key]]
	print(text)
