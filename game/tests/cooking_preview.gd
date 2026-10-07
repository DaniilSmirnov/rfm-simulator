extends SceneTree
const Props = preload("res://scripts/props.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280, 720)
	var world = Node3D.new()
	root.add_child(world)
	var environment = WorldEnvironment.new()
	var settings = Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("283742")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("fff1d2")
	settings.ambient_light_energy = 0.7
	environment.environment = settings
	world.add_child(environment)
	var light = DirectionalLight3D.new()
	world.add_child(light)
	light.rotation_degrees = Vector3(-50, -25, 0)
	light.light_energy = 1.4
	Props.box(world, Vector3(0, -0.1, 0), Vector3(12, 0.2, 12), Color("647344"))
	var fire = Props.campfire(world)
	var pot = Props.cauldron(fire)
	var camera = Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(2.4, 3.2, 3.5)
	camera.look_at(Vector3(0, 0.95, 0))
	camera.fov = 40
	camera.current = true
	for view in [
		["empty", "empty", 0.0, 0],
		["cooking", "cooking", 0.5, 0],
		["ready", "ready", 1.0, 10],
		["half", "ready", 1.0, 5],
		["exhausted", "exhausted", 1.0, 0]
	]:
		Props.pose_cauldron(pot, view[1], view[2], view[3], 1.3)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var error = root.get_texture().get_image().save_png("../cooking-%s.png" % view[0])
		if error != OK:
			push_error("Cannot save cooking preview")
			quit(1)
			return
		print("COOKING PREVIEW: " + view[0])
	quit()
