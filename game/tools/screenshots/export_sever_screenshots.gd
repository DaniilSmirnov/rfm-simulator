extends SceneTree
# Actual game geometry and lighting for the «Поречье» stage menu art and docs.
# Run: xvfb-run godot --path game --rendering-method gl_compatibility --script res://tools/screenshots/export_sever_screenshots.gd
# With `-- --views=<dir>` it only saves inspection views of the village there.
const ScreenshotRig = preload("res://tools/screenshots/screenshot_rig.gd")
var rig
func _initialize() -> void: call_deferred("run")

func road_view(stage, s: float, lateral: float, height: float, target_s: float, target_lateral: float, fov: float = 58.0) -> void:
	var view = stage.at(s) + stage.side(s) * lateral
	view.y = stage.ground(view) + height
	var target = stage.at(target_s) + stage.side(target_s) * target_lateral
	target.y = stage.ground(target) + 1.0
	rig.aim(view, target, fov)

func building_view(stage, node: Node3D, distance: float, height: float, angle: float, fov: float = 55.0, look: float = 3.0) -> void:
	var view = node.global_position + Vector3(sin(angle), 0, cos(angle)).rotated(Vector3.UP, node.rotation.y) * distance
	view.y = stage.ground(view) + height
	rig.aim(view, node.global_position + Vector3(0, look, 0), fov)

func run() -> void:
	rig = ScreenshotRig.new(self, "SEVER_SCREENSHOT")
	var index = -1
	for i in range(preload("res://scripts/stages/stage.gd").STAGES.size()):
		if preload("res://scripts/stages/stage_registry.gd").entry(i).id == "sever":
			index = i
	var game = rig.open_stage(index)
	if game == null:
		return
	var stage = game.stage
	var sever = stage.biome
	for i in range(20):
		sever.life.update(1.0 / 30.0, stage.at(440.0))
	var views = ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--views="):
			views = arg.trim_prefix("--views=")
	var scenery: Node3D = stage.get_node("SeverScenery")
	if views != "":
		var size = Vector2i(1280, 720)
		road_view(stage, sever.VILLAGE_BEGIN - 30.0, 0.0, 2.2, sever.VILLAGE_BEGIN + 40.0, 0.0)
		await rig.capture(views + "/street.png", size)
		var house: Node3D = scenery.get_node("Izba_364_1")
		building_view(stage, house, 16.0, 2.0, 0.35)
		await rig.capture(views + "/izba.png", size)
		building_view(stage, house, 14.0, 2.0, 2.4)
		await rig.capture(views + "/izba_back.png", size)
		var church: Node3D = scenery.get_node("VillageChurch")
		building_view(stage, church, 46.0, 3.0, 0.75, 55.0, 10.0)
		await rig.capture(views + "/church.png", size)
		building_view(stage, church, 30.0, 3.0, 2.2)
		await rig.capture(views + "/church_back.png", size)
		road_view(stage, sever.BRIDGE_S - 40.0, 0.0, 1.6, sever.BRIDGE_S, 0.0)
		await rig.capture(views + "/bridge_road.png", size)
		var bridge = stage.at(sever.BRIDGE_S) + stage.side(sever.BRIDGE_S) * 18.0
		bridge.y = stage.ground(bridge) + 3.0
		rig.aim(bridge, stage.at(sever.BRIDGE_S), 55.0)
		await rig.capture(views + "/bridge_side.png", size)
		var well: Node3D = scenery.get_node("CraneWell")
		building_view(stage, well, 9.0, 1.8, 0.8)
		await rig.capture(views + "/well.png", size)
		var barn: Node3D = scenery.get_node("VillageBarn")
		building_view(stage, barn, 18.0, 2.0, 0.5)
		await rig.capture(views + "/barn.png", size)
		var above = stage.at(440.0) + Vector3(60.0, 70.0, 40.0)
		rig.aim(above, stage.at(450.0), 60.0)
		await rig.capture(views + "/village_above.png", size)
		var gully = stage.at(sever.BRIDGE_S) + stage.side(sever.BRIDGE_S) * 24.0 + stage.direction(sever.BRIDGE_S) * 3.0
		gully.y = stage.ground(gully) + 1.2
		rig.aim(gully, stage.at(sever.BRIDGE_S) + Vector3(0, -0.5, 0), 55.0)
		await rig.capture(views + "/bridge_gully.png", size)
		road_view(stage, sever.BRIDGE_S - 12.0, 0.0, 1.5, sever.BRIDGE_S + 30.0, 0.0)
		await rig.capture(views + "/bridge_deck.png", size)
		for s in [40.0, 110.0, 150.0, 240.0, 630.0, 700.0, 760.0]:
			road_view(stage, s, 0.0, 1.4, s + 60.0, 0.0, 62.0)
			await rig.capture(views + "/road_%d.png" % int(s), size)
		await game._shutdown_audio()
		quit()
		return

	# Menu card: a rally car on the village street between the izbas and the church.
	var racer = game.Props.rally_car(3)
	game.add_child(racer)
	var station = sever.VILLAGE_BEGIN + 92.0
	racer.position = stage.at(station)
	racer.position.y = stage.vehicle_ground(racer.position) + 0.06
	racer.rotation.y = atan2(-stage.direction(station).x, -stage.direction(station).z)
	var view = racer.position + stage.direction(station) * 11.0 + stage.side(station) * 4.5
	view.y = stage.ground(view) + 2.2
	rig.aim(view, racer.position + Vector3(0, 1.4, 0) - stage.direction(station) * 6.0, 60.0)
	await rig.capture("res://textures/previews/stage_%d.webp" % index, Vector2i(480, 240))
	await rig.capture("res://../docs/screenshots/sever-rally.webp", Vector2i(1920, 1080))
	racer.hide()

	# Menu backdrop: the village across the snowy fields, church tent roof above the izbas.
	var church_node: Node3D = scenery.get_node("VillageChurch")
	view = stage.at(410.0) + stage.side(410.0) * -50.0
	view.y = stage.ground(view) + 5.0
	rig.aim(view, church_node.global_position + Vector3(0, 8.0, 0) + stage.direction(470.0) * -12.0, 52.0)
	await rig.capture("res://textures/previews/backdrop_%d.webp" % index, Vector2i(1280, 720))
	await rig.capture("res://../docs/screenshots/sever-overview.webp", Vector2i(1920, 1080))

	road_view(stage, sever.VILLAGE_BEGIN + 60.0, 0.6, 1.8, sever.CHURCH.s, -4.0)
	await rig.capture("res://../docs/screenshots/sever-street.webp", Vector2i(1920, 1080))
	building_view(stage, church_node, 46.0, 3.0, 0.75, 55.0, 10.0)
	await rig.capture("res://../docs/screenshots/sever-church.webp", Vector2i(1920, 1080))
	road_view(stage, sever.BRIDGE_S - 45.0, 0.0, 2.0, sever.BRIDGE_S + 10.0, 0.0)
	await rig.capture("res://../docs/screenshots/sever-bridge.webp", Vector2i(1920, 1080))
	await game._shutdown_audio()
	quit()
