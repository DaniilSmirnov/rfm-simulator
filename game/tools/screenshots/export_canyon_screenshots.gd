extends SceneTree
# Actual game geometry and lighting for the «Чарынский каньон» menu art and
# docs. Run: xvfb-run godot --path game --rendering-method gl_compatibility
# --script res://tools/screenshots/export_canyon_screenshots.gd
const ScreenshotRig = preload("res://tools/screenshots/screenshot_rig.gd")
var rig

func _initialize() -> void: call_deferred("run")

func view(stage, s: float, lateral: float, height: float) -> Vector3:
	var p = stage.at(s) + stage.side(s) * lateral
	p.y = stage.ground(p) + height
	return p

func run() -> void:
	rig = ScreenshotRig.new(self, "CANYON_SCREENSHOT")
	var game = rig.open_stage(3)
	if game == null:
		return
	var stage = game.stage
	var canyon = stage.biome
	for i in range(30):
		canyon.canyon_life.update(1.0 / 30.0, Vector3(0, 0, 400))

	# The Valley of Castles from the rim: the gorge, its towers and the road
	# threading the floor far below.
	var rim = stage.at(470.0) + stage.side(470.0) * -150.0
	rim.y = canyon.PLATEAU + 16.0
	rig.aim(rim, stage.at(500.0) + Vector3(0, 10, 0), 62.0)
	await rig.capture("res://textures/previews/stage_3.webp", Vector2i(480, 240))
	await rig.capture("res://textures/previews/backdrop_3.webp", Vector2i(1280, 720))
	await rig.capture("res://../docs/screenshots/charyn-overview.webp", Vector2i(1920, 1080))

	# A rally car on the ledge of the descent, wall above, gorge below.
	var racer = game.Props.rally_car(2)
	game.add_child(racer)
	var station = 300.0
	racer.position = stage.at(station) + Vector3(0, 0.35, 0)
	racer.rotation = Vector3(0, atan2(-stage.direction(station).x, -stage.direction(station).z), 0)
	var over_void = stage.at(346.0) + stage.side(346.0) * -21.0 + Vector3(0, 7.0, 0)
	rig.aim(over_void, stage.at(station) + Vector3(0, 1.0, 0), 55.0)
	await rig.capture("res://../docs/screenshots/charyn-ledge.webp", Vector2i(1920, 1080))
	racer.hide()

	# The narrow corridor of the floor between the walls.
	rig.aim(view(stage, 556.0, 4.0, 2.4), stage.at(610.0) + Vector3(0, 6, 0), 62.0)
	await rig.capture("res://../docs/screenshots/charyn-gorge.webp", Vector2i(1920, 1080))

	# The amphitheatre under the wall, with its benches and pinnacles.
	var bay = stage.at(616.0) + stage.side(616.0) * -24.0
	bay.y = stage.ground(bay) + 2.0
	rig.aim(bay, stage.at(616.0) + stage.side(616.0) * -96.0 + Vector3(0, 34, 0), 62.0)
	await rig.capture("res://../docs/screenshots/charyn-wall.webp", Vector2i(1920, 1080))

	# The yurt camp on the steppe above the gorge.
	var camp = stage.get_node("SteppeYurtCamp")
	rig.aim(camp.position + Vector3(18.0, 7.0, 24.0), camp.position + Vector3(0, 2.4, 0), 56.0)
	await rig.capture("res://../docs/screenshots/charyn-yurts.webp", Vector2i(1920, 1080))

	# A herd of bactrian camels in the feather grass.
	var camel: Node3D = canyon.canyon_life.camels[0].node
	rig.aim(camel.position + Vector3(6.5, 2.6, 7.0), camel.position + Vector3(0, 1.6, 0), 52.0)
	await rig.capture("res://../docs/screenshots/charyn-camels.webp", Vector2i(1920, 1080))

	# The dry bed and the ash grove under the walls.
	rig.aim(view(stage, 620.0, 26.0, 14.0), stage.at(660.0) + Vector3(0, 3, 0), 60.0)
	await rig.capture("res://../docs/screenshots/charyn-ash-grove.webp", Vector2i(1920, 1080))
	await rig.close()
