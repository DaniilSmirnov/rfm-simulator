extends SceneTree
# Actual game geometry and lighting for the "Финский лес" stage menu art and docs.
# Run: xvfb-run godot --path game --rendering-method gl_compatibility --script res://tools/export_finnish_forest_screenshots.gd
var viewport: SubViewport
var camera: Camera3D
func _initialize() -> void: call_deferred("run")

func capture(path: String, size: Vector2i) -> void:
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	var image = viewport.get_texture().get_image()
	assert(image != null and not image.is_empty())
	assert(image.save_webp(path, false, 0.9) == OK)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	print("FINNISH_FOREST_SCREENSHOT ", path, " ", size)

func aim(position: Vector3, target: Vector3, fov: float = 56.0) -> void:
	camera.fov = fov
	camera.position = position
	camera.look_at(target)

func run() -> void:
	assert(DisplayServer.get_name() != "headless", "Screenshots require a real renderer")
	var game = load("res://main.tscn").instantiate()
	game.defer_world = true
	root.add_child(game)
	game.set_process(false)
	game.room.set_process(false)
	game.select_stage(4)
	game.stage.build()
	game.draw_distance.mode = game.draw_distance.FAR
	game.draw_distance.apply(game.stage)
	game.spectators.rebuild()
	var stage = game.stage
	var ff = stage.finnish_forest
	# Let the boat, ducks and ants settle into their animated poses.
	for i in range(30):
		stage.water.update(1.0 / 30.0)
		stage.forest_life.update(1.0 / 30.0, stage.at(380))
	viewport = SubViewport.new()
	viewport.world_3d = game.get_world_3d()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	camera = Camera3D.new()
	camera.far = 1100
	viewport.add_child(camera)
	camera.current = true
	DirAccess.make_dir_recursive_absolute("res://../docs/screenshots")

	# Overview of the first lake from above the road.
	var view = stage.at(318) + stage.side(318) * 6.0
	view.y = stage.ground(view) + 13.0
	aim(view, stage.at(392) + stage.side(392) * 24.0 + Vector3(0, -2, 0))
	await capture("res://textures/previews/stage_4.webp", Vector2i(480, 240))
	await capture("res://textures/previews/backdrop_4.webp", Vector2i(1280, 720))
	await capture("res://../docs/screenshots/finnish-forest-lake.webp", Vector2i(1920, 1080))

	# A rally car flying over the yellow-house crest.
	var racer = game.Props.rally_car(1)
	game.add_child(racer)
	var station = ff.YELLOW_HOUSE_STATION + 6.0
	racer.position = stage.at(station) + Vector3(0, 1.1, 0)
	racer.rotation = Vector3(-0.12, atan2(-stage.direction(station).x, -stage.direction(station).z), 0)
	view = stage.at(station + 16) + stage.side(station) * -7.5
	view.y = stage.ground(view) + 1.6
	aim(view, racer.position + Vector3(0, 0.6, 0), 60.0)
	await capture("res://../docs/screenshots/finnish-forest-jump.webp", Vector2i(1920, 1080))

	# Crew splashing through the ford between the two lakes.
	station = ff.FORD_STATION + 2.0
	racer.position = stage.at(station)
	racer.position.y = stage.ground(racer.position) + 0.06
	racer.rotation = Vector3(0, atan2(-stage.direction(station).x, -stage.direction(station).z), 0)
	for i in range(6):
		stage.water.splash(racer.position + stage.side(station) * (1.2 if i % 2 == 0 else -1.2) + stage.direction(station) * 0.8, 1.3, stage.direction(station) * 3.0)
	stage.water.update(0.12)
	view = stage.at(station + 14) + stage.side(station) * 9.0
	view.y = stage.ground(view) + 2.2
	aim(view, racer.position + Vector3(0, 0.5, 0), 58.0)
	await capture("res://../docs/screenshots/finnish-forest-ford.webp", Vector2i(1920, 1080))
	racer.hide()

	# Living forest floor: grass, berries, mushrooms, stones and an ant hill.
	var hill: Dictionary = stage.forest_life.anthills[0]
	for candidate in stage.forest_life.anthills:
		if stage.road_distance(candidate.base) > 14.0 and stage.road_distance(candidate.base) < 30.0:
			hill = candidate
			break
	stage.forest_life.update(0.1, hill.base)
	var base: Vector3 = hill.base
	var side_dir = (base - stage.at(stage.road_s(base)))
	side_dir.y = 0
	side_dir = side_dir.normalized()
	view = base - side_dir * 4.0 + Vector3(1.2, 0, 0)
	view.y = stage.ground(view) + 1.4
	aim(view, base + Vector3(0, 0.3, 0), 62.0)
	await capture("res://../docs/screenshots/finnish-forest-floor.webp", Vector2i(1920, 1080))

	# Sauna, jetty and the moored boat.
	var jetty_end: Vector3 = ff.jetty.end
	view = jetty_end + Vector3(ff.jetty.side * 9.0, 0, 7.0)
	view.y = float(ff.jetty.deck) + 3.2
	var sauna_target: Vector3 = (ff.sauna + jetty_end) * 0.5
	sauna_target.y = float(ff.jetty.deck) + 0.8
	aim(view, sauna_target, 60.0)
	await capture("res://../docs/screenshots/finnish-forest-sauna.webp", Vector2i(1920, 1080))
	await game._shutdown_audio()
	quit()
