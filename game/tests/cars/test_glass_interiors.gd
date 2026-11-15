extends "res://tests/harness.gd"
# See-through glass with a cabin behind it (car_interior.gd), furnished village
# rooms behind street windows (village_rooms.gd), rooms drawn behind every
# other building window (window_rooms.gd), players at the wheel
# (car_drivers.gd) and night-only glow meshes.
const Props = preload("res://scripts/core/props.gd")
const Glass = preload("res://scripts/core/glass.gd")
const CarInterior = preload("res://scripts/cars/car_interior.gd")
const Rooms = preload("res://scripts/stages/village/village_rooms.gd")
const WindowRooms = preload("res://scripts/core/window_rooms.gd")
const Carpentry = preload("res://scripts/stages/sever/sever_carpentry.gd")
const NightLights = preload("res://scripts/core/night_lights.gd")
const RallyCarModel = preload("res://scripts/cars/rally_car_model.gd")
const CarOccupants = preload("res://scripts/cars/car_occupants.gd")
const CarDrivers = preload("res://scripts/cars/car_drivers.gd")

func _initialize() -> void:
	call_deferred("run")

static func glass_meshes(node: Node) -> int:
	var count = 0
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		if mesh.material_override == Glass.material():
			count += 1
	return count

func run() -> void:
	check(Glass.material().transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and Glass.material().albedo_color.a < 0.5, "window glass is see-through")
	# Generic bodies, the compact sedan and the sport sedan have glass and a cabin.
	for variant in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]:
		var raw = Props.player_car(variant, false)
		check(raw.find_child("SteeringWheel", true, false) != null, "car %d has a steering wheel behind the glass" % variant)
		var dials = raw.find_children("*", "MeshInstance3D", true, false).filter(func(m): return m.get_meta("lamp", "") == "dash").size()
		check(dials > 0, "car %d has dials that glow at night" % variant)
		raw.free()
		var car = Props.player_car(variant)
		root.add_child(car)
		check(glass_meshes(car) > 0, "car %d has see-through glass" % variant)
		var glow = car.get_node_or_null("LampGlow")
		check(glow != null and glow.find_child("LampGlowMesh", true, false) != null, "car %d still has its night lamps" % variant)
		car.free()
	# The helicopter's cockpit bubble is glass with two seats and a panel.
	var heli = Props.player_car(11)
	root.add_child(heli)
	check(glass_meshes(heli) > 0 and heli.has_meta(CarInterior.SEAT_META), "the helicopter cockpit is see-through with seats behind it")
	heli.free()
	# Players at the wheel: the driver's own character sits in the cabin.
	for variant in [0, 2, 8, 11]:
		var own = Props.player_car(variant)
		root.add_child(own)
		CarDrivers.seat(own, CarDrivers.DRIVER, {"variant": 3, "outfit": ""})
		var driver: Node3D = own.get_node_or_null(CarDrivers.DRIVER)
		check(driver != null and CarDrivers.occupant(own, CarDrivers.DRIVER) == "3:" and driver.find_children("*", "MeshInstance3D", true, false).size() == 1, "car %d shows its driver at the wheel as one mesh" % variant)
		var seats: Dictionary = own.get_meta(CarInterior.SEAT_META)
		var mesh: MeshInstance3D = driver.find_children("*", "MeshInstance3D", true, false)[0]
		var box: AABB = mesh.transform * mesh.get_aabb()
		check(box.end.y <= float(seats.floor) + float(seats.avail) + 0.01, "car %d driver's head stays under the roof" % variant)
		CarDrivers.seat(own, CarDrivers.RIDER, {"variant": 5, "outfit": ""})
		check(CarDrivers.occupant(own, CarDrivers.RIDER) == "5:", "car %d carries a friend in the front seat" % variant)
		CarDrivers.seat(own, CarDrivers.DRIVER, {})
		check(own.get_node_or_null(CarDrivers.DRIVER) == null, "car %d driver's seat empties when they get out" % variant)
		own.free()
	var rally = Props.rally_car(0)
	root.add_child(rally)
	check(glass_meshes(rally) > 0, "rally cars have see-through glass")
	check(rally.find_children("*", "MeshInstance3D", true, false).size() > 0 and rally.get_node_or_null(CarOccupants.PASSENGER) == null, "a rally crew rides in the body mesh")
	rally.free()
	var raw_rally = RallyCarModel.build(0)
	check(raw_rally.find_children("*", "MeshInstance3D", true, false).filter(func(m): return m.mesh is ArrayMesh or m.mesh is BoxMesh).size() > 200, "the rally car carries a pilot and a navigator")
	raw_rally.free()
	var ambulance = Props.course_car("ambulance")
	root.add_child(ambulance)
	var passenger = ambulance.get_node_or_null(CarOccupants.PASSENGER)
	check(passenger != null and passenger.visible and passenger.find_children("*", "MeshInstance3D", true, false).filter(func(m): return m.mesh != null).size() == 1, "the ambulance doctor sits beside the driver as one mesh")
	CarOccupants.passenger_aboard(ambulance, false)
	check(not passenger.visible, "the doctor who gets out leaves an empty seat")
	CarOccupants.passenger_aboard(ambulance, true)
	check(passenger.visible, "the doctor is back in the seat")
	ambulance.free()
	# A furnished house: hollow ground floor, glass only in its street windows.
	var house = Node3D.new()
	root.add_child(house)
	check(Rooms.furnished(0, {}) and not Rooms.furnished(1, {}) and not Rooms.furnished(0, {"text": "CAFE"}), "every third street house without a shop is furnished")
	Rooms.mass(house, 7.0, 9.0, 6.5, -0.3, 3.0, Color.WHITE, 0, {})
	check(house.get_meta("room", false) and house.get_child_count() > 40, "the furnished house gets walls and furniture")
	check(house.find_child("RoomLamp", true, false) != null and house.find_child("RoomLamp", true, false).get_meta("night_light", "") == "lamp", "the room lamp lights the room at night")
	for spec in [[Vector3(-1.75, 1.45, 0), 0.0, true], [Vector3(-1.75, 4.3, 0), 0.0, false], [Vector3(-1.75, 1.4, 9.0), PI, false]]:
		var w = Node3D.new()
		house.add_child(w)
		w.position = spec[0]
		w.rotation.y = spec[1]
		Rooms.pane(w, house, spec[0])
		check((glass_meshes(w) == 1) == spec[2], "window at %s is %s" % [spec[0], "glass" if spec[2] else "a window room"])
		check(spec[2] or w.get_children().any(func(n): return WindowRooms.is_pane(n)), "window at %s shows a room behind it" % spec[0])
	var plain = Node3D.new()
	root.add_child(plain)
	Rooms.mass(plain, 7.0, 9.0, 6.5, -0.3, 3.0, Color.WHITE, 1, {})
	check(not plain.get_meta("room", false) and plain.get_child_count() == 1, "other houses stay one solid block")
	# Window rooms: one quad per pane, folded into one mesh per building.
	var building = Node3D.new()
	root.add_child(building)
	for i in range(3):
		var holder = Node3D.new()
		building.add_child(holder)
		holder.position = Vector3(i * 2.3, 4.3, 0)
		WindowRooms.pane(holder, Vector3.ZERO, Vector2(0.82, 1.38), Vector3.FORWARD, "home")
	Rooms.shop_glass(building, 6.0, {"text": "TABAC · PRESSE"})
	check(building.find_children("*", "MeshInstance3D", true, false).filter(func(n): return WindowRooms.is_pane(n)).size() == 5, "the shop window and its door show the shop inside")
	var merged = WindowRooms.merge(building)
	check(merged != null and merged.mesh.get_surface_count() == 1 and merged.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 20, "a building's window rooms merge into one mesh")
	check(merged.material_override == WindowRooms.material() and building.find_children("*", "MeshInstance3D", true, false).size() == 2, "the merged rooms keep the room shader and replace the panes")
	var uv2: PackedVector2Array = merged.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2]
	check(int(uv2[0].x) == WindowRooms.KINDS.home and int(uv2[16].x) == WindowRooms.KINDS.shop, "each pane keeps its kind of room")
	building.free()
	var izba = Node3D.new()
	root.add_child(izba)
	Carpentry.window(izba, Vector3(0, 3.0, 2.0), Vector2(0.78, 1.0), Color.WHITE, Color.RED, true)
	var izba_room = izba.get_children().filter(func(n): return WindowRooms.is_pane(n))
	check(izba_room.size() == 1 and int(izba_room[0].mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2][0].x) == WindowRooms.KINDS.izba, "an izba window looks into the izba")
	check(is_equal_approx(izba_room[0].mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR][0].a, 1.0), "a lit izba window keeps its lamp on")
	izba.free()
	# Glow meshes show only at night.
	var lights = NightLights.new()
	var shade: MeshInstance3D = house.find_child("LampGlow", true, false)
	check(shade != null and not shade.visible, "the lamp glow is off by day")
	lights.update(self, true, Vector3.ZERO, 0.1)
	check(shade.visible, "the lamp glows at night")
	lights.update(self, false, Vector3.ZERO, 0.1)
	check(not shade.visible, "the lamp goes dark again by day")
	lights.clear()
	house.free()
	plain.free()
	finish()
