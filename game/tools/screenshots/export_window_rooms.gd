extends SceneTree
# Buildings with rooms behind their windows (window_rooms.gd), by day and night:
#   xvfb-run -a godot --path game --rendering-method gl_compatibility --script res://tools/screenshots/export_window_rooms.gd -- out_dir stage prefix[,prefix] [count] [day,night] [distance] [facade] [lateral] [height]
# stage: index in data/stages.json (1 winter, 2 Provence, 6 Поречье, 7 quarry).
# Nodes whose names start with a prefix are shot from `distance` m in front of
# their facade; facade is the local z direction the front faces (-1 village
# houses, 1 izbas and chalets).
var game

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args = OS.get_cmdline_user_args()
	var out = args[0] if args.size() > 0 else "/tmp"
	var stage = int(args[1]) if args.size() > 1 else 2
	var prefixes = (args[2] if args.size() > 2 else "VillageHouse_").split(",")
	var count = int(args[3]) if args.size() > 3 else 3
	var times = args[4].split(",") if args.size() > 4 else PackedStringArray(["day", "night"])
	var distance = float(args[5]) if args.size() > 5 else 6.0
	var facade = float(args[6]) if args.size() > 6 else -1.0
	var lateral = float(args[7]) if args.size() > 7 else 1.4
	var height = float(args[8]) if args.size() > 8 else 2.2
	root.size = Vector2i(1280, 720)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.select_stage(stage)
	game.start_game()
	for layer in game.find_children("*", "CanvasLayer", true, false):
		layer.visible = false
	var targets: Array = []
	for node in game.stage.find_children("*", "Node3D", true, false):
		for prefix in prefixes:
			if str(node.name).begins_with(prefix) and not node.get_meta("room", false):
				targets.append(node)
				break
	print("targets: ", targets.size())
	targets = targets.slice(0, count)
	for time in times:
		game.sky_weather.set_conditions(time, "sun")
		for i in range(targets.size()):
			var node: Node3D = targets[i]
			var basis: Basis = node.global_transform.basis
			var at: Vector3 = node.global_position
			game.camera.fov = 60
			game.camera.global_position = at + basis * Vector3(lateral, height - 0.3, facade * distance)
			game.camera.look_at(at + basis * Vector3(0, height, 0))
			for frame in range(8):
				game.sky_weather._process(0.1)
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/%s_%s.png" % [out, node.name, time])
	quit()
