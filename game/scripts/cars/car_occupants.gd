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
# The driver bakes into the car body with the cabin; a passenger who gets out
# (the ambulance doctor who treats casualties, ambulance_medics.gd) is its own
# merged node, PASSENGER, hidden while they are outside.
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
static func seat(root: Node3D, p: Dictionary, f: Dictionary, driver: String, passenger: String = "", leaves: bool = false, cache_key: String = "", seed: int = 0) -> void:
	var c = CarInterior.cabin(p, f)
	var wheel = CarInterior.wheel_centre(p, c)
	_person(root, p, c, wheel.x, driver, wheel, seed * 2)
	if passenger == "":
		return
	var holder: Node3D = root
	if leaves:
		holder = Node3D.new()
		holder.name = PASSENGER
		# Kept out of the car body bake: it hides while the doctor is outside.
		holder.set_meta("unbatched", true)
		root.add_child(holder)
	_person(holder, p, c, -wheel.x, passenger, null, seed * 2 + 1)
	if leaves:
		# Where the doctor sits, for the climb out and back in.
		var person: Node3D = holder.get_child(0)
		holder.set_meta("seat_feet", person.position)
		holder.set_meta("seat_scale", person.scale.x)
		MeshMerge.bake(holder, cache_key + ":" + PASSENGER if cache_key != "" else "")
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

static func _person(root: Node3D, p: Dictionary, c: Dictionary, x: float, role: String, wheel, seed: int) -> void:
	var spec: Dictionary = ROLES[role]
	var avatar: Node3D
	if spec.get("medic", false):
		avatar = MedicModel.create("")
	else:
		avatar = P.player_avatar(BARE_HEADS[posmod(seed, BARE_HEADS.size())])
	avatar.name = "Occupant_" + role.capitalize()
	var dress = func() -> void:
		if not spec.get("medic", false):
			_dress(avatar, p, spec)
	place(root, c, x, avatar, wheel, dress)
	if spec.get("holds", "") == "notes":
		# Pace-note book in the navigator's right hand.
		P.box(CharacterRig.hand(avatar), CharacterRig.grip() + Vector3(-0.08, 0, -0.06), Vector3(0.22, 0.02, 0.16), Color("f3efe2"))

# Seats `avatar` (a character model) in the cabin `c` at lateral `x`: scaled to
# the cabin, hands on the wheel when `wheel` is a hub position, otherwise in
# the lap. `dress` runs before the figure is measured against the roof.
static func place(root: Node3D, c: Dictionary, x: float, avatar: Node3D, wheel, dress: Callable = Callable()) -> void:
	root.add_child(avatar)
	var seat = fit(c)
	avatar.scale = Vector3.ONE * seat.x
	avatar.position = Vector3(x, seat.y, c.front_seat - 0.2 * seat.x)
	if dress.is_valid():
		dress.call()
	_strip_hidden(avatar)
	_pose(avatar, wheel)
	# The formula guesses the seated height; hats and big heads can still
	# reach above it, so measure the posed figure and shrink it under the roof.
	var roof: float = c.floor + c.avail - 0.03
	var top = _top(avatar, root)
	if top > roof:
		var k = (roof - seat.y) / maxf(0.1, top - seat.y)
		avatar.scale *= k
		_pose(avatar, wheel)

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
