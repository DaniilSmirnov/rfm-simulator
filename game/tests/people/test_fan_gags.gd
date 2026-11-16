extends "res://tests/harness.gd"
# Fan gags from real rallies: mooning a crew (the pilot has a moment), a crew
# that retires walking over to a camp for lunch, red hand flares at night.
const CharacterRig = preload("res://scripts/people/character_rig.gd")
const Mooning = preload("res://scripts/people/mooning.gd")
const FanFlares = preload("res://scripts/people/fan_flares.gd")
const CrewLunch = preload("res://scripts/people/crew_lunch.gd")
const NetProtocol = preload("res://scripts/net/net_protocol.gd")
const NightLights = preload("res://scripts/core/night_lights.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	await game.start_game()
	game.in_car = false
	rig(game)
	moon_crew(game)
	player_moon(game)
	flares(game)
	await lunch(game)
	print("FAN GAGS RESULT: %d checks, %d failures" % [checks, failures])
	finish()

func rig(game) -> void:
	var avatar = game.Props.player_avatar(0)
	game.add_child(avatar)
	avatar.rotation.y = 0.3
	var shin: Node3D = avatar.get_node("LeftLeg/LeftShin")
	CharacterRig.pose(avatar, {})
	var standing = (shin.global_transform * Vector3(0, -0.31, 0)).y
	CharacterRig.pose(avatar, {"moon": true})
	var censor = avatar.get_node_or_null(CharacterRig.MOON_CENSOR)
	check(censor != null and censor.visible, "mooning shows the censor mosaic")
	check(absf(avatar.rotation.x + CharacterRig.MOON_LEAN) < 0.001 and absf(avatar.rotation.y - 0.3) < 0.001, "the body bends forward and keeps its heading")
	# Feet stay on the ground: bent knees take up the lean.
	var foot = shin.global_transform * Vector3(0, -0.31, 0)
	check(absf(foot.y - standing) < 0.04, "bent knees keep the feet on the ground (%.3f)" % (foot.y - standing))
	var behind = censor.global_position - avatar.global_position
	check(behind.dot(avatar.global_basis.z) > 0.1 or behind.dot(Basis(Vector3.UP, 0.3).z) > 0.1, "the mosaic is on the backside")
	CharacterRig.pose(avatar, {})
	check(not censor.visible and absf(avatar.rotation.x) < 0.001 and not avatar.has_meta("rig_moon"), "standing up puts everything back")
	avatar.rotation.x = 1.2
	CharacterRig.pose(avatar, {})
	check(absf(avatar.rotation.x - 1.2) < 0.001, "someone who never mooned keeps their own tilt (a casualty)")
	avatar.free()

func racing_crew(game, s: float) -> Dictionary:
	game.course.phase = "racing"
	game.spawn_racer("pass")
	var racer: Dictionary = game.racers[-1]
	racer.s = s
	racer.node.position = game.stage.at(s)
	var direction = game.stage.direction(s)
	racer.node.rotation = Vector3(0, atan2(-direction.x, -direction.z), 0)
	racer.state = "racing"
	racer.erase("mistake")
	return racer

func moon_crew(game) -> void:
	var racer = racing_crew(game, 400.0)
	var node: Node3D = racer.node
	var ahead: Vector3 = node.position - node.basis.z * 12.0 + node.basis.x * 6.0
	var behind: Vector3 = node.position + node.basis.z * 12.0
	check(Mooning.scare(game, [{"key": "npc:1", "pos": behind}]).is_empty() and racer.get("mistake", {}).is_empty(), "a fan behind the car goes unseen")
	check(Mooning.scare(game, [{"key": "npc:1", "pos": node.position - node.basis.z * 40.0}]).is_empty(), "a fan too far ahead goes unseen")
	var hits = Mooning.scare(game, [{"key": "npc:1", "pos": ahead}])
	check(hits.size() == 1 and str(racer.get("mistake", {}).get("kind", "")) == "moment", "a fan mooning ahead gives the crew a moment")
	check(float(racer.mistake.kick) > 0.0, "the tail steps out away from the fan on the right")
	racer.erase("mistake")
	check(Mooning.scare(game, [{"key": "npc:1", "pos": ahead}]).is_empty(), "the same fan fools a crew only once")
	check(Mooning.scare(game, [{"key": "npc:2", "pos": ahead}]).size() == 1, "another fan still does")
	racer.erase("mistake")
	# Camp pranksters: about one in four, at about half the crews.
	var pranks = 0
	for id in range(400):
		pranks += 1 if Mooning.prankster(id, 0, 7) else 0
	check(pranks > 20 and pranks < 80, "a few camp fans moon a given crew (%d of 400)" % pranks)
	# A camp spectator who moons turns his back on the road.
	var person: Dictionary = {}
	for candidate in game.spectators.people:
		if Mooning.prankster(int(candidate.id), game.stage.variant, int(racer.id)):
			person = candidate
			break
	if person.is_empty():
		check(false, "the stage has a prankster for this crew")
		return
	var watch: Vector3 = person.watch
	person.avatar.position = watch
	racer.s = game.stage.road_s(watch)
	node.position = game.stage.at(racer.s) - node.basis.z * 0.0
	racer.mooned = {}
	game.spectators.update(idle_time(game, person), 0.0, false)
	check(person.action == "moon", "a prankster moons the passing crew instead of cheering")
	var road = game.stage.at(game.stage.road_s(person.avatar.position)) - person.avatar.position
	check(Vector3(-sin(person.avatar.rotation.y), 0, -cos(person.avatar.rotation.y)).dot(road.normalized()) < -0.5, "with his back to the road")
	check(game.spectators.actor_snapshot().any(func(e): return int(e.id) == int(person.id) and e.get("action", "") == "moon"), "guests get the mooning in the people snapshot")
	game.racers.erase(racer)
	node.queue_free()

# A moment when the camp fan has nothing in hand (no beer, no skewer).
func idle_time(game, person: Dictionary) -> float:
	var t = game.spectators.clock + 0.01
	while game.spectators.activity(int(person.id), t).action != "idle":
		t += 0.25
	return t

func player_moon(game) -> void:
	var racer = racing_crew(game, 600.0)
	var node: Node3D = racer.node
	game.walker = node.position - node.basis.z * 15.0 + node.basis.x * 7.0
	game.walker.y = game.stage.ground(game.walker)
	game.camera.global_position = game.walker + Vector3(0, 1.72, 0)
	game.camera.look_at(node.position + Vector3(0, 0.8, 0))
	game.beers = 0
	var target = game.interaction.current()
	check(target.get("action", "") == "moon" and target.get("label", "") == preload("res://scripts/ui/loc.gd").t("Показать зад экипажу"), "looking at a crew coming offers the prank")
	game.interaction.activate()
	check(game.player.moon.active and game.room.local_state().get("moon", false), "the prank starts and goes into the room state")
	check(game.interaction.current().is_empty(), "nothing else is offered meanwhile")
	var mooners = Mooning.players(game)
	check(mooners.size() == 1 and mooners[0].key == game.injuries.local_key(), "the host counts the player among the mooners")
	game.spectators._scare_crews()
	check(str(racer.get("mistake", {}).get("kind", "")) == "moment", "the crew has a moment for the player")
	for i in range(int(game.player.moon.DURATION * 30) + 2):
		game.player.walk(1.0 / 30.0)
	check(not game.player.moon.active, "after a few seconds the fan stands up")
	var clean = NetProtocol.clean_state({"pos": [0, 0, 0], "car": [0, 0, 0], "heading": 0, "yaw": 0, "pitch": 0, "in_car": false, "moon": true})
	check(clean.moon == true and NetProtocol.clean_state({"pos": [0, 0, 0], "car": [0, 0, 0], "heading": 0, "yaw": 0, "pitch": 0, "in_car": true, "moon": true}).moon == false, "only a fan on foot moons in a room")
	game.racers.erase(racer)
	node.queue_free()

func flares(game) -> void:
	var person: Dictionary = game.spectators.people[0]
	check(not FanFlares.update(person, false, 0.1) and not person.has("flare"), "no flare by day or without a crew")
	check(FanFlares.update(person, true, 0.1), "a passing crew at night lights the flare")
	var flare: Node3D = person.flare
	check(flare.visible and flare.get_node("Smoke").emitting, "it burns and smokes")
	var fire = flare.get_node("Fire")
	check(fire.is_in_group(NightLights.GROUP) and NightLights.KINDS.has(str(fire.get_meta("night_light"))), "the flame lights the night around it")
	check(FanFlares.update(person, false, FanFlares.LINGER - 0.5), "it keeps burning a little after the car")
	check(not FanFlares.update(person, false, 1.0) and not flare.visible, "then goes out")
	# Spectators hold it up at night only.
	game.sky_weather.daytime = "night"
	person.flare_left = 0.0
	var holder: Dictionary = {}
	var racer = racing_crew(game, 300.0)
	for candidate in game.spectators.people:
		if int(candidate.id) % 2 == 0 and not Mooning.prankster(int(candidate.id), game.stage.variant, int(racer.id)):
			holder = candidate
			break
	holder.avatar.position = holder.watch
	racer.s = game.stage.road_s(holder.watch)
	racer.node.position = game.stage.at(racer.s)
	game.spectators.update(idle_time(game, holder), 0.0, false)
	check(holder.action == "cheer" and holder.has("flare") and holder.flare.visible, "a cheering camp fan waves a lit flare at night")
	game.sky_weather.daytime = "day"
	game.racers.erase(racer)
	racer.node.queue_free()

func lunch(game) -> void:
	game.course.phase = "racing"
	game.spawn_racer("crash")
	var racer: Dictionary = game.racers[-1]
	var group: Dictionary = game.spectators.groups[0]
	var s = game.stage.road_s(group.table.position) + 70.0
	racer.s = s
	racer.node.position = game.stage.at(s)
	racer.state = "stranded"
	var before: Mesh = racer.node.get_node("Baked").mesh
	var spectators = game.spectators
	# Fans nearby would push it: here nobody is close enough.
	for i in range(int(CrewLunch.DELAY / 0.5) - 2):
		spectators.lunch.update(spectators, 0.5, false)
	check(racer.state == "stranded", "a stranded crew first waits to be pulled out")
	racer.recovery_helpers = 1
	spectators.lunch.update(spectators, 5.0, false)
	check(float(racer.get("lunch_wait", 0.0)) == 0.0, "someone working on the car keeps the crew waiting")
	racer.erase("recovery_helpers")
	for i in range(int(CrewLunch.DELAY / 0.5) + 2):
		spectators.lunch.update(spectators, 0.5, false)
	check(racer.state == "parked" and int(racer.get("lunch", -1)) == CrewLunch.nearest_camp(spectators, racer.node.position), "left alone, the crew retires to the nearest camp")
	check(not game.can_tow_racer(racer), "a crew at lunch is no longer towed")
	check(spectators.lunch.crews.has(racer.id) and spectators.lunch.crews[racer.id].people.size() == 2, "pilot and navigator get out")
	check(racer.node.get_node("Baked").mesh != before, "the cabin of the car empties")
	var snapshot = game.room.world_state()
	check(snapshot.racers.any(func(r): return int(r.get("lunch", -1)) == int(racer.lunch)), "guests learn where the crew went")
	var crew: Dictionary = spectators.lunch.crews[racer.id]
	for i in range(1800):
		spectators.lunch.update(spectators, 1.0 / 10.0, false)
		await process_frame
		if crew.people.all(func(p): return p.phase == "lunch"):
			break
	check(crew.people.all(func(p): return p.phase == "lunch"), "both walk over to the camp table")
	for person in crew.people:
		check(Vector2(person.avatar.position.x - group.table.position.x, person.avatar.position.z - group.table.position.z).length() < 2.5 or int(racer.lunch) != 0, "and eat there")
	game.racers.erase(racer)
	spectators.lunch.update(spectators, 0.1, false)
	check(not spectators.lunch.crews.has(racer.id), "the walkers go with the crew")
