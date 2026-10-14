extends SceneTree
# Actual game geometry and lighting for the «Майншафт» stage menu art and docs.
# Run: xvfb-run godot --path game --rendering-method gl_compatibility --script res://tools/screenshots/export_mineshaft_screenshots.gd
const ScreenshotRig = preload("res://tools/screenshots/screenshot_rig.gd")
var rig
func _initialize() -> void: call_deferred("run")

func run() -> void:
	rig = ScreenshotRig.new(self, "MINESHAFT_SCREENSHOT")
	var game = rig.open_stage(5)
	if game == null:
		return
	var stage = game.stage
	var mine = stage.biome
	var life = mine.outback_life
	for i in range(20):
		life.update(1.0 / 30.0, Vector3(0, 0, 400))

	# A rally car flying off the lip of the giant jump, seen from the landing bank.
	var racer = game.Props.rally_car(1)
	game.add_child(racer)
	var station = mine.LIP + 16.0
	racer.position = stage.at(station) + Vector3(0, 3.2, 0)
	racer.rotation = Vector3(0.18, atan2(-stage.direction(station).x, -stage.direction(station).z), 0)
	var view = stage.at(mine.CREEK + 6.0) + stage.side(mine.CREEK) * -14.0
	view.y = stage.ground(view) + 1.8
	rig.aim(view, stage.at(mine.LIP + 10.0) + Vector3(0, 1.5, 0), 66.0)
	await rig.capture("res://textures/previews/stage_5.webp", Vector2i(480, 240))
	await rig.capture("res://../docs/screenshots/mineshaft-jump.webp", Vector2i(1920, 1080))

	# The long straight up to the lip, the headframe and the bush beyond.
	view = stage.at(mine.LIP - 170.0) + stage.side(mine.LIP - 170.0) * -3.0
	view.y = stage.ground(view) + 6.0
	rig.aim(view, stage.at(mine.LIP + 10.0) + Vector3(0, 2.0, 0), 58.0)
	await rig.capture("res://textures/previews/backdrop_5.webp", Vector2i(1280, 720))
	await rig.capture("res://../docs/screenshots/mineshaft-straight.webp", Vector2i(1920, 1080))
	racer.hide()

	# Opening bends from above, with the homestead and its windmill.
	view = mine.homestead + Vector3(-20.0, 22.0, 34.0)
	rig.aim(view, stage.at(120.0), 60.0)
	await rig.capture("res://../docs/screenshots/mineshaft-opening.webp", Vector2i(1920, 1080))

	# A mob of kangaroos by a warning sign.
	var roo: Node3D = life.kangaroos[0].node
	view = roo.position + Vector3(7.0, 0, 6.0)
	view.y = stage.ground(view) + 1.6
	rig.aim(view, roo.position + Vector3(0, 0.8, 0), 60.0)
	await rig.capture("res://../docs/screenshots/mineshaft-kangaroos.webp", Vector2i(1920, 1080))

	# Mine headframe close up.
	view = mine.mine + (stage.at(mine.MINE[0]) - mine.mine).normalized() * 18.0 + Vector3(6.0, 0, 0)
	view.y = stage.ground(view) + 3.0
	rig.aim(view, mine.mine + Vector3(0, 7.0, 0), 62.0)
	await rig.capture("res://../docs/screenshots/mineshaft-headframe.webp", Vector2i(1920, 1080))
	# Kangaroo warning sign and the Drive On Left reminder from the road.
	for shot in [["KangarooSigns", 0, 2.0, "mineshaft-kangaroo-sign"], ["DriveLeftSigns", 0, 1.9, "mineshaft-drive-left"], ["DriveLeftSigns", 1, 1.9, "mineshaft-drive-left-after-jump"]]:
		var posts = stage.get_node(shot[0]).get_children().filter(func(n): return not n is MeshInstance3D)
		var post: Node3D = posts[shot[1]]
		view = post.to_global(Vector3(0.9, shot[2] - 0.2, 3.6))
		rig.aim(view, post.to_global(Vector3(0, shot[2] - 0.15, 0)), 50.0)
		await rig.capture("res://../docs/screenshots/%s.webp" % shot[3], Vector2i(1280, 720))
	await game._shutdown_audio()
	quit()
