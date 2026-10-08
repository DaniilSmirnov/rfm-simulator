extends "res://scripts/city.gd"
# Reuse swept solid collisions, destructible lamps and spatial mesh batches.
const VILLAGE_START = 300.0
const VILLAGE_END = 570.0
var vine_count = 0
var village_houses = 0
var village_cobblestones = 0
var sidewalk_segments = 0
var roadside_grass_count = 0
var roadside_stone_count = 0
var roadside_bush_count = 0
var thuja_count = 0
var mixed_tree_count = 0
var forest_grass_count = 0
var forest_stone_count = 0
var forest_boulder_count = 0
var forest_bush_count = 0
var forest_berry_bush_count = 0
var forest_mushroom_count = 0
var village_grass_count = 0
var village_stone_count = 0
var village_detail_positions: Array[Vector3] = []
var church_square_cobblestones = 0
var side_lane_house_count = 0
var cemetery_grave_count = 0
var village_sign_count = 0
var church_square_center = Vector3.ZERO
var cemetery_center = Vector3.ZERO
var paved_areas: Array[Dictionary] = []
var tree_positions: Array[Vector3] = []
var village_prop_count = 0
var sidewalk_poses: Array[Transform3D] = []

func build(cooperative: bool = false) -> void:
	var floor_body = StaticBody3D.new()
	floor_body.name = "VillagePhysicsGround"
	stage.add_child(floor_body)
	floor_body.position = Vector3(0, 1.75, -435)
	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(230, 0.5, 290)
	shape.shape = box
	floor_body.add_child(shape)
	if cooperative:
		await _village_street(true)
	else:
		_village_street()
	for s in range(316, 562, 18):
		if cooperative:
			await get_tree().process_frame
		for side_value in [-1.0, 1.0]:
			var p = stage.village_main_at(s) + stage.village_main_side(s) * side_value * 14.0
			var reserved = absf(s - 370) < 11 or absf(s - 500) < 11
			for parking in stage.clearings:
				reserved = reserved or stage.flat(p).distance_to(stage.flat(parking)) < 13
			if not reserved:
				_house(p, atan2(stage.village_main_side(s).x * side_value, stage.village_main_side(s).z * side_value), int(s / 18) + int(side_value))
	_side_lane_houses()
	_church(stage.village_main_at(435.0) + stage.village_main_side(435.0) * 43.0)
	_cemetery()
	_village_sign(VILLAGE_START - 10.0, -1.0)
	_village_sign(VILLAGE_END + 10.0, 1.0)
	for s in range(318, 565, 28):
		for side_value in [-1.0, 1.0]:
			_lamp(stage.village_main_at(s) + stage.village_main_side(s) * side_value * 6.2, -side_value)
	_village_props()
	if cooperative:
		await _vineyards(true)
	else:
		_vineyards()
	if cooperative:
		await _roadside_details(true)
	else:
		_roadside_details()
	if cooperative:
		await _thuja_forest(true)
	else:
		_thuja_forest()
	if cooperative:
		await _mixed_forest(true)
	else:
		_mixed_forest()
	if cooperative:
		await _village_natural_details(true)
	else:
		_village_natural_details()
	_forest_mushrooms()
	_landscape()
	_flush_batches()

func _village_street(cooperative: bool = false) -> void:
	var street = Node3D.new()
	street.name = "VillageCobblestoneStreet"
	stage.add_child(street)
	for s in range(300, 570):
		if cooperative and int(s) % 20 == 0:
			await get_tree().process_frame
		var p = stage.village_main_at(s)
		var right = stage.village_main_side(s)
		var yaw = atan2(-stage.village_main_direction(s).x, -stage.village_main_direction(s).z)
		for column in range(-5, 5):
			var stone = Props.box(street, p + right * (column * 0.72 + (0.18 if s % 2 else 0.0)) + Vector3(0, 0.065, 0), Vector3(0.68, 0.045, 0.95), Color("a5a095").lightened(((s * 13 + column * 7) % 9) * 0.015 - 0.07))
			stone.rotation.y = yaw
			village_cobblestones += 1
	for s in range(300, 571):
		if cooperative and int(s) % 20 == 0:
			await get_tree().process_frame
		if absf(s - 370.0) <= 2.5 or absf(s - 500.0) <= 2.5:
			continue # Side-street junctions must stay open, without a raised kerb.
		var p = stage.village_main_at(s)
		var yaw = atan2(-stage.village_main_direction(s).x, -stage.village_main_direction(s).z)
		for side_value in [-1.0, 1.0]:
			var sidewalk = Props.box(street, p + stage.village_main_side(s) * side_value * 5.1 + Vector3(0, 0.18, 0), Vector3(2.7, 0.36, 1.55), Color("c8c1ae"))
			sidewalk.rotation.y = yaw
			sidewalk_poses.append(sidewalk.transform)
			sidewalk_segments += 1
			var curb = Props.box(street, p + stage.village_main_side(s) * side_value * 3.83 + Vector3(0, 0.16, 0), Vector3(0.17, 0.32, 1.55), Color("ded8c6"))
			curb.rotation.y = yaw
			var seam = Props.box(street, p + stage.village_main_side(s) * side_value * 5.1 + Vector3(0, 0.365, 0), Vector3(2.45, 0.012, 0.025), Color("8f8e81"))
			seam.rotation.y = yaw
			if s % 24 == 0:
				var drain = Props.box(street, p + stage.village_main_side(s) * side_value * 3.6 + Vector3(0, 0.10, 0), Vector3(0.35, 0.04, 0.65), Color("434941"))
				drain.rotation.y = yaw
	_batch(street, Transform3D.IDENTITY)
	# Short village side lanes really connect to the main road.
	for s in [370.0, 500.0]:
		var lane = Node3D.new()
		lane.name = "VillageSideLane_%d" % int(s)
		stage.add_child(lane)
		lane.position = stage.village_main_at(s)
		lane.rotation.y = atan2(-stage.village_main_direction(s).x, -stage.village_main_direction(s).z)
		paved_areas.append({"pose": lane.transform, "half": Vector2(47.0, 2.5)})
		for x in range(-46, 47):
			for z in range(-2, 3):
				Props.box(lane, Vector3(x, 0.06, z * 0.8), Vector3(0.95, 0.035, 0.76), Color("a49d8e"))
		_batch(lane, lane.transform)

func _side_lane_houses() -> void:
	for lane_s in [370.0, 500.0]:
		var lane_direction = stage.village_main_side(lane_s).normalized()
		var lane_normal = stage.village_main_direction(lane_s).normalized()
		# Keep the junction open and place homes deeper along each secondary street.
		# A small collision padding protects existing yards without incorrectly
		# rejecting neighbouring houses whose gardens merely approach each other.
		for along in [-40.0, -28.0, 28.0, 40.0]:
			for side_value in [-1.0, 1.0]:
				var p = stage.village_main_at(lane_s) + lane_direction * along + lane_normal * side_value * 12.5
				p.y = stage.ground(p)
				var blocked = false
				for spot in stage.clearings:
					blocked = blocked or stage.flat(p).distance_to(stage.flat(spot)) < 9.0
				if blocked or not _point_clear_of_obstacles(p, 1.75):
					continue
				var facing = -lane_normal * side_value
				var yaw = atan2(-facing.x, -facing.z)
				_house(p, yaw, 100 + int(lane_s) + int(along) + int(side_value))
				side_lane_house_count += 1

