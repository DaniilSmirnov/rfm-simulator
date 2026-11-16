extends SceneTree
# Close-ups of the furnished village rooms behind see-through windows
# (village_rooms.gd), by day and by night:
#   xvfb-run -a godot --path game --rendering-method gl_compatibility --script res://tools/screenshots/export_glass_rooms.gd -- out_dir [count] [day,night]
var game

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args = OS.get_cmdline_user_args()
	var out = args[0] if args.size() > 0 else "/tmp"
	var count = int(args[1]) if args.size() > 1 else 2
	root.size = Vector2i(1280, 720)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.select_stage(2)
	game.start_game()
	for layer in game.find_children("*", "CanvasLayer", true, false):
		layer.visible = false
	var houses: Array = []
	for node in game.stage.find_children("VillageHouse_*", "Node3D", true, false):
		if node.get_meta("room", false):
			houses.append(node)
	print("furnished houses: ", houses.size())
	var times = args[2].split(",") if args.size() > 2 else PackedStringArray(["day", "night"])
	for time in times:
		game.sky_weather.set_conditions(time, "sun")
		for i in range(mini(count, houses.size())):
			var house: Node3D = houses[i]
			var panes = house.find_children("WindowGlass", "MeshInstance3D", true, false)
			if panes.is_empty():
				continue
			var pane: Node3D = panes[0]
			var basis: Basis = house.global_transform.basis
			var at: Vector3 = pane.global_position
			game.camera.fov = 58
			game.camera.global_position = at + basis * Vector3(0.5, 0.2, -1.6)
			game.camera.look_at(at + basis * Vector3(0, -0.5, 3.0))
			for frame in range(10):
				game.sky_weather._process(0.1)
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/room_%d_%s.png" % [out, i, time])
			game.camera.global_position = at + basis * Vector3(-3.5, 0.6, -7.5)
			game.camera.look_at(at + basis * Vector3(0, -0.2, 0.5))
			for frame in range(4):
				game.sky_weather._process(0.1)
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/street_%d_%s.png" % [out, i, time])
	quit()
