extends "res://tests/harness.gd"
const CampSite = preload("res://scripts/people/camp_site.gd")
# A camp's lowest foot, wheel or leg stays this close to the drawn ground:
# neither sunk into it nor hanging over it. Audit a stage in detail with
# tools/profile/find_camp_ground.gd.
const FOOTING = 0.08
# Gear settling onto its legs moves a few centimetres; a car dropping onto
# its sills, a table sliding off a slope or a flung chair moves far more.
const DRIFT = 0.06
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	for variant in range(RallyStage.STAGES.size()):
		game.select_stage(variant)
		var crowd = game.spectators
		# Two people at every clearing camp, plus one at each of four roadside
		# spots on stages that keep them (not the village or the canyon).
		var camps = game.stage.clearings.size()
		var roadside = 4 if game.stage.biome.roadside_spectators() else 0
		check(crowd.groups.size() == camps + roadside, "NPC camps populate stage %d" % variant)
		check(crowd.people.size() == camps * 2 + roadside, "NPC spectators populate stage %d" % variant)
		var clear_road = true
		for group in crowd.groups:
			clear_road = clear_road and game.stage.road_distance(group.car.position) > 4.6
		check(clear_road, "parked NPC cars leave the road open")
		await camp_ground(game, variant)
		var actions = {}
		var props_match = true
		for time in range(90):
			crowd.update(float(time), 0.0, false)
			for person in crowd.people:
				actions[person.action] = true
				props_match = props_match and person.can.visible == (person.action == "beer") and person.food.visible == (person.action == "eat")
		check(props_match, "NPC props match activity")
		var served = false
		for group in crowd.groups:
			served = served or int(group.servings) < 10
		check(served, "NPCs consume skewers from their own 10-stick grills")
		check(crowd.snapshot().size() == crowd.groups.size(), "NPC grill servings are snapshot-ready")
		check(actions.has("beer") and actions.has("eat") and actions.has("idle"), "NPCs alternate between watching, drinking and eating")
		var second = load("res://scripts/people/spectators.gd").new()
		second.game = game
		game.add_child(second)
		second.rebuild()
		crowd.update(91.5, 0.0, false)
		second.update(91.5, 0.0, false)
		var same = second.people.size() == crowd.people.size()
		for i in range(crowd.people.size()):
			same = same and second.people[i].avatar.position == crowd.people[i].avatar.position and second.people[i].action == crowd.people[i].action and second.people[i].time == crowd.people[i].time
		check(same, "late join reconstructs identical NPC positions and animation phase")
		second.free()
		check(game.personal_chairs.is_empty() and game.camp == null and not game.has_chairs, "NPC furniture never counts as a player's camp or chair")
		var previous = crowd.clock
		game.playing = true
		game.paused = true
		game._process(0.5)
		check(crowd.clock == previous, "paused game freezes NPC animations")
		game.paused = false
		game.playing = false
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	print("NPC RESULT: %d failures" % failures)
	finish()

# Every piece of NPC camp gear stands on the drawn ground, and stays where it
# stands once its physics runs: no table legs or wheels in the land, no chair
# tipping off a hillside, no car settling 0.4 m down onto its sills.
func camp_ground(game, variant: int) -> void:
	var gear: Array = game.stage.solids.movables.filter(func(r): return is_instance_valid(r.node) and str(r.key).begins_with("npc:"))
	var placed = {}
	var footing = true
	for record in gear:
		var gap: Vector2 = CampSite.clearance(game.stage, record.node)
		placed[record.key] = record.node.global_transform
		if absf(gap.x) > FOOTING:
			footing = false
			print("  %s on stage %d: lowest foot %+.3f m" % [record.key, variant, gap.x])
	check(footing, "NPC camp gear stands on the ground of stage %d" % variant)
	var car_posts = true
	for group in game.spectators.groups:
		var lowest = INF
		for part in group.car.get_meta("prop_shapes"): lowest = minf(lowest, part.position.y)
		car_posts = car_posts and lowest < 0.02
	check(car_posts, "NPC cars collide on their tyres, not on their sills")
	game.movable_props.refresh()
	game.playing = true
	game.paused = false
	# Long enough for a car to drop onto its sills or a table to slide.
	for i in range(45):
		await physics_frame
	game.playing = false
	var still = true
	for record in gear:
		var moved: float = record.node.global_position.distance_to(placed[record.key].origin)
		var gap: Vector2 = CampSite.clearance(game.stage, record.node)
		if moved > DRIFT or absf(gap.x) > FOOTING:
			still = false
			print("  %s on stage %d: moved %.3f m, lowest foot %+.3f m" % [record.key, variant, moved, gap.x])
	check(still, "NPC camp gear stays put and grounded once physics runs on stage %d" % variant)
