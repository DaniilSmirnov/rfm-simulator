extends "res://tests/harness.gd"
const Stage = preload("res://scripts/stage.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	for variant in range(RallyStage.STAGES.size()):
		var stage = Stage.new(variant)
		root.add_child(stage)
		stage.build()
		var officials = stage.officials
		check(officials.arches.size() == 2, "stage %d has start and finish arches" % variant)
		check(officials.cars.size() == 2 and officials.judges.size() == 4, "stage %d has two complete judge posts" % variant)
		check(officials.marshals.size() == (3 if stage.winter else 4), "stage %d has three or four marshals" % variant)
		for arch in officials.arches:
			var s = float(arch.get_meta("station"))
			check(arch.position.distance_to(stage.at(s)) < 1, "arch is aligned with actual route")
			check(stage.rock_hit(stage.at(s - 2), stage.at(s + 2), 1.1, false).is_empty(), "centre of gate leaves passage for rally cars")
			check(arch.get_children().any(func(n): return n is Label3D and n.text == arch.get_meta("caption")), "arch has readable start/finish caption")
		for person in officials.judges + officials.marshals:
			check(person.get_node_or_null("SafetyVest") != null, "official wears visible high-visibility vest")
			check(stage.road_distance(person.position) > 5.3, "official stands clear of racing line")
			check(person.get_node("RightArm/BeerCan").visible == false and person.get_node("RightArm/Skewer").visible == false, "officials carry no picnic food or beer")
			check(absf(person.position.y - stage.ground(person.position)) < 0.01, "official stands on terrain")
			if stage.provence:
				check(stage.solids.hit(person.position, person.position, 0.35, false).is_empty(), "village official stands outside buildings")
		for car in officials.cars:
			check(stage.road_distance(car.position) > 5.3 and car.get_meta("role") == "judge_car", "marked judge car parks beside route")
			check(car.get_node_or_null("AmberBeacon") != null, "judge car has amber beacon")
		var first = officials.cars[0]
		check(not stage.rock_hit(first.position, first.position, 0.3, false).is_empty(), "parked judge car participates in collision checks")
		# Deterministic layout derives only from stage geometry and obstacle placement.
		var spot = officials.roadside(180.0, -1.0, 0.6)
		var again = officials.roadside(180.0, -1.0, 0.6)
		check(spot == again, "roadside placement is deterministic")
		var total = stage.rocks.filter(func(r): return r.get("official", false)).size()
		check(total == 2 * 2 + 2 * 3 + officials.judges.size() + officials.marshals.size(), "official collision shapes created exactly once")
		stage.queue_free()
		await process_frame
	print("COURSE OFFICIALS RESULT: %d failures" % failures)
	finish()