func _roof(parent: Node3D, width: float, depth: float, y: float, height: float, color: Color) -> void:
	if not meshes.has("village_roof"):
		meshes.village_roof = _roof_mesh(0)
	var roof = MeshInstance3D.new()
	roof.mesh = meshes.village_roof
	roof.set_meta("batch_key", "village_roof")
	roof.material_override = Props.material(color)
	parent.add_child(roof)
	roof.position.y = y
	roof.scale = Vector3(width, height, depth)
	# Ridges and tile courses make the roofs readable from the stage.
	for i in range(1, 7):
		for face in [-1.0, 1.0]:
			var tile = Props.box(parent, Vector3(0, y + height * (1.0 - i / 7.0) + 0.02, face * depth * i / 14.0), Vector3(width, 0.045, 0.055), color.darkened(0.12))
			tile.rotation.x = face * atan2(height * 2, depth)
	Props.box(parent, Vector3(0, y + height, 0), Vector3(width, 0.12, 0.14), color.lightened(0.1))

func _window(parent: Node3D, p: Vector3, yaw: float, shutters: Color, flower: bool) -> void:
	var window = Node3D.new()
	parent.add_child(window)
	window.position = p
	window.rotation.y = yaw
	Props.box(window, Vector3(0, 0, -0.025), Vector3(0.95, 1.35, 0.07), Color("4d6870"))
	for x in [-0.54, 0.54]:
		Props.box(window, Vector3(x, 0, -0.06), Vector3(0.12, 1.6, 0.14), Color("e4d9bd"))
		Props.box(window, Vector3(x * 1.65, 0, 0), Vector3(0.43, 1.4, 0.10), shutters)
		for y in [-0.48, -0.24, 0.0, 0.24, 0.48]:
			Props.box(window, Vector3(x * 1.65, y, -0.075), Vector3(0.39, 0.04, 0.05), shutters.darkened(0.25))
	for y in [-0.75, 0.75]:
		Props.box(window, Vector3(0, y, -0.06), Vector3(1.17, 0.12, 0.16), Color("e4d9bd"))
	Props.box(window, Vector3(0, 0, -0.08), Vector3(0.055, 1.4, 0.05), Color("e7dfca"))
	Props.box(window, Vector3(0, 0, -0.08), Vector3(0.95, 0.045, 0.05), Color("e7dfca"))
	if flower:
		Props.box(window, Vector3(0, -0.86, -0.22), Vector3(1.15, 0.18, 0.35), Color("815642"))
		for x in [-0.4, -0.2, 0.0, 0.2, 0.4]:
			Props.cylinder(window, Vector3(x, -0.65, -0.23), 0.09, 0.13, 0.23, Color("60733e"), 6)
			Props.box(window, Vector3(x, -0.5, -0.23), Vector3(0.12, 0.10, 0.10), Color("ba5363"))

func _house(p: Vector3, yaw: float, seed_value: int) -> void:
	var house = Node3D.new()
	house.name = "VillageHouse_%d" % village_houses
	village_houses += 1
	stage.add_child(house)
	house.position = p
	house.rotation.y = yaw
	var style = posmod(seed_value, 5)
	var height = 5.2 + style * 0.55
	var wall = [Color("e4caa3"), Color("dbc6b2"), Color("d8aa8d"), Color("bec7aa"), Color("eedbc1")][style]
	var shutters = [Color("526b58"), Color("6c7d87"), Color("7c4c3d")][style % 3]
	Props.box(house, Vector3(0, height / 2, 0), Vector3(8, height, 8), wall)
	Props.box(house, Vector3(0, 0.32, 0), Vector3(8.2, 0.64, 8.2), Color("9f9b89"))
	for floor in range(2):
		for x in [-2.5, 0.0, 2.5]:
			if floor == 0 and x == 0:
				continue
			_window(house, Vector3(x, 1.65 + floor * 2.6, -4.04), 0, shutters, floor == 1)
		for side_value in [-1.0, 1.0]:
			_window(house, Vector3(side_value * 4.04, 1.65 + floor * 2.6, 0), -side_value * PI / 2, shutters, false)
	Props.box(house, Vector3(0, 1.16, -4.05), Vector3(1.3, 2.3, 0.12), Color("6a4938"))
	for x in [-0.74, 0.74]:
		Props.box(house, Vector3(x, 1.23, -4.12), Vector3(0.14, 2.5, 0.25), Color("ddd2b5"))
	Props.box(house, Vector3(0, 2.5, -4.12), Vector3(1.62, 0.18, 0.25), Color("ddd2b5"))
	Props.box(house, Vector3(0.42, 1.13, -4.15), Vector3(0.06, 0.07, 0.05), Color("dfc987"))
	for step in range(3):
		Props.box(house, Vector3(0, 0.04 + step * 0.055, -4.8 + step * 0.22), Vector3(1.65, 0.08 + step * 0.11, 0.65), Color("b4ae98"))
	_roof(house, 8.8, 8.8, height, 3.5, Color("9d513b") if style % 2 else Color("785c50"))
	Props.box(house, Vector3(2, height + 2.7, 1.6), Vector3(0.7, 2.5, 0.7), Color("ac8c73"))
	Props.box(house, Vector3(2, height + 4, 1.6), Vector3(0.95, 0.20, 0.95), Color("756c5b"))
	for x in [-4.25, 4.25]:
		Props.cylinder(house, Vector3(x, height / 2, -4.1), 0.055, 0.055, height, Color("6a7268"), 8)
	Props.box(house, Vector3(0, 0.02, -6.5), Vector3(2, 0.04, 4.8), Color("bbb39c"))
	# Walled courtyard, open front gate, rear garden and a small shed.
	Props.box(house, Vector3(0, 0.01, 7), Vector3(12, 0.02, 7), Color("849366"))
	for side_value in [-1.0, 1.0]:
		Props.box(house, Vector3(side_value * 6, 0.6, 3.5), Vector3(0.3, 1.2, 14), Color("a6a18e"))
		_solid(house, Vector3(side_value * 6, 0.6, 3.5), Vector3(0.3, 1.2, 14), "wall")
	Props.box(house, Vector3(0, 0.6, 10.5), Vector3(12, 1.2, 0.3), Color("a6a18e"))
	_solid(house, Vector3(0, 0.6, 10.5), Vector3(12, 1.2, 0.3), "wall")
	for x in [-4.2, 4.2]:
		Props.box(house, Vector3(x, 0.6, -3.5), Vector3(3.4, 1.2, 0.3), Color("a6a18e"))
		_solid(house, Vector3(x, 0.6, -3.5), Vector3(3.4, 1.2, 0.3), "wall")
	for z in [6.0, 7.5, 9.0]:
		Props.box(house, Vector3(-2, 0.12, z), Vector3(5, 0.2, 0.6), Color("655941"))
		for x in [-4.0, -3.0, -2.0, -1.0, 0.0]:
			Props.cylinder(house, Vector3(x, 0.35, z), 0.16, 0.03, 0.5, Color("688847"), 7)
	_solid(house, Vector3(0, height / 2, 0), Vector3(8, height, 8), "building")
	_batch(house, house.transform)

