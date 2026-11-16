extends SceneTree
# Contact sheet of the camp mangal, for reviewing its model by eye:
#   xvfb-run godot --path game --script res://tools/screenshots/export_grill_sheet.gd -- [out.png] [cell=480x340]
# Rows: cold and empty by day; burning with flames by day; glowing coals with
# meat and mushroom skewers at dusk. Columns: three-quarter, side, end, top.
var CELL = Vector2i(480, 340)
const VIEWS = [Vector3(1.25, 1.0, 1.35), Vector3(0.0, 0.55, 1.75), Vector3(1.8, 0.75, 0.15), Vector3(0.25, 1.5, 0.55)]
const STATES = ["cold", "flames", "coals"]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args = OS.get_cmdline_user_args()
	var out = args[0] if args.size() > 0 and not args[0].begins_with("cell=") else "res://../docs/screenshots/grill.png"
	for arg in args:
		if arg.begins_with("cell="):
			var size = arg.substr(5).split("x")
			CELL = Vector2i(int(size[0]), int(size[1]))
	var props = load("res://scripts/core/props.gd")
	var grill_model = load("res://scripts/camp/grill_model.gd")
	var world = Node3D.new()
	root.add_child(world)
	var env = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.add_child(env)
	var sun = DirectionalLight3D.new()
	sun.rotation = Vector3(-0.85, 0.65, 0)
	sun.shadow_enabled = true
	world.add_child(sun)
	props.box(world, Vector3(0, -0.05, 0), Vector3(20, 0.1, 20), Color("6f7a68"))
	var viewport = SubViewport.new()
	viewport.size = CELL
	viewport.world_3d = world.get_world_3d()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	var camera = Camera3D.new()
	camera.fov = 40
	viewport.add_child(camera)
	camera.current = true
	var sheet = Image.create(CELL.x * VIEWS.size(), CELL.y * STATES.size(), false, Image.FORMAT_RGBA8)
	for row in range(STATES.size()):
		var state: String = STATES[row]
		var dusk = state == "coals"
		env.environment.background_color = Color("1d2433") if dusk else Color("b9c7cc")
		env.environment.ambient_light_color = Color("5d6f9c") if dusk else Color("9aa7ad")
		env.environment.ambient_light_energy = 0.4 if dusk else 0.9
		sun.light_energy = 0.2 if dusk else 1.2
		var grill: Node3D = props.grill(world)
		var light: OmniLight3D = null
		grill_model.set_servings(grill, 0)
		match state:
			"flames":
				grill_model.set_fire(grill, 0.6, 0.9, 0.4)
			"coals":
				grill.set_meta("mushrooms", 3)
				grill_model.set_servings(grill, 6)
				grill_model.set_fire(grill, 1.0, 0.0, 0.4)
				light = OmniLight3D.new()
				light.light_color = Color("ff7c32")
				light.light_energy = 1.3
				light.omni_range = 6.0
				light.position = Vector3(0, 1.1, 0)
				grill.add_child(light)
		var centre = Vector3(0, 0.55, 0)
		for col in range(VIEWS.size()):
			camera.position = centre + VIEWS[col]
			camera.look_at(centre + Vector3(0, 0.12 if col == 3 else 0.0, 0))
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			for frame in range(3):
				await process_frame
			await RenderingServer.frame_post_draw
			var image = viewport.get_texture().get_image()
			image.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(image, Rect2i(Vector2i.ZERO, CELL), Vector2i(col * CELL.x, row * CELL.y))
		print("GRILL ", state, " size ", grill.get_node("Baked").mesh.get_aabb().size)
		grill.free()
	sheet.save_png(out)
	print("SHEET ", out)
	quit()
