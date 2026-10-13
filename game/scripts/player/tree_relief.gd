extends RefCounted
# Unlisted on purpose: after at least one beer, F at a standing tree lets the
# fan relieve himself. The camera stays free, the stream follows where he
# looks (yaw and pitch), splashes on whatever it reaches and leaves a puddle
# on the ground; people it reaches complain. Friends in a room see the pose
# and the stream (state "relief"), drawn by the same code from their yaw and pitch.
const Props = preload("res://scripts/core/props.gd")
const CharacterRig = preload("res://scripts/people/character_rig.gd")
const ORIGIN_HEIGHT = 0.74
const ORIGIN_AHEAD = 0.26
const SPEED = 3.6
const GRAVITY = 9.8
const STEP = 0.02
const MAX_FLIGHT = 1.4
const SEGMENTS = 24
const DROPLETS = 8
const TREE_REACH = 1.9
const PUDDLE_LIFETIME = 90.0
const MAX_PUDDLES = 24
const COLOR = Color("e9d257")
const PUDDLE_COLOR = Color("7d6b31")
const COMPLAINTS = ["Эй! Аккуратнее!", "Ты что творишь?!", "Фу-у-у!", "Совсем уже?!"]

var game
var active = false
var time_left = 0.0
var stream: Dictionary = {}
var puddles: Array[Dictionary] = []
var complaint_at = -INF

# The bladder empties in 8–20 s, longer after more beer.
func duration() -> float:
	return clampf(6.0 + 2.0 * game.beers, 8.0, 20.0)

func can_start() -> bool:
	return not active and game.beers >= 1 and game.beers < 30 and not game.in_car and not game.seated and not game.injuries.down \
		and game.drink_time < 0 and game.eat_time < 0 and game.placement_kind == "" and not game.cargo.held.has(game.chair_owner())

# Standing trees within reach, offered as a gaze target on the trunk.
func offers(items: Array, interaction) -> void:
	if not can_start():
		return
	var stage = game.stage
	var nearby: Array = []
	if stage.tree_cells.is_empty() or stage.indexed_tree_count != stage.trees.size():
		nearby = range(stage.trees.size())
	else:
		var cell = Vector2i(floori(game.walker.x / stage.TREE_CELL_SIZE), floori(game.walker.z / stage.TREE_CELL_SIZE))
		for x in range(cell.x - 1, cell.x + 2):
			for z in range(cell.y - 1, cell.y + 2):
				nearby.append_array(stage.tree_cells.get(Vector2i(x, z), []))
	for index in nearby:
		var base: Vector3 = stage.trees[index]
		if stage.fallen.has(index) or Vector2(base.x - game.walker.x, base.z - game.walker.z).length() > TREE_REACH:
			continue
		# Aim at the bark on the fan's side, so the trunk itself does not hide it.
		var toward = Vector3(game.walker.x - base.x, 0, game.walker.z - base.z).normalized()
		interaction.offer(items, base + toward * 0.3 + Vector3(0, 1.0, 0), 0.55, TREE_REACH + 0.6, "relief", "Отлить", index)

func start() -> void:
	if not can_start():
		return
	active = true
	time_left = duration()

func stop() -> void:
	active = false
	_show(stream, false)

# One frame of the local session. Returns true while the fan stands still.
func update(delta: float) -> bool:
	if not active:
		return false
	if game.in_car or game.seated or game.injuries.down or game.beers >= 30 or game.drink_time >= 0 or game.eat_time >= 0 or game.placement_kind != "":
		stop()
		return false
	time_left -= delta
	if time_left <= 0.0:
		stop()
		game.toast("Полегчало.")
		return false
	var feet = game.walker - Vector3(0, game.jump_height, 0)
	var hit = draw(stream, feet, game.view_yaw, game.view_pitch, game.injuries.local_key())
	if hit.get("kind", "") == "person":
		complain(COMPLAINTS[int(Time.get_ticks_msec() / 3000) % COMPLAINTS.size()])
	return true

func complain(text: String) -> void:
	var now = Time.get_ticks_msec() / 1000.0
	if now - complaint_at < 3.0:
		return
	complaint_at = now
	game.toast(text)

# A friend's stream on this client, from the friend's replicated yaw and pitch.
func draw_peer(peer: Dictionary, state: Dictionary) -> void:
	var on = bool(state.get("relief", false)) and not state.in_car and peer.avatar.visible
	if not peer.has("relief"):
		peer.relief = {}
	if not on:
		_show(peer.relief, false)
		return
	var hit = draw(peer.relief, peer.avatar.position, peer.avatar.rotation.y, float(state.get("pitch", 0.0)), "player:%s" % peer.id)
	if hit.get("key", "") == game.injuries.local_key():
		complain("Тебя облили! Фу-у-у!")

# Traces the stream from the fan at `feet` facing `yaw`, aimed by `pitch`, and
# shows it. Returns what it reached: {"kind": ground|tree|rock|solid|car|person, "key", "point"}.
func draw(view: Dictionary, feet: Vector3, yaw: float, pitch: float, owner_key: String) -> Dictionary:
	_build(view)
	var time = Time.get_ticks_msec() / 1000.0
	var forward = Vector3(-sin(yaw), 0, -cos(yaw))
	var side = forward.cross(Vector3.UP)
	var elevation = clampf(pitch * 0.8 + 0.25, -0.8, 0.95)
	var velocity = (forward * cos(elevation) + Vector3.UP * sin(elevation)) * (SPEED + sin(time * 5.3) * 0.15) + side * sin(time * 17.0) * 0.06
	var origin = feet + Vector3(0, ORIGIN_HEIGHT, 0) + forward * ORIGIN_AHEAD
	var points: Array[Vector3] = [origin]
	var hit = {}
	var t = 0.0
	while t < MAX_FLIGHT and hit.is_empty():
		t += STEP
		var point = origin + velocity * t + Vector3.DOWN * GRAVITY * 0.5 * t * t
		hit = _contact(points[-1], point, owner_key)
		points.append(hit.get("point", point))
	view.points = points
	view.hit = hit
	_place_segments(view, points)
	_splash(view, points[-1], time, not hit.is_empty())
	if hit.get("kind", "") == "ground":
		_wet(points[-1])
	_show(view, true)
	return hit

