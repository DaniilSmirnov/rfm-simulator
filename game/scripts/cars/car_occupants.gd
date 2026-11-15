extends RefCounted
# People seated in a car_body.gd cabin, seen through the glass: the pilot and
# navigator of rally crews and zero cars (overalls and helmets), the police
# officer driving a course police car (uniform and cap), and the two doctors
# of the ambulance. Figures are sized to the cabin (car_interior.gd cabin()),
# whose floor is at the belt line, so a seated person fits under the roof.
# The driver is plain boxes and bakes into the car body. A passenger who gets
# out (the ambulance doctor who treats casualties, ambulance_medics.gd) is its
# own merged node, PASSENGER, hidden while they are outside.
#
#   CarOccupants.seat(root, p, f, "pilot", "navigator")
const P = preload("res://scripts/core/props.gd")
const CarInterior = preload("res://scripts/cars/car_interior.gd")
const MeshMerge = preload("res://scripts/core/mesh_merge.gd")
const PASSENGER = "CabinPassenger"
const SKIN = Color("d9a98a")
const HAIR = Color("4a3426")
# Outfit per role: body colour, head ("helmet", "cap", "hair") and what the
# hands hold when not driving.
const ROLES = {
	"pilot": {"suit": "", "head": "helmet"},
	"navigator": {"suit": "", "head": "helmet", "holds": "notes"},
	"police": {"suit": "3e5168", "head": "cap", "cap": "26324a"},
	"medic": {"suit": "e4efee", "head": "hair", "cross": true},
}

# Seats a driver and, if `passenger` is not "", a front passenger. A passenger
# that `leaves` goes into its own node (PASSENGER) so it can be hidden.
static func seat(root: Node3D, p: Dictionary, f: Dictionary, driver: String, passenger: String = "", leaves: bool = false, cache_key: String = "") -> void:
	var c = CarInterior.cabin(p, f)
	var wheel = CarInterior.wheel_centre(p, c)
	_person(root, p, c, wheel.x, driver, wheel)
	if passenger == "":
		return
	var holder: Node3D = root
	if leaves:
		holder = Node3D.new()
		holder.name = PASSENGER
		# Kept out of the car body bake: it hides while the doctor is outside.
		holder.set_meta("unbatched", true)
		root.add_child(holder)
	_person(holder, p, c, -wheel.x, passenger, null)
	if leaves:
		MeshMerge.bake(holder, cache_key + ":" + PASSENGER if cache_key != "" else "")

# Shows or hides the passenger who gets out (no-op for cars without one).
static func passenger_aboard(car: Node3D, aboard: bool) -> void:
	var holder = car.get_node_or_null(PASSENGER) if car != null else null
	if holder != null:
		holder.visible = aboard

