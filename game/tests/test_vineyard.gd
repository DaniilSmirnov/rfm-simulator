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
	var nature_assets = ["tree_trunk.tres", "tree_crown_lower.tres", "tree_crown_middle.tres", "tree_crown_top.tres", "thuja_lower.tres", "thuja_middle.tres", "thuja_top.tres", "stone.tres", "boulder.tres", "bush.tres", "roadside_bush.tres", "bush_stem.tres", "berry.tres", "mushroom_cap.tres", "mushroom_stem.tres", "grass.obj"]
	var nature_assets_valid = true
	for asset in nature_assets:
		var path = "res://models/nature/" + asset
		nature_assets_valid = nature_assets_valid and ResourceLoader.exists(path) and ResourceLoader.load(path) is Mesh
	check(nature_assets_valid, "vegetation rocks and mushroom meshes load from separate resource files")
	check(stage.shared_tree_mesh(0).resource_path.ends_with("tree_trunk.tres") and stage.shared_stone_mesh().resource_path.ends_with("stone.tres"), "summer stage uses external tree and stone geometry")
	check(stage.city.vine_count > 2000 and stage.get_node_or_null("VillageChurch") != null, "vineyard stage includes vines and church")
	check(stage.city.church_square_cobblestones >= 180 and stage.get_node_or_null("VillageChurch/VillageChurchSquare") != null, "church forecourt is fully paved with cobblestones")
	check(not stage.city.village_detail_allowed(stage.city.church_square_center), "church cobblestone square rejects grass and loose stones")
	check(stage.get_node_or_null("VillageCemetery") != null and stage.city.cemetery_grave_count == 28, "forest behind church contains an open cemetery with ordered graves")
	var church_center = stage.at(435.0) + stage.side(435.0) * 43.0
	check(absf(stage.road_distance(stage.city.cemetery_center) - 26.0) < 10.0, "forest route passes alongside cemetery")
	check(not stage.city._forest_spot_allowed(stage.city.cemetery_center), "mixed forest generation preserves the cemetery clearing")
	check(stage.city.side_lane_house_count >= 12, "both secondary village streets have additional houses")
	check(stage.city.village_sign_count == 2, "village has name signs at both entrance and exit")
	var village_name_labels = stage.find_children("*", "Label3D", true, false).filter(func(label): return str(label.text) == "Ля Газ в Польен")
	var signs_face_outward = true
	for label in village_name_labels:
		signs_face_outward = signs_face_outward and (label.basis.z.z * label.position.z > 0) and not label.double_sided
	check(signs_face_outward, "village name text faces outward on both sides of each sign")
	var trees_clear_of_paving = true
	for position in stage.city.tree_positions:
		trees_clear_of_paving = trees_clear_of_paving and not stage.city.paved_at(position, 1.6)
	check(trees_clear_of_paving, "all generated village trees keep clearance from paving including rotated side lanes")
	for lane_s in [370.0, 500.0]:
		for along in [-46.0, -25.0, 25.0, 46.0]:
			check(stage.city.paved_at(stage.at(lane_s) + stage.side(lane_s) * along), "paving mask covers transverse lane ends")
	check(stage.city.village_prop_count >= 36, "village contains benches planters bins and wine delivery props")
	var sidewalk_coverage = true
	for station in range(301, 570):
		if absf(station - 370.0) < 4.0 or absf(station - 500.0) < 4.0:
			continue
		for side_value in [-1.0, 1.0]:
			for lateral in [3.96, 5.1, 6.35]:
				var sample = stage.at(station + 0.5) + stage.side(station + 0.5) * side_value * lateral
				var covered = false
				for pose in stage.city.sidewalk_poses:
					var local = pose.affine_inverse() * sample
					covered = covered or (absf(local.x) <= 1.35 and absf(local.z) <= 0.775)
				sidewalk_coverage = sidewalk_coverage and covered
	check(sidewalk_coverage, "sidewalks cover both edges and centers continuously around village bends")
	check(is_equal_approx(stage.ground(stage.at(335) + stage.side(335) * 5.1), 2.36), "walking height matches the raised village sidewalk surface")
	check(is_equal_approx(stage.ground(stage.at(370) + stage.side(370) * 5.1), 2.0), "side street junction has no raised sidewalk across its entrance")
	check(village_name_labels.size() == 4, "both village signs show Ля Газ в Польен on both faces")
	check(stage.city.thuja_count > 300, "dense thuja forest surrounds the village")
	check(stage.woodland_details.get("VillageThujaLower", 0) == stage.city.thuja_count and stage.woodland_details.get("VillageThujaCrown", 0) == stage.city.thuja_count, "thuja forest is rendered through instanced layers")
	check(stage.city.mixed_tree_count >= 900, "village has a denser forest using the shared summer tree asset")
	var shared_tree_layers_match = true
	for layer in range(4):
		shared_tree_layers_match = shared_tree_layers_match and stage.woodland_details.get("VillageForestTreeLayer%d" % layer, 0) == stage.city.mixed_tree_count
	check(shared_tree_layers_match, "all village forest trees use the same four instanced layers as the first summer stage")
	var village_tree_tiles = stage.find_children("VillageForestTreeLayer0_Tile_*", "MultiMeshInstance3D", true, false)
	check(not village_tree_tiles.is_empty() and village_tree_tiles[0].multimesh.mesh.radial_segments == stage.shared_tree_mesh(0).radial_segments, "village tree trunk mesh matches the shared forest primitive")
	var village_stone_tiles = stage.find_children("VillageForestStones_Tile_*", "MultiMeshInstance3D", true, false)
	var shared_stone_mesh = stage.shared_stone_mesh()
	check(not village_stone_tiles.is_empty() and village_stone_tiles[0].multimesh.mesh.radial_segments == shared_stone_mesh.radial_segments and village_stone_tiles[0].multimesh.mesh.rings == shared_stone_mesh.rings, "village forest stones reuse the first-stage stone geometry")
	var village_grass_tiles = stage.find_children("VillageForestGrass_Tile_*", "MultiMeshInstance3D", true, false)
	check(not village_grass_tiles.is_empty() and village_grass_tiles[0].multimesh.mesh.get_aabb() == stage._grass_mesh().get_aabb(), "village forest grass reuses the first-stage grass mesh")
	check(stage.city.forest_grass_count > 1000 and stage.city.forest_stone_count > 200, "mixed forest has dense grass and loose stones")
	check(stage.city.forest_boulder_count > 25 and stage.rocks.size() >= stage.city.forest_boulder_count, "forest contains collidable boulders")
	check(stage.city.forest_bush_count > 100 and stage.city.forest_berry_bush_count > 40, "forest has ordinary and berry undergrowth")
	var forest_berry_items = stage.collectibles.filter(func(item): return item.get("name", "") == "лесные ягоды")
	check(forest_berry_items.size() == stage.city.forest_berry_bush_count, "forest berry bushes expose deterministic collectible berries")
	check(stage.woodland_details.get("VillageForestBerries", 0) > stage.city.forest_berry_bush_count * 6, "forest berry fruit is visibly instanced on bushes")
	check(stage.city.village_grass_count > 400 and stage.city.village_stone_count > 80, "village yards and verges contain natural grass and stones")
	var village_details_clear = true
	for detail_position in stage.city.village_detail_positions:
		village_details_clear = village_details_clear and stage.city.village_detail_allowed(detail_position)
	check(village_details_clear, "generated village details never land on paved surfaces or occupied structures")
	check(not stage.city.village_detail_allowed(stage.at(435.0)), "main village cobblestones reject natural detail")
	check(not stage.city.village_detail_allowed(stage.at(435.0) + stage.side(435.0) * 5.1), "village sidewalks reject natural detail")
	check(not stage.city.village_detail_allowed(stage.at(370.0) + stage.side(370.0) * 20.0), "transverse cobbled lanes reject natural detail")
	var parking_labels = 0
	for label in stage.find_children("*", "Label3D", true, false):
		if str(label.text).begins_with("P "):
			parking_labels += 1
	check(parking_labels == 0, "vineyard spectator spots have no dedicated parking signs")
	check(stage.city.roadside_grass_count > 500 and stage.city.roadside_stone_count > 20 and stage.city.roadside_bush_count > 20, "country road has dense grass, stones and bushes before and after village")
	check(stage.woodland_details.get("VineyardRoadsideGrass", 0) == stage.city.roadside_grass_count, "roadside grass is instanced through shared detail batches")
	check(not stage.city._roadside_station_allowed(435.0) and stage.city._roadside_station_allowed(180.0), "roadside vegetation stays outside village")
	check(stage.city.village_cobblestones >= 1500 and stage.city.sidewalk_segments >= 170, "both remaining village streets have dense cobblestone paving and sidewalks")
	check(not stage.draw_base_road_surface(335.0) and stage.draw_base_road_surface(435.0) and stage.draw_base_road_surface(180.0), "village road uses cobblestones while the forest detour has a gravel base")
	check(stage.direction(320).z < -0.8 and stage.direction(530).z < -0.8, "village route continues toward finish without a reversal")
	check(stage.village_forest_offset(435.0) > 80.0 and stage.village_forest_offset(370.0) == 0.0 and stage.village_forest_offset(500.0) == 0.0, "forest diversion joins both village side streets")
	check(stage.village_forest_detour(435.0) and not stage.village_forest_detour(320.0), "only wooded section uses gravel grip and light terrain")
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