func _church(p: Vector3) -> void:
	var church = Node3D.new()
	church.name = "VillageChurch"
	stage.add_child(church)
	church.position = p
	church.rotation.y = PI / 2
	Props.box(church, Vector3(0, 4.5, 0), Vector3(10, 9, 21), Color("dbcfb5"))
	_roof(church, 11, 22, 9, 6, Color("875441"))
	for side_value in [-1.0, 1.0]:
		for z in [-7.0, -2.0, 3.0, 8.0]:
			Props.box(church, Vector3(side_value * 5.3, 3.2, z), Vector3(0.9, 6.4, 1), Color("c3b9a1"))
			_window(church, Vector3(side_value * 5.05, 5.8, z), -side_value * PI / 2, Color("aeb3a2"), false)
	Props.box(church, Vector3(0, 8, -11), Vector3(6, 16, 6), Color("c7b99b"))
	for y in [0.4, 5.2, 10.8, 15.6]:
		Props.box(church, Vector3(0, y, -11), Vector3(6.5, 0.3, 6.5), Color("e5dcc4"))
	for x in [-2.9, 2.9]:
		Props.box(church, Vector3(x, 8, -14.1), Vector3(0.4, 16, 0.4), Color("e3d8b9"))
	Props.box(church, Vector3(0, 1.8, -14.08), Vector3(2.6, 3.6, 0.18), Color("624936"))
	for side_value in [-1.0, 1.0]:
		Props.box(church, Vector3(side_value * 1.5, 2, -14.2), Vector3(0.35, 4, 0.4), Color("eee0bd"))
	for angle in range(0, 181, 15):
		var a = deg_to_rad(angle)
		var stone = Props.box(church, Vector3(cos(a) * 1.45, 3.8 + sin(a) * 1.45, -14.2), Vector3(0.40, 0.36, 0.38), Color("eee0bd"))
		stone.rotation.z = a
	for side_value in [-1.0, 1.0]:
		_window(church, Vector3(side_value * 3.05, 12.9, -11), -side_value * PI / 2, Color("6b7367"), false)
	var clock = Props.cylinder(church, Vector3(0, 9.1, -14.2), 1, 1, 0.09, Color("f0e7ce"), 32)
	clock.rotation.x = PI / 2
	Props.box(church, Vector3(0, 9.4, -14.27), Vector3(0.08, 0.6, 0.05), Color("384439"))
	var hand = Props.box(church, Vector3(0.28, 9.1, -14.28), Vector3(0.65, 0.08, 0.05), Color("384439"))
	hand.rotation.z = -0.3
	Props.cylinder(church, Vector3(0, 20, -11), 4.3, 0, 8.6, Color("665f5c"), 8)
	Props.box(church, Vector3(0, 25.1, -11), Vector3(0.17, 2, 0.17), Color("c4ab6e"))
	Props.box(church, Vector3(0, 25.5, -11), Vector3(1.1, 0.17, 0.17), Color("c4ab6e"))
	var square = Node3D.new()
	square.name = "VillageChurchSquare"
	church.add_child(square)
	square.position = Vector3(0, 0.045, -18)
	church_square_center = church.transform * square.position
	paved_areas.append({"pose": church.transform * square.transform, "half": Vector2(8.5, 5.5)})
	for x in range(-8, 9):
		for z in range(-5, 6):
			var offset = Vector3(x * 0.92 + (0.28 if z % 2 else 0.0), 0, z * 0.92)
			var stone = Props.box(square, offset, Vector3(0.88, 0.06, 0.88), Color("a7a194").lightened(float(posmod(x * 5 + z * 7, 9)) * 0.012 - 0.05))
			stone.rotation.y = (PI / 2.0) if (x + z) % 7 == 0 else 0.0
			church_square_cobblestones += 1
	_solid(church, Vector3(0, 4.5, 0), Vector3(10, 9, 21), "building")
	_solid(church, Vector3(0, 8, -11), Vector3(6, 16, 6), "building")
	_batch(church, church.transform)

func _cemetery() -> void:
	var root = Node3D.new()
	root.name = "VillageCemetery"
	stage.add_child(root)
	var s = 435.0
	cemetery_center = stage.village_main_at(s) + stage.village_main_side(s) * 87.0
	cemetery_center.y = stage.ground(cemetery_center)
	root.position = cemetery_center
	root.rotation.y = 0.0
	Props.box(root, Vector3(0, 0.015, 0), Vector3(32, 0.03, 24), Color("64794d"))
	# Open lawn with regular rows, inspired by small North American rural cemeteries.
	for row in range(4):
		for column in range(7):
			var x = -12.0 + column * 4.0
			var z = -8.0 + row * 5.2
			var grave = Node3D.new()
			grave.name = "CemeteryGrave_%02d" % cemetery_grave_count
			root.add_child(grave)
			grave.position = Vector3(x, 0.03, z)
			Props.box(grave, Vector3(0, 0.015, 1.0), Vector3(1.4, 0.03, 2.6), Color("71815a").lightened(float((row + column) % 4) * 0.025))
			if (row + column) % 3 == 0:
				Props.box(grave, Vector3(0, 0.58, -0.62), Vector3(1.05, 1.15, 0.16), Color("9d9a8e"))
			else:
				Props.box(grave, Vector3(0, 0.78, -0.62), Vector3(0.18, 1.55, 0.18), Color("a7a397"))
				Props.box(grave, Vector3(0, 1.03, -0.62), Vector3(0.92, 0.18, 0.18), Color("a7a397"))
			cemetery_grave_count += 1
	# A simple gravel walk keeps the lawn readable without fencing it off.
	Props.box(root, Vector3(0, 0.025, 10.2), Vector3(28, 0.05, 1.5), Color("aaa38f"))
	_batch(root, root.transform)

