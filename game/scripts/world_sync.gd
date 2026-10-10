extends RefCounted
# The shared world as a list of providers instead of one dictionary literal.
# Each provider owns some snapshot keys: it writes them on the host and applies
# them on guests. Providers in a named `section` change slowly ("cold") and
# travel only when their revision changes; the rest ("hot") goes every sync.
# Stage modules add their own providers through stage.sync_providers(), so the
# network code has no per-stage branches.
#
# Provider: {"name": String, "section": String ("" = hot), "keys": Array,
#            "snapshot": Callable() -> Dictionary, "apply": Callable(fields, sample_time),
#            "collision": bool (applied before guest drive reconciliation),
#            "interval": float (seconds; a busy section uploads at most this often)}
const Props = preload("res://scripts/props.gd")
const SnapshotMotion = preload("res://scripts/snapshot_motion.gd")

var room
var game
var providers: Array[Dictionary] = []
# Providers are rebuilt whenever the game switches to another stage instance.
var _stage_instance_id = -1
# Cold revisions this client has applied, as reported by the host.
var cold_revs: Dictionary = {}
# Host: revisions the server already holds, and uploads still in flight.
var server_cold_revs: Dictionary = {}
var cold_sent: Dictionary = {}
# Host: when each section was last uploaded, for sections with an interval.
var cold_uploaded_at: Dictionary = {}
var last_impact = 0
var last_notice = ""
var racer_motion: Dictionary = {}
var racer_targets: Dictionary = {}
const PEOPLE_INTERVAL = 0.3

static func provider(name: String, section: String, keys: Array, snapshot: Callable, apply: Callable, collision: bool = false, interval: float = 0.0) -> Dictionary:
	return {"name": name, "section": section, "keys": keys, "snapshot": snapshot, "apply": apply, "collision": collision, "interval": interval}

func setup(owner_room) -> void:
	room = owner_room
	game = room.game

func _ensure() -> void:
	var current = game.stage.get_instance_id() if game.stage != null else 0
	if current != _stage_instance_id:
		_stage_instance_id = current
		rebuild()

# Stage providers depend on the stage, so they are collected per stage.
func rebuild() -> void:
	providers.clear()
	if game.stage != null and game.stage.has_method("sync_providers"):
		for p in game.stage.sync_providers(game):
			providers.append(p)
	providers.append(provider("camp", "camp", ["camp", "table_yaw", "chairs", "chair_poses", "flag_poses", "cooking", "grill_pose", "grill_servings", "npc_servings", "eaten"], _camp_snapshot, _camp_apply))
	providers.append(provider("drive", "", ["drive_protocol", "driving"], _drive_snapshot, func(_f, _t): pass))
	providers.append(provider("stones", "", ["stones", "impacts"], func(): return {"stones": room.stone_state(), "impacts": game.impact_serials}, _stones_apply))
	providers.append(provider("status", "", ["paused", "notice", "notice_time", "cook_time"], _status_snapshot, _status_apply))
	# Spectators, marshals, the schedule, trunks and foraging stand still most of
	# the time: as their own sections they travel only when they change.
	# Walking spectators and marshals are smoothed on guests, so three updates a
	# second are enough even while someone walks.
	providers.append(_subsystem("npc_people", func(): return game.spectators, "actor_snapshot", "apply_actor_snapshot", "people", PEOPLE_INTERVAL))
	providers.append(_subsystem("marshals", func(): return game.stage.officials if game.stage != null else null, "snapshot", "apply_snapshot", "marshals", PEOPLE_INTERVAL))
	providers.append(_subsystem("foraging", func(): return game.foraging, "snapshot", "apply_snapshot", "foraging"))
	providers.append(_subsystem("course", func(): return game.course, "snapshot", "apply_snapshot", "course"))
	providers.append(_subsystem("cargo", func(): return game.cargo, "snapshot", "apply_snapshot", "cargo"))
	providers.append(provider("progress", "", ["racing", "passed", "helped", "elapsed"], _progress_snapshot, _progress_apply))
	providers.append(_subsystem("camp_cooking", func(): return game.camp_cooking, "snapshot", "apply_snapshot"))
	providers.append(provider("racers", "", ["racers", "tow", "tow_progress", "tow_owner", "recovery_links", "recovery_helpers"], _racers_snapshot, _racers_apply))
	providers.append(provider("outcome", "", ["dead", "finished", "title", "text"], _outcome_snapshot, _outcome_apply))

