extends RefCounted
# Shared setup for the documentation and menu screenshot tools: one way to load
# a stage with far draw distance, aim a camera and save a WebP from an
# offscreen viewport. Tools keep only their camera positions.
#   var rig = ScreenshotRig.new(self)        # self = the SceneTree tool
#   var game = rig.open_stage(4)
#   rig.aim(from, to)
#   await rig.capture("res://../docs/screenshots/x.webp", Vector2i(1920, 1080))
const SETTLE_FRAMES = 8
const QUALITY = 0.9

var tree: SceneTree
var game: Node
var viewport: SubViewport
var camera: Camera3D
var label = "SCREENSHOT"

func _init(owner_tree: SceneTree, log_label: String = "SCREENSHOT") -> void:
	tree = owner_tree
	label = log_label

# Builds the stage synchronously with the game paused, as the menu and tests do.
func open_stage(stage_index: int) -> Node:
	if DisplayServer.get_name() == "headless":
		push_error("Screenshots require a real renderer (run through xvfb-run).")
		tree.quit(1)
		return null
	game = load("res://main.tscn").instantiate()
	game.defer_world = true
	tree.root.add_child(game)
	game.set_process(false)
	game.room.set_process(false)
	game.select_stage(stage_index)
	game.stage.build()
	game.draw_distance.mode = game.draw_distance.FAR
	game.draw_distance.apply(game.stage)
	game.spectators.rebuild()
	viewport = SubViewport.new()
	viewport.world_3d = game.get_world_3d()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(viewport)
	camera = Camera3D.new()
	camera.fov = 56
	camera.far = 1400
	viewport.add_child(camera)
	camera.current = true
	DirAccess.make_dir_recursive_absolute("res://../docs/screenshots")
	return game

func aim(position: Vector3, target: Vector3, fov: float = 56.0) -> void:
	camera.fov = fov
	camera.position = position
	camera.look_at(target)

# Saves outside assert(): asserts are stripped from release builds.
func capture(path: String, size: Vector2i, quality: float = QUALITY) -> bool:
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for frame in range(SETTLE_FRAMES):
		await tree.process_frame
	await RenderingServer.frame_post_draw
	var image = viewport.get_texture().get_image()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if image == null or image.is_empty():
		push_error("Empty frame for " + path)
		return false
	var error = image.save_webp(path, false, quality)
	if error != OK:
		push_error("Could not save %s (%d)" % [path, error])
		return false
	print(label, " ", path, " ", size)
	return true

func close() -> void:
	if game != null:
		await game._shutdown_audio()
	tree.quit()
