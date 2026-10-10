extends SceneTree
# Contact sheet of every vehicle model, for reviewing car geometry by eye:
#   xvfb-run godot --path game --script res://tools/export_car_sheet.gd -- [out.png] [player|rally|all] [spin] [only=0,2] [cell=360x220] [views=fq,side,rq,front,rear,top,low]
# Each car is shown from front-three-quarter, side and rear-three-quarter.
# "spin" drives every car 0.3 m before capturing, so frozen wheels stand out.
var CELL = Vector2i(360, 220)
const NAMED_VIEWS = {
	"fq": Vector3(4.4, 1.7, -4.6), "side": Vector3(6.2, 1.1, 0.0), "rq": Vector3(-4.4, 2.0, 4.8),
	"front": Vector3(0.0, 1.2, -6.4), "rear": Vector3(0.0, 1.4, 6.4), "top": Vector3(0.6, 6.4, 0.2),
	"low": Vector3(3.2, 0.25, -2.2),
}
var VIEWS: Array = [NAMED_VIEWS.fq, NAMED_VIEWS.side, NAMED_VIEWS.rq]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args = OS.get_cmdline_user_args()
	var out = args[0] if args.size() > 0 else "res://../docs/screenshots/cars.png"
	var which = args[1] if args.size() > 1 else "all"
	var spin = "spin" in args
	var only: Array = []
	for arg in args:
		if arg.begins_with("only="):
			for part in arg.substr(5).split(","):
				only.append(int(part))
		elif arg.begins_with("views="):
			VIEWS = []
			for part in arg.substr(6).split(","):
				VIEWS.append(NAMED_VIEWS[part])
		elif arg.begins_with("cell="):
			var size = arg.substr(5).split("x")
			CELL = Vector2i(int(size[0]), int(size[1]))
	var props = load("res://scripts/props.gd")
	var builders: Array = []
	if which in ["player", "all"]:
		for i in range(props.PLAYER_MODELS.size()):
			if only.is_empty() or i in only:
				builders.append(func(): return props.player_car(i))
	if which in ["rally", "all"]:
		for i in range(props.RALLY_MODELS.size()):
			if only.is_empty() or i in only:
				builders.append(func(): return props.rally_car(i))
		builders.append(func(): return props.course_car("police"))
	var world = Node3D.new()
	root.add_child(world)
	var env = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("b9c7cc")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("9aa7ad")
	env.environment.ambient_light_energy = 0.9
	world.add_child(env)
	var sun = DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.7, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	world.add_child(sun)
	props.box(world, Vector3(0, -0.05, 0), Vector3(40, 0.1, 40), Color("6f7a68"))
	var viewport = SubViewport.new()
	viewport.size = CELL
	viewport.world_3d = world.get_world_3d()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	var camera = Camera3D.new()
	camera.fov = 42
	viewport.add_child(camera)
	camera.current = true
	var sheet = Image.create(CELL.x * VIEWS.size(), CELL.y * builders.size(), false, Image.FORMAT_RGBA8)
	for row in range(builders.size()):
		var car: Node3D = builders[row].call()
		world.add_child(car)
		if spin:
			props.animate_wheels(car)
			car.position.z -= 0.3
			props.animate_wheels(car)
		var aabb = _bounds(car)
		var centre = aabb.get_center()
		var reach = maxf(aabb.size.z, 4.2) / 4.6
		for col in range(VIEWS.size()):
			camera.position = centre + VIEWS[col] * reach
			camera.look_at(centre)
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			for frame in range(3):
				await process_frame
			await RenderingServer.frame_post_draw
			var image = viewport.get_texture().get_image()
			image.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(image, Rect2i(Vector2i.ZERO, CELL), Vector2i(col * CELL.x, row * CELL.y))
		print("CAR ", row, " ", car.get_meta("model", car.name), " size ", aabb.size)
		car.free()
	sheet.save_png(out)
	print("SHEET ", out)
	quit()

static func _bounds(node: Node3D) -> AABB:
	var result = AABB()
	var first = true
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result
