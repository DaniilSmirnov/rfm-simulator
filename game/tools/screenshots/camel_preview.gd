extends SceneTree
# Stand-alone views of the bactrian camel model (camel_model.gd), every pose.
# Run: xvfb-run godot --path game --rendering-method gl_compatibility
# --script res://tools/screenshots/camel_preview.gd -- <out_dir>
const CamelModel = preload("res://scripts/stages/canyon/camel_model.gd")

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var args = OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://"
	var viewport = SubViewport.new()
	viewport.size = Vector2i(960, 640)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var env = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("c9bfa8")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("b8b0a0")
	env.environment.ambient_light_energy = 0.7
	viewport.add_child(env)
	var sun = DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.6, 0)
	viewport.add_child(sun)
	var ground = MeshInstance3D.new()
	ground.mesh = PlaneMesh.new()
	ground.mesh.size = Vector2(20, 20)
	viewport.add_child(ground)
	var camel = CamelModel.build(false)
	viewport.add_child(camel)
	var camera = Camera3D.new()
	camera.fov = 40
	viewport.add_child(camera)
	camera.current = true
	for pose_name in ["Stand", "Graze", "StepA"]:
		CamelModel.pose(camel, pose_name)
		for view in [["side", Vector3(6.5, 1.5, -0.3)], ["front", Vector3(3.5, 2.2, -5.0)], ["back", Vector3(-3.0, 2.4, 4.5)]]:
			if pose_name != "Stand" and view[0] != "side":
				continue
			camera.position = view[1]
			camera.look_at(Vector3(0, 1.3, -0.3))
			for frame in range(4):
				await process_frame
			await RenderingServer.frame_post_draw
			viewport.get_texture().get_image().save_png(out + "/camel-%s-%s.png" % [pose_name.to_lower(), view[0]])
	quit()
