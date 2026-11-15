extends RefCounted
# Players seen in their cars: whoever drives their own car sits at its wheel
# behind the glass, and the first friend who rides along takes the front
# passenger seat. On foot a player is their avatar (peer_view.gd); in a car
# that avatar hides, so the same character model, in the same clothes, is
# seated in the cabin (car_occupants.gd place()) and baked into one mesh.
# The cabin's seats come from car_interior.gd (meta SEAT_META on the car).
#
#   CarDrivers.update(game)  # once a frame, for the local car and every peer's
const CarInterior = preload("res://scripts/cars/car_interior.gd")
const CarOccupants = preload("res://scripts/cars/car_occupants.gd")
const MeshMerge = preload("res://scripts/core/mesh_merge.gd")
const P = preload("res://scripts/core/props.gd")
const DRIVER = "SeatedDriver"
const RIDER = "SeatedRider"
# Same reach as the avatar's own body parts (props.gd player_avatar()).
const VISIBLE_RANGE = 110.0

static func update(game) -> void:
	if game.car == null or game.room == null or game.room.Dedicated.active():
		return
	var people: Dictionary = {}
	var me = game.rides.me()
	people[me] = {"variant": game.avatar_variant, "outfit": str(game.stage.outfit) if game.stage != null else "",
		"in_car": game.in_car, "ride": game.rides.ride, "car": game.car}
	for id in game.room.peers:
		var peer: Dictionary = game.room.peers[id]
		if peer.get("state") == null or peer.get("avatar") == null or peer.get("car") == null:
			continue
		people[str(id)] = {"variant": int(peer.avatar.get_meta("variant", 0)), "outfit": str(peer.avatar.get_meta("outfit", "")),
			"in_car": bool(peer.state.get("in_car", false)), "ride": str(peer.state.get("ride", "")), "car": peer.car}
	for id in people:
		var person: Dictionary = people[id]
		var at_wheel = person.in_car and person.ride == ""
		seat(person.car, DRIVER, person if at_wheel else {})
		var riders: Array = game.rides.riders(id)
		var rider: Dictionary = people.get(riders[0], {}) if not riders.is_empty() else {}
		seat(person.car, RIDER, rider)

# Puts `who` ({"variant", "outfit"}, or {} for an empty seat) in seat `slot`
# (DRIVER or RIDER) of `car`; rebuilt only when the person changes.
static func seat(car: Node3D, slot: String, who: Dictionary) -> void:
	if car == null or not is_instance_valid(car) or not car.has_meta(CarInterior.SEAT_META):
		return
	var key = "" if who.is_empty() else "%d:%s" % [int(who.variant), str(who.outfit)]
	var node: Node3D = car.get_node_or_null(slot)
	if node != null and str(node.get_meta("who", "")) == key:
		return
	if node != null:
		car.remove_child(node)
		node.free()
	if key == "":
		return
	var c: Dictionary = car.get_meta(CarInterior.SEAT_META)
	var holder = Node3D.new()
	holder.name = slot
	holder.set_meta("who", key)
	holder.set_meta("unbatched", true)
	holder.set_meta("perch_ignore", true)
	car.add_child(holder)
	var wheel: Vector3 = c.wheel
	var avatar = P.player_avatar(int(who.variant), str(who.outfit))
	avatar.name = "Seated_" + slot
	if slot == DRIVER:
		CarOccupants.place(holder, c, wheel.x, avatar, wheel)
	else:
		CarOccupants.place(holder, c, -wheel.x, avatar, null)
	var baked = MeshMerge.bake(holder, "seated:%s:%s:%s" % [car.get_meta("variant", car.name), slot, key])
	if baked != null:
		baked.visibility_range_end = VISIBLE_RANGE
		baked.set_meta("perch_ignore", true)

# The person in a seat ("" when it is empty), for tests and tools.
static func occupant(car: Node3D, slot: String) -> String:
	var node = car.get_node_or_null(slot) if car != null else null
	return str(node.get_meta("who", "")) if node != null else ""
