extends SceneTree
# «Виноградники · провансальская деревня»: route, road sections, the village,
# the countryside patchwork, village life and collectible grapes and figs.
const Stage = preload("res://scripts/stage.gd")
const Layout = preload("res://scripts/village_layout.gd")
var failures = 0
func check(ok: bool, title: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + title)
	if not ok: failures += 1
func _initialize() -> void:
	call_deferred("run")

func labels(stage: Node) -> Array:
	var result: Array = []
	for node in stage.find_children("*", "Label3D", true, false):
		result.append(node.text)
	return result

func run() -> void:
	check(Stage.STAGES[2].contains("провансальская деревня"), "third stage is called the Provençal village in the menu")
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.select_stage(2)
	game.start_game()
	game.in_car = false
	var stage = game.stage
	var village = stage.village

	# ------------------------------------------------------------ route
	var stations_ok = true
	for s in range(0, 840, 5):
		stations_ok = stations_ok and absf(stage.road_s(stage.at(s)) - s) < 1.0
	check(stations_ok, "route stations are recovered from world positions along the whole stage")
	var length = 0.0
	for s in range(0, 840):
		length += stage.flat(stage.at(s + 1) - stage.at(s)).length()
	check(absf(length - 840.0) < 6.0, "station is arc length: the route is 840 m long (%.1f)" % length)
	var square_turn = absf(stage.direction(372.0).signed_angle_to(stage.direction(430.0), Vector3.UP))
	check(square_turn > deg_to_rad(60.0), "the road turns sharply around the square (%.0f°)" % rad_to_deg(square_turn))
	var hairpin = absf(stage.direction(Layout.HAIRPIN.x).signed_angle_to(stage.direction(Layout.HAIRPIN.y), Vector3.UP))
	check(hairpin > deg_to_rad(120.0), "a hairpin links the vineyard terraces (%.0f°)" % rad_to_deg(hairpin))
	check(stage.at(0).z > stage.at(840).z + 550.0, "the stage runs from the lavender plateau to the vineyard valley")

	# ------------------------------------------------------------ sections
	var surfaces = {"plateau": "asphalt", "avenue": "asphalt", "grand_rue": "cobble", "square": "cobble", "lane": "cobble", "terraces": "gravel", "valley": "gravel"}
	var sections_ok = true
	for item in Layout.SECTIONS:
		var middle = (item.from + minf(item.to, 840.0)) * 0.5
		sections_ok = sections_ok and village.section(middle).id == item.id and village.surface(middle) == surfaces[item.id]
	check(sections_ok, "every section has its own road surface")
	check(stage.rally_speed(400.0) < stage.rally_speed(330.0) and stage.rally_speed(330.0) < stage.rally_speed(120.0), "pace drops from the plateau to the Grand-Rue and the square")
	check(stage.rally_speed(666.0) <= Layout.HAIRPIN_SPEED and stage.rally_speed(780.0) > 20.0, "crews slow for the hairpin and run fast through the valley")
	var kerb = village.anchor(330.0, stage.road_width(330.0) * 0.5 + 0.8)
	check(village.pavement(330.0) and stage.ground(kerb) > stage.at(330.0).y + Layout.KERB * 0.8, "the Grand-Rue has raised pavements")
	check(not village.pavement(Layout.ALLEYS[0]), "side alleys keep the kerb open")
	var crest_ok = true
	for s in range(4, 836, 2):
		var grade = absf(stage.at(s + 2).y - stage.at(s).y) / 2.0
		crest_ok = crest_ok and grade < 0.12
	check(crest_ok, "the smoothed road profile has no abrupt grades")

	# The game loads the baked scene; generator details live on a fresh build.
	var built = Stage.new(2)
	root.add_child(built)
	built.build(false)
	var generated = built.village

	# ------------------------------------------------------------ the village
	var architecture = generated.architecture
	check(architecture.house_count >= 40, "terraced stone houses line the streets (%d)" % architecture.house_count)
	check(architecture.shop_count >= 6, "the Grand-Rue has shops (%d)" % architecture.shop_count)
	var texts = labels(stage)
	for shop in ["BOULANGERIE", "PHARMACIE", "CAFÉ DE LA PLACE", "MAIRIE", "CAVE COOPÉRATIVE", "DOMAINE DES CIGALES"]:
		check(texts.has(shop), "%s sign is on the stage" % shop)
	check(texts.count("Ля Газ в Польен") == 4, "both village signs show the name on both faces")
	for node_name in ["VillageChurch", "VillageMairie", "VillageCafe", "VillageCafeTerrace", "VillageLavoir", "VillageCemetery", "VillageSquare", "LavenderDistillery", "VillageBorie", "VillageDomaine", "VillageCooperative"]:
		check(stage.get_node_or_null(node_name) != null, "%s is built" % node_name)
	check(built.solids.bell != null and built.solids.viewpoints.size() >= 2, "church tower bell and viewpoints are kept")
	check(stage.solids.lamps.size() == Layout.LAMPS.size(), "lantern posts line the village streets")
	var square_center: Vector3 = village.square.center
	square_center.y = stage.ground(square_center)
	check(stage.clearings[1].distance_to(square_center) < 20.0, "the second spectator spot is on the square")
	for clearing in stage.clearings:
		check(stage.solids.hit(clearing, clearing, 1.0, false).is_empty() and stage.road_distance(clearing) > 6.0, "spectator spot is open ground off the road")

	# ------------------------------------------------------------ countryside
	var landscape = generated.landscape
	check(landscape.lavender_count > 1500, "lavender rows fill the plateau (%d)" % landscape.lavender_count)
	check(landscape.vine_count > 500, "trellised vines line the descent (%d)" % landscape.vine_count)
	var farmland = landscape.farmland
	check(farmland.parcels.size() > 120, "a patchwork of fields covers the countryside (%d parcels)" % farmland.parcels.size())
	for crop in ["lavender", "wheat", "vines", "olive", "sunflower"]:
		check(int(farmland.counts.get(crop, 0)) > 0, "the patchwork includes %s fields" % crop)
	check(int(farmland.counts.get("farmhouses", 0)) >= 3, "farmhouses stand among the fields")
	check(int(generated.counts.get("cypresses", 0)) > 100, "cypress windbreaks line the fields")
	var fields_off_road = true
	for parcel in farmland.parcels:
		var nearest: Dictionary = built.route_nearest(parcel.center)
		fields_off_road = fields_off_road and nearest.distance > built.road_width(nearest.s) * 0.5 + farmland.ROAD_CLEARANCE - 0.01
	check(fields_off_road, "no field reaches the road")
	var empty_cells = 0
	var cells = 0
	for x in range(-180, 181, 30):
		for z in range(-900, 61, 30):
			var p = Vector3(x, 0, z)
			if built.road_distance(p) < 15.0:
				continue
			cells += 1
			if landscape.crop_clear(p, 18.0) and architecture.open_ground(p, 14.0):
				empty_cells += 1
	check(float(empty_cells) / cells < 0.35, "the countryside is not empty (%d of %d sample cells bare)" % [empty_cells, cells])

	# ------------------------------------------------------------ life
	var life = stage.life
	check(life != null, "the village has local life")
	check(life.walkers.size() >= 6 and life.sitters.size() >= 4 and life.players.size() == 4, "villagers stroll, sit at the café and play pétanque")
	check(life.pigeons.size() >= 10 and life.cats.size() >= 2 and life.swallows.size() >= 4, "pigeons, cats and swallows")
	check(life.pickers.size() >= 4 and not life.tractor.is_empty(), "grape pickers and a tractor work the valley")
	check(life.laundry.size() >= 12 and not life.smoke.is_empty(), "washing lines and chimney smoke")
	var on_pavement = true
	for walker in life.walkers:
		for point in walker.path:
			on_pavement = on_pavement and stage.road_distance(point) > stage.road_width(stage.road_s(point)) * 0.5
	check(on_pavement, "walking villagers never step onto the road")
	var walker: Dictionary = life.walkers[0]
	var before = walker.node.position
	stage.update_life(0.5, before)
	stage.update_life(0.5, before)
	check(walker.node.position.distance_to(before) > 0.05 or walker.pause > 0.0, "villagers move along their pavement route")
	game.course.phase = "racing"
	game.spawn_racer("pass")
	var racer = game.racers[0]
	racer.node.position = walker.node.position + Vector3(10, 0, 0)
	walker.pause = 0.0
	var parked = walker.node.position
	stage.update_life(0.1, parked)
	check(walker.node.position.distance_to(parked) < 0.001 and walker.node.get_node("RightArm").rotation.x > 2.0, "villagers stop and wave as a rally car passes")
	racer.node.position = Vector3(1000, 0, 1000)
	var swing_before = life.laundry[0].node.rotation
	stage.update_life(0.3, life.laundry[0].node.position)
	check(life.laundry[0].node.rotation != swing_before, "laundry moves in the breeze")
	stage.update_life(0.1, life.anchors("beehives")[0])
	check(life.active_bees > 0, "bees fly near the hives")

	# ------------------------------------------------------------ collectibles
	var grapes = stage.collectibles.filter(func(item): return item.get("name", "") == "виноград")
	var figs = stage.collectibles.filter(func(item): return item.get("name", "") == "инжир")
	check(grapes.size() == landscape.vine_count and figs.size() == landscape.fig_count and figs.size() > 0, "every vine and fig tree is collectible")
	check(built.collectibles == stage.collectibles and built.woodland_details == stage.woodland_details, "the baked scene matches a fresh build")
	built.free()
	var id = stage.collectibles.find(grapes[grapes.size() / 2])
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
	check(stage.collectible_parts.VineyardGrapes[first].hidden, "harvesting hides the bunch but keeps leaves and posts")
	var remote = Stage.new(2)
	root.add_child(remote)
	remote.build()
	check(remote.loaded_baked, "room members load the prepared village scene")
	check(remote.collectibles.size() == stage.collectibles.size() and remote.collectibles[id].pos.is_equal_approx(grape.pos), "room members generate matching resource identities")
	remote.apply_harvested([id])
	check(remote.harvested.has(id) and remote.collectible_parts.VineyardGrapes[first].hidden, "late join replicates harvested bunches")
	remote.free()
	var bell = stage.solids.bell
	game.walker = bell.handle_position() - Vector3(0.8, 0.4, 0)
	game._update_camera(1)
	game.camera.look_at(bell.handle_position())
	check(game.interaction.current().get("action", "") == "church_bell", "aiming at the rope offers the church bell")
	game.interaction.activate()
	check(bell.serial == 1, "F rings the church bell")
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	print("PROVENCE VILLAGE RESULT: %d failures" % failures)
	quit(1 if failures else 0)
