extends RefCounted
var game: Node3D
var room: Node

func world_state() -> Dictionary:
	var chair_poses = {}
	for owner in game.personal_chairs:
		var chair = game.personal_chairs[owner]
		chair_poses[owner] = {"pos": room.a(chair.position), "yaw": chair.rotation.y}
	var flag_poses = {}
	for owner in game.personal_flags:
		flag_poses[owner] = []
		for flag in game.personal_flags[owner]:
			flag_poses[owner].append({"pos": room.a(flag.position), "yaw": flag.rotation.y})
	var racers = []
	for r in game.racers:
		racers.append({"id": r.id, "role": r.get("role", "racer"), "zero_index": r.get("zero_index", 0), "variant": r.variant, "pos": room.a(r.node.position), "yaw": r.node.rotation.y, "tilt": room.a(r.node.rotation), "state": r.state, "recovery_progress": r.get("recovery_progress", 0), "recovery_helpers": r.get("recovery_helpers", 0)})
	var driving = {}
	for id in room.host_drives:
		driving[id] = room.host_drives[id].snapshot()
	return {"world_protocol": room.WorldProtocol.VERSION, "generation_version": 1, "drive_protocol": 1, "driving": driving, "camp_cooking": game.camp_cooking.snapshot(), "cargo": game.cargo.snapshot(), "foraging": game.foraging.snapshot(), "course": game.course.snapshot(), "city_lamps": game.stage.city.snapshot() if game.stage.urban else [], "chair_poses": chair_poses, "flag_poses": flag_poses, "table_yaw": game.camp.rotation.y if game.camp != null else 0.0, "grill_pose": {"pos": room.a(game.grill.position), "yaw": game.grill.rotation.y} if game.grill != null else null, "fallen": game.stage.tree_snapshot(), "stones": stone_state(), "impacts": game.impact_serials, "camp": room.a(game.camp.position) if game.camp != null else null, "chairs": game.has_chairs, "cooking": game.cooking, "cook_time": game.cook_time, "grill_servings": game.grill_servings, "npc_servings": game.spectators.snapshot(), "npc_people": game.spectators.actor_snapshot(), "marshals": game.stage.officials.snapshot(), "eaten": game.eaten, "racing": game.racing, "passed": game.passed, "helped": game.helped, "elapsed": game.elapsed, "paused": game.paused, "dead": game.dead, "finished": game.finished, "title": game.menu_title.text, "text": game.menu_text.text, "racers": racers, "tow": game.tow_target.get_meta("room_id") if game.tow_target != null else -1, "tow_progress": game.tow_progress, "tow_owner": room.tow_owner, "recovery_links": game.recovery_links, "recovery_helpers": game.recovery_helpers, "notice": game.toast_label.text, "notice_time": game.toast_time}

func stone_state() -> Array:
	var result = []
	for stone in game.stones:
		result.append({"id": stone.id, "pos": room.a(stone.node.position), "velocity": room.a(stone.velocity), "bounces": int(stone.get("bounces", 0))})
	return result

func apply_stones(w: Dictionary, sample_time: float = -1.0) -> void:
	var age = clampf(room.server_clock() - sample_time, 0, 0.15) if sample_time >= 0 else 0.0
	var count = int(w.get("impacts", {}).get(room.player_id, 0))
	if count > room.last_impact:
		game.impact_shake = 0.8
		if game.in_car:
			if not room.prediction_enabled or not room.prediction.active:
				game.condition = maxf(0, game.condition - (count - room.last_impact) * 0.8)
		game.toast("Гравий из-под колёс! Отойди дальше от края СУ.")
	room.last_impact = count
	var present = {}
	for remote in w.get("stones", []):
		var velocity = room.v(remote.velocity) + Vector3(0, -9.8 * age, 0)
		var position = room.v(remote.pos) + room.v(remote.velocity) * age + Vector3(0, -4.9 * age * age, 0)
		present[remote.id] = true
		var found = false
		for stone in game.stones:
			if stone.id == remote.id:
				stone.node.position = stone.node.position.lerp(position, 0.35) if stone.node.position.distance_to(position) < 3 else position
				stone.velocity = velocity
				stone.bounces = int(remote.get("bounces", 0))
				stone.node.show()
				found = true
		if not found:
			var node = room.Props.box(game, position, Vector3.ONE * 0.10, Color("9b9079"))
			game.stones.append({"id": remote.id, "node": node, "velocity": velocity, "bounces": int(remote.get("bounces", 0))})
	for stone in game.stones.duplicate():
		if not present.has(stone.id):
			stone.node.queue_free()
			game.stones.erase(stone)

