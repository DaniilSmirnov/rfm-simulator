extends RefCounted
# People seated in a car_body.gd cabin, seen through the glass: the pilot and
# navigator of rally crews and zero cars, the police officer driving a course
# police car, and the two doctors of the ambulance. They are the same
# character models as the players and NPCs (Props.player_avatar(), the medic
# of medic_model.gd), seated by CharacterRig with their hands on the wheel or
# in the lap, dressed per role: overalls and a helmet, a uniform and a cap,
# the doctor's white coat. The cabin floor is at the belt line
# (car_interior.gd cabin()), so a person is scaled to put the head under the
# roof and the shoulders at the belt, the way you see a driver from outside.
# Each person is one mesh of its own, built once per car model (_person());
# a passenger who gets out (the ambulance doctor who treats casualties,
# ambulance_medics.gd) sits under PASSENGER, hidden while they are outside.
#
#   CarOccupants.seat(root, p, f, "pilot", "navigator", false, "", seed)
const P = preload("res://scripts/core/props.gd")
const CarInterior = preload("res://scripts/cars/car_interior.gd")
const MeshMerge = preload("res://scripts/core/mesh_merge.gd")
const CharacterRig = preload("res://scripts/people/character_rig.gd")
const MedicModel = preload("res://scripts/people/medic_model.gd")
const Glass = preload("res://scripts/core/glass.gd")
const PASSENGER = "CabinPassenger"
const DOOR = "CabinDoor"
# How far the passenger's door swings out (rad).
const DOOR_SWING = 1.15
# Characters without a hat or cap (a helmet or a uniform cap goes on instead).
const BARE_HEADS = [0, 2, 4, 5, 7, 9, 10]
# Seat height above the feet (m, unscaled) and the body above the shoulders:
# shoulder joints stand at 1.29 m, the top of the head at about 2.2 m.
const SEAT = 0.3
const SHOULDER_Y = 1.29
const HEAD_TOP = 2.2
# The cartoon characters stand 2.2 m tall; in a cab with room (the ambulance)
# they still sit smaller, so the heads do not fill the windscreen.
const MAX_SCALE = 0.75
# Seated people are drawn this close to the camera (m) and no further.
const VISIBLE = 45.0
# Triangles lower than this under the belt line (the cabin floor) are cut.
const BELOW_BELT = 0.05
# Clothes per role over the character's own: torso colour ("" = livery accent),
# head gear, what the hands hold.
const ROLES = {
	"pilot": {"suit": "", "head": "helmet"},
	"navigator": {"suit": "", "head": "helmet", "holds": "notes"},
	"police": {"suit": "3e5168", "head": "cap", "cap": "26324a"},
	"medic": {"medic": true},
}

# Seats a driver and, if `passenger` is not "", a front passenger. A passenger
# that `leaves` goes into its own node (PASSENGER) so it can be hidden. `seed`
# picks the characters (the same car always carries the same people).
static var _people: Dictionary = {}

static func seat(root: Node3D, p: Dictionary, f: Dictionary, driver: String, passenger: String = "", leaves: bool = false, _cache_key: String = "", seed: int = 0) -> void:
	var c = CarInterior.cabin(p, f)
	var wheel = CarInterior.wheel_centre(p, c)
	root.add_child(_person(p, c, wheel.x, driver, wheel, seed * 2).node)
	if passenger == "":
		return
	var person = _person(p, c, -wheel.x, passenger, null, seed * 2 + 1)
	if not leaves:
		root.add_child(person.node)
		return
	var holder = Node3D.new()
	holder.name = PASSENGER
	root.add_child(holder)
	holder.add_child(person.node)
	# Where the doctor sits, for the climb out and back in.
	holder.set_meta("seat_feet", person.feet)
	holder.set_meta("seat_scale", person.scale)
	_door(root, p, f, c, signf(-wheel.x))

# Shows or hides the passenger who gets out (no-op for cars without one).
static func passenger_aboard(car: Node3D, aboard: bool) -> void:
	var holder = car.get_node_or_null(PASSENGER) if car != null else null
	if holder != null:
		holder.visible = aboard