func _contact(from: Vector3, to: Vector3, owner_key: String) -> Dictionary:
	var stage = game.stage
	var ground = stage.ground(to)
	if to.y <= ground:
		return {"kind": "ground", "point": Vector3(to.x, ground + 0.01, to.z)}
	if stage.obstacle_hit(from, to, 0.03) >= 0:
		return {"kind": "tree", "point": from}
	if not stage.rock_hit(from, to, 0.03).is_empty():
		return {"kind": "rock", "point": from}
	if not stage.solids.hit(from, to, 0.03).is_empty():
		return {"kind": "solid", "point": from}
	for person in game.injuries.people():
		if str(person.key) == owner_key:
			continue
		var pos: Vector3 = person.pos
		if Vector2(to.x - pos.x, to.z - pos.z).length() < 0.32 and to.y > pos.y - 0.1 and to.y < pos.y + 1.95:
			return {"kind": "person", "key": str(person.key), "point": to}
	for car in _cars():
		if Vector2(to.x - car.x, to.z - car.z).length() < 1.05 and to.y < car.y + 1.45:
			return {"kind": "car", "point": to}
	return {}

func _cars() -> Array:
	var result: Array = [game.car.position]
	for peer in game.room.peers.values():
		result.append(peer.car.position)
	if game.spectators != null:
		for group in game.spectators.groups:
			result.append(group.car.position)
	return result

# ---------------------------------------------------------------- visuals

func _build(view: Dictionary) -> void:
	if view.has("segments"):
		return
	var parts = Node3D.new()
	game.add_child(parts)
	var sample = Props.cylinder(parts, Vector3.ZERO, 0.016, 0.016, 1.0, COLOR, 5)
	view.segments = _instances(sample, SEGMENTS)
	view.droplets = _instances(sample, DROPLETS)
	sample.free()
	parts.free()

func _instances(sample: MeshInstance3D, count: int) -> MultiMeshInstance3D:
	var multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = sample.mesh
	multimesh.instance_count = count
	var node = MultiMeshInstance3D.new()
	node.multimesh = multimesh
	node.material_override = sample.material_override
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Instances are placed in world space; never cull them by a stale origin box.
	node.custom_aabb = AABB(Vector3(-4000, -1000, -4000), Vector3(8000, 3000, 8000))
	game.add_child(node)
	node.hide()
	return node

func _show(view: Dictionary, on: bool) -> void:
	if view.has("segments"):
		view.segments.visible = on
		view.droplets.visible = on
	if not on:
		view.erase("points")

# Spreads the traced points over the fixed number of segments.
func _place_segments(view: Dictionary, points: Array[Vector3]) -> void:
	var multimesh: MultiMesh = view.segments.multimesh
	for i in range(SEGMENTS):
		var a = points[mini(points.size() - 1, int(float(i) / SEGMENTS * (points.size() - 1)))]
		var b = points[mini(points.size() - 1, int(float(i + 1) / SEGMENTS * (points.size() - 1)))]
		multimesh.set_instance_transform(i, _segment(a, b))

static func _segment(a: Vector3, b: Vector3) -> Transform3D:
	var along = b - a
	var length = along.length()
	if length < 0.0001:
		return Transform3D(Basis().scaled(Vector3(0.0001, 0.0001, 0.0001)), a)
	var y = along / length
	var x = y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z = x.cross(y)
	return Transform3D(Basis(x, y * length, z), (a + b) * 0.5)

func _splash(view: Dictionary, at: Vector3, time: float, landed: bool) -> void:
	var multimesh: MultiMesh = view.droplets.multimesh
	for i in range(DROPLETS):
		if not landed:
			multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.0001), at))
			continue
		var phase = fmod(time * 3.0 + i * 0.37, 1.0)
		var angle = i * TAU / DROPLETS + time
		var spot = at + Vector3(cos(angle), 0, sin(angle)) * phase * 0.18 + Vector3.UP * sin(phase * PI) * 0.12
		multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(1, 0.05, 1)), spot))

# A wet patch grows where the stream lands; a new one starts when it moves on.
func _wet(at: Vector3) -> void:
	var now = Time.get_ticks_msec() / 1000.0
	for i in range(puddles.size() - 1, -1, -1):
		if now - float(puddles[i].born) > PUDDLE_LIFETIME or puddles.size() > MAX_PUDDLES:
			puddles[i].node.queue_free()
			puddles.remove_at(i)
	for puddle in puddles:
		if Vector2(puddle.node.position.x - at.x, puddle.node.position.z - at.z).length() < 0.35:
			puddle.size = minf(1.0, float(puddle.size) + 0.004)
			puddle.node.scale = Vector3(puddle.size, 1, puddle.size)
			return
	var node = Node3D.new()
	game.add_child(node)
	node.position = at
	Props.cylinder(node, Vector3.ZERO, 0.42, 0.42, 0.012, PUDDLE_COLOR, 9)
	node.scale = Vector3(0.15, 1, 0.15)
	puddles.append({"node": node, "size": 0.15, "born": now})

# Pose of a fan standing at a tree: both hands in front of the belt.
static func pose(avatar: Node3D) -> void:
	CharacterRig.pose(avatar, {"arms": "relief"})