func _village_sign(s: float, side_value: float) -> void:
	var root = Node3D.new()
	root.name = "VillageNameSign_%d" % village_sign_count
	stage.add_child(root)
	var p = stage.village_main_at(s) + stage.village_main_side(s) * side_value * 7.2
	p.y = stage.ground(p)
	root.position = p
	root.rotation.y = atan2(-stage.village_main_direction(s).x, -stage.village_main_direction(s).z)
	for x in [-1.45, 1.45]:
		Props.cylinder(root, Vector3(x, 1.2, 0), 0.065, 0.065, 2.4, Color("62665f"), 7)
	Props.box(root, Vector3(0, 2.15, 0), Vector3(4.2, 1.25, 0.12), Color("eee9d6"))
	for face in [-1.0, 1.0]:
		var label = Label3D.new()
		root.add_child(label)
		label.position = Vector3(0, 2.15, face * 0.075)
		label.rotation.y = PI if face < 0 else 0.0
		label.double_sided = false
		label.text = "Ля Газ в Польен"
		label.font_size = 44
		label.pixel_size = 0.005
		label.modulate = Color("30342f")
		label.outline_size = 0
	_solid(root, Vector3(0, 2.15, 0), Vector3(4.2, 1.25, 0.12), "sign")
	_batch(root, root.transform)
	village_sign_count += 1

func _vineyards(cooperative: bool = false) -> void:
	var leaves: Array = []
	var leaf_colors: Array = []
	var fruit: Array = []
	var fruit_colors: Array = []
	var sphere = SphereMesh.new()
	sphere.radial_segments = 8
	sphere.rings = 3
	for start in [18, 585]:
		for side_value in [-1.0, 1.0]:
			for row in range(18):
				if cooperative:
					await get_tree().process_frame
				var root = Node3D.new()
				root.name = "VineyardRow_%d_%d_%d" % [start, int(side_value), row]
				stage.add_child(root)
				var row_end = 286 if start == 18 else 825
				for s in range(start, row_end, 6):
					if cooperative and int(s) % 20 == 0:
						await get_tree().process_frame
					var p = stage.village_main_at(s) + stage.village_main_side(s) * side_value * (13.0 + row * 4)
					var blocked = false
					for parking in stage.clearings:
						blocked = blocked or stage.flat(p).distance_to(stage.flat(parking)) < 10
					if blocked:
						continue
					p.y = stage.ground(p)
					vine_count += 1
					var soil = Props.box(root, p + Vector3(0, 0.015, 0), Vector3(1.4, 0.03, 6.2), Color("7e7054"))
					soil.rotation.y = atan2(-stage.village_main_direction(s).x, -stage.village_main_direction(s).z)
					Props.cylinder(root, p + Vector3(0, 0.70, 0), 0.08, 0.04, 1.4, Color("735943"), 6)
					Props.cylinder(root, p + Vector3(0, 1, 0), 0.04, 0.025, 2.0, Color("8b8063"), 6)
					var yaw = atan2(-stage.village_main_direction(s).x, -stage.village_main_direction(s).z)
					for y in [0.85, 1.35, 1.80]:
						var wire = Props.box(root, p + Vector3(0, y, 0), Vector3(0.018, 0.018, 6.2), Color("7b7d68"))
						wire.rotation.y = yaw
					for offset in [-1.7, -0.65, 0.65, 1.7]:
						var position = p + stage.village_main_direction(s) * offset + Vector3(0, 1.2 + sin(s + offset) * 0.15, 0)
						leaves.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(0.85, 0.60, 1.05)), position))
						leaf_colors.append(Color("526e37").lightened(float((s + row) % 5) * 0.025))
					var indices: Array = []
					for cluster in [-1.0, 1.0]:
						for berry in range(12):
							var tier = berry / 4
							var angle = berry * 2.4
							var radius = 0.12 - tier * 0.025
							var position = p + stage.village_main_direction(s) * cluster * 1.0 + stage.village_main_side(s) * 0.43 + Vector3(cos(angle) * radius, 1.08 - tier * 0.105, sin(angle) * radius)
							indices.append(fruit.size())
							fruit.append(Transform3D(Basis.from_scale(Vector3.ONE * 0.12), position))
							fruit_colors.append(Color("6b4769") if row % 3 else Color("a3b657"))
					stage.collectibles.append({"kind": "berries", "name": "виноград", "pos": p, "quantity": 3, "parts": {"VineyardGrapes": indices}})
				_batch(root, Transform3D.IDENTITY)
	stage._detail_batch("VineyardLeaves", sphere, leaves, leaf_colors)
	stage._detail_batch("VineyardGrapes", sphere, fruit, fruit_colors)

func _roadside_station_allowed(s: float, buffer: float = 8.0) -> bool:
	return s < VILLAGE_START - buffer or s > VILLAGE_END + buffer

func _roadside_details(cooperative: bool = false) -> void:
	# Fill the previously empty verge between the road edge and the first vine
	# rows. Keep the village and spectator parking pockets clean and readable.
	var detail_rng = RandomNumberGenerator.new()
	detail_rng.seed = 71020263
	var grass_poses: Array = []
	var grass_colors: Array = []
	var stone_poses: Array = []
	var stone_colors: Array = []
	var bush_poses: Array = []
	var bush_colors: Array = []
	for s in range(14, 828, 2):
		if cooperative and int(s) % 20 == 0:
			await get_tree().process_frame
		if not _roadside_station_allowed(float(s), 8.0):
			continue
		for side_value in [-1.0, 1.0]:
			for tuft in range(3):
				var lateral = detail_rng.randf_range(5.0, 11.6)
				var p = stage.at(s) + stage.side(s) * side_value * lateral + stage.direction(s) * detail_rng.randf_range(-1.2, 1.2)
				var blocked = false
				for parking in stage.clearings:
					blocked = blocked or stage.flat(p).distance_to(stage.flat(parking)) < 8.0
				if blocked:
					continue
				p.y = stage.ground(p) - 0.08
				var size = detail_rng.randf_range(0.28, 0.62)
				grass_poses.append(Transform3D(Basis(Vector3.UP, detail_rng.randf() * TAU).scaled(Vector3(size * 1.8, size, size * 1.8)), p))
				grass_colors.append(stage.shared_grass_color(detail_rng.randf()))
				roadside_grass_count += 1
	for s in range(22, 820, 7):
		if cooperative and int(s) % 20 == 0:
			await get_tree().process_frame
		if not _roadside_station_allowed(float(s), 10.0):
			continue
		var side_value = -1.0 if detail_rng.randi() % 2 == 0 else 1.0
		var p = stage.at(s) + stage.side(s) * side_value * detail_rng.randf_range(5.4, 11.2)
		var blocked = false
		for parking in stage.clearings:
			blocked = blocked or stage.flat(p).distance_to(stage.flat(parking)) < 8.0
		if blocked:
			continue
		p.y = stage.ground(p)
		var radius = detail_rng.randf_range(0.16, 0.48)
		stone_poses.append(stage.shared_stone_pose(p + Vector3(0, radius * 0.20, 0), radius, detail_rng.randf() * TAU))
		stone_colors.append(stage.shared_stone_color(detail_rng.randf_range(-0.10, 0.12)))
		roadside_stone_count += 1
	for s in range(28, 816, 9):
		if cooperative and int(s) % 20 == 0:
			await get_tree().process_frame
		if not _roadside_station_allowed(float(s), 12.0):
			continue
		for side_value in [-1.0, 1.0]:
			if detail_rng.randf() < 0.38:
				continue
			var center = stage.at(s) + stage.side(s) * side_value * detail_rng.randf_range(7.0, 11.8)
			var blocked = false
			for parking in stage.clearings:
				blocked = blocked or stage.flat(center).distance_to(stage.flat(parking)) < 9.0
			if blocked:
				continue
			center.y = stage.ground(center)
			var size = detail_rng.randf_range(0.55, 1.15)
			for lobe in range(3):
				var angle = detail_rng.randf() * TAU
				var offset = Vector3(cos(angle), 0, sin(angle)) * size * 0.28
				var pose = Transform3D(Basis(Vector3.UP, angle).scaled(Vector3(size * 0.95, size * 0.72, size * 0.90)), center + offset + Vector3(0, size * 0.45, 0))
				bush_poses.append(pose)
				bush_colors.append(Color("405f32").lerp(Color("718044"), detail_rng.randf() * 0.6))
			roadside_bush_count += 1
	var bush_mesh = preload("res://models/nature/roadside_bush.tres")
	stage._detail_batch("VineyardRoadsideGrass", stage._grass_mesh(), grass_poses, grass_colors)
	stage._detail_batch("VineyardRoadsideStones", stage.shared_stone_mesh(), stone_poses, stone_colors)
	stage._detail_batch("VineyardRoadsideBushes", bush_mesh, bush_poses, bush_colors)

