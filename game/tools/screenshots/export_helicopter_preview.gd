extends SceneTree
# Isolated studio render: regenerate the catalog thumbnail and inspect cargo.
const Props = preload("res://scripts/core/props.gd")
var viewport: SubViewport
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(960, 540)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world = Node3D.new()
	viewport.add_child(world)
	var env = WorldEnvironment.new()
	var environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("253b4b")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d4e5ed")
	environment.ambient_light_energy = 0.6
	env.environment = environment
	world.add_child(env)
	var light = DirectionalLight3D.new()
	world.add_child(light)
	light.rotation_degrees = Vector3(-45, -35, 0)
	light.light_energy = 1.2
	var car = Props.player_car(11)
	world.add_child(car)
	var camera = Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(6, 4.7, -7)
	camera.look_at(Vector3(0, 1.3, 0))
	camera.fov = 38
	camera.current = true
	await capture("res://textures/previews/car_11.webp")
	Props.update_player_trunk(car, true, [true,true,true,true,true,true], 1)
	await capture("res://../docs/screenshots/helicopter-cargo.webp")
	quit()
func capture(path: String) -> void:
	for i in range(6): await process_frame
	RenderingServer.force_draw()
	var image = viewport.get_texture().get_image()
	var error = image.save_webp(path, false, 0.9)
	if error != OK:
		push_error("Cannot save " + path)
		quit(1)
	print("HELICOPTER PREVIEW ", path)
