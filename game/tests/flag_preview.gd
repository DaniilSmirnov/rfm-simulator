extends SceneTree
const Props = preload("res://scripts/props.gd")
var failures = 0

func _initialize() -> void:
	call_deferred("run")

func white_pixels(image: Image, camera: Camera3D, flag: Node3D, height: float) -> int:
	var a = camera.unproject_position(flag.to_global(Vector3(0.12, height + 0.18, 0)))
	var b = camera.unproject_position(flag.to_global(Vector3(1.32, height - 0.18, 0)))
	# Project coordinates use the stretched viewport; PNGs use render pixels.
	var scale = Vector2(image.get_size()) / root.get_visible_rect().size
	var area = Rect2(a * scale, Vector2.ZERO).expand(b * scale)
	var count = 0
	for y in range(maxi(0, floori(area.position.y)), mini(image.get_height(), ceili(area.end.y))):
		for x in range(maxi(0, floori(area.position.x)), mini(image.get_width(), ceili(area.end.x))):
			var color = image.get_pixel(x, y)
			count += int(color.r > 0.85 and color.g > 0.85 and color.b > 0.7)
	return count

func frame() -> Image:
	await create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func run() -> void:
	root.size = Vector2i(1280, 720)
	var scene = Node3D.new()
	root.add_child(scene)
	var environment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("14242c")
	scene.add_child(environment)
	var flag = Props.rally_fans_map_flag(scene, Vector3.ZERO, 0)
	var camera = Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.5
	for angle in [0.0, 0.9]:
		flag.rotation.y = angle
		for face in [-1, 1]:
			camera.position = flag.to_global(Vector3(0.72 + (1.5 if angle > 0 else 0.0), 1.65, face * 5.0))
			camera.look_at(flag.to_global(Vector3(0.72, 1.65, 0)))
			var image = await frame()
			var top = white_pixels(image, camera, flag, 1.75)
			var bottom = white_pixels(image, camera, flag, 1.34)
			var name = "front" if face > 0 else "back"
			image.save_png("res://../flag-%s-%d.png" % [name, roundi(angle * 100)])
			if top < 50 or bottom < 50:
				failures += 1
				push_error("Flag %s at %.1f: missing rendered text (%d / %d white pixels)" % [name, angle, top, bottom])
			else:
				print("PASS: rendered flag %s at %.1f has both readable text lines (%d / %d)" % [name, angle, top, bottom])
	# The wordmark must still obey scene depth instead of showing through objects.
	flag.rotation.y = 0
	camera.position = Vector3(0.72, 1.65, 5)
	camera.look_at(Vector3(0.72, 1.65, 0))
	Props.box(scene, Vector3(0.72, 1.65, 2), Vector3(3, 4, 0.2), Color("14242c"))
	var hidden = await frame()
	if white_pixels(hidden, camera, flag, 1.75) != 0 or white_pixels(hidden, camera, flag, 1.34) != 0:
		failures += 1
		push_error("Flag text leaks through an opaque obstacle")
	print("FLAG RENDER RESULT: %d failures" % failures)
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
