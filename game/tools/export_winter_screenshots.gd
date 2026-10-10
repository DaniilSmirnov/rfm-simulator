extends SceneTree
# Actual game geometry and lighting; no promotional overlays or generated artwork.
# Run: xvfb-run godot --path game --rendering-method gl_compatibility --script res://tools/export_winter_screenshots.gd
const ScreenshotRig = preload("res://tools/screenshot_rig.gd")
var rig
var camera: Camera3D
func _initialize() -> void: call_deferred("run")
func capture(path: String, size: Vector2i) -> void:
	await rig.capture(path, size, 0.93)
# Looking back down the ladder of lacets towards the valley and the Alps.
static func frame_overview(stage, view: Camera3D) -> void:
	view.fov = 54
	view.far = 1400
	view.position = stage.at(250)
	view.position.y = stage.ground(view.position) + 16.0
	view.look_at(stage.at(175) + Vector3(0, 1.0, 0))

static func frame_road(stage, view: Camera3D, s: float, lateral: float, height: float, target_s: float, target_lateral: float) -> void:
	view.fov = 58
	view.position = stage.at(s) + stage.side(s) * lateral
	view.position.y = stage.ground(view.position) + height
	var target = stage.at(target_s) + stage.side(target_s) * target_lateral
	target.y = stage.ground(target) + 1.0
	view.look_at(target)

func run() -> void:
	rig = ScreenshotRig.new(self, "WINTER_SCREENSHOT")
	var game = rig.open_stage(1)
	if game == null:
		return
	camera = rig.camera
	camera.fov = 54
	var target: Vector3
	frame_overview(game.stage, camera)
	await capture("res://textures/previews/stage_1.webp", Vector2i(480, 240))
	await capture("res://textures/previews/backdrop_1.webp", Vector2i(1280, 720))
	await capture("res://../docs/screenshots/winter-overview.webp", Vector2i(1920, 1080))
	var racer = game.Props.rally_car(2)
	game.add_child(racer)
	var station = float(game.stage.alpine.bends[3].s) + 6.0
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
	game.stage.alpine_life.update(0.5, game.stage.at(440))
	frame_road(game.stage, camera, 404.0, 1.5, 4.5, 448.0, 0.0)
	await capture("res://../docs/screenshots/winter-col.webp", Vector2i(1920, 1080))
	frame_road(game.stage, camera, 8.0, 1.0, 3.0, 70.0, -4.0)
	await capture("res://../docs/screenshots/winter-corniche.webp", Vector2i(1920, 1080))
	await rig.close()