# Feet position (car space) and scale of the passenger who gets out, or {}.
static func passenger_seat(car: Node3D) -> Dictionary:
	var holder = car.get_node_or_null(PASSENGER) if car != null else null
	if holder == null or not holder.has_meta("seat_feet"):
		return {}
	return {"feet": holder.get_meta("seat_feet"), "scale": float(holder.get_meta("seat_scale")), "side": float(car.get_node(DOOR).get_meta("side")) if car.has_node(DOOR) else 1.0}

# Swings the passenger's door: 0 shut (the body's own door shows), 1 wide open.
static func door_open(car: Node3D, amount: float) -> void:
	var door = car.get_node_or_null(DOOR) if car != null else null
	if door == null:
		return
	var open = clampf(amount, 0.0, 1.0)
	door.visible = open > 0.01
	door.get_node("Leaf").rotation.y = float(door.get_meta("side")) * DOOR_SWING * open

# The passenger's door as its own leaf on a hinge at the front edge, shown only
# while open, and the dark doorway it leaves in the side of the body.
static func _door(root: Node3D, p: Dictionary, f: Dictionary, c: Dictionary, side: float) -> void:
	var holder = Node3D.new()
	holder.name = DOOR
	holder.set_meta("unbatched", true)
	holder.set_meta("side", side)
	holder.visible = false
	root.add_child(holder)
	var hinge: float = float(f.shape[0]) + 0.12
	var back: float = float(p.get("pillar", 0.1)) - 0.02
	var length = maxf(0.4, back - hinge)
	var x: float = side * (float(f.half) + 0.01)
	var low: float = float(f.sill) + 0.1
	var belt: float = float(f.floor)
	var top: float = float(f.height) - 0.08
	P.box(holder, Vector3(x - side * 0.02, (low + belt) * 0.5, hinge + length * 0.5), Vector3(0.02, belt - low, length - 0.04), Color("23272b"))
	var leaf = Node3D.new()
	leaf.name = "Leaf"
	holder.add_child(leaf)
	leaf.position = Vector3(x, 0, hinge)
	var paint = Color(p.color)
	var frame = Color(p.get("trim", "30383b"))
	P.box(leaf, Vector3(0, (low + belt) * 0.5, length * 0.5), Vector3(0.05, belt - low, length), paint)
	P.box(leaf, Vector3(-side * 0.03, (low + belt) * 0.5, length * 0.5), Vector3(0.01, belt - low - 0.08, length - 0.1), Color(p.get("interior", "2a2e33")))
	P.box(leaf, Vector3(0, belt + 0.02, length * 0.5), Vector3(0.05, 0.04, length), frame)
	P.box(leaf, Vector3(0, top, length * 0.5), Vector3(0.05, 0.04, length), frame)
	for z in [0.02, length - 0.02]:
		P.box(leaf, Vector3(0, (belt + top) * 0.5, z), Vector3(0.05, top - belt, 0.04), frame)
	var pane = P.box(leaf, Vector3(0, (belt + top) * 0.5 + 0.01, length * 0.5), Vector3(0.012, top - belt - 0.04, length - 0.06), Color.WHITE)
	Glass.glaze(pane)
	P.box(leaf, Vector3(side * 0.035, belt - 0.12, length - 0.14), Vector3(0.02, 0.03, 0.12), frame.darkened(0.3))

# Scale and feet height of a seated person in this cabin: head just under the
# roof, shoulders near the belt; in a tall cab (the ambulance) they sit on the
# cushion at full size instead.
static func fit(c: Dictionary) -> Vector2:
	var roof: float = c.floor + c.avail - 0.03
	var drop = SEAT - CharacterRig.PELVIS_BOTTOM
	var cushion: float = c.floor + c.avail * 0.12
	var scale = clampf((roof - c.floor + 0.04) / (HEAD_TOP - SHOULDER_Y), 0.4, MAX_SCALE)
	var feet = roof - (HEAD_TOP + drop) * scale
	if feet + SEAT * scale <= cushion:
		return Vector2(scale, feet)
	# A tall cab: on the cushion, with the whole body under the roof.
	scale = minf(MAX_SCALE, (roof - cushion) / (HEAD_TOP + drop - SEAT))
	return Vector2(scale, cushion - SEAT * scale)

