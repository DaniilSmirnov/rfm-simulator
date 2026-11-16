extends SceneTree
# The enterable yurt, the camels and the far meadow of «Чарынский каньон».
# Run: xvfb-run godot --path game --rendering-method gl_compatibility
# --script res://tools/screenshots/export_charyn_details.gd -- <out_dir>
const ScreenshotRig = preload("res://tools/screenshots/screenshot_rig.gd")
var rig

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var args = OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "res://../docs/screenshots"
	rig = ScreenshotRig.new(self, "CHARYN_DETAILS")
	var game = rig.open_stage(3)
	if game == null:
		return
	var stage = game.stage
	var canyon = stage.biome
	for i in range(30):
		canyon.canyon_life.update(1.0 / 30.0, Vector3(0, 0, 400))
	var size = Vector2i(1280, 720)

	var camp: Node3D = stage.get_node("SteppeYurtCamp")
	rig.aim(camp.position + Vector3(17.0, 7.0, 23.0), camp.position + Vector3(0, 2.4, 0), 56.0)
	await rig.capture(out + "/yurt-camp.webp", size)
	var yurt: Node3D = camp.get_node_or_null("GuestYurt")
	if yurt != null:
		var door = yurt.global_transform * Vector3(0, 1.6, 7.0)
		rig.aim(door, yurt.global_transform * Vector3(0, 1.4, 0), 56.0)
		await rig.capture(out + "/yurt-door.webp", size)
		for shot in [[Vector3(0, 1.62, 2.6), Vector3(0, 1.0, -3.0), "yurt-inside-tor"], [Vector3(-0.4, 1.62, 1.8), Vector3(-3.0, 1.0, -1.0), "yurt-inside-left"], [Vector3(0.4, 1.62, 1.8), Vector3(3.0, 1.0, -0.8), "yurt-inside-right"], [Vector3(0, 1.62, -2.0), Vector3(0, 1.3, 3.0), "yurt-inside-door"], [Vector3(0.6, 1.62, 0.6), Vector3(0.0, 3.6, 0.0), "yurt-inside-crown"]]:
			rig.aim(yurt.global_transform * shot[0], yurt.global_transform * shot[1], 72.0)
			await rig.capture(out + "/" + shot[2] + ".webp", size)

	var camel: Node3D = canyon.canyon_life.camels[0].node
	rig.aim(camel.position + Vector3(6.5, 2.6, 7.0), camel.position + Vector3(0, 1.6, 0), 52.0)
	await rig.capture(out + "/camels.webp", size)
	var side = camel.global_transform.basis.x
	rig.aim(camel.position + side * 5.5 + Vector3(0, 1.6, 0), camel.position + Vector3(0, 1.3, 0), 50.0)
	await rig.capture(out + "/camel-side.webp", size)
	var front = camel.global_transform.basis.z
	rig.aim(camel.position + front * 4.5 + side * 2.5 + Vector3(0, 2.0, 0), camel.position + Vector3(0, 1.8, 0), 50.0)
	await rig.capture(out + "/camel-front.webp", size)

	var bridge = canyon.bridge
	rig.aim(bridge.b + Vector3(0, 3.0, 0) - bridge.along * 4.0, bridge.meadow + Vector3(0, 0.5, 0), 66.0)
	await rig.capture(out + "/meadow-from-bridge.webp", size)
	rig.aim(bridge.meadow + Vector3(35.0, 22.0, 30.0), bridge.meadow, 60.0)
	await rig.capture(out + "/meadow-above.webp", size)
	await rig.close()
