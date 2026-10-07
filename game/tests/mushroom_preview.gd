extends SceneTree
const Props = preload("res://scripts/props.gd")
func _initialize() -> void:
	call_deferred("run")
func capture(path: String) -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image = root.get_texture().get_image()
	assert(image.save_png(path) == OK)
	return image
func run() -> void:
	root.size = Vector2i(800, 480)
	var world = Node3D.new()
	root.add_child(world)
	var env = WorldEnvironment.new()
	var settings = Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("283742")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = 0.8
	env.environment = settings
	world.add_child(env)
	var light = DirectionalLight3D.new()
	world.add_child(light)
	light.rotation_degrees = Vector3(-40, -25, 0)
	Props.box(world, Vector3(0, -0.12, 0), Vector3(8, 0.2, 3), Color("69765b"))
	var species = ["edible", "fly_agaric", "toadstool"]
	for i in range(3):
		var x = (i - 1) * 2.0
		Props.cylinder(world, Vector3(x, 0.38, 0), 0.10, 0.09, 0.75, Color("e7ddba"), 12)
		var cap = Props.faceted(world, Vector3(x, 0.93, 0), Vector3(1.25, 0.55, 1.25), Color.WHITE, 24, 12)
		Props.texture_mushroom_cap(cap, species[i])
		Props.label_3d(world, Vector3(x, 1.65, 0), ["Гриб", "Мухомор", "Поганка"][i], 28, 0.012, Color.WHITE)
	var camera = Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 3.6, 7)
	camera.look_at(Vector3(0, 0.8, 0))
	camera.fov = 48
	camera.current = true
	var effect = load("res://scripts/mushroom_effect.gd").new()
	effect.setup(world)
	var hud_layer = CanvasLayer.new()
	hud_layer.layer = 1
	world.add_child(hud_layer)
	var hud = ColorRect.new()
	hud.color = Color("ff6622")
	hud.position = Vector2(8, 8)
	hud.size = Vector2(80, 32)
	hud_layer.add_child(hud)
	DirAccess.make_dir_recursive_absolute("res://../preview-artifacts")
	var normal = await capture("res://../preview-artifacts/mushrooms-normal.png")
	effect.trigger(1)
	var inverted = await capture("res://../preview-artifacts/mushrooms-inverted.png")
	var a = normal.get_pixel(10, 250)
	var b = inverted.get_pixel(10, 250)
	var complemented = absf(a.r + b.r - 1) < 0.06 and absf(a.g + b.g - 1) < 0.06 and absf(a.b + b.b - 1) < 0.06
	var hud_unchanged = normal.get_pixel(20, 20).is_equal_approx(inverted.get_pixel(20, 20))
	print("MUSHROOM_RENDER normal=", a, " inverted=", b, " hud_unchanged=", hud_unchanged)
	quit(0 if complemented and hud_unchanged else 1)