func _thuja_forest(cooperative: bool = false) -> void:
	# A dense evergreen belt frames the village without intruding on the road,
	# houses, church or the spectator spots. Three tapered layers read as thuja.
	var tree_rng = RandomNumberGenerator.new()
	tree_rng.seed = 71020264
	var lower_poses: Array = []
	var lower_colors: Array = []
	var middle_poses: Array = []
	var middle_colors: Array = []
	var crown_poses: Array = []
	var crown_colors: Array = []
	for s in range(int(VILLAGE_START) - 34, int(VILLAGE_END) + 35, 4):
		if cooperative and int(s) % 20 == 0:
			await get_tree().process_frame
		for side_value in [-1.0, 1.0]:
			for row in range(4):
				var lateral = 27.0 + row * 9.0 + tree_rng.randf_range(-2.0, 2.0)
				var p = stage.at(clampf(float(s), 0.0, stage.LENGTH - 0.01)) + stage.side(clampf(float(s), 0.0, stage.LENGTH - 0.01)) * side_value * lateral
				p += stage.direction(clampf(float(s), 0.0, stage.LENGTH - 0.01)) * tree_rng.randf_range(-2.0, 2.0)
				var blocked = false
				for spot in stage.clearings:
					blocked = blocked or stage.flat(p).distance_to(stage.flat(spot)) < 10.0
				for obstacle in obstacles:
					blocked = blocked or stage.flat(p).distance_to(stage.flat(_relative_pose(obstacle.body).origin)) < 7.0
				if blocked or paved_at(p, 2.0):
					continue
				p.y = stage.terrain_surface_height(p) - 0.03
				tree_positions.append(p)
				var height = tree_rng.randf_range(5.5, 9.5)
				var width = tree_rng.randf_range(1.15, 1.75)
				var yaw = tree_rng.randf() * TAU
				lower_poses.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(width, height * 0.48, width)), p + Vector3(0, height * 0.24, 0)))
				lower_colors.append(Color("314f35").lightened(tree_rng.randf_range(-0.04, 0.05)))
				middle_poses.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(width * 0.78, height * 0.39, width * 0.78)), p + Vector3(0, height * 0.57, 0)))
				middle_colors.append(Color("3b5c3b").lightened(tree_rng.randf_range(-0.04, 0.06)))
				crown_poses.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(width * 0.48, height * 0.28, width * 0.48)), p + Vector3(0, height * 0.82, 0)))
				crown_colors.append(Color("476a43").lightened(tree_rng.randf_range(-0.03, 0.06)))
				thuja_count += 1
	# Close the forest belt around the village ends while keeping the road mouth open.
	for station in [VILLAGE_START - 28.0, VILLAGE_END + 28.0]:
		for lateral_step in range(-6, 7):
			if abs(lateral_step) < 2:
				continue
			var lateral = lateral_step * 7.0 + tree_rng.randf_range(-1.5, 1.5)
			var s = clampf(station + tree_rng.randf_range(-4.0, 4.0), 0.0, stage.LENGTH - 0.01)
			var p = stage.at(s) + stage.side(s) * lateral
			var blocked = false
			for spot in stage.clearings:
				blocked = blocked or stage.flat(p).distance_to(stage.flat(spot)) < 10.0
			if blocked or paved_at(p, 2.0):
				continue
			p.y = stage.terrain_surface_height(p) - 0.03
			tree_positions.append(p)
			var height = tree_rng.randf_range(5.5, 9.5)
			var width = tree_rng.randf_range(1.15, 1.75)
			var yaw = tree_rng.randf() * TAU
			lower_poses.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(width, height * 0.48, width)), p + Vector3(0, height * 0.24, 0)))
			lower_colors.append(Color("314f35").lightened(tree_rng.randf_range(-0.04, 0.05)))
			middle_poses.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(width * 0.78, height * 0.39, width * 0.78)), p + Vector3(0, height * 0.57, 0)))
			middle_colors.append(Color("3b5c3b").lightened(tree_rng.randf_range(-0.04, 0.06)))
			crown_poses.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(width * 0.48, height * 0.28, width * 0.48)), p + Vector3(0, height * 0.82, 0)))
			crown_colors.append(Color("476a43").lightened(tree_rng.randf_range(-0.03, 0.06)))
			thuja_count += 1
	var lower = preload("res://models/nature/thuja_lower.tres")
	var middle = preload("res://models/nature/thuja_middle.tres")
	var crown = preload("res://models/nature/thuja_top.tres")
	stage._detail_batch("VillageThujaLower", lower, lower_poses, lower_colors)
	stage._detail_batch("VillageThujaMiddle", middle, middle_poses, middle_colors)
	stage._detail_batch("VillageThujaCrown", crown, crown_poses, crown_colors)

func _point_clear_of_obstacles(p: Vector3, padding: float = 0.0) -> bool:
	for obstacle in obstacles:
		var pose = _relative_pose(obstacle.body)
		var local = pose.affine_inverse() * p
		var half: Vector3 = obstacle.half + Vector3.ONE * padding
		if absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z:
			return false
	return true

