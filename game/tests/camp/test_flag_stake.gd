extends "res://tests/harness.gd"
# A placed flag is staked into the ground: it stands plumb on a hillside, never
# tips by itself, and falls only when a car runs into it, for host and guest.
func _initialize() -> void:
	call_deferred("run")

func up(node: Node3D) -> float:
	return node.global_basis.y.normalized().dot(Vector3.UP)

func run() -> void:
	var host = load("res://main.tscn").instantiate()
	var guest = load("res://main.tscn").instantiate()
	for game in [host, guest]:
		root.add_child(game)
	await process_frame
	for game in [host, guest]:
		game.set_process(false)
		game.room.set_process(false)
		game.start_game()
		game.in_car = false
		game.room.connected = true
	host.room.is_host = true
	host.room.player_id = "host"
	guest.room.player_id = "guest"
	var spots: Array = [host.stage.clearings[0] + Vector3(3, 0, 0)]
	for x in range(-180, 181, 6):
		for z in range(-180, 181, 6):
			var candidate = Vector3(x, 0, z)
			candidate.y = host.stage.ground(candidate)
			var slope = host.stage.terrain_basis(candidate, 0.0, host.stage.ground).y.dot(Vector3.UP)
			if slope < 0.9 and slope > 0.75 and host.valid_furniture_spot(candidate, "flag"):
				spots.append(candidate)
				break
		if spots.size() > 1:
			break
	check(spots.size() == 2, "a permitted hillside flag spot exists")
	for spot in spots:
		# The walker stays clear so nothing but the ground touches the flags.
		host.walker = spot
		check(host.place_flag(spot, 0.6), "a flag can be placed")
	host.walker = spots[0] + Vector3(0, 0, 8)
	var flags: Array = host.personal_flags.get("host", [])
	host.movable_props.refresh()
	for i in range(240):
		await physics_frame
	for i in range(flags.size()):
		check(up(flags[i]) > 0.999, "a placed flag stays upright by itself (%s, up %.3f)" % ["hillside" if i == 1 else "clearing", up(flags[i])])
	guest.room.apply_world(host.room.world_state())
	var copies: Array = guest.personal_flags.get("host", [])
	check(copies.size() == 2 and up(copies[0]) > 0.999 and up(copies[1]) > 0.999, "the guest sees the flags standing upright")
	# A car running into it pulls the stake out and the flag falls.
	var key = String(flags[1].get_meta("prop_key"))
	host.movable_props.solid_hit({"prop": key}, Vector3(8, 0, 0))
	for i in range(180):
		host.movable_props.update({}, {}, 1.0 / 60.0)
		await physics_frame
	check(up(flags[1]) < 0.7, "a car running into a flag knocks it over (up %.3f)" % up(flags[1]))
	check(up(flags[0]) > 0.999, "the other flag keeps standing")
	guest.movable_props.apply_snapshot(host.movable_props.snapshot())
	for i in range(30):
		guest.movable_props.update({}, {}, 1.0 / 60.0)
		await physics_frame
	check(up(copies[1]) < 0.7 and up(copies[0]) > 0.999, "the guest sees the knocked flag lying and the other standing")
	for game in [host, guest]:
		await game._shutdown_audio()
		game.queue_free()
	await process_frame
	finish()
