extends SceneTree
const Props = preload("res://scripts/props.gd")

func _initialize() -> void:
	call_deferred("run")

func snap(path: String) -> void:
	await create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func run() -> void:
	var world = Node3D.new()
	root.add_child(world)
	var environment = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("9fae9b")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("e6e1cc")
	env.ambient_light_energy = 0.55
	environment.environment = env
	world.add_child(environment)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	world.add_child(sun)
	Props.box(world, Vector3(0, -0.1, 0), Vector3(45, 0.2, 20), Color("6a7661"))
	for i in range(5):
		var car = Props.rally_car(i)
		world.add_child(car)
		car.position = Vector3((i - 2) * 5.4, 0, 0)
		car.rotation.y = -0.45
		Props.label_3d(world, car.position + Vector3(0, 2.6, 0), Props.RALLY_MODELS[i].name, 48, 0.012, Color("f5efdc"), PI)
	var camera = Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 6.5, -17)
	camera.look_at(Vector3(0, 0.8, 0))
	camera.current = true
	camera.fov = 48
	await snap("res://../rally-lineup.png")
	camera.fov = 58
	for i in range(5):
		var target = Vector3((i - 2) * 5.4, 0.9, 0)
		camera.position = target + Vector3(3.1, 2.3, -6.0)
		camera.look_at(target)
		await snap("res://../rally-model-%d.png" % i)
	world.queue_free()
	await process_frame
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.start_game()
	game.in_car = false
	game.walker = game.stage.clearings[0]
	game.view_yaw = 0
	game.place_table()
	game.place_chairs()
	game._update_camera(1.0)
	game._update_hud()
	game.drink_beer()
	game._update_drinking(0.8)
	game._update_hud()
	await snap("res://../beer-open.png")
	game._update_drinking(1.1)
	game._update_camera(0.1)
	game._update_hud()
	await snap("res://../beer-sip.png")
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	quit()
