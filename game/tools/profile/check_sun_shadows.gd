extends SceneTree
# GPU regression fixture: run with Compatibility/OpenGL, not --headless.
# A high canopy behind the walker must shade the ground in the near cascade.
const Distance = preload("res://scripts/core/draw_distance.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var scene = Node3D.new()
	root.add_child(scene)
	var env = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("8baabd")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.25
	scene.add_child(env)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color("c1bca0")
	var ground = MeshInstance3D.new()
	ground.mesh = PlaneMesh.new()
	ground.mesh.size = Vector2(200,200)
	ground.material_override = mat
	scene.add_child(ground)
	var roof = MeshInstance3D.new()
	roof.mesh = BoxMesh.new()
	roof.mesh.size = Vector3(30, 2, 30)
	roof.position = Vector3(-10,35,22)
	roof.material_override = mat
	scene.add_child(roof)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55,-25,0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	scene.add_child(sun)
	var cam = Camera3D.new()
	cam.position = Vector3(0,1.7,0)
	cam.rotation_degrees.x = -25
	scene.add_child(cam)
	root.size = Vector2i(640,400)
	var setting = Distance.new()
	var failures = 0
	for mode in [Distance.NEAR, Distance.MEDIUM, Distance.FAR]:
		setting.mode = mode
		for position in [Vector3(0, 1.7, 0), Vector3(0, 1.7, -4), Vector3(0, 4.5, 4)]:
			cam.position = position
			sun.shadow_enabled = false
			var lit = await sample_ground()
			if "--baseline" in OS.get_cmdline_user_args():
				sun.shadow_enabled = true
				sun.directional_shadow_max_distance = Distance.SHADOW_DISTANCE[mode]
				sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if mode == Distance.FAR else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			else:
				setting.apply_shadows(sun)
			var shaded = await sample_ground()
			var passed = shaded < lit * 0.7
			if not passed:
				failures += 1
			print("SUN SHADOW mode=%d camera=%s lit=%.3f shaded=%.3f %s" % [mode, position, lit, shaded, "PASS" if passed else "FAIL"])
	print("SUN SHADOW RESULT: %d failures" % failures)
	quit(1 if failures else 0)

func sample_ground() -> float:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var frame = root.get_texture().get_image()
	var total = 0.0
	for y in range(290, 310):
		for x in range(310, 330):
			total += frame.get_pixel(x, y).get_luminance()
	return total / 400.0