func _forest_spot_allowed(p: Vector3, padding: float = 0.0) -> bool:
	if paved_at(p, padding):
		return false
	if cemetery_center != Vector3.ZERO and stage.flat(p).distance_to(stage.flat(cemetery_center)) < 20.0 + padding:
		return false
	var s = stage.road_s(p)
	if s < VILLAGE_START - 55.0 or s > VILLAGE_END + 55.0:
		return false
	var distance = stage.road_distance(p)
	var minimum = 8.0 if stage.village_forest_detour(s) else (48.0 if stage.village(s) else 92.0)
	if distance < minimum + padding or distance > 145.0:
		return false
	for spot in stage.clearings:
		if stage.flat(p).distance_to(stage.flat(spot)) < 12.0 + padding:
			return false
	return _point_clear_of_obstacles(p, 4.0 + padding)

func _mixed_forest(cooperative: bool = false) -> void:
	# The village uses the exact same four-layer tree asset as the first summer
	# stage. Only density and placement differ, so both stages read as one world.
	var forest_rng = RandomNumberGenerator.new()
	forest_rng.seed = 71020265
	var tree_data: Array[Dictionary] = []
	for i in range(3600):
		if cooperative and i % 200 == 0:
			await get_tree().process_frame
		var s = forest_rng.randf_range(VILLAGE_START - 52.0, VILLAGE_END + 52.0)
		var side_value = -1.0 if forest_rng.randi() % 2 == 0 else 1.0
		var lateral = forest_rng.randf_range(48.0, 142.0)
		var p = stage.at(s) + stage.side(s) * side_value * lateral + stage.direction(s) * forest_rng.randf_range(-4.0, 4.0)
		if not _forest_spot_allowed(p, 1.6):
			continue
		p.y = stage.terrain_surface_height(p) - 0.03
		tree_positions.append(p)
		tree_data.append({
			"position": p,
			"height": forest_rng.randf_range(6.0, 17.0),
			"shade": forest_rng.randf_range(-0.025, 0.045),
		})
		mixed_tree_count += 1
		if mixed_tree_count >= 1050:
			break
	for layer in range(4):
		var poses: Array = []
		var colors: Array = []
		for tree in tree_data:
			poses.append(stage.shared_tree_pose(tree.position, float(tree.height), layer))
			colors.append(stage.shared_tree_color(layer, float(tree.shade), false))
		stage._detail_batch("VillageForestTreeLayer%d" % layer, stage.shared_tree_mesh(layer), poses, colors)

	var grass_poses: Array = []
	var grass_colors: Array = []
	for i in range(4200):
		if cooperative and i % 200 == 0:
			await get_tree().process_frame
		var s = forest_rng.randf_range(VILLAGE_START - 52.0, VILLAGE_END + 52.0)
		var side_value = -1.0 if forest_rng.randi() % 2 == 0 else 1.0
		var p = stage.at(s) + stage.side(s) * side_value * forest_rng.randf_range(48.0, 142.0)
		if not _forest_spot_allowed(p):
			continue
		p.y = stage.ground(p) - 0.12
		var size = forest_rng.randf_range(0.28, 0.70)
		grass_poses.append(Transform3D(Basis(Vector3.UP, forest_rng.randf() * TAU).scaled(Vector3(size * 1.8, size, size * 1.8)), p))
		grass_colors.append(stage.shared_grass_color(forest_rng.randf()))
		forest_grass_count += 1
		if forest_grass_count >= 1900:
			break
	stage._detail_batch("VillageForestGrass", stage._grass_mesh(), grass_poses, grass_colors)

	var stone_poses: Array = []
	var stone_colors: Array = []
	for i in range(900):
		if cooperative and i % 200 == 0:
			await get_tree().process_frame
		var s = forest_rng.randf_range(VILLAGE_START - 50.0, VILLAGE_END + 50.0)
		var side_value = -1.0 if forest_rng.randi() % 2 == 0 else 1.0
		var p = stage.at(s) + stage.side(s) * side_value * forest_rng.randf_range(50.0, 140.0)
		if not _forest_spot_allowed(p):
			continue
		p.y = stage.ground(p)
		var radius = forest_rng.randf_range(0.12, 0.38)
		stone_poses.append(stage.shared_stone_pose(p + Vector3(0, radius * 0.22, 0), radius, forest_rng.randf() * TAU))
		stone_colors.append(stage.shared_stone_color(forest_rng.randf_range(-0.10, 0.12)))
		forest_stone_count += 1
		if forest_stone_count >= 320:
			break
	stage._detail_batch("VillageForestStones", stage.shared_stone_mesh(), stone_poses, stone_colors)

	var boulder_poses: Array = []
	var boulder_colors: Array = []
	for i in range(260):
		if cooperative and i % 200 == 0:
			await get_tree().process_frame
		var s = forest_rng.randf_range(VILLAGE_START - 48.0, VILLAGE_END + 48.0)
		var side_value = -1.0 if forest_rng.randi() % 2 == 0 else 1.0
		var p = stage.at(s) + stage.side(s) * side_value * forest_rng.randf_range(55.0, 138.0)
		var radius = forest_rng.randf_range(0.75, 2.1)
		if not _forest_spot_allowed(p, radius + 0.5) or not stage.rock_hit(p, p, radius, false).is_empty():
			continue
		p.y = stage.ground(p)
		var height = forest_rng.randf_range(0.8, 2.3)
		boulder_poses.append(Transform3D(Basis(Vector3.UP, forest_rng.randf() * TAU).scaled(Vector3(radius * 2.0, height, radius * 1.65)), p + Vector3(0, height * 0.35, 0)))
		boulder_colors.append(Color("697064").lightened(forest_rng.randf_range(-0.12, 0.12)))
		stage.rocks.append({"pos": p, "radius": radius, "height": height * 0.9, "forest": true})
		forest_boulder_count += 1
		if forest_boulder_count >= 44:
			break
	var boulder = stage.NATURE_BOULDER
	stage._detail_batch("VillageForestBoulders", boulder, boulder_poses, boulder_colors)

	var bush_poses: Array = []
	var bush_colors: Array = []
	var berry_bush_poses: Array = []
	var berry_bush_colors: Array = []
	var berry_poses: Array = []
	var berry_colors: Array = []
	for i in range(900):
		if cooperative and i % 200 == 0:
			await get_tree().process_frame
		var s = forest_rng.randf_range(VILLAGE_START - 50.0, VILLAGE_END + 50.0)
		var side_value = -1.0 if forest_rng.randi() % 2 == 0 else 1.0
		var center = stage.at(s) + stage.side(s) * side_value * forest_rng.randf_range(50.0, 136.0)
		if not _forest_spot_allowed(center, 1.0) or not stage.rock_hit(center, center, 0.8, false).is_empty():
			continue
		center.y = stage.ground(center)
		var size = forest_rng.randf_range(0.55, 1.35)
		var bearing = forest_rng.randf() * TAU
		var berry_bush = forest_rng.randf() < 0.30
		var berry_begin = berry_poses.size()
		for lobe in range(3):
			var angle = bearing + lobe * TAU / 3.0
			var leaf_center = center + Vector3(cos(angle) * size * 0.28, size * (0.55 + lobe * 0.08), sin(angle) * size * 0.28)
			var pose = Transform3D(Basis(Vector3.UP, angle).scaled(Vector3(size * 0.95, size * 0.72, size * 0.88)), leaf_center)
			var color = Color("3c5830").lerp(Color("6c8040"), forest_rng.randf())
			if berry_bush:
				berry_bush_poses.append(pose)
				berry_bush_colors.append(color.darkened(0.08))
				for fruit in range(4):
					var fruit_angle = angle + fruit * TAU / 4.0
					var fruit_pos = leaf_center + Vector3(cos(fruit_angle) * size * 0.34, size * 0.18, sin(fruit_angle) * size * 0.31)
					berry_poses.append(Transform3D(Basis.from_scale(Vector3.ONE * 0.085), fruit_pos))
					berry_colors.append(Color("c34237") if i % 2 == 0 else Color("383353"))
			else:
				bush_poses.append(pose)
				bush_colors.append(color)
		if berry_bush:
			var fruit_indices: Array = []
			for fruit_index in range(berry_begin, berry_poses.size()):
				fruit_indices.append(fruit_index)
			stage.collectibles.append({"kind": "berries", "name": "лесные ягоды", "pos": center, "quantity": 3, "parts": {"VillageForestBerries": fruit_indices}})
			forest_berry_bush_count += 1
		else:
			forest_bush_count += 1
		if forest_bush_count >= 170 and forest_berry_bush_count >= 70:
			break
	var bush_mesh = stage.NATURE_BUSH
	var berry_mesh = stage.NATURE_BERRY
	stage._detail_batch("VillageForestBushes", bush_mesh, bush_poses, bush_colors)
	stage._detail_batch("VillageForestBerryBushes", bush_mesh, berry_bush_poses, berry_bush_colors)
	stage._detail_batch("VillageForestBerries", berry_mesh, berry_poses, berry_colors)


