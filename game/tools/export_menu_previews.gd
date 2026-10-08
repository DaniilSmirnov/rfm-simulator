extends SceneTree
var previews: Array[SubViewport] = []
var cameras: Array[Camera3D] = []
# Regenerate menu images from game geometry, outside the runtime menu.
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	game.defer_world = false
	root.add_child(game)
	for i in range(2):
		var viewport = SubViewport.new()
		viewport.size = Vector2i(480, 240)
		viewport.world_3d = game.get_world_3d()
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		root.add_child(viewport)
		var camera = Camera3D.new()
		camera.fov = 48
		camera.far = 60 if i == 0 else 160
		viewport.add_child(camera)
		camera.current = true
		previews.append(viewport)
		cameras.append(camera)
	game.set_process(false)
	game.room.set_process(false)
	for i in range(0 if "--stages-only" in OS.get_cmdline_user_args() else game.Props.PLAYER_MODELS.size()):
		game.select_player_car(i)
		await capture(game, 0, "car_%d" % i)
	for i in range(0 if "--cars-only" in OS.get_cmdline_user_args() else game.Stage.STAGES.size()):
		game.select_stage(i)
		await capture(game, 1, "stage_%d" % i)
	await game._shutdown_audio()
	quit()
func capture(game: Node, index: int, name: String) -> void:
	var target = game.car.position + Vector3(0, 0.9, 0) if index == 0 else game.stage.at(390 if game.stage.urban else 200)
	cameras[index].position = target + (Vector3(4.8, 2.2, 5.6) if index == 0 else Vector3(28, 20, 30))
	if index == 1 and game.stage.desert:
		cameras[index].far = 1100
		cameras[index].fov = 66
		cameras[index].position = Vector3(150, 125, -235)
		target = Vector3(0, 40, -410)
	else:
		cameras[index].far = 60 if index == 0 else 160
		cameras[index].fov = 48
	if index == 1 and game.stage.variant == 0:
		cameras[index].far = 400
		target = game.stage.at(290)
		cameras[index].position = game.stage.at(260) + Vector3(4, 32, 18)
	elif index == 1 and game.stage.urban:
		cameras[index].far = 500
		target = game.stage.village_main_at(435) + game.stage.village_main_side(435) * 20.0
		cameras[index].position = target + Vector3(-40, 42, 52)
	if index == 0:
		frame_car(game.car, cameras[index])
	else:
		cameras[index].look_at(target)
	previews[index].render_target_update_mode = SubViewport.UPDATE_ONCE
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image = previews[index].get_texture().get_image()
	image.save_webp("res://textures/previews/%s.webp" % name, false, 0.85)

# Fit every actual model, including roof cargo, with consistent front-quarter framing.
func frame_car(car: Node3D, camera: Camera3D) -> void:
	var bounds = AABB()
	var found = false
	for node in car.find_children("*", "MeshInstance3D", true, false):
		if not node.is_visible_in_tree() or node.mesh == null:
			continue
		var part: AABB = node.global_transform * node.mesh.get_aabb()
		bounds = bounds.merge(part) if found else part
		found = true
	if not found:
		camera.look_at(car.global_position)
		return
	var target = bounds.get_center()
	var backward = (car.global_basis * Vector3(4.8, 2.2, -5.6)).normalized()
	var right = Vector3.UP.cross(backward).normalized()
	var up = backward.cross(right).normalized()
	var tangent = tan(deg_to_rad(camera.fov) * 0.5)
	var distance = 0.0
	for corner in range(8):
		var point = bounds.get_endpoint(corner) - target
		distance = maxf(distance, point.dot(backward) + maxf(absf(point.dot(up)) / tangent, absf(point.dot(right)) / (tangent * 2.0)))
	camera.position = target + backward * distance * 1.15
	camera.look_at(target)
