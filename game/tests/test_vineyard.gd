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
	check(stage.city.vine_count > 1000 and stage.get_node_or_null("VillageChurch") != null, "vineyard stage includes vines and church")
	check(stage.city.lavender_count > 4000, "start side contains dense lavender rows")
	check(stage.woodland_details.get("LavenderBands", 0) == stage.city.lavender_count, "lavender flowers form spatially divided bands")
	var lavender_clear = true
	for p in stage.city.lavender_positions:
		lavender_clear = lavender_clear and -p.z < 300.0 and stage.road_distance(p) >= 6.0
	check(lavender_clear, "lavender stays before village and leaves the road clear")
	var forest_crops_clear = true
	for p in stage.city.tree_positions:
		forest_crops_clear = forest_crops_clear and stage.city.crop_clear(p)
	check(forest_crops_clear, "all village forest trees leave six metres around cultivated plants")
	var soil_contact = true
	var soil_tiles = 0
	for node in stage.get_children():
		if not str(node.name).begins_with("VineyardSoil_"):
			continue
		soil_tiles += 1
		var arrays = node.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		soil_contact = soil_contact and arrays[Mesh.ARRAY_NORMAL][0].y > 0.0
		for i in range(0, vertices.size(), 31):
			var p: Vector3 = vertices[i]
			soil_contact = soil_contact and absf(p.y - stage.terrain_surface_height(p)) < 0.025
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for i in range(0, indices.size() - 2, 111):
			var p = (vertices[indices[i]] + vertices[indices[i + 1]] + vertices[indices[i + 2]]) / 3.0
			soil_contact = soil_contact and absf(p.y - stage.terrain_surface_height(p)) < 0.025
	check(stage.city.crop_heights.is_empty(), "temporary planting height cache is released after generation")
	check(soil_contact and soil_tiles > 0 and soil_tiles < 40, "vineyard soil follows rendered hills using spatial mesh tiles")
	var slope = stage.at(178.0) + stage.side(178.0) * 42.0
	var basis = stage.terrain_basis(slope, 0.0)
	check(basis.y.y > 0.85 and basis.y.distance_to(Vector3.UP) > 0.01, "planting frame follows gentle rendered hillside")
	for station in [407.0, 412.0, 463.0, 469.0]:
		check(stage.get_node_or_null("GravelPuddle_%d" % int(station)) != null, "gravel has water in physical depressions")

	var lavender_tiles = stage.find_children("LavenderBands_*", "MeshInstance3D", false, false)
	var thuja_tiles = stage.find_children("VillageThujaLower_Tile_*", "MultiMeshInstance3D", false, false)
	check(lavender_tiles.size() > 8 and thuja_tiles.size() > 4, "lavender and thuja use spatially culled instance tiles")
	check(lavender_tiles[0].material_override.albedo_texture != null and thuja_tiles[0].get_meta("draw_distance_base_end", thuja_tiles[0].visibility_range_end) == 160, "lavender has a fine texture and trees retain their authored medium drawing range")
	var bands_touch_terrain = true
	for tile in lavender_tiles:
		var vertices = tile.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for index in range(0, vertices.size(), 29):
			var v: Vector3 = vertices[index]
			var gap = v.y - stage.terrain_surface_height(v)
			bands_touch_terrain = bands_touch_terrain and gap >= 0.015 and gap <= 0.63
	check(bands_touch_terrain, "lavender bands follow the rendered terrain")
	var microdetail_tiles = stage.find_children("CityDetail_*_no_shadow", "MultiMeshInstance3D", false, false)
	check(microdetail_tiles.size() > 4 and microdetail_tiles[0].cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "paving and thin decorative geometry omit shadow passes")
	var grape_positions = stage.collectibles.filter(func(item): return item.get("name", "") == "виноград")
	check(not grape_positions.is_empty() and stage.find_children("VineyardRow_18_*", "Node3D", true, false).is_empty() and not stage.find_children("VineyardRow_585_*", "Node3D", true, false).is_empty(), "grapes remain only in finish-side vineyards")
	var bell = stage.city.bell
	var saved_walker: Vector3 = game.walker
	game.walker = bell.handle_position() - Vector3(0.8, 0.4, 0)
	game._update_camera(1)
	game.camera.look_at(bell.handle_position())
	check(game.interaction.current().get("action", "") == "church_bell", "aiming at rope offers church bell interaction")
	game.interaction.activate()
	check(bell.serial == 1, "F interaction rings bell")
	game.walker = saved_walker
	check(stage.city.church_square_cobblestones >= 180 and stage.get_node_or_null("VillageChurch/VillageChurchSquare") != null, "church forecourt is fully paved with cobblestones")
	check(not stage.city.village_detail_allowed(stage.city.church_square_center), "church cobblestone square rejects grass and loose stones")
	check(stage.get_node_or_null("VillageCemetery") != null and stage.city.cemetery_grave_count == 28, "forest behind church contains an open cemetery with ordered graves")
	var church_center = stage.village_main_at(435.0) + stage.village_main_side(435.0) * 43.0
	var cemetery_lateral = (stage.city.cemetery_center - stage.village_main_at(435.0)).dot(stage.village_main_side(435.0))
	var detour_lateral = (stage.at(435.0) - stage.village_main_at(435.0)).dot(stage.village_main_side(435.0))
	var cemetery_edge_gap = detour_lateral - cemetery_lateral - 16.0 - stage.WIDTH * 0.5
	check(cemetery_lateral > 80.0 and detour_lateral > 45.0 and detour_lateral > cemetery_lateral, "church and cemetery remain together inside the outer gravel loop")
	check(cemetery_edge_gap >= 5.0 and cemetery_edge_gap <= 10.0, "gravel road runs 5-10 m from cemetery boundary")
	check(stage.village_main_at(435.0).distance_to(stage.at(435.0)) > 45.0, "historic cobblestone road remains separate from gravel detour")
	var main_road_clear = true
	var main_height_matches = true
	for station in range(301, 570):
		var point = stage.village_main_at(float(station))
		main_road_clear = main_road_clear and stage.city.paved_at(point, 1.6) and not stage.city._forest_spot_allowed(point, 1.6)
		main_height_matches = main_height_matches and is_equal_approx(stage.ground(point), 2.0875)
	check(main_road_clear, "entire historic main road rejects trees even opposite forest bypass")
	check(main_height_matches, "main-road wheel contact matches the top of cobblestones")
	for lane_station in [370.0, 500.0]:
		var end = stage.village_main_at(lane_station) + stage.village_main_side(lane_station) * 47.0
		var route_station = 382.0 if lane_station == 370.0 else 488.0
		check(stage.urban_at(route_station).distance_to(end) < 0.001, "gravel starts at outer side-lane endpoint")
		for along in [10.0, 25.0, 40.0]:
			var point = stage.village_main_at(lane_station) + stage.village_main_side(lane_station) * along
			check(is_equal_approx(stage.ground(point), 2.0775), "side-lane wheel contact matches cobblestone top")
	check(not stage.city._forest_spot_allowed(stage.city.cemetery_center), "mixed forest generation preserves the cemetery clearing")
	var cemetery_empty = true
	for tree in stage.city.tree_positions:
		cemetery_empty = cemetery_empty and stage.city.cemetery_clear(tree, 2.0)
	check(cemetery_empty, "all generated trees keep their crowns outside the cemetery")
	for corner in [Vector3(-16, 0, -12), Vector3(16, 0, -12), Vector3(-16, 0, 12), Vector3(16, 0, 12)]:
		check(not stage.city.cemetery_clear(stage.city.cemetery_center + corner, 2.0), "cemetery corners are included in the forest exclusion")
	check(stage.city.side_lane_house_count >= 8, "both secondary village streets have additional houses")
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
			check(stage.city.paved_at(stage.village_main_at(lane_s) + stage.village_main_side(lane_s) * along), "paving mask covers transverse lane ends")
	check(stage.city.village_prop_count >= 36, "village contains benches planters bins and wine delivery props")
	var sidewalk_coverage = true
	for station in range(301, 570):
		if absf(station - 370.0) < 4.0 or absf(station - 500.0) < 4.0:
			continue
		for side_value in [-1.0, 1.0]:
			for lateral in [3.96, 5.1, 6.35]:
				var sample = stage.village_main_at(station + 0.5) + stage.village_main_side(station + 0.5) * side_value * lateral
				var covered = false
				for pose in stage.city.sidewalk_poses:
					var local = pose.affine_inverse() * sample
					covered = covered or (absf(local.x) <= 1.35 and absf(local.z) <= 0.775)
				sidewalk_coverage = sidewalk_coverage and covered
	check(sidewalk_coverage, "sidewalks cover both edges and centers continuously around village bends")
	check(is_equal_approx(stage.ground(stage.at(335) + stage.side(335) * 5.1), 2.36), "walking height matches the raised village sidewalk surface")
	check(is_equal_approx(stage.ground(stage.village_main_at(370) + stage.village_main_side(370) * 5.1), 2.0775), "side street junction has no raised sidewalk across its entrance")
	check(village_name_labels.size() == 4, "both village signs show Ля Газ в Польен on both faces")
	check(stage.city.thuja_count > 300, "dense thuja forest surrounds the village")
	check(stage.woodland_details.get("VillageThujaLower", 0) == stage.city.thuja_count and stage.woodland_details.get("VillageThujaCrown", 0) == stage.city.thuja_count, "thuja forest is rendered through instanced layers")
	check(stage.city.mixed_tree_count >= 1500, "village has a denser forest using the shared summer tree asset")
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
	check(stage.city.mixed_tree_count > 1800 and stage.city.forest_grass_count > 2300 and stage.city.forest_stone_count > 400, "village forest has denser spatially batched trees grass and stones")
	var mushrooms = stage.collectibles.filter(func(item): return item.kind == "mushrooms")
	check(mushrooms.size() > 200, "village forest has harvestable mushroom clusters")
	var mushroom_contact = true
	for item in mushrooms:
		mushroom_contact = mushroom_contact and absf(item.pos.y - stage.terrain_surface_height(item.pos)) < 0.001 and stage.city._forest_spot_allowed(item.pos, 0.2)
	var mushroom_id = stage.collectibles.find(mushrooms[0])
	check(stage.harvest(mushroom_id), "village mushroom can be harvested")
	var mushroom_hidden = true
	for layer in mushrooms[0].parts:
		for part_index in mushrooms[0].parts[layer]:
			mushroom_hidden = mushroom_hidden and stage.collectible_parts[layer][part_index].hidden
	check(mushroom_hidden, "harvest hides both cap and stem of the village mushroom")
	check(mushroom_contact, "mushrooms touch rendered forest terrain and avoid crops roads and buildings")
	check(stage.find_children("MushroomCaps_Tile_*", "MultiMeshInstance3D", true, false).size() > 4, "mushrooms retain spatial culling")
	var entry = stage.flat(stage.urban_at(402) - stage.urban_at(382)).normalized()
	var lane = stage.flat(stage.village_main_side(370)).normalized()
	check(absf(rad_to_deg(entry.angle_to(lane))) > 25 and absf(rad_to_deg(entry.angle_to(lane))) < 35, "forest entry diagonal is about thirty degrees")
	check(absf(stage.village_forest_microrelief(Vector3(110, 0, -430))) > 0.01, "forest has continuous microrelief")

	var forest_berry_items = stage.collectibles.filter(func(item): return item.get("name", "") == "лесные ягоды")
	check(forest_berry_items.size() == stage.city.forest_berry_bush_count, "forest berry bushes expose deterministic collectible berries")
	check(stage.woodland_details.get("VillageForestBerries", 0) > stage.city.forest_berry_bush_count * 6, "forest berry fruit is visibly instanced on bushes")
	check(stage.city.village_grass_count > 400 and stage.city.village_stone_count > 80, "village yards and verges contain natural grass and stones")
	var village_details_clear = true
	for detail_position in stage.city.village_detail_positions:
		village_details_clear = village_details_clear and stage.city.village_detail_allowed(detail_position)
	check(village_details_clear, "generated village details never land on paved surfaces or occupied structures")
	check(not stage.city.village_detail_allowed(stage.village_main_at(335.0)), "main village cobblestones reject natural detail")
	check(not stage.city.village_detail_allowed(stage.village_main_at(435.0) + stage.village_main_side(435.0) * 5.1), "village sidewalks reject natural detail")
	check(not stage.city.village_detail_allowed(stage.village_main_at(370.0) + stage.village_main_side(370.0) * 20.0), "transverse cobbled lanes reject natural detail")
	var parking_labels = 0
	for label in stage.find_children("*", "Label3D", true, false):
		if str(label.text).begins_with("P "):
			parking_labels += 1
	check(parking_labels == 0, "vineyard spectator spots have no dedicated parking signs")
	check(stage.city.roadside_grass_count > 500 and stage.city.roadside_stone_count > 20 and stage.city.roadside_bush_count > 20, "country road has dense grass, stones and bushes before and after village")
	check(stage.woodland_details.get("VineyardRoadsideGrass", 0) == stage.city.roadside_grass_count, "roadside grass is instanced through shared detail batches")
	check(not stage.city._roadside_station_allowed(435.0) and stage.city._roadside_station_allowed(180.0), "roadside vegetation stays outside village")
	check(stage.city.village_cobblestones >= 2700 and stage.city.sidewalk_segments >= 170, "both remaining village streets have dense cobblestone paving and sidewalks")
	check(not stage.draw_base_road_surface(335.0) and stage.draw_base_road_surface(435.0) and stage.draw_base_road_surface(180.0), "village road uses cobblestones while the forest detour has a gravel base")
	check(stage.direction(320).z < -0.8 and stage.direction(530).z < -0.8, "village route continues toward finish without a reversal")
	check(stage.village_forest_offset(435.0) > 45.0 and stage.village_forest_offset(370.0) == 0.0 and stage.village_forest_offset(500.0) == 0.0, "forest diversion joins both village side streets")
	check(stage.village_forest_detour(435.0) and not stage.village_forest_detour(320.0), "only wooded section uses gravel grip and light terrain")
	var id = stage.collectibles.find(grape_positions[grape_positions.size() / 2])
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
