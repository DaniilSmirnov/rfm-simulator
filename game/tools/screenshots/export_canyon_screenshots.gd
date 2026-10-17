extends SceneTree
# Actual game geometry and lighting for the «Чарынский каньон» menu art and
# docs. Run: xvfb-run godot --path game --rendering-method gl_compatibility
# --script res://tools/screenshots/export_canyon_screenshots.gd
const ScreenshotRig = preload("res://tools/screenshots/screenshot_rig.gd")
const Form = preload("res://scripts/stages/canyon/canyon_form.gd")
var rig

func _initialize() -> void: call_deferred("run")

# A camera spot beside the road at station s.
func view(stage, s: float, lateral: float, height: float) -> Vector3:
	var p = stage.at(s) + stage.side(s) * lateral
	p.y = stage.ground(p) + height
	return p

# A camera spot out on the rim of the gorge at world z.
func rim(z: float, side: float, back: float, height: float) -> Vector3:
	var p = Vector3(Form.axis_x(z) + side * (Form.rim_edge(z, side) + back), 0.0, z)
	p.y = Form.rim_level(p) + height
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

	# The Valley of Castles from the rim: the gorge, its towers and the shelf
	# road slanting down the far wall.
	rig.aim(rim(-250.0, -1.0, 3.0, 7.0), Vector3(Form.axis_x(-400.0), Form.bed_level(-400.0) + 12.0, -400.0), 64.0)
	await rig.capture("res://textures/previews/stage_3.webp", Vector2i(480, 240))
	await rig.capture("res://textures/previews/backdrop_3.webp", Vector2i(1280, 720))
	await rig.capture("res://../docs/screenshots/charyn-overview.webp", Vector2i(1920, 1080))

	# The rim road, the steppe on one side and the gorge opening on the other.
	var racer = game.Props.rally_car(2)
	game.add_child(racer)
	_place(stage, racer, 96.0)
	rig.aim(view(stage, 52.0, 16.0, 11.0), stage.at(112.0) + Vector3(0, 0.5, 0), 62.0)
	await rig.capture("res://../docs/screenshots/charyn-rim.webp", Vector2i(1920, 1080))

	# The hairpin at the head of the gorge, seen from the table above it.
	_place(stage, racer, 206.0)
	rig.aim(view(stage, 150.0, -34.0, 26.0), stage.at(212.0), 60.0)
	await rig.capture("res://../docs/screenshots/charyn-hairpin.webp", Vector2i(1920, 1080))

	# The shelf road on the wall, the gorge falling away below it.
	_place(stage, racer, 430.0)
	rig.aim(view(stage, 378.0, 3.0, 5.0), stage.at(436.0) + Vector3(0, 0.8, 0), 58.0)
	await rig.capture("res://../docs/screenshots/charyn-ledge.webp", Vector2i(1920, 1080))
	racer.hide()

	# The wall itself: cliff bands, benches and castles, from the floor.
	var floor_spot = Vector3(Form.axis_x(-330.0), 0.0, -330.0)
	floor_spot.y = Form.bed_level(-330.0) + 2.0
	rig.aim(floor_spot, Vector3(Form.axis_x(-330.0) - 70.0, Form.rim_level(floor_spot) - 6.0, -340.0), 64.0)
	await rig.capture("res://../docs/screenshots/charyn-wall.webp", Vector2i(1920, 1080))

	# The gravel floor running out into the ash grove above the Ili.
	rig.aim(view(stage, 690.0, 8.0, 7.0), stage.at(806.0) + Vector3(0, 2.0, 0), 62.0)
	await rig.capture("res://../docs/screenshots/charyn-grove.webp", Vector2i(1920, 1080))

	# The yurt camp on the steppe.
	var camp = stage.get_node("SteppeYurtCamp")
	rig.aim(camp.position + Vector3(17.0, 7.0, 23.0), camp.position + Vector3(0, 2.4, 0), 56.0)
	await rig.capture("res://../docs/screenshots/charyn-yurts.webp", Vector2i(1920, 1080))

	# A herd of bactrian camels in the feather grass.
	var camel: Node3D = canyon.canyon_life.camels[0].node
	rig.aim(camel.position + Vector3(6.5, 2.6, 7.0), camel.position + Vector3(0, 1.6, 0), 52.0)
	await rig.capture("res://../docs/screenshots/charyn-camels.webp", Vector2i(1920, 1080))

	# The Ili below the mouth of the gorge, from the gravel above the park.
	var mouth = Vector3(Form.axis_x(-744.0), 0.0, -744.0)
	mouth.y = stage.ground(mouth) + 9.0
	rig.aim(mouth, Vector3(Form.axis_x(-860.0) + 40.0, Form.ILI_LEVEL + 6.0, -880.0), 66.0)
	await rig.capture("res://../docs/screenshots/charyn-ili.webp", Vector2i(1920, 1080))

	# The flag over the herders' camp.
	# The emblem faces the camp's own +z, so stand in front of the cloth.
	var cloth: Vector3 = camp.to_global(Vector3(-5.05, 5.6, -4.5))
	rig.aim(camp.to_global(Vector3(-5.05, 5.75, -1.3)), cloth, 34.0)
	await rig.capture("res://../docs/screenshots/charyn-flag.webp", Vector2i(1280, 720))
	await rig.close()

func _place(stage, racer: Node3D, s: float) -> void:
	racer.show()
	racer.position = stage.at(s) + Vector3(0, 0.35, 0)
	racer.rotation = Vector3(0, atan2(-stage.direction(s).x, -stage.direction(s).z), 0)