# Same edible, fly agaric and toadstool species as the original forest stage.
# Separate deterministic RNG keeps collectible IDs stable across room members.
func _forest_mushrooms() -> void:
	var mushroom_rng = RandomNumberGenerator.new()
	mushroom_rng.seed = 71020266
	var stem_poses: Array = []
	var stem_colors: Array = []
	var cap_poses: Array = []
	var cap_colors: Array = []
	var poison_caps = {"fly_agaric": [], "toadstool": []}
	for i in range(460):
		var s = mushroom_rng.randf_range(VILLAGE_START - 48.0, VILLAGE_END + 48.0)
		var side_value = -1.0 if mushroom_rng.randi() % 2 == 0 else 1.0
		var p = stage.at(s) + stage.side(s) * side_value * mushroom_rng.randf_range(12.0, 118.0)
		if not _forest_spot_allowed(p, 0.9) or not stage.rock_hit(p, p, 0.5, false).is_empty():
			continue
		for j in range(2):
			var item_pos = p + Vector3(mushroom_rng.randf_range(-0.45, 0.45), 0, mushroom_rng.randf_range(-0.45, 0.45))
			if not _forest_spot_allowed(item_pos, 0.5):
				continue
			item_pos.y = stage.ground(item_pos)
			var size = mushroom_rng.randf_range(0.10, 0.22)
			var species = "fly_agaric" if i % 10 == 4 else ("toadstool" if i % 10 == 7 else "edible")
			var layer = "VillageFlyAgaricCaps" if species == "fly_agaric" else ("VillageToadstoolCaps" if species == "toadstool" else "VillageMushroomCaps")
			var index = cap_poses.size() if species == "edible" else poison_caps[species].size()
			stage.collectibles.append({
				"kind": "mushrooms", "species": species,
				"name": "мухомор" if species == "fly_agaric" else ("поганка" if species == "toadstool" else "гриб"),
				"pos": item_pos, "quantity": 1,
				"parts": {layer: [index], "VillageMushroomStems": [stem_poses.size()]}
			})
			var origin = item_pos + Vector3(0, 0.02, 0)
			stem_poses.append(Transform3D(Basis.from_scale(Vector3(size * 0.20, size, size * 0.20)), origin + Vector3(0, size * 0.5, 0)))
			stem_colors.append(Color("c5baa1"))
			var cap = Transform3D(Basis.from_scale(Vector3(size * 1.4, size * 0.55, size * 1.4)), origin + Vector3(0, size, 0))
			if species == "edible":
				cap_poses.append(cap)
				cap_colors.append(Color("b87743"))
			else:
				poison_caps[species].append(cap)
			forest_mushroom_count += 1
	stage._detail_batch("VillageMushroomStems", stage.NATURE_MUSHROOM_STEM, stem_poses, stem_colors)
	stage._detail_batch("VillageMushroomCaps", stage.NATURE_MUSHROOM_CAP, cap_poses, cap_colors)
	for species in poison_caps:
		var colors: Array = []
		colors.resize(poison_caps[species].size())
		colors.fill(Color.WHITE)
		stage._detail_batch("VillageFlyAgaricCaps" if species == "fly_agaric" else "VillageToadstoolCaps", stage.NATURE_MUSHROOM_CAP, poison_caps[species], colors)

func village_detail_allowed(p: Vector3) -> bool:
	var s = stage.road_s(p)
	if not stage.village(s):
		return false
	if paved_at(p, 0.9):
		return false
	var distance = stage.road_distance(p)
	# Main cobblestone road, kerbs and both sidewalks.
	if distance <= 6.65:
		return false
	# The two transverse village lanes are cobbled from wall to wall.
	for lane_s in [370.0, 500.0]:
		if absf(s - lane_s) <= 3.2 and distance <= 48.5:
			return false
	# Keep the church building and its cobbled square clean.
	var church_center = stage.village_main_at(435.0) + stage.village_main_side(435.0) * 43.0
	if stage.flat(p).distance_to(stage.flat(church_center)) < 13.5:
		return false
	if church_square_center != Vector3.ZERO and stage.flat(p).distance_to(stage.flat(church_square_center)) < 10.5:
		return false
	for spot in stage.clearings:
		if stage.flat(p).distance_to(stage.flat(spot)) < 3.5:
			return false
	return _point_clear_of_obstacles(p, 0.9)