# One seated person as a single mesh in car space, shared by every car of the
# same model: {"node", "feet", "scale"}. The character models are detailed
# (about 40k vertices each), so building and merging a crew into every new
# car body stalled the game for a tenth of a second per car (more on the
# Web) and drew the hidden legs in every frame. Now each person is posed and
# merged once, cut at the belt line (nothing below it shows through the
# glass), kept out of the body bake and its shadows, and drawn only near
# the camera (VISIBLE): through tinted glass nobody makes out a face beyond.
static func _person(p: Dictionary, c: Dictionary, x: float, role: String, wheel, seed: int) -> Dictionary:
	var key = str([p.get("name", ""), p.get("color", ""), p.get("suit", ""), p.get("accent", ""), p.get("helmet", ""), role, seed, x, c, wheel])
	if not _people.has(key):
		_people[key] = _bake_person(p, c, x, role, wheel, seed)
	var entry: Dictionary = _people[key]
	var node = MeshInstance3D.new()
	node.name = "Occupant_" + role.capitalize()
	node.mesh = entry.mesh
	# Its own draw call: kept out of the car body bake (MeshMerge) so a new
	# car does not merge the crew again.
	node.set_meta("unbatched", true)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = VISIBLE
	node.visibility_range_end_margin = 5.0
	return {"node": node, "feet": entry.feet, "scale": entry.scale}

static func _bake_person(p: Dictionary, c: Dictionary, x: float, role: String, wheel, seed: int) -> Dictionary:
	var spec: Dictionary = ROLES[role]
	var holder = Node3D.new()
	var avatar: Node3D
	if spec.get("medic", false):
		avatar = MedicModel.create("")
	else:
		avatar = P.player_avatar(BARE_HEADS[posmod(seed, BARE_HEADS.size())])
	holder.add_child(avatar)
	var place = fit(c)
	avatar.scale = Vector3.ONE * place.x
	avatar.position = Vector3(x, place.y, c.front_seat - 0.2 * place.x)
	if not spec.get("medic", false):
		_dress(avatar, p, spec)
	_strip_hidden(avatar)
	_pose(avatar, wheel)
	# The formula guesses the seated height; hats and big heads can still
	# reach above it, so measure the posed figure and shrink it under the roof.
	var roof: float = c.floor + c.avail - 0.03
	var top = _top(avatar, holder)
	if top > roof:
		var k = (roof - place.y) / maxf(0.1, top - place.y)
		avatar.scale *= k
		_pose(avatar, wheel)
	if spec.get("holds", "") == "notes":
		# Pace-note book in the navigator's right hand.
		P.box(CharacterRig.hand(avatar), CharacterRig.grip() + Vector3(-0.08, 0, -0.06), Vector3(0.22, 0.02, 0.16), Color("f3efe2"))
	var feet = avatar.position
	var scale = avatar.scale.x
	var baked = MeshMerge.bake(holder)
	var mesh: ArrayMesh = _above(baked.mesh, c.floor - BELOW_BELT) if baked != null else ArrayMesh.new()
	holder.free()
	return {"mesh": mesh, "feet": feet, "scale": scale}

# The triangles of a merged (unindexed) mesh that reach above `floor`.
static func _above(mesh: ArrayMesh, floor: float) -> ArrayMesh:
	var result = ArrayMesh.new()
	for surface in range(mesh.get_surface_count()):
		var arrays = mesh.surface_get_arrays(surface)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var col: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var kv = PackedVector3Array()
		var kn = PackedVector3Array()
		var kc = PackedColorArray()
		for i in range(0, v.size() - 2, 3):
			if maxf(v[i].y, maxf(v[i + 1].y, v[i + 2].y)) < floor:
				continue
			for j in range(i, i + 3):
				kv.append(v[j])
				kn.append(n[j])
				kc.append(col[j])
		if kv.is_empty():
			continue
		var out = []
		out.resize(Mesh.ARRAY_MAX)
		out[Mesh.ARRAY_VERTEX] = kv
		out[Mesh.ARRAY_NORMAL] = kn
		out[Mesh.ARRAY_COLOR] = kc
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
		result.surface_set_material(result.get_surface_count() - 1, mesh.surface_get_material(surface))
	return result

