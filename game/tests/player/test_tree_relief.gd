extends "res://tests/harness.gd"
# The unlisted tree break: only after a beer and only at a standing tree; the
# stream follows the view, lands and wets the ground, makes people complain,
# and friends see it.
const PeerView = preload("res://scripts/net/peer_view.gd")
const NetProtocol = preload("res://scripts/net/net_protocol.gd")
const TreeRelief = preload("res://scripts/player/tree_relief.gd")

func _initialize() -> void:
	call_deferred("run")

func face(game, target: Vector3) -> void:
	var to = target - game.walker
	game.view_yaw = atan2(-to.x, -to.z)
	game.camera.position = game.walker + Vector3(0, 1.72, 0)
	game.camera.look_at(target)
	game.view_pitch = game.camera.rotation.x

func frames(game, count: int) -> Dictionary:
	var relief = game.player.relief
	for i in range(count):
		game.player.walk(1.0 / 30.0)
	return relief.stream

func stream_end(relief) -> Vector3:
	return relief.stream.points[-1]

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	await game.start_game()
	game.in_car = false
	var relief = game.player.relief
	# A standing tree with flat-ish ground in front of it.
	var tree = -1
	for i in range(game.stage.trees.size()):
		var base: Vector3 = game.stage.trees[i]
		if not game.stage.fallen.has(i) and absf(base.x) < 120 and game.stage.road_distance(base) > 9:
			tree = i
			break
	var base: Vector3 = game.stage.trees[tree]
	var away = (game.stage.at(game.stage.road_s(base)) - base)
	away.y = 0
	game.walker = base + away.normalized() * 1.3
	game.walker.y = game.stage.ground(game.walker)
	face(game, base + Vector3(0, 1.0, 0))
	game.beers = 0
	check(game.interaction.current().get("action", "") != "relief", "sober fans get no tree option")
	game.beers = 1
	var target = game.interaction.current()
	check(target.get("action", "") == "relief" and target.get("label", "") == "Отлить", "after a beer the tree offers its hidden action")
	game.interaction.activate()
	check(relief.active and game.walking_intent() == Vector3.ZERO and not game.jump(), "standing still while busy")
	check(game.interaction.current().get("action", "") == "relief_stop", "F again finishes")
	# Aim at the tree trunk, then down at the ground.
	frames(game, 3)
	check(relief.stream.segments.visible and relief.stream.hit.get("kind", "") == "tree", "the stream reaches the tree")
	game.view_yaw += PI / 2
	game.view_pitch = -0.9
	frames(game, 40)
	var ahead = stream_end(relief) - game.walker
	game.view_yaw += PI
	frames(game, 2)
	var behind = stream_end(relief) - game.walker
	check(Vector2(ahead.x, ahead.z).dot(Vector2(behind.x, behind.z)) < 0, "turning the camera turns the stream with the fan")
	game.view_pitch = 0.4
	frames(game, 2)
	var far = stream_end(relief) - game.walker
	check(Vector2(far.x, far.z).length() > Vector2(behind.x, behind.z).length() + 0.3, "looking up sends the stream further")
	# Someone standing in front of the fan complains.
	var person: Dictionary = game.spectators.people[0]
	var forward = Vector3(-sin(game.view_yaw), 0, -cos(game.view_yaw))
	game.view_pitch = -0.2
	person.avatar.position = game.walker + forward * 0.9
	person.avatar.position.y = game.stage.ground(person.avatar.position)
	relief.complaint_at = -INF
	game.toast_label.text = ""
	frames(game, 2)
	check(game.toast_label.text in TreeRelief.COMPLAINTS, "a person in the way complains (%s)" % game.toast_label.text)
	person.avatar.position = person.home
	# Finishing: F, running out, or doing something else.
	game.interaction.activate()
	check(not relief.active and not relief.stream.segments.visible, "F again ends it and hides the stream")
	relief.start()
	relief.time_left = 0.01
	frames(game, 2)
	check(not relief.active and game.toast_label.text == "Полегчало.", "an empty bladder ends it")
	relief.start()
	game.drink_time = 0.0
	frames(game, 1)
	check(not relief.active, "starting to drink ends it")
	game.drink_time = -1.0
	# The room: the state carries the flag; friends see the pose and the stream.
	relief.start()
	check(game.room.local_state().relief == true, "the room state reports it")
	var clean = NetProtocol.clean_state(game.room.local_state())
	check(clean.relief == true, "the host keeps the flag of a pedestrian")
	var state = game.room.local_state()
	state.in_car = true
	check(NetProtocol.clean_state(state).relief == false, "never from a car")
	relief.stop()
	var friend_spot = game.walker + forward * 1.2
	friend_spot.y = game.stage.ground(friend_spot)
	var peer = PeerView.create(game, {"id": "friend", "name": "Друг", "slot": 2, "car_model": 0, "state": null})
	var friend_yaw = atan2(forward.x, forward.z) # facing back at the local fan
	peer.state = {"in_car": false, "pos": [friend_spot.x, friend_spot.y, friend_spot.z], "car": [friend_spot.x + 30, friend_spot.y, friend_spot.z], "push": [0, 0, 0], "beers": 2, "beer": -1, "eat": -1, "pitch": -0.25, "yaw": friend_yaw, "relief": true}
	for i in range(3):
		peer.avatar_motion.push(i * 0.1, friend_spot, Vector3(0, friend_yaw, 0))
		peer.car_motion.push(i * 0.1, friend_spot + Vector3(30, 0, 0), Vector3.ZERO)
	relief.complaint_at = -INF
	PeerView.animate(game, peer, 1.0 / 30.0, 0.3, false, false)
	check(peer.relief.segments.visible, "friends see the stream")
	check(CharacterRig_grip_low(peer.avatar), "friends see both hands in front of the belt")
	check(game.toast_label.text == "Тебя облили! Фу-у-у!", "being reached by a friend's stream is noticed (%s)" % game.toast_label.text)
	peer.state.relief = false
	PeerView.animate(game, peer, 1.0 / 30.0, 0.4, false, false)
	check(not peer.relief.segments.visible, "the friend's stream stops with the state")
	PeerView.remove(peer)
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	print("TREE RELIEF RESULT: %d checks, %d failures" % [checks, failures])
	finish()

func CharacterRig_grip_low(avatar: Node3D) -> bool:
	var rig = preload("res://scripts/people/character_rig.gd")
	var left = rig.grip_position(avatar, "Left")
	var right = rig.grip_position(avatar, "Right")
	return left.y < 0.95 and right.y < 0.95 and left.z < -0.15 and right.z < -0.15 and absf(left.x) < 0.2 and absf(right.x) < 0.2
