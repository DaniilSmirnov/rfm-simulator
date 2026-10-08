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
	for i in range(game.Props.PLAYER_MODELS.size()):
		game.select_player_car(i)
		await capture(game, 0, "car_%d" % i)
	for i in range(game.Stage.STAGES.size()):
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
	cameras[index].look_at(target)
	previews[index].render_target_update_mode = SubViewport.UPDATE_ONCE
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image = previews[index].get_texture().get_image()
	image.save_webp("res://textures/previews/%s.webp" % name, false, 0.85)