static func _pose(avatar: Node3D, wheel) -> void:
	var pose = {"seat": SEAT, "arms": "lap"}
	if wheel != null:
		# Both hands on the rim: the target is the right hand's, mirrored left.
		var hub: Vector3 = avatar.transform.affine_inverse() * wheel
		pose.arms = "steer"
		pose.steer = Vector3(0.17, hub.y + 0.04, hub.z + 0.03)
	CharacterRig.pose(avatar, pose)

# Highest point of the person's meshes in the car's space.
static func _top(avatar: Node3D, root: Node3D) -> float:
	var top = -INF
	for mesh in avatar.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		var at: Transform3D = _local(mesh, root)
		top = maxf(top, (at * mesh.mesh.get_aabb()).end.y)
	return top

# Transform of `node` relative to its ancestor `root`, without the scene tree.
static func _local(node: Node3D, root: Node3D) -> Transform3D:
	var t = Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			t = n.transform * t
		n = n.get_parent()
	return t

# Overalls or a uniform jacket over the character's clothes, and the head gear.
static func _dress(avatar: Node3D, p: Dictionary, spec: Dictionary) -> void:
	var suit = Color(spec.suit) if spec.suit != "" else Color(p.get("suit", p.get("accent", "2f4a7a")))
	P.box(avatar, Vector3(0, 1.1, 0), Vector3(0.68, 0.6, 0.55), suit)
	for side in ["LeftArm", "RightArm"]:
		P.box(avatar.get_node(side), Vector3(0, -0.10, 0), Vector3(0.23, 0.27, 0.24), suit)
	if spec.head == "helmet":
		# Harness straps over the overalls.
		for dx in [-0.1, 0.1]:
			P.box(avatar, Vector3(dx, 1.12, -0.28), Vector3(0.07, 0.56, 0.02), Color("1d2125"))
	else:
		P.box(avatar, Vector3(-0.15, 1.25, -0.28), Vector3(0.08, 0.07, 0.02), Color("c9a95b")) # badge
	var head: Node3D = avatar.get_node("Head")
	var box = AABB()
	for mesh in head.find_children("*", "MeshInstance3D", true, false):
		var part: AABB = mesh.transform * mesh.mesh.get_aabb()
		box = part if box.size == Vector3.ZERO else box.merge(part)
	var centre = Vector3(0, box.end.y - 0.24, box.get_center().z)
	if spec.head == "helmet":
		P.faceted(head, centre, Vector3(0.62, 0.56, 0.64), Color(p.get("helmet", "f1f0ea")), 12, 6)
		P.box(head, centre + Vector3(0, -0.04, -0.31), Vector3(0.46, 0.17, 0.03), Color("1b2228"))
		P.box(head, centre + Vector3(0, 0.25, 0), Vector3(0.12, 0.03, 0.62), suit)
	else:
		P.faceted(head, centre + Vector3(0, 0.12, 0), Vector3(0.6, 0.24, 0.6), Color(spec.cap), 12, 4)
		P.box(head, centre + Vector3(0, 0.05, 0), Vector3(0.6, 0.06, 0.6), Color("b8312f"))
		P.box(head, centre + Vector3(0, 0.03, -0.34), Vector3(0.4, 0.025, 0.16), Color("151a22"))

# Hand props kept hidden on the character (a beer can, a skewer) have no use
# in a car: drop them so they do not ride along outside the baked body.
static func _strip_hidden(node: Node) -> void:
	for child in node.get_children():
		if child is Node3D and not child.visible:
			node.remove_child(child)
			child.free()
		else:
			_strip_hidden(child)
