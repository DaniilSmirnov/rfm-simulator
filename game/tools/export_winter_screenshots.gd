extends SceneTree
# Actual game geometry and lighting; no promotional overlays or generated artwork.
# Run: xvfb-run godot --path game --rendering-method gl_compatibility --script res://tools/export_winter_screenshots.gd
var viewport: SubViewport
var camera: Camera3D
func _initialize() -> void: call_deferred("run")
func capture(path: String, size: Vector2i) -> void:
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	var image = viewport.get_texture().get_image()
	assert(image != null and not image.is_empty())
	assert(image.save_webp(path, false, 0.93) == OK)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	print("WINTER_SCREENSHOT ", path, " ", size)
static func frame_overview(stage, view: Camera3D) -> void:
	view.fov = 54
	view.far = 1100
	view.position = stage.at(205) + stage.side(205) * 2.0
	view.position.y = stage.ground(view.position) + 7.0
	view.look_at(stage.at(255) + Vector3(0, 1.0, 0))

func run() -> void:
	assert(DisplayServer.get_name() != "headless", "Screenshots require a real renderer")
	var game = load("res://main.tscn").instantiate()
	game.defer_world = true
	root.add_child(game)
	game.set_process(false)
	game.room.set_process(false)
	game.select_stage(1)
	game.stage.build()
	game.draw_distance.mode = game.draw_distance.FAR
	game.draw_distance.apply(game.stage)
	game.spectators.rebuild()
	viewport = SubViewport.new()
	viewport.world_3d = game.get_world_3d()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	camera = Camera3D.new()
	camera.fov = 54
	camera.far = 1100
	viewport.add_child(camera)
	camera.current = true
	DirAccess.make_dir_recursive_absolute("res://../docs/screenshots")
	var target: Vector3
	frame_overview(game.stage, camera)
	await capture("res://textures/previews/stage_1.webp", Vector2i(480, 240))
	await capture("res://textures/previews/backdrop_1.webp", Vector2i(1280, 720))
	await capture("res://../docs/screenshots/winter-overview.webp", Vector2i(1920, 1080))
	var racer = game.Props.rally_car(2)
	game.add_child(racer)
	var station = 390.0
	racer.position = game.stage.at(station)
	racer.position.y = game.stage.vehicle_ground(racer.position) + 0.06
	racer.rotation.y = atan2(-game.stage.direction(station).x, -game.stage.direction(station).z)
	target = racer.position + Vector3(0, 0.8, 0)
	camera.fov = 58
	camera.position = target + game.stage.direction(station) * 8 + game.stage.side(station) * 5
	camera.position.y = game.stage.ground(camera.position) + 2.0
	camera.look_at(target + Vector3(0, 0.5, 0))
	await capture("res://../docs/screenshots/winter-rally.webp", Vector2i(1920, 1080))
	racer.hide()
	var group: Dictionary = game.spectators.groups[4]
	target = group.table.position
	camera.position = target + game.stage.side(game.stage.road_s(target)) * -8 + game.stage.direction(game.stage.road_s(target)) * 7
	camera.position.y = game.stage.ground(camera.position) + 3.5
	camera.look_at(target + Vector3(0, 0.8, 0))
	await capture("res://../docs/screenshots/winter-camp.webp", Vector2i(1920, 1080))
	await game._shutdown_audio()
	quit()
