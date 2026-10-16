extends "res://tests/harness.gd"
const Props = preload("res://scripts/core/props.gd")
const Perches = preload("res://scripts/player/perches.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.start_game()
	game.in_car = false
	var person: Dictionary = game.spectators.people[0]
	var pos: Vector3 = game.stage.at(200) + game.stage.side(200) * 8
	pos.y = game.stage.ground(pos)
	person.avatar.position = pos
	var key = "npc:%d" % person.id
	var play = game.injuries.play
	play.injuries = game.injuries
	# Target the host from a guest, away from NPCs, through the network sweep.
	game.walker = pos + Vector3(20, 0, 0)
	var target: Vector3 = game.walker
	check(not play.landing("player:friend", target + Vector3(0.6, 1.1, 0), target + Vector3(0.6, 1.3, 0)), "ascending upper-body contact does not knock a player")
	check(not play.landing("player:friend", target + Vector3(0.6, 0.84, 0), target + Vector3(0.6, 0.7, 0)), "ordinary jump from the same ground is too low")
	check(not play.landing("player:friend", target + Vector3(0.8, 1.4, 0), target + Vector3(0.8, 1.1, 0)), "falling past outside body contact does not knock a player")
	check(not play.landing("player:local", target + Vector3.UP * 1.4, target + Vector3.UP * 1.1), "player cannot knock themselves down")
	var jumper = {"pos": game.room.a(target + Vector3(1.0, 1.4, 0)), "in_car": false, "airborne": true}
	play.update({"friend": jumper}, 0.1)
	jumper.pos = game.room.a(target + Vector3(0.6, 1.1, 0))
	play.update({"friend": jumper}, 0.1)
	check(game.injuries.down and game.injuries.records["player:local"].play, "guest descending into upper body below shoulders knocks the host playfully")
	check(not game.injuries.red_flag(), "player jump contact does not call an ambulance")
	game.injuries._land(game.injuries.records["player:local"])
	check(play.stand("player:local"), "player can get up after the easier jump contact")
	game.injuries.records.erase("player:local")
	play.previous.clear()
	check(not play.landing("player:local", pos + Vector3.UP, pos + Vector3.UP * 2), "ascending through shoulder height does not knock a person")
	check(not play.landing("player:local", pos + Vector3(2, 2, 0), pos + Vector3(2, 1, 0)), "missing the person horizontally does not knock them")
	check(play.landing("player:local", pos + Vector3.UP * 2, pos + Vector3.UP), "descending feet sweep knocks a spectator")
	check(game.injuries.records[key].play and not game.injuries.red_flag(), "playful fall never calls an ambulance or red flag")
	check(not play.stand(key), "cannot stand while still flying")
	game.injuries._land(game.injuries.records[key])
	var fallen: Vector3 = game.injuries.records[key].pos
	game.enable_mobile()
	game.walker = fallen + Vector3(2, 0, 0)
	check(game.mobile_controls.tow_caption() == "Тащить", "mobile tow caption names a nearby person")
	game.walker = fallen + Vector3(10, 0, 0)
	check(game.mobile_controls.tow_caption() == "Трос", "mobile caption switches back after leaving a person")
	game.walker = fallen + Vector3(2, 0, 0)
	var helper = {"pos": game.room.a(fallen + Vector3(2, 0, 0)), "in_car": false, "tow": true, "push": [1, 0, 0]}
	var occupied = play.update({"local": helper}, 0.1)
	check(occupied.has("local"), "person interaction consumes tow so it cannot also pull a car")
	check(game.injuries.records[key].pos.x > fallen.x, "moving helper drags the person")
	helper.tow = false
	play.update({"local": helper}, 0.1)
	check(not play.grabbed(key), "releasing tow releases person")
	helper.tow = true
	helper.push = [0, 0, 0]
	play.update({"local": helper}, 1.1)
	check(not game.injuries.is_down(key) and game.injuries.returning.has(key), "stationary help gets NPC up and sends them home")
	check(game.injuries.knock("player:local", pos, Vector3.ZERO, pos, true), "player can suffer playful fall")
	game.injuries._land(game.injuries.records["player:local"])
	check(game.jump() and not game.injuries.down and game.injuries.limp == 0, "space stands up without medical limp")
	game.injuries.records.erase("player:local")
	game.injuries.knock("player:local", pos, Vector3(8, 0, 0), pos)
	game.injuries._land(game.injuries.records["player:local"])
	check(not play.stand("player:local"), "space cannot bypass treatment for a car casualty")
	var casualty: Dictionary = game.injuries.records["player:local"]
	var casualty_start: Vector3 = casualty.pos
	var ambulance_id = int(casualty.ambulance)
	var rescuer = {"pos": game.room.a(casualty_start + Vector3(2, 0, 0)), "in_car": false, "tow": true, "push": [1, 0, 0]}
	occupied = play.update({"friend": rescuer}, 0.1)
	check(occupied.has("friend") and casualty.pos.x > casualty_start.x, "helper can drag a car casualty")
	check(absf(casualty.station - game.race_station(casualty.pos)) < 0.001 and int(casualty.ambulance) == ambulance_id, "dragging updates rescue location without discarding ambulance")
	rescuer.push = [0, 0, 0]
	play.update({"friend": rescuer}, 2.0)
	check(game.injuries.is_down("player:local") and not play.stand("player:local"), "stationary helper cannot heal a car casualty")
	rescuer.tow = false
	play.update({"friend": rescuer}, 0.1)
	check(not play.grabbed("player:local"), "releasing tow also releases a car casualty")
	for node in [Props.grill(game), Props.campfire(game), Props.cauldron(game)]:
		check(node.is_in_group(Perches.GROUP), "camp object supplies a jump surface")
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	finish()