static func _person(root: Node3D, p: Dictionary, c: Dictionary, x: float, role: String, wheel) -> void:
	var spec: Dictionary = ROLES[role]
	var a: float = c.avail
	var suit = Color(spec.suit) if spec.suit != "" else Color(p.get("suit", p.get("accent", "2f4a7a")))
	# Life size: the head just under the roof, the body down past the belt
	# line into the shell (the cabin floor is at the belt), as seen from outside.
	var head = 0.21
	var chest = 0.5
	var top: float = c.floor + a - 0.035
	var chest_top = top - head * 1.12 - 0.05
	# A tall cab (the ambulance) has room to sit on the cushion, legs and all.
	var seated = chest_top - chest >= c.floor + a * 0.12
	var hip = Vector3(x, minf(chest_top - chest, c.floor + a * 0.12), c.front_seat - 0.16)
	if seated:
		P.box(root, hip + Vector3(0, 0.06, -0.22), Vector3(0.36, 0.12, 0.44), suit.darkened(0.12))
		for dx in [-0.09, 0.09]:
			P.box(root, Vector3(x + dx, (c.floor + hip.y) * 0.5, hip.z - 0.42), Vector3(0.12, hip.y - c.floor, 0.12), suit.darkened(0.12))
	var torso = Node3D.new()
	root.add_child(torso)
	torso.position = hip
	torso.rotation.x = 0.12 # leaning back like the seat
	P.box(torso, Vector3(0, chest * 0.5, 0), Vector3(0.4, chest, 0.22), suit)
	if role in ["pilot", "navigator"]:
		# Harness straps over the overalls.
		for dx in [-0.08, 0.08]:
			P.box(torso, Vector3(dx, chest * 0.6, -0.113), Vector3(0.045, chest * 0.8, 0.006), Color("1d2125"))
	if spec.get("cross", false):
		P.box(torso, Vector3(0.1, chest * 0.8, -0.113), Vector3(0.07, 0.02, 0.006), Color("d93742"))
		P.box(torso, Vector3(0.1, chest * 0.8, -0.113), Vector3(0.02, 0.07, 0.006), Color("d93742"))
	if role == "police":
		P.box(torso, Vector3(-0.1, chest * 0.82, -0.113), Vector3(0.06, 0.05, 0.006), Color("c9a95b")) # badge
	var neck = Vector3(0, chest + 0.025, 0)
	P.box(torso, neck, Vector3(0.1, 0.06, 0.1), SKIN)
	var centre = neck + Vector3(0, 0.03 + head * 0.5, 0)
	_head(torso, p, spec, centre, head, suit)
	# Arms from the shoulders: to the steering wheel rim, or to the lap.
	var shoulder_y = chest * 0.92
	for side in [-1.0, 1.0]:
		var shoulder = hip + Basis(Vector3.RIGHT, 0.12) * Vector3(side * 0.2, shoulder_y, 0)
		var hand: Vector3
		if wheel != null:
			hand = wheel + Vector3(side * minf(0.15, a * 0.32), 0.04, 0.03)
		else:
			hand = Vector3(x + side * 0.12, c.floor + 0.06, hip.z - 0.3)
		var elbow = (shoulder + hand) * 0.5 + Vector3(side * 0.04, -0.05, 0.02)
		P.car_beam(root, shoulder, elbow, 0.085, suit)
		P.car_beam(root, elbow, hand, 0.075, suit)
		P.box(root, hand, Vector3(0.06, 0.06, 0.06), Color("1d2125") if spec.head == "helmet" else SKIN)
	if spec.get("holds", "") == "notes":
		# Pace-note book open on the navigator's lap.
		var notes = P.box(root, Vector3(x, c.floor + 0.09, hip.z - 0.32), Vector3(0.24, 0.015, 0.17), Color("f3efe2"))
		notes.rotation.x = 0.5

static func _head(torso: Node3D, p: Dictionary, spec: Dictionary, centre: Vector3, head: float, suit: Color) -> void:
	match str(spec.head):
		"helmet":
			var helmet = Color(p.get("helmet", "f1f0ea"))
			P.faceted(torso, centre, Vector3(head * 1.15, head * 1.1, head * 1.2), helmet, 10, 5)
			P.box(torso, centre + Vector3(0, 0.0, -head * 0.55), Vector3(head * 0.85, head * 0.32, 0.02), Color("1b2228"))
			P.box(torso, centre + Vector3(0, head * 0.42, 0), Vector3(head * 0.24, 0.012, head * 1.1), suit)
		"cap":
			P.faceted(torso, centre, Vector3(head * 0.92, head, head), SKIN, 8, 4)
			P.box(torso, centre + Vector3(0, head * 0.45, 0.01), Vector3(head * 1.05, head * 0.28, head * 1.05), Color(spec.cap))
			P.box(torso, centre + Vector3(0, head * 0.34, 0.01), Vector3(head * 1.07, head * 0.08, head * 1.07), Color("b8312f"))
			P.box(torso, centre + Vector3(0, head * 0.33, -head * 0.6), Vector3(head * 0.8, 0.012, head * 0.3), Color("151a22"))
		_:
			P.faceted(torso, centre, Vector3(head * 0.92, head, head), SKIN, 8, 4)
			P.box(torso, centre + Vector3(0, head * 0.38, 0.02), Vector3(head * 0.98, head * 0.3, head), HAIR)
