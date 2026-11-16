extends SceneTree
# Rally crews in their cabin seen from 4 to 30 m, to check the occupants'
# detail levels (car_occupants.gd with_lods()) against the full mesh:
#   xvfb-run -a godot --path game --rendering-method gl_compatibility --script res://tools/screenshots/export_cabin_lods.gd -- out_dir
const DISTANCES = [4.0, 8.0, 15.0, 30.0]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args = OS.get_cmdline_user_args()
	var out = args[0] if args.size() > 0 else "/tmp"
	root.size = Vector2i(960, 540)
	var game = load("res://main.tscn").instantiate()
	game.defer_world = true
	root.add_child(game)
	await process_frame
	game.room.set_process(false)
	game.select_stage(0)
	game.rng.seed = 20261008
	await game.start_game()
	game.course.phase = "racing"
	game.spawn_clock = 999.0
	game.spawn_racer("pass")
	var racer = game.racers.back()
	racer.s = 400.0
	racer.node.position = game.race_at(racer.s)
	for frame in range(10):
		await process_frame
	game.set_process(false)
	for layer in game.find_children("*", "CanvasLayer", true, false):
		layer.visible = false
	var car: Node3D = racer.node
	var side: Vector3 = car.global_basis.x
	var forward: Vector3 = -car.global_basis.z
	for d in DISTANCES:
		var target = car.global_position + Vector3(0, 1.0, 0)
		game.camera.global_position = target + (side * 0.85 + forward * 0.5).normalized() * d + Vector3(0, 0.6 + d * 0.3, 0)
		game.camera.look_at(target)
		game.camera.fov = 40.0 if d > 10.0 else 60.0
		for frame in range(8):
			await process_frame
		var image = root.get_texture().get_image()
		# The car fills about the same share of the frame at every distance.
		image.save_png("%s/cabin_%02d.png" % [out, int(d)])
	quit()
