extends SceneTree
# Views of the service park at the start of a stage, with the convoy in its
# bays and a player's car at the aisle's end, for reviewing it by eye:
#   xvfb-run godot --path game --rendering-method gl_compatibility --script res://tools/screenshots/export_service_park.gd -- [stage=0] [out=res://../docs/screenshots/service-park] [night]
const ScreenshotRig = preload("res://tools/screenshots/screenshot_rig.gd")
const Parks = preload("res://scripts/traffic/service_parks.gd")
# Camera spots in park space: (x, z, height) and what they look at.
const VIEWS = {
	"overview": [Vector3(-24.0, 4.0, 14.0), Vector3(2.0, 0.0, 30.0)],
	"entrance": [Vector3(-2.5, -6.0, 2.2), Vector3(0.0, 1.2, 20.0)],
	"bays": [Vector3(-1.5, 15.0, 1.8), Vector3(10.0, 1.0, 26.0)],
	"tent": [Vector3(1.5, 27.0, 3.4), Vector3(14.0, 0.8, 22.5)],
	"far_end": [Vector3(3.0, 30.0, 2.4), Vector3(-8.0, 1.0, 44.0)],
}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var variant = 0
	var out = "res://../docs/screenshots/service-park"
	var night = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("stage="):
			variant = int(arg.substr(6))
		elif arg.begins_with("out="):
			out = arg.substr(4)
		elif arg == "night":
			night = true
	var rig = ScreenshotRig.new(self, "SERVICE_PARK_SCREENSHOT")
	var game = rig.open_stage(variant)
	if game == null:
		return
	if night:
		game.sky_weather.set_conditions("night", "sun")
	var parks = game.stage.parks
	var index = 0
	for i in range(Parks.KEYS.size()):
		var key: String = Parks.KEYS[i]
		var car: Node3D
		if key.begins_with("crew"):
			car = game.Props.rally_car(int(key.substr(4)) % 6)
		elif key.begins_with("zero"):
			car = game.Props.course_car("zero", int(key.substr(4)) - 1)
		else:
			car = game.Props.course_car("police")
		game.add_child(car)
		var pose: Transform3D = parks.slot_pose(index, key)
		car.transform = pose
		car.position.y = game.stage.ground(pose.origin) + 0.06
	var player = game.Props.player_car(0)
	game.add_child(player)
	player.transform = parks.visitor_pose(index, 0)
	player.position.y = game.stage.ground(player.position) + 0.06
	for name in VIEWS:
		var view: Array = VIEWS[name]
		var from: Vector3 = parks.world(index, view[0].x, view[0].y)
		from.y = game.stage.ground(from) + view[0].z
		var to: Vector3 = parks.world(index, view[1].x, view[1].z)
		to.y = game.stage.ground(to) + view[1].y
		rig.aim(from, to, 62.0)
		# Night lamps light up near the game camera: put it at the shot.
		if game.camera != null:
			game.camera.global_transform = rig.camera.global_transform
		await rig.capture("%s-%s.webp" % [out, name], Vector2i(1280, 720))
	await rig.close()