# A subsystem that already owns snapshot()/apply_snapshot() under one key.
# `owner` returns the subsystem when it is needed: some are created later.
func _subsystem(key: String, owner: Callable, snapshot_method: String, apply_method: String, section: String = "", interval: float = 0.0) -> Dictionary:
	var snapshot = func() -> Dictionary:
		var target = owner.call()
		return {key: target.call(snapshot_method) if target != null else {}}
	var apply = func(f: Dictionary, _t: float) -> void:
		var target = owner.call()
		if target != null and f.has(key):
			target.call(apply_method, f[key])
	return provider(key, section, [key], snapshot, apply, false, interval)

# Shortest time between uploads of each cold section (0 = every change).
func section_intervals() -> Dictionary:
	_ensure()
	var result = {}
	for p in providers:
		if p.section != "":
			result[p.section] = maxf(float(result.get(p.section, 0.0)), float(p.get("interval", 0.0)))
	return result

func cold_sections() -> Dictionary:
	_ensure()
	var sections = {}
	for p in providers:
		if p.section != "":
			if not sections.has(p.section):
				sections[p.section] = []
			sections[p.section].append_array(p.keys)
	return sections

# ---------------------------------------------------------------- host side

func world_state() -> Dictionary:
	_ensure()
	var world = {}
	for p in providers:
		world.merge(p.snapshot.call(), true)
	return world

static func split_world_by(full: Dictionary, sections: Dictionary) -> Dictionary:
	var hot = full.duplicate()
	var cold = {}
	var revisions = {}
	for section in sections:
		var part = {}
		for key in sections[section]:
			if full.has(key):
				part[key] = full[key]
				hot.erase(key)
		cold[section] = part
		revisions[section] = JSON.stringify(part).hash()
	hot.cold_revs = revisions
	return {"hot": hot, "cold": cold}

func split_world(full: Dictionary) -> Dictionary:
	return split_world_by(full, cold_sections())

# What the host uploads: the hot world every time, a cold section only when the
# server does not hold its revision and it is not already in flight.
func host_upload(body: Dictionary) -> void:
	var parts = split_world(world_state())
	body.world = parts.hot
	var now = Time.get_ticks_msec()
	var intervals = section_intervals()
	var cold = {}
	for section in parts.cold:
		var revision = int(parts.hot.cold_revs[section])
		if server_cold_revs.has(section) and int(server_cold_revs[section]) == revision:
			continue
		# A busy section waits for its interval; the change goes with the next upload.
		var interval_ms = int(float(intervals.get(section, 0.0)) * 1000.0)
		if interval_ms > 0 and cold_uploaded_at.has(section) and now - int(cold_uploaded_at[section]) < interval_ms:
			continue
		# A section in flight is not repeated until the server could have answered.
		var sent: Dictionary = cold_sent.get(section, {})
		if int(sent.get("revision", -1)) == revision and now - int(sent.get("time", 0)) < 1000:
			continue
		cold[section] = parts.cold[section]
		cold_sent[section] = {"revision": revision, "time": now}
		cold_uploaded_at[section] = now
	if not cold.is_empty():
		body.cold = cold

func reset() -> void:
	cold_revs.clear()
	server_cold_revs.clear()
	cold_sent.clear()
	cold_uploaded_at.clear()

# ---------------------------------------------------------------- guest side

# Cold sections arrive inside "cold" when their revision changes. A complete
# snapshot (tests, late joins through older servers) carries them inline.
func cold_part(w: Dictionary):
	if w.get("cold") is Dictionary:
		var fields = {}
		for section in w.cold:
			if w.cold[section] is Dictionary:
				fields.merge(w.cold[section], true)
		return {"fields": fields, "sections": w.cold.keys()}
	if w.has("camp"):
		return {"fields": w, "sections": cold_sections().keys()}
	return null

# World collision geometry (snow, trees, lamps) a guest needs before replaying
# its own unacknowledged driving input.
func apply_collision(w: Dictionary) -> void:
	_ensure()
	var cold = cold_part(w)
	if cold == null:
		return
	for p in providers:
		if p.collision and p.section in cold.sections:
			p.apply.call(cold.fields, -1.0)

