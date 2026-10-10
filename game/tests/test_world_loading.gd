extends SceneTree
var failures = 0
var frames = 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	game.defer_world = true
	root.add_child(game)
	game.set_process(false)
	game.room.set_process(false)
	await process_frame
	check(not game.world_ready and game.stage.get_child_count() == 0 and game.spectators.people.is_empty(), "menu does not allocate world or spectators")
	check(game.lobby_ui.find_children("*", "SubViewport", true, false).is_empty(), "menu previews have no extra render targets")
	for i in range(10):
		game.select_player_car(i)
		check(game.lobby_ui.images[0].texture != null, "every car has a thumbnail")
	for i in range(game.Stage.STAGES.size()):
		game.select_stage(i)
		check(game.lobby_ui.images[1].texture != null and game.stage.get_child_count() == 0, "stage selection only loads thumbnail")
	game.select_stage(2) # Keep the locked-content check on the paid village stage.
	game.platform_service.catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/store_catalog.json"))
	game.platform_service.entitlements = {"mode": "restricted", "skus": []}
	await game.start_game()
	check(not game.playing and not game.loading_world and game.stage.get_child_count() == 0, "locked selection cannot build or start the world")
	game.select_player_car(0)
	game.select_stage(0)
	var track_frames = func():
		if game.loading_world:
			frames += 1
	process_frame.connect(track_frames)
	game.start_game()
	check(game.loading_world and game.loading_screen.overlay.visible and not game.playing, "loading screen appears before construction")
	var stage_before = game.stage
	game.select_stage(1)
	game.select_player_car(1)
	game.start_game()
	check(game.stage == stage_before and game.selected_car == 0, "loading prevents selection changes and duplicate starts")
	while game.loading_world:
		await process_frame
	process_frame.disconnect(track_frames)
	check(game.playing and game.world_ready and not game.loading_screen.overlay.visible, "world becomes playable only after loading completes")
	check(frames > 30 and game.loading_screen.bar.value == 100 and game.loading_screen.history.size() == 8, "loading yields real frames and reports every stage")
	var sync = game.Stage.new(0)
	root.add_child(sync)
	sync.build()
	check(game.stage.trees == sync.trees, "cooperative build preserves trees")
	check(game.stage.rocks.size() == sync.rocks.size(), "cooperative build preserves rock count")
	for i in range(mini(game.stage.rocks.size(), sync.rocks.size())):
		var actual = game.stage.rocks[i].duplicate()
		var expected = sync.rocks[i].duplicate()
		actual.erase("actor")
		expected.erase("actor")
		check(actual == expected, "cooperative build preserves collision geometry")
	check(game.stage.collectibles == sync.collectibles, "cooperative build preserves collectibles")
	check(game.stage.woodland_details == sync.woodland_details, "cooperative build preserves decorative batches")
	sync.free()
	await game._shutdown_audio()
	game.free()
	# Guest handshake may borrow a locked host stage; no state sync runs until ready.
	var guest = load("res://main.tscn").instantiate()
	guest.defer_world = true
	root.add_child(guest)
	guest.set_process(false)
	guest.room.set_process(false)
	guest.platform_service.catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/store_catalog.json"))
	guest.platform_service.entitlements = {"mode": "restricted", "skus": []}
	guest.room.room_id = "ABCDEF"
	guest.room.request_kind = "join"
	var response = {"player": "guest", "token": "test", "host": false, "stage": 2, "car_model": 0, "slot": 3}
	guest.room._response(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(response).to_utf8_buffer())
	guest.room._process(1)
	check(guest.loading_world and not guest.room.busy and guest.room.request_kind == "join", "room does not publish partial world during preparation")
	while guest.loading_world:
		await process_frame
	check(guest.playing and guest.world_ready and guest.stage.provence, "guest finishes world preparation before handshake enters play")
	check(guest.car.position == guest.stage.at(30) and guest.avatar_variant == 3, "handshake applies assigned lane after preparation")
	check(int(guest.stage.village.counts.get("vines", 0)) > 0 and int(guest.stage.village.counts.get("houses", 0)) > 0 and guest.stage.solids.lamps.size() > 0, "cooperative village creates landscape and physics")
	var urban_sync = guest.Stage.new(2)
	root.add_child(urban_sync)
	urban_sync.build()
	check(guest.stage.collectibles == urban_sync.collectibles and guest.stage.woodland_details == urban_sync.woodland_details, "cooperative village preserves collectible positions and instance batches")
	check(guest.stage.village.counts == urban_sync.village.counts and guest.stage.solids.obstacles.size() == urban_sync.solids.obstacles.size(), "cooperative village preserves vines, houses and collision obstacles")
	urban_sync.free()
	guest.room.connected = false
	await guest._shutdown_audio()
	guest.free()
	print("WORLD_LOADING frames=", frames, " failures=", failures)
	quit(1 if failures else 0)
