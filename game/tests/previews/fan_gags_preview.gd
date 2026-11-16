extends SceneTree
# Screenshots of the fan gags (mooning, a crew at lunch, a night flare):
#   xvfb-run godot --path game --script res://tests/previews/fan_gags_preview.gd -- <out_dir>
const CharacterRig = preload("res://scripts/people/character_rig.gd")
const FanFlares = preload("res://scripts/people/fan_flares.gd")
const CrewLunch = preload("res://scripts/people/crew_lunch.gd")

var out = ".."

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if not args.is_empty():
		out = args[0]
	call_deferred("run")

func shot(name: String) -> void:
	for i in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("FAN GAGS PREVIEW: " + name)

func aim(game, from: Vector3, to: Vector3) -> void:
	game.camera.global_position = from
	game.camera.look_at(to)
	game.sky_weather.night_lights.update(self, game.sky_weather.daytime == "night", from, 0.4)

func run() -> void:
	root.size = Vector2i(1280, 720)
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await game.start_game()
	game.set_process(false)
	game.room.set_process(false)
	game.in_car = false
	game.car.position += Vector3(0, -50, 0)
	if game.hud is CanvasItem or game.hud is CanvasLayer:
		game.hud.visible = false
	var spectators = game.spectators
	var person: Dictionary = spectators.people[0]
	var watch: Vector3 = person.watch
	var s = game.stage.road_s(watch)
	var direction: Vector3 = game.stage.direction(s)
	var side: Vector3 = (watch - game.stage.at(s)).normalized()
	# A crew coming at the fan, the fan mooning it.
	game.course.phase = "racing"
	game.spawn_racer("pass")
	var racer: Dictionary = game.racers[-1]
	racer.node.position = game.stage.at(s - 14.0)
	racer.node.position.y = game.stage.ground(racer.node.position)
	racer.node.rotation.y = atan2(-direction.x, -direction.z)
	person.avatar.position = watch
	var toward = game.stage.at(s) - watch
	person.avatar.rotation.y = atan2(-toward.x, -toward.z) + PI
	CharacterRig.pose(person.avatar, {"moon": true, "time": 0.4})
	aim(game, game.stage.at(s - 7.0) + Vector3(0, 1.3, 0), watch + Vector3(0, 0.8, 0))
	await shot("moon-crew-view")
	aim(game, game.stage.at(s + 1.5) + Vector3(0, 1.2, 0), watch + Vector3(0, 0.8, 0))
	await shot("moon-road")
	aim(game, watch - side * 3.0 + direction * 0.8 + Vector3(0, 1.1, 0), watch + Vector3(0, 0.8, 0))
	await shot("moon-close")
	aim(game, watch + side * 3.0 - direction * 4.0 + Vector3(0, 1.4, 0), watch + Vector3(0, 0.8, 0))
	await shot("moon-side")
	# A night flare for the passing crew.
	game.sky_weather.set_conditions("night", "sun")
	CharacterRig.pose(person.avatar, {})
	person.avatar.rotation.y -= PI
	var other: Dictionary = spectators.people[1] if spectators.people.size() > 1 else person
	for fan in [person]:
		FanFlares.update(fan, true, 0.1)
		CharacterRig.pose(fan.avatar, {"arms": "flag", "wave": 0.3})
	CharacterRig.pose(other.avatar, {"arms": "cheer", "wave": 0.6})
	for i in range(40):
		await process_frame
	aim(game, watch + side * 4.0 - direction * 6.0 + Vector3(0, 1.8, 0), watch + Vector3(0, 1.4, 0))
	await shot("flare-night")
	aim(game, game.stage.at(s + 2.0) + Vector3(0, 1.5, 0), watch + Vector3(0, 1.3, 0))
	await shot("flare-night-road")
	FanFlares.update(person, false, 99.0)
	game.sky_weather.set_conditions("day", "sun")
	# A crew at lunch at the camp table.
	racer.state = "stranded"
	racer.node.position = game.stage.at(s + 40.0) + game.stage.side(s + 40.0) * 3.0
	racer.lunch_wait = CrewLunch.DELAY + 1.0
	spectators.lunch.update(spectators, 0.1, false)
	var crew: Dictionary = spectators.lunch.crews.get(racer.id, {})
	if crew.is_empty():
		push_error("no lunch")
		quit(1)
		return
	aim(game, racer.node.position + game.stage.side(s + 40.0) * 3.5 + Vector3(0, 1.6, 2.5), racer.node.position + Vector3(0, 0.9, 0))
	await shot("lunch-empty-car")
	for i in range(3000):
		spectators.lunch.update(spectators, 0.1, false)
		if crew.people.all(func(p): return p.phase == "lunch"):
			break
	for i in range(12):
		spectators.lunch.update(spectators, 0.1, false)
	var group: Dictionary = spectators.groups[int(racer.lunch)]
	var table: Vector3 = group.table.position
	var away = (table - game.stage.at(game.stage.road_s(table)))
	away.y = 0
	aim(game, table + away.normalized() * 4.5 + Vector3(0, 2.0, 0) + group.table.global_basis.z * 2.0, table + Vector3(0, 0.8, 0))
	await shot("lunch-table")
	quit()