func apply_world(w: Dictionary, sample_time: float) -> void:
	_ensure()
	var cold = cold_part(w)
	if cold != null:
		for p in providers:
			if p.section != "" and p.section in cold.sections:
				p.apply.call(cold.fields, sample_time)
		var revisions = w.get("cold_revs", {})
		if revisions is Dictionary:
			for section in cold.sections:
				if revisions.has(section):
					cold_revs[section] = int(revisions[section])
	for p in providers:
		if p.section == "":
			p.apply.call(w, sample_time)

# ---------------------------------------------------------------- providers

func _drive_snapshot() -> Dictionary:
	var driving = {}
	for id in room.host_drives:
		driving[id] = room.host_drives[id].snapshot()
	return {"drive_protocol": 1, "driving": driving}

func _status_snapshot() -> Dictionary:
	# The toast text only travels while it is on screen.
	var showing: bool = game.toast_time > 0
	return {"paused": game.paused, "notice": game.toast_label.text if showing else "", "notice_time": snappedf(game.toast_time, 0.1) if showing else 0.0, "cook_time": snappedf(game.cook_time, 0.01)}

func _status_apply(w: Dictionary, _t: float) -> void:
	room.world_paused = bool(w.get("paused", false))
	if w.get("notice_time", 0) > 0 and w.get("notice", "") != last_notice:
		last_notice = w.notice
		game.toast(last_notice)
	game.cook_time = float(w.get("cook_time", game.cook_time))

func _progress_snapshot() -> Dictionary:
	return {"racing": game.racing, "passed": game.passed, "helped": game.helped, "elapsed": game.elapsed}

func _progress_apply(w: Dictionary, _t: float) -> void:
	game.racing = bool(w.get("racing", game.racing))
	game.passed = int(w.get("passed", game.passed))
	game.helped = int(w.get("helped", game.helped))
	game.elapsed = float(w.get("elapsed", game.elapsed))

func _outcome_snapshot() -> Dictionary:
	var result = {"dead": game.dead, "finished": game.finished}
	# The result text is only needed once the shared run ends.
	if game.dead or game.finished:
		result.title = game.menu_title.text
		result.text = game.menu_text.text
	return result

func _outcome_apply(w: Dictionary, _t: float) -> void:
	var dead = bool(w.get("dead", false))
	var finished = bool(w.get("finished", false))
	if (dead or finished) and not game.dead and not game.finished:
		game.dead = dead
		game.finished = finished
		game._show_result(str(w.get("title", "")), str(w.get("text", "")))

func _stones_apply(w: Dictionary, sample_time: float) -> void:
	room.apply_stones(w, sample_time)

func _camp_snapshot() -> Dictionary:
	var chair_poses = {}
	for owner in game.personal_chairs:
		var chair = game.personal_chairs[owner]
		chair_poses[owner] = {"pos": room.a(chair.position), "yaw": chair.rotation.y}
	var flag_poses = {}
	for owner in game.personal_flags:
		flag_poses[owner] = []
		for flag in game.personal_flags[owner]:
			flag_poses[owner].append({"pos": room.a(flag.position), "yaw": flag.rotation.y})
	return {"camp": room.a(game.camp.position) if game.camp != null else null, "table_yaw": game.camp.rotation.y if game.camp != null else 0.0, "chairs": game.has_chairs, "chair_poses": chair_poses, "flag_poses": flag_poses, "cooking": game.cooking, "grill_pose": {"pos": room.a(game.grill.position), "yaw": game.grill.rotation.y} if game.grill != null else null, "grill_servings": game.grill_servings, "npc_servings": game.spectators.snapshot(), "eaten": game.eaten}

