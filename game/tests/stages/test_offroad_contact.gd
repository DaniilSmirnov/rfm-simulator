extends "res://tests/harness.gd"
# A car off the road rests on the land that is drawn, on every stage; on the
# road it keeps the road surface.
const Stage = preload("res://scripts/stages/stage.gd")

func _initialize() -> void:
	call_deferred("run")

func settle(game, p: Vector3) -> float:
	game.car.position = p
	game.car.position.y = game.stage.vehicle_ground(p) + 0.3
	game.vehicle_motion.initialized = false
	game.vehicle_motion.vertical_speed = 0.0
	for i in range(180):
		game.vehicle_motion.suspension(game.car, game.stage, 1.0 / 60.0, 0.0)
	return game.car.position.y

func recovery_contact(game, p: Vector3) -> bool:
	for yaw in [0.0, 0.73, PI / 2]:
		game.heading = yaw
		# Wrong old height and a moving spring must not survive recovery.
		game.vehicle_motion.vertical_speed = -4.0
		game.Recovery.move_car(game, "local", p - Vector3.UP * 3, NAN, 1.0 / 60)
		var forward = Vector3(-sin(yaw), 0, -cos(yaw))
		var expected_pitch = atan2(game.stage.vehicle_ground(p + forward * 1.15) - game.stage.vehicle_ground(p - forward * 1.15), 2.3)
		if absf(game.car.rotation.x - expected_pitch) > 0.00001:
			return false
		for x in [-0.7, 0.7]:
			for z in [-1.15, 1.15]:
				var wheel: Vector3 = game.car.position + game.car.basis * Vector3(x, 0, z)
				if wheel.y < game.stage.vehicle_ground(wheel) + 0.055:
					return false
		if game.vehicle_motion.vertical_speed != 0 or absf(game.vehicle_motion.pitch - game.car.rotation.x) > 0.00001 or absf(game.vehicle_motion.roll - game.car.rotation.z) > 0.00001:
			return false
	return true

# Mean of a height function under the four tyres of the settled car: the
# suspension rests on their average, not on the land under the car's centre.
func _contact(game, st, p: Vector3, height: Callable) -> float:
	var along = game.car.basis.z
	along.y = 0
	along = along.normalized()
	var across = along.cross(Vector3.UP)
	var mean = 0.0
	for offset in [along * 1.15, -along * 1.15, across * 0.7, -across * 0.7]:
		mean += float(height.call(p + offset)) * 0.25
	return mean

func run() -> void:
	for stage_index in range(Stage.STAGES.size()):
		var game = load("res://main.tscn").instantiate()
		game.defer_world = true
		root.add_child(game)
		await process_frame
		game.set_process(false)
		game.room.set_process(false)
		game.select_stage(stage_index)
		await game.prepare_world()
		var st = game.stage
		var winter = "has_snow" in st and st.has_snow
		var worst = 0.0
		var samples = 0
		var recovery_supported = true
		for s in range(60, int(st.LENGTH) - 60, 60):
			for side in [-1.0, 1.0]:
				var p: Vector3 = st.at(s) + st.side(s) * side * (st.road_width(s) * 0.5 + 6.0)
				if st.water != null and st.water.depth(p) > 0.0:
					continue
				if not st.solids.clear(p, 1.5) or st.obstacle_hit(p, p + Vector3(0.01, 0, 0), 1.5) >= 0:
					continue
				if st.biome.has_method("in_village") and st.biome.in_village(st.road_s(p)):
					continue
				# Nowhere to park: a shelf cut into a cliff has a bank on one
				# side and the drop on the other.
				if not st.biome.level_ground(p, 1.4, 1.2):
					continue
				var y = settle(game, p)
				recovery_supported = recovery_contact(game, p) and recovery_supported
				# The car origin sits 0.06 m above the four tyre contact points.
				worst = maxf(worst, y - 0.06 - st.terrain_surface_height(p))
				samples += 1
		if not winter:
			check(samples > 3 and worst < 0.12, "%s: an off-road car touches the drawn land (worst gap %.2f m over %d spots)" % [Stage.STAGES[stage_index], worst, samples])
		check(samples > 3 and recovery_supported, "%s: pushed/towed wheels stay above the rendered terrain at every heading" % Stage.STAGES[stage_index])
		var road: Vector3 = st.at(300.0)
		var settled = settle(game, road)
		# The suspension averages four contact points, so a bumpy road is
		# compared with their mean, not with the centre alone.
		var on_road = settled - 0.06 - _contact(game, st, road, st.ground)
		check(absf(on_road) < 0.05, "%s: on the road the car keeps the road surface (%.2f m)" % [Stage.STAGES[stage_index], on_road])
		await game._shutdown_audio()
		game.queue_free()
		await process_frame
	print("OFFROAD CONTACT RESULT: %d checks, %d failures" % [checks, failures])
	finish()