func apply_world(w: Dictionary, sample_time: float = -1.0) -> void:
	var validation_error = room.WorldProtocol.validate(w, false)
	if validation_error != "":
		room.reject_snapshot(validation_error)
		return
	if sample_time < 0:
		sample_time = room.server_clock()
	if game.stage.urban:
		game.stage.city.apply_snapshot(w.get("city_lamps", []))
		for item in w.get("city_lamps", []):
			game.lamp_requests.erase(int(item.id))
	game.stage.apply_trees(w.get("fallen", []))
	for f in w.get("fallen", []):
		game.tree_requests.erase(int(f.id))
	apply_stones(w, sample_time)
	room.world_paused = w.paused
	if w.get("notice_time", 0) > 0 and w.get("notice", "") != room.last_notice:
		room.last_notice = w.notice
		game.toast(room.last_notice)
	# Full snapshots reconcile removals as well as additions.
	if w.camp == null and game.camp != null:
		game.packing.remove({"kind": "table", "node": game.camp})
	if w.has("chair_poses"):
		for owner in game.personal_chairs.keys():
			if not w.chair_poses.has(owner):
				game.packing.remove({"kind": "chair", "owner": owner, "node": game.personal_chairs[owner]})
	if w.has("flag_poses"):
		for owner in game.personal_flags.keys():
			if not w.flag_poses.has(owner):
				for node in game.personal_flags[owner].duplicate():
					game.packing.remove({"kind": "flag", "owner": owner, "node": node})
	if not w.cooking and game.grill != null:
		game.packing.remove({"kind": "grill", "node": game.grill})
	if w.camp != null:
		if game.camp == null:
			game.camp = Node3D.new()
			game.add_child(game.camp)
			room.Props.table(game.camp)
		game.camp.position = room.v(w.camp)
		game.camp.rotation.y = float(w.get("table_yaw", 0.0))
	if w.has("flag_poses"):
		for owner in w.flag_poses:
			var poses = w.flag_poses[owner]
			var existing: Array = game.personal_flags.get(owner, [])
			while existing.size() > poses.size():
				var old_flag = existing.pop_back()
				old_flag.queue_free()
			for i in range(poses.size()):
				var pose = poses[i]
				if i >= existing.size():
					game.place_flag(room.v(pose.pos), float(pose.yaw), str(owner), true)
					existing = game.personal_flags.get(owner, [])
				else:
					existing[i].position = room.v(pose.pos)
					existing[i].rotation.y = float(pose.yaw)
			game.personal_flags[owner] = existing
	if w.has("chair_poses"):
		for owner in w.chair_poses:
			var pose = w.chair_poses[owner]
			game.apply_chair(owner, room.v(pose.pos), float(pose.yaw))
	else:
		if w.chairs and not game.has_chairs and game.camp != null:
			game.apply_chair("legacy", game.camp.position + Vector3(-1.6, 0, 0.7), 0.0)
	game.has_chairs = w.chairs
	if w.cooking:
		var grill_pose = w.get("grill_pose", null)
		var spot = room.v(grill_pose.pos) if grill_pose != null else game.camp.position + Vector3(0.3, 0, -2.4)
		var yaw = float(grill_pose.yaw) if grill_pose != null else 0.0
		game.start_grill(spot, yaw, true)
	game.cook_time = w.cook_time
	game.grill_servings = int(w.get("grill_servings", room.Props.FOOD_PORTIONS))
	if game.grill != null:
		room.Props.set_grill_servings(game.grill, game.grill_servings)
	game.spectators.apply_snapshot(w.get("npc_servings", []))
	game.spectators.apply_actor_snapshot(w.get("npc_people", []))
	game.stage.officials.apply_snapshot(w.get("marshals", []))
	game.foraging.apply_snapshot(w.get("foraging", {}))
	game.eaten = w.eaten
	game.course.apply_snapshot(w.get("course", {}))
	game.cargo.apply_snapshot(w.get("cargo", {}))
	game.racing = w.racing
	game.passed = w.passed
	game.helped = w.helped
	game.elapsed = w.elapsed
	game.camp_cooking.apply_snapshot(w.get("camp_cooking", {}))
	var present = {}
	for r in w.racers:
		present[r.id] = true
		var exists = false
		for local in game.racers:
			if local.id == r.id:
				local.state = r.state
				local.recovery_progress = float(r.get("recovery_progress", 0))
				local.recovery_helpers = int(r.get("recovery_helpers", 0))
				exists = true
				break
		if not exists:
			var role = str(r.get("role", "racer"))
			var node = room.Props.car(Color.WHITE, true, int(r.variant)) if role == "racer" else room.Props.course_car(role, int(r.get("zero_index", 0)))
			game.add_child(node)
			node.position = room.v(r.pos)
			node.set_meta("room_id", r.id)
			game.racers.append({"id": r.id, "role": role, "zero_index": int(r.get("zero_index", 0)), "node": node, "state": r.state, "variant": r.variant})
		if not room.racer_motion.has(r.id):
			room.racer_motion[r.id] = room.SnapshotMotion.new()
		var tilt = room.v(r.get("tilt", [0, r.yaw, 0]))
		tilt.y = r.yaw
		room.racer_motion[r.id].push(sample_time, room.v(r.pos), tilt)
		room.racer_targets[r.id] = r
	for local in game.racers.duplicate():
		if not present.has(local.id):
			local.node.queue_free()
			game.racers.erase(local)
			room.racer_targets.erase(local.id)
			room.racer_motion.erase(local.id)
	game._cancel_tow()
	for local in game.racers:
		if local.id == w.tow:
			game.tow_target = local.node
	game.tow_progress = w.tow_progress
	game.recovery_links = w.get("recovery_links", []).duplicate(true)
	game.recovery_helpers = int(w.get("recovery_helpers", 0))
	game.draw_recovery_ropes()
	if (w.dead or w.finished) and not game.dead and not game.finished:
		game.dead = w.dead
		game.finished = w.finished
		game._show_result(w.title, w.text)