func _village_natural_details(cooperative: bool = false) -> void:
	var detail_rng = RandomNumberGenerator.new()
	detail_rng.seed = 71020266
	var grass_poses: Array = []
	var grass_colors: Array = []
	var stone_poses: Array = []
	var stone_colors: Array = []
	for i in range(2600):
		if cooperative and i % 200 == 0:
			await get_tree().process_frame
		var s = detail_rng.randf_range(VILLAGE_START + 3.0, VILLAGE_END - 3.0)
		var side_value = -1.0 if detail_rng.randi() % 2 == 0 else 1.0
		var p = stage.village_main_at(s) + stage.village_main_side(s) * side_value * detail_rng.randf_range(7.0, 47.0) + stage.village_main_direction(s) * detail_rng.randf_range(-1.5, 1.5)
		if not village_detail_allowed(p):
			continue
		p.y = stage.ground(p) - 0.06
		var size = detail_rng.randf_range(0.20, 0.52)
		grass_poses.append(Transform3D(Basis(Vector3.UP, detail_rng.randf() * TAU).scaled(Vector3(size * 1.8, size, size * 1.8)), p))
		grass_colors.append(stage.shared_grass_color(detail_rng.randf()))
		village_detail_positions.append(p)
		village_grass_count += 1
		if village_grass_count >= 720:
			break
	for i in range(900):
		if cooperative and i % 200 == 0:
			await get_tree().process_frame
		var s = detail_rng.randf_range(VILLAGE_START + 4.0, VILLAGE_END - 4.0)
		var side_value = -1.0 if detail_rng.randi() % 2 == 0 else 1.0
		var p = stage.village_main_at(s) + stage.village_main_side(s) * side_value * detail_rng.randf_range(7.2, 46.0)
		if not village_detail_allowed(p):
			continue
		p.y = stage.ground(p)
		var radius = detail_rng.randf_range(0.10, 0.30)
		stone_poses.append(stage.shared_stone_pose(p + Vector3(0, radius * 0.18, 0), radius, detail_rng.randf() * TAU))
		stone_colors.append(stage.shared_stone_color(detail_rng.randf_range(-0.10, 0.10)))
		village_detail_positions.append(p)
		village_stone_count += 1
		if village_stone_count >= 150:
			break
	stage._detail_batch("VillageGrass", stage._grass_mesh(), grass_poses, grass_colors)
	stage._detail_batch("VillageStones", stage.shared_stone_mesh(), stone_poses, stone_colors)

func _landscape() -> void:
	var root = Node3D.new()
	root.name = "VineyardLandscape"
	stage.add_child(root)
	for s in range(40, 820, 32):
		for side_value in [-1.0, 1.0]:
			var p = stage.village_main_at(s) + stage.village_main_side(s) * side_value * 100
			p.y = stage.ground(p)
			Props.cylinder(root, p + Vector3(0, 3.5, 0), 0.10, 0.06, 7, Color("795e44"), 8)
			Props.cylinder(root, p + Vector3(0, 5, 0), 1.5, 0.08, 8, Color("426345"), 10)
	for i in range(18):
		var p = Vector3((-1.0 if i % 2 else 1.0) * (180 + i % 3 * 25), -20, -i * 55)
		Props.cylinder(root, p, 150, 0, 100 + i % 4 * 16, Color("84917a"), 12)
	_batch(root, Transform3D.IDENTITY)

# Use each paved area's real local frame: cross streets are rotated relative
# to the route, so a station-only test misses their far ends.
func paved_at(p: Vector3, padding: float = 0.0) -> bool:
	var nearest = stage.urban_nearest(p)
	if nearest.s >= VILLAGE_START - padding and nearest.s <= VILLAGE_END + padding and nearest.distance <= 6.65 + padding:
		return true
	for area in paved_areas:
		var local = area.pose.affine_inverse() * p
		if absf(local.x) <= area.half.x + padding and absf(local.z) <= area.half.y + padding:
			return true
	return false

func _village_props() -> void:
	for station in [335.0, 405.0, 465.0, 540.0]:
		for side_value in [-1.0, 1.0]:
			var root = Node3D.new()
			root.name = "VillageStreetFurniture_%d_%d" % [int(station), int(side_value)]
			stage.add_child(root)
			root.position = stage.village_main_at(station) + stage.village_main_side(station) * side_value * 7.7
			root.rotation.y = atan2(-stage.village_main_direction(station).x, -stage.village_main_direction(station).z)
			# Benches face the stage and stand behind the pedestrian corridor.
			for slat in range(4):
				Props.box(root, Vector3(0, 0.48, -0.24 + slat * 0.16), Vector3(1.8, 0.07, 0.12), Color("93684a"))
			for x in [-0.65, 0.65]:
				Props.box(root, Vector3(x, 0.24, 0), Vector3(0.09, 0.48, 0.5), Color("424a42"))
			for y in [0.75, 0.95]:
				Props.box(root, Vector3(0, y, side_value * 0.32), Vector3(1.8, 0.14, 0.07), Color("93684a"))
			_solid(root, Vector3(0, 0.5, 0), Vector3(1.8, 1.0, 0.7), "street_furniture")
			# Flower planters and litter bins, away from the racing line.
			Props.cylinder(root, Vector3(1.65, 0.3, 0), 0.42, 0.52, 0.6, Color("a26c50"), 10)
			for flower in range(7):
				var a = flower * TAU / 7
				var pos = Vector3(1.65 + cos(a) * 0.3, 0.75, sin(a) * 0.3)
				Props.cylinder(root, pos - Vector3(0, 0.15, 0), 0.025, 0.025, 0.3, Color("527843"), 5)
				Props.box(root, pos, Vector3(0.14, 0.10, 0.14), Color("d58b45") if flower % 2 else Color("b95068"))
			Props.cylinder(root, Vector3(-1.5, 0.4, 0), 0.28, 0.28, 0.8, Color("485b50"), 10)
			Props.cylinder(root, Vector3(-1.5, 0.82, 0), 0.31, 0.31, 0.06, Color("303a34"), 10)
			_batch(root, root.transform)
			village_prop_count += 3
	for station in [370.0, 500.0]:
		var root = Node3D.new()
		root.name = "VillageWineDelivery_%d" % int(station)
		stage.add_child(root)
		root.position = stage.village_main_at(station) + stage.village_main_side(station) * -20.0 + stage.village_main_direction(station) * 5.0
		root.rotation.y = atan2(-stage.village_main_direction(station).x, -stage.village_main_direction(station).z)
		for x in [-1.0, 0.0, 1.0]:
			Props.cylinder(root, Vector3(x, 0.6, 0), 0.43, 0.43, 1.2, Color("886345"), 12)
			for y in [0.18, 0.95]:
				Props.cylinder(root, Vector3(x, y, 0), 0.445, 0.445, 0.055, Color("555b52"), 12)
			Props.box(root, Vector3(x, 0.25, 1.2), Vector3(0.8, 0.5, 0.65), Color("ac8352"))
			for grape in range(6):
				Props.cylinder(root, Vector3(x - 0.25 + (grape % 3) * 0.25, 0.53, 1.08 + (grape / 3) * 0.2), 0.10, 0.10, 0.12, Color("725077"), 6)
		_solid(root, Vector3(0, 0.6, 0), Vector3(3, 1.2, 0.9), "wine_barrels")
		_batch(root, root.transform)
		village_prop_count += 6
