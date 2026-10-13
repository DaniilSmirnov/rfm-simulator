extends SceneTree
# Climbing onto things (perches.gd) in the real game scene: the walker is moved
# by the game's own walking code (jumps, landings, riding a car) and a visible
# avatar is put where the walker is, since the player's own body is not drawn
# in first person.
# Run: xvfb-run -a godot --path game --rendering-method gl_compatibility --audio-driver Dummy --script res://tools/screenshots/export_perch_screenshots.gd -- [frames_dir]
# With frames_dir, every second frame of the car sequence is saved there as
# PNG (for a video: ffmpeg -framerate 30 -i frames_dir/%04d.png ...).
const ScreenshotRig = preload("res://tools/screenshots/screenshot_rig.gd")
const CharacterRig = preload("res://scripts/people/character_rig.gd")
const Props = preload("res://scripts/core/props.gd")
const STATION = 300.0

var rig
var game
var avatar: Node3D
var frames_dir = ""
var frame = 0

func _initialize() -> void: call_deferred("run")

func face(target: Vector3) -> void:
	var to = target - game.walker
	game.view_yaw = atan2(-to.x, -to.z)

# One game frame of walking; the avatar follows the walker; the camera
# follows `follow` from the side.
func step(target, leap: bool, follow: Node3D) -> void:
	if target != null:
		face(target)
		Input.action_press("forward")
	else:
		Input.action_release("forward")
	if leap:
		game.jump()
	game._walk(1.0 / 60.0)
	avatar.position = game.walker
	avatar.rotation = Vector3(0, game.view_yaw, 0)
	CharacterRig.pose(avatar, {"gait": 1 if target != null else 0, "time": frame / 60.0, "airborne": game.jump_height > 0.01})
	var side: Vector3 = game.stage.side(STATION)
	var centre = follow.position + Vector3(0, 1.0, 0)
	rig.aim(centre + side * 7.5 + game.stage.direction(STATION) * 2.5 + Vector3(0, 2.6, 0), centre, 60.0)
	frame += 1
	if frames_dir != "" and frame % 2 == 0:
		rig.viewport.size = Vector2i(960, 540)
		rig.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		await process_frame
		await RenderingServer.frame_post_draw
		rig.viewport.get_texture().get_image().save_png(frames_dir.path_join("%04d.png" % (frame / 2)))

func walk_for(seconds: float, target, leap: bool, follow: Node3D) -> void:
	for i in range(int(seconds * 60.0)):
		await step(target, leap and i == 0, follow)

func run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() > 0:
		frames_dir = args[0]
		DirAccess.make_dir_recursive_absolute(frames_dir)
	rig = ScreenshotRig.new(self, "PERCH_SCREENSHOT")
	game = rig.open_stage(0)
	if game == null:
		return
	var stage = game.stage
	stage.trees.clear()
	stage.rocks.clear()
	game.playing = true
	game.in_car = false
	var forward: Vector3 = stage.direction(STATION)
	var side: Vector3 = stage.side(STATION)
	var yaw = atan2(-forward.x, -forward.z)
	avatar = Props.player_avatar(2)
	game.add_child(avatar)

	# A car on the road: a jump onto the bonnet, a second one onto the roof.
	var car: Node3D = Props.player_car(1)
	game.add_child(car)
	car.position = stage.at(STATION)
	car.position.y = stage.ground(car.position)
	car.rotation.y = yaw
	game.car.position = stage.at(30)
	game.walker = car.position + forward * 1.5 + side * 3.2
	game.walker.y = stage.ground(game.walker)
	await walk_for(0.6, null, false, car)
	await walk_for(0.5, car.position + forward * 1.5, false, car)
	await walk_for(0.9, car.position + forward * 1.4, true, car)
	await walk_for(0.4, car.position + forward * 0.9, false, car)
	await walk_for(0.4, null, false, car)
	await walk_for(0.8, car.position + forward * 0.1, true, car)
	await walk_for(0.5, null, false, car)
	await rig.capture("res://../docs/screenshots/perch-car-roof.webp", Vector2i(1920, 1080))
	# The car drives off with the fan on the roof.
	for i in range(150):
		car.position += forward.rotated(Vector3.UP, i * 0.002) * minf(i, 60) / 60.0 * 0.16
		car.position.y = stage.ground(car.position)
		car.rotation.y += 0.002
		Props.animate_wheels(car)
		await step(null, false, car)
	await rig.capture("res://../docs/screenshots/perch-car-ride.webp", Vector2i(1920, 1080))
	frames_dir = ""

	# Camp: a fan on the table, one on a chair, one on a casualty lying down.
	var camp_at: Vector3 = stage.at(STATION + 40.0) + stage.side(STATION + 40.0) * 7.0
	camp_at.y = stage.ground(camp_at)
	game.camp = Node3D.new()
	game.add_child(game.camp)
	Props.table(game.camp, 2)
	game.camp.position = camp_at
	game.camp.rotation.y = yaw
	var chair = Node3D.new()
	game.add_child(chair)
	Props.chair(chair, Vector3.ZERO)
	chair.position = camp_at + forward * 1.8
	chair.position.y = stage.ground(chair.position)
	chair.rotation.y = yaw
	var person: Dictionary = game.spectators.people[0]
	var key = "npc:%d" % person.id
	var body: Vector3 = camp_at - forward * 2.2
	body.y = stage.ground(body) + 0.25
	game.injuries.records[key] = {"phase": "lying", "pos": body, "rot": Vector3(0, yaw + PI / 2, PI / 2), "time": 0.0, "treat": 0.0, "limp": 0.0, "ambulance": -1, "station": STATION + 40.0}
	game.injuries._pose(key, body, Vector3(0, yaw + PI / 2, PI / 2), 1.0)
	var climbers: Array = []
	for target in [camp_at, chair.position, body - forward * 0.6]:
		game.walker = target + side * 1.5
		game.walker.y = stage.ground(game.walker)
		game.jump_height = 0
		game.jump_velocity = 0
		game.player.perches.clear()
		await walk_for(0.6, target, true, game.camp)
		await walk_for(0.4, null, false, game.camp)
		var fan = Props.player_avatar(climbers.size() + 3)
		game.add_child(fan)
		fan.position = game.walker
		fan.rotation.y = yaw + PI / 2
		CharacterRig.pose(fan, {"arms": "cheer"})
		climbers.append(fan)
		print("PERCH_SCREENSHOT standing %.2f m above the ground" % (game.walker.y - stage.ground(game.walker)))
	avatar.hide()
	var centre = camp_at + Vector3(0, 0.8, 0)
	rig.aim(centre + side * 6.5 - forward * 3.0 + Vector3(0, 2.2, 0), centre - forward * 0.3, 62.0)
	await rig.capture("res://../docs/screenshots/perch-camp.webp", Vector2i(1920, 1080))
	await rig.close()
