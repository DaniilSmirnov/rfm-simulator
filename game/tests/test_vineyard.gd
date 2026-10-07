extends SceneTree
const Stage = preload("res://scripts/stage.gd")
var failures = 0
func check(ok: bool, title: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + title)
	if not ok: failures += 1
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.select_stage(2)
	game.start_game()
	game.in_car = false
	var stage = game.stage
	check(stage.city.vine_count > 2000 and stage.get_node_or_null("VillageChurch") != null, "vineyard stage includes vines and church")
	check(stage.city.roadside_grass_count > 500 and stage.city.roadside_stone_count > 20 and stage.city.roadside_bush_count > 20, "country road has dense grass, stones and bushes before and after village")
	check(stage.woodland_details.get("VineyardRoadsideGrass", 0) == stage.city.roadside_grass_count, "roadside grass is instanced through shared detail batches")
	check(not stage.city._roadside_station_allowed(435.0) and stage.city._roadside_station_allowed(180.0), "roadside vegetation stays outside village")
	check(stage.city.village_cobblestones >= 2700 and stage.city.sidewalk_segments >= 170, "village has dense cobblestone paving and continuous sidewalks")
	check(not stage.draw_base_road_surface(435.0) and stage.draw_base_road_surface(180.0), "village road uses cobblestones without the generic road surface underneath")
	check(stage.direction(320).z < -0.8 and stage.direction(530).z < -0.8, "village route continues toward finish without a reversal")
	var id = stage.collectibles.size() / 2
	var grape = stage.collectibles[id]
	game.walker = grape.pos
	game.camera.position = grape.pos + Vector3(0, 1.6, 1.3)
	game.camera.look_at(grape.pos + Vector3(0, 0.6, 0))
	var offer = game.interaction.current()
	check(offer.get("action", "") == "collect" and offer.get("label", "") == "Собрать виноград", "F offers grape collection while aiming at a vine")
	check(game.foraging.collect(id), "grapes can be harvested on foot")
	check(game.foraging.stock().berries == 3, "grapes use the shared berry inventory")
	check(not game.foraging.collect(id), "a harvested vine cannot grant duplicate fruit")
	var first = grape.parts.VineyardGrapes[0]
	check(stage.collectible_parts.VineyardGrapes[first].hidden, "harvesting hides the bunch but retains leaves and supports")
	var remote = Stage.new(2)
	root.add_child(remote)
	remote.build()
	check(remote.collectibles.size() == stage.collectibles.size() and remote.collectibles[id].pos.is_equal_approx(grape.pos), "room members generate matching resource identities")
	remote.apply_harvested([id])
	check(remote.harvested.has(id) and remote.collectible_parts.VineyardGrapes[first].hidden, "late join replicates harvested bunches")
	check(game.eat_foraged("berries"), "collected grapes use the animated berry eating action")
	game._update_eating(3.8)
	check(game.foraging.stock().berries == 2, "one completed eating animation consumes one portion")
	game.walker = grape.pos + Vector3(20, 0, 0)
	check(not game.foraging.collect(id + 1), "grapes cannot be collected remotely")
	remote.free()
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	print("VINEYARD RESULT: %d failures" % failures)
	quit(1 if failures else 0)
