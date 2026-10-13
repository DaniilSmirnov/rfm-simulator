extends "res://tests/harness.gd"
const Props = preload("res://scripts/props.gd")
const Perches = preload("res://scripts/perches.gd")

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
	check(not play.landing("player:local", pos + Vector3.UP, pos + Vector3.UP * 2), "ascending through shoulder height does not knock a person")
	check(not play.landing("player:local", pos + Vector3(2, 2, 0), pos + Vector3(2, 1, 0)), "missing the person horizontally does not knock them")
	check(play.landing("player:local", pos + Vector3.UP * 2, pos + Vector3.UP), "descending feet sweep knocks a spectator")
	check(game.injuries.records[key].play and not game.injuries.red_flag(), "playful fall never calls an ambulance or red flag")
	check(not play.stand(key), "cannot stand while still flying")
	game.injuries._land(game.injuries.records[key])
	var fallen: Vector3 = game.injuries.records[key].pos
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
	for node in [Props.grill(game), Props.campfire(game), Props.cauldron(game)]:
		check(node.is_in_group(Perches.GROUP), "camp object supplies a jump surface")
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	finish()