func _camp_apply(f: Dictionary, _t: float) -> void:
	var camp_position = f.get("camp")
	var cooking = bool(f.get("cooking", false))
	# Full snapshots reconcile removals as well as additions.
	if camp_position == null and game.camp != null:
		game.packing.remove({"kind": "table", "node": game.camp})
	if f.has("chair_poses"):
		for owner in game.personal_chairs.keys():
			if not f.chair_poses.has(owner):
				game.packing.remove({"kind": "chair", "owner": owner, "node": game.personal_chairs[owner]})
	if f.has("flag_poses"):
		for owner in game.personal_flags.keys():
			if not f.flag_poses.has(owner):
				for node in game.personal_flags[owner].duplicate():
					game.packing.remove({"kind": "flag", "owner": owner, "node": node})
	if not cooking and game.grill != null:
		game.packing.remove({"kind": "grill", "node": game.grill})
	if camp_position != null:
		if game.camp == null:
			game.camp = Node3D.new()
			game.add_child(game.camp)
			Props.table(game.camp)
		game.camp.position = room.v(camp_position)
		game.camp.rotation.y = float(f.get("table_yaw", 0.0))
	if f.has("flag_poses"):
		for owner in f.flag_poses:
			var poses = f.flag_poses[owner]
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
	if f.has("chair_poses"):
		for owner in f.chair_poses:
			var pose = f.chair_poses[owner]
			game.apply_chair(owner, room.v(pose.pos), float(pose.yaw))
	else:
		if f.get("chairs", false) and not game.has_chairs and game.camp != null:
			game.apply_chair("legacy", game.camp.position + Vector3(-1.6, 0, 0.7), 0.0)
	game.has_chairs = bool(f.get("chairs", false))
	if cooking:
		var grill_pose = f.get("grill_pose", null)
		var spot = room.v(grill_pose.pos) if grill_pose != null else game.camp.position + Vector3(0.3, 0, -2.4)
		var yaw = float(grill_pose.yaw) if grill_pose != null else 0.0
		game.start_grill(spot, yaw, true)
	game.grill_servings = int(f.get("grill_servings", Props.FOOD_PORTIONS))
	if game.grill != null:
		Props.set_grill_servings(game.grill, game.grill_servings)
	game.spectators.apply_snapshot(f.get("npc_servings", []))
	game.eaten = bool(f.get("eaten", false))

func _racers_snapshot() -> Dictionary:
	var racers = []
	for r in game.racers:
		# Default fields are left out; the guest reads them with the same defaults.
		var entry = {"id": r.id, "variant": r.variant, "pos": room.a(r.node.position), "yaw": snappedf(r.node.rotation.y, 0.001), "tilt": room.a(r.node.rotation), "state": r.state}
		if r.get("role", "racer") != "racer":
			entry.role = r.role
		if int(r.get("zero_index", 0)) != 0:
			entry.zero_index = r.zero_index
		if float(r.get("recovery_progress", 0)) != 0.0:
			entry.recovery_progress = snappedf(float(r.recovery_progress), 0.01)
		if int(r.get("recovery_helpers", 0)) != 0:
			entry.recovery_helpers = r.recovery_helpers
		racers.append(entry)
	return {"racers": racers, "tow": game.tow_target.get_meta("room_id") if game.tow_target != null else -1, "tow_progress": game.tow_progress, "tow_owner": room.tow_owner, "recovery_links": game.recovery_links, "recovery_helpers": game.recovery_helpers}

func _racers_apply(w: Dictionary, sample_time: float) -> void:
	if not w.has("racers"):
		return
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
			var node = Props.car(Color.WHITE, true, int(r.variant)) if role == "racer" else Props.course_car(role, int(r.get("zero_index", 0)))
			game.add_child(node)
			node.position = room.v(r.pos)
			node.set_meta("room_id", r.id)
			game.racers.append({"id": r.id, "role": role, "zero_index": int(r.get("zero_index", 0)), "node": node, "state": r.state, "variant": r.variant})
		if not racer_motion.has(r.id):
			racer_motion[r.id] = SnapshotMotion.new()
		var tilt = room.v(r.get("tilt", [0, r.yaw, 0]))
		tilt.y = r.yaw
		racer_motion[r.id].push(sample_time, room.v(r.pos), tilt)
		racer_targets[r.id] = r
	for local in game.racers.duplicate():
		if not present.has(local.id):
			local.node.queue_free()
			game.racers.erase(local)
			racer_targets.erase(local.id)
			racer_motion.erase(local.id)
	game._cancel_tow()
	for local in game.racers:
		if local.id == w.get("tow", -1):
			game.tow_target = local.node
	game.tow_progress = float(w.get("tow_progress", 0.0))
	game.recovery_links = w.get("recovery_links", []).duplicate(true)
	game.recovery_helpers = int(w.get("recovery_helpers", 0))
	game.draw_recovery_ropes()
