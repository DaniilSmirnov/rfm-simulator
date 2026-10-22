extends SceneTree
# Actual game geometry and lighting for the «Асбестовский карьер» stage menu
# art and docs.
# Run: xvfb-run godot --path game --rendering-method gl_compatibility --script res://tools/screenshots/export_quarry_screenshots.gd
# With `-- --views=<dir>` it only saves inspection views of the pit there.
const ScreenshotRig = preload("res://tools/screenshots/screenshot_rig.gd")
var rig
func _initialize() -> void: call_deferred("run")

func road_view(stage, s: float, lateral: float, height: float, target_s: float, target_lateral: float, fov: float = 58.0) -> void:
	var view = stage.at(s) + stage.side(s) * lateral
	view.y = stage.ground(view) + height
	var target = stage.at(target_s) + stage.side(target_s) * target_lateral
	target.y = stage.ground(target) + 1.0
	rig.aim(view, target, fov)

func machine_view(stage, node: Node3D, distance: float, height: float, angle: float, fov: float = 55.0, look: float = 3.0) -> void:
	var view = node.global_position + Vector3(sin(angle), 0, cos(angle)).rotated(Vector3.UP, node.rotation.y) * distance
	view.y = stage.ground(view) + height
	rig.aim(view, node.global_position + Vector3(0, look, 0), fov)

# A rally car on the road at `station`, with its dust trail behind it.
func place_racer(game, stage, station: float) -> Node3D:
	var racer = game.Props.rally_car(5)
	game.add_child(racer)
	racer.position = stage.at(station)
	racer.position.y = stage.vehicle_ground(racer.position) + 0.06
	racer.rotation.y = atan2(-stage.direction(station).x, -stage.direction(station).z)
	return racer

# Runs the stage's life with the car driving towards `station` so its dust
# cloud trails behind it.
func raise_dust(game, stage, racer: Node3D, station: float) -> void:
	game.racers.append({"node": racer})
	# Software rendering draws a few frames a second: slow the clock so the
	# cloud lives as many frames as it would behind a car at 24 m/s.
	Engine.time_scale = 0.25
	for i in range(150):
		var s = station - 120.0 + i * 0.8
		racer.position = stage.at(s)
		racer.position.y = stage.vehicle_ground(racer.position) + 0.06
		racer.rotation.y = atan2(-stage.direction(s).x, -stage.direction(s).z)
		stage.biome.update_life(1.0 / 30.0, racer.position)
		await process_frame
	Engine.time_scale = 1.0
	game.racers.pop_back()

func run() -> void:
	rig = ScreenshotRig.new(self, "QUARRY_SCREENSHOT")
	var index = -1
	for i in range(preload("res://scripts/stages/stage.gd").STAGES.size()):
		if preload("res://scripts/stages/stage_registry.gd").entry(i).id == "quarry":
			index = i
	var game = rig.open_stage(index)
	if game == null:
		return
	var stage = game.stage
	var quarry = stage.biome
	var scenery = quarry.scenery
	for i in range(60):
		quarry.update_life(1.0 / 30.0, stage.at(quarry.ramp_end))
	var views = ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--views="):
			views = arg.trim_prefix("--views=")
	var size = Vector2i(1280, 720)
	if views != "":
		rig.aim(Vector3(150, 120, -260), Vector3(-40, 12, -560), 62.0)
		await rig.capture(views + "/overview.png", size)
		rig.aim(Vector3(-150, 80, -820), Vector3(-30, 20, -480), 62.0)
		await rig.capture(views + "/overview_south.png", size)
		road_view(stage, 80.0, 0.0, 1.6, 140.0, 0.0)
		await rig.capture(views + "/dumps.png", size)
		road_view(stage, quarry.ramp_begin - 30.0, 0.0, 1.6, quarry.ramp_begin + 40.0, 0.0)
		await rig.capture(views + "/ramp_top.png", size)
		road_view(stage, quarry.ramp_begin + 200.0, 0.0, 1.6, quarry.ramp_begin + 260.0, 0.0)
		await rig.capture(views + "/ramp_mid.png", size)
		road_view(stage, 760.0, 0.0, 1.6, 820.0, 0.0)
		await rig.capture(views + "/ramp_turn.png", size)
		road_view(stage, quarry.ramp_end - 20.0, 0.0, 1.6, quarry.ramp_end + 60.0, 0.0)
		await rig.capture(views + "/floor.png", size)
		machine_view(stage, scenery.shovel, 34.0, 4.0, 0.6, 55.0, 6.0)
		await rig.capture(views + "/shovel.png", size)
		machine_view(stage, scenery.machines[0], 16.0, 2.0, 2.4, 55.0, 3.0)
		await rig.capture(views + "/belaz.png", size)
		machine_view(stage, scenery.machines[2], 18.0, 2.0, 0.6, 55.0, 3.0)
		await rig.capture(views + "/belaz_rim.png", size)
		machine_view(stage, scenery.machines[3], 22.0, 3.0, 0.8, 55.0, 8.0)
		await rig.capture(views + "/drill.png", size)
		var racer = place_racer(game, stage, quarry.ramp_begin + 120.0)
		await raise_dust(game, stage, racer, quarry.ramp_begin + 120.0)
		road_view(stage, quarry.ramp_begin + 132.0, -3.0, 2.4, quarry.ramp_begin + 100.0, 0.5)
		await rig.capture(views + "/dust.png", size)
		await game._shutdown_audio()
		quit()
		return

	# Menu card: a rally car on the haul road in its own white dust.
	var station = quarry.ramp_begin + 120.0
	var car = place_racer(game, stage, station)
	await raise_dust(game, stage, car, station)
	road_view(stage, station + 11.0, -2.6, 2.1, station - 10.0, 2.0, 62.0)
	await rig.capture("res://textures/previews/stage_%d.webp" % index, Vector2i(480, 240))
	await rig.capture("res://../docs/screenshots/quarry-rally.webp", Vector2i(1920, 1080))
	car.hide()

	# Menu backdrop: the pit from the east rim, the haul road down its walls.
	rig.aim(Vector3(150, 120, -260), Vector3(-40, 12, -560), 62.0)
	await rig.capture("res://textures/previews/backdrop_%d.webp" % index, Vector2i(1280, 720))
	await rig.capture("res://../docs/screenshots/quarry-overview.webp", Vector2i(1920, 1080))
	road_view(stage, quarry.ramp_begin - 30.0, 0.0, 1.6, quarry.ramp_begin + 40.0, 0.0)
	await rig.capture("res://../docs/screenshots/quarry-ramp-top.webp", Vector2i(1920, 1080))
	road_view(stage, 760.0, 0.0, 1.6, 820.0, 0.0)
	await rig.capture("res://../docs/screenshots/quarry-ramp-turn.webp", Vector2i(1920, 1080))
	machine_view(stage, scenery.shovel, 34.0, 4.0, 0.6, 55.0, 6.0)
	await rig.capture("res://../docs/screenshots/quarry-shovel.webp", Vector2i(1920, 1080))
	road_view(stage, 80.0, 0.0, 1.6, 140.0, 0.0)
	await rig.capture("res://../docs/screenshots/quarry-dumps.webp", Vector2i(1920, 1080))
	await game._shutdown_audio()
	quit()
