extends SceneTree
const Props = preload("res://scripts/props.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280, 720)
	var world = Node3D.new()
	root.add_child(world)
	var env = WorldEnvironment.new()
	var settings = Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("283742")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = 0.7
	env.environment = settings
	world.add_child(env)
	var light = DirectionalLight3D.new()
	world.add_child(light)
	light.rotation_degrees = Vector3(-40, -25, 0)
	Props.box(world, Vector3(0, -0.12, 0), Vector3(9, 0.2, 4), Color("69765b"))
	for i in range(4):
		var avatar = Props.player_avatar(i)
		world.add_child(avatar)
		avatar.position.x = (i - 1.5) * 1.5
		avatar.rotation.y = PI
		if i == 1:
			avatar.get_node("RightArm").rotation.x = 1.2
			avatar.get_node("RightArm/BeerCan").show()
		if i == 2:
			avatar.get_node("RightArm").rotation.x = 1.0
			avatar.get_node("RightArm/Skewer").show()
	var camera = Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0.3, 2.3, 8)
	camera.look_at(Vector3(0, 1.0, 0))
	camera.fov = 40
	camera.current = true
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png("../character-preview.png") == OK)
	quit()
