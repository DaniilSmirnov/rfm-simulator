extends SceneTree
# Close-up of the «Майншафт» kangaroo: doe and buck, standing and bounding,
# from the side and from the front three-quarters.
#   xvfb-run godot --path game --rendering-method gl_compatibility \
#     --script res://tools/export_kangaroo_sheet.gd -- --out=/tmp/kangaroo
const ScreenshotRig = preload("res://tools/screenshot_rig.gd")
const KangarooModel = preload("res://scripts/kangaroo_model.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var out = "res://../docs/screenshots"
	for value in OS.get_cmdline_user_args():
		if value.begins_with("--out="):
			out = value.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	var rig = ScreenshotRig.new(self, "KANGAROO_SHEET")
	var game = rig.open_stage(5)
	if game == null:
		return
	var stage = game.stage
	for roo in stage.biome.outback_life.kangaroos:
		roo.node.hide()
	var center = stage.at(330.0) + stage.side(330.0) * 6.0
	center.y = stage.ground(center)
	var models: Array = []
	for i in range(4):
		var roo = KangarooModel.build(i % 2 == 1)
		stage.add_child(roo)
		roo.position = center + Vector3((i - 1.5) * 1.6, 0, 0)
		roo.position.y = stage.ground(roo.position) + (0.35 if i >= 2 else 0.0)
		KangarooModel.pose(roo, i >= 2)
		models.append(roo)
	var target = center + Vector3(0, 0.7, 0)
	rig.aim(target + Vector3(0, 0.4, -5.5), target, 50.0)
	await rig.capture(out + "/mineshaft-kangaroo-front.webp", Vector2i(1600, 900))
	for roo in models:
		roo.rotation.y = PI * 0.5
	rig.aim(target + Vector3(0, 0.3, 5.5), target, 50.0)
	await rig.capture(out + "/mineshaft-kangaroo-side.webp", Vector2i(1600, 900))
	for roo in models:
		roo.rotation.y = PI * 0.8
	await rig.capture(out + "/mineshaft-kangaroo-quarter.webp", Vector2i(1600, 900))
	await game._shutdown_audio()
	quit()
