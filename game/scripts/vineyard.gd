extends "res://scripts/city.gd"
# Reuse swept solid collisions, destructible lamps and spatial mesh batches.
const VILLAGE_START = 300.0
const VILLAGE_END = 570.0
var cultivated_cells: Dictionary = {}
var crop_ground_cells: Dictionary = {}
var crop_soil: Dictionary = {}
var crop_heights: Dictionary = {}
var vine_count = 0
var lavender_count = 0
var lavender_positions: Array[Vector3] = []
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
var interior_footprints: Array[Dictionary] = []
var bell: Node3D
var walk_surfaces: Array[Dictionary] = []
var viewpoints: Array[Dictionary] = []
const Interiors = preload("res://scripts/village_interiors.gd")

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
			# Reserve the frontage for the cafe instead of building through its terrace.
			reserved = reserved or (s == 334 and side_value == -1.0)
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
	_village_landmarks()
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
		await _gravel_forest_details(true)
	else:
		_gravel_forest_details()
	if cooperative:
		await _village_natural_details(true)
	else:
		_village_natural_details()
	if cooperative:
		await _crop_ground_details(true)
	else:
		_crop_ground_details()
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
				_house(p, yaw, 100 + int(lane_s) + int(along) + int(side_value), along == 28.0 and side_value == 1.0)
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

func _house(p: Vector3, yaw: float, seed_value: int, accessible: bool = false) -> void:
	var house = Node3D.new()
	house.name = "VillageHouse_%d" % village_houses
	village_houses += 1
	stage.add_child(house)
	house.position = p
	house.rotation.y = yaw
	if accessible:
		Interiors.house(self, house)
		_batch(house, house.transform)
		return
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
	Interiors.church(self, church)
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

# Village terrain uses 4 m triangles. Cache their vertices only while building
# crops; thousands of nearby stems share the same terrain cell.
func _crop_height(p: Vector3) -> float:
	var cell_x = floorf(p.x / 4) * 4
	var cell_z = floorf(p.z / 4) * 4
	var step = stage.terrain_tile_step(cell_x, cell_z)
	var x = cell_x + floorf((p.x - cell_x) / step) * step
	var z = cell_z + floorf((p.z - cell_z) / step) * step
	var heights: Array[float] = []
	for point in [Vector2(x, z), Vector2(x + step, z), Vector2(x, z + step), Vector2(x + step, z + step)]:
		if not crop_heights.has(point):
			crop_heights[point] = stage.terrain_vertex_height(point.x, point.y)
		heights.append(crop_heights[point])
	var u = (p.x - x) / step
	var v = (p.z - z) / step
	if u + v <= 1:
		return heights[0] + (heights[1] - heights[0]) * u + (heights[2] - heights[0]) * v
	return heights[3] + (heights[2] - heights[3]) * (1 - u) + (heights[1] - heights[3]) * (1 - v)

# Soil ribbons use sampled terrain heights, including curved hills and parking
# transitions. Keep a mesh per spatial tile rather than one draw per plant.
func _clip_crop_polygon(polygon: Array[Vector2], a: Vector2, b: Vector2) -> Array[Vector2]:
	var clipped: Array[Vector2] = []
	if polygon.is_empty():
		return clipped
	var edge = b - a
	var previous = polygon.back()
	var previous_side = edge.cross(previous - a)
	for point in polygon:
		var side = edge.cross(point - a)
		if (side >= 0.0) != (previous_side >= 0.0):
			clipped.append(previous.lerp(point, previous_side / (previous_side - side)))
		if side >= 0.0:
			clipped.append(point)
		previous = point
		previous_side = side
	return clipped

func _crop_soil(pose: Transform3D) -> void:
	var key = Vector2i(floori(pose.origin.x / 64.0), floori(pose.origin.z / 64.0))
	if not crop_soil.has(key):
		var builder = SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		crop_soil[key] = builder
	var builder: SurfaceTool = crop_soil[key]
	var footprint: Array[Vector2] = []
	for local in [Vector3(-0.7, 0, -3.1), Vector3(0.7, 0, -3.1), Vector3(0.7, 0, 3.1), Vector3(-0.7, 0, 3.1)]:
		var world: Vector3 = pose * local
		footprint.append(Vector2(world.x, world.z))
	var bounds = Rect2(footprint[0], Vector2.ZERO)
	for point in footprint:
		bounds = bounds.expand(point)
	# Clip each ribbon against the terrain triangles: sampling just the edge
	# can bury a long overlay when it crosses a different triangle's slope.
	for x in range(floori(bounds.position.x / 4.0), floori(bounds.end.x / 4.0) + 1):
		for z in range(floori(bounds.position.y / 4.0), floori(bounds.end.y / 4.0) + 1):
			var step = int(stage.terrain_tile_step(x * 4, z * 4))
			for dx in range(0, 4, step):
				for dz in range(0, 4, step):
					var a = Vector2(x * 4.0 + dx, z * 4.0 + dz)
					var b = a + Vector2(step, 0)
					var c = a + Vector2(0, step)
					var d = a + Vector2(step, step)
					for triangle in [[a, b, c], [d, c, b]]:
						var polygon = footprint.duplicate()
						for i in range(3):
							polygon = _clip_crop_polygon(polygon, triangle[i], triangle[(i + 1) % 3])
						for i in range(1, polygon.size() - 1):
							for point in [polygon[0], polygon[i], polygon[i + 1]]:
								var world = Vector3(point.x, 0, point.y)
								world.y = _crop_height(world) + 0.012
								builder.add_vertex(world)

func _flush_crop_soil() -> void:
	for key in crop_soil:
		var builder: SurfaceTool = crop_soil[key]
		builder.index()
		builder.generate_normals()
		var mesh = MeshInstance3D.new()
		mesh.name = "VineyardSoil_%d_%d" % [key.x, key.y]
		mesh.mesh = builder.commit()
		mesh.material_override = Props.material(Color("7e7054"))
		stage.add_child(mesh)
	crop_soil.clear()

func _register_crop(p: Vector3, station: float) -> void:
	var key = Vector2i(floori(p.x / 8.0), floori(p.z / 8.0))
	if not cultivated_cells.has(key):
		cultivated_cells[key] = []
	cultivated_cells[key].append(p)
	if not crop_ground_cells.has(key):
		crop_ground_cells[key] = []
	crop_ground_cells[key].append({"pos": p, "side": stage.village_main_side(station), "direction": stage.village_main_direction(station), "half": Vector2(0.95, 1.5) if station < 300.0 else Vector2(1.3, 3.5)})

func crop_clear(p: Vector3, clearance: float = 6.0) -> bool:
	var key = Vector2i(floori(p.x / 8.0), floori(p.z / 8.0))
	var reach = ceili(clearance / 8.0)
	for x in range(-reach, reach + 1):
		for z in range(-reach, reach + 1):
			for plant in cultivated_cells.get(key + Vector2i(x, z), []):
				if stage.flat(p).distance_squared_to(stage.flat(plant)) < clearance * clearance:
					return false
	return true

func _vineyards(cooperative: bool = false) -> void:
	if cooperative:
		await _lavender_fields(true)
	else:
		_lavender_fields()
	var leaves: Array = []
	var leaf_colors: Array = []
	var fruit: Array = []
	var fruit_colors: Array = []
	var sphere = SphereMesh.new()
	sphere.radial_segments = 8
	sphere.rings = 3
	for start in [585]:
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
					p.y = _crop_height(p) - 0.02
					_register_crop(p, s)
					var yaw = atan2(-stage.village_main_direction(s).x, -stage.village_main_direction(s).z)
					var pose = Transform3D(stage.terrain_basis(p, yaw, _crop_height), p)
					var section = Node3D.new()
					root.add_child(section)
					section.transform = pose
					vine_count += 1
					_crop_soil(pose)
					Props.cylinder(section, Vector3(0, 0.70, 0), 0.08, 0.04, 1.4, Color("735943"), 6)
					Props.cylinder(section, Vector3(0, 1, 0), 0.04, 0.025, 2.0, Color("8b8063"), 6)
					for y in [0.85, 1.35, 1.80]:
						Props.box(section, Vector3(0, y, 0), Vector3(0.018, 0.018, 6.2), Color("7b7d68"))
					for offset in [-1.7, -0.65, 0.65, 1.7]:
						var position = pose * Vector3(0, 1.2 + sin(s + offset) * 0.15, -offset)
						leaves.append(Transform3D(pose.basis.scaled(Vector3(0.85, 0.60, 1.05)), position))
						leaf_colors.append(Color("526e37").lightened(float((s + row) % 5) * 0.025))
					var indices: Array = []
					for cluster in [-1.0, 1.0]:
						for berry in range(12):
							var tier = berry / 4
							var angle = berry * 2.4
							var radius = 0.12 - tier * 0.025
							var position = pose * Vector3(0.43 + cos(angle) * radius, 1.08 - tier * 0.105, -cluster + sin(angle) * radius)
							indices.append(fruit.size())
							fruit.append(Transform3D(Basis.from_scale(Vector3.ONE * 0.12), position))
							fruit_colors.append(Color("6b4769") if row % 3 else Color("a3b657"))
					stage.collectibles.append({"kind": "berries", "name": "виноград", "pos": p, "quantity": 3, "parts": {"VineyardGrapes": indices}})
					_batch(section, pose)
					section.free()
				_batch(root, Transform3D.IDENTITY)
	_flush_crop_soil()
	crop_heights.clear()
	stage._detail_batch("VineyardLeaves", sphere, leaves, leaf_colors)
	stage._detail_batch("VineyardGrapes", sphere, fruit, fruit_colors)

# Low flowering rows replace the start-side vines; no trellises or grapes.
func _lavender_fields(cooperative: bool = false) -> void:
	# Continuous rounded flowering bands, divided into local culling tiles.
	var builders = {}
	var profile = [Vector2(-0.95, 0.02), Vector2(-0.65, 0.28), Vector2(-0.30, 0.53), Vector2(0, 0.60), Vector2(0.30, 0.53), Vector2(0.65, 0.28), Vector2(0.95, 0.02)]
	for side_value in [-1.0, 1.0]:
		for row in range(18):
			if cooperative:
				await get_tree().process_frame
			var previous: Array[Vector3] = []
			for station in range(18, 286, 2):
				var s = float(station) + (0.4 if row % 2 else 0.0)
				var p = stage.village_main_at(s) + stage.village_main_side(s) * side_value * (13.0 + row * 4.0)
				var blocked = stage.road_distance(p) < 7.0 or -p.z < 12.0 or -p.z >= VILLAGE_START - 10.0
				for parking in stage.clearings:
					blocked = blocked or stage.flat(p).distance_to(stage.flat(parking)) < 11.0
				if blocked:
					previous.clear()
					continue
				p.y = _crop_height(p)
				_register_crop(p, s)
				lavender_positions.append(p)
				lavender_count += 1
				var section: Array[Vector3] = []
				for shape in profile:
					var vertex = p + stage.village_main_side(s) * shape.x
					vertex.y = _crop_height(vertex) + shape.y * (1.0 + sin(s * 0.47 + row) * 0.035)
					section.append(vertex)
				if not previous.is_empty():
					var tile = Vector2i(floor(p.x / 64.0), floor(p.z / 64.0))
					if not builders.has(tile):
						var builder = SurfaceTool.new()
						builder.begin(Mesh.PRIMITIVE_TRIANGLES)
						builders[tile] = builder
					var builder: SurfaceTool = builders[tile]
					for strip in range(profile.size() - 1):
						var color = Color("526849") if strip == 0 or strip == profile.size() - 2 else Color("8654b5").lerp(Color("b089d0"), (sin(s * 0.08 + row) + 1.0) * 0.15)
						for vertex in [previous[strip], section[strip + 1], section[strip], previous[strip], previous[strip + 1], section[strip + 1]]:
							builder.set_color(color)
							builder.set_uv(Vector2(vertex.x, vertex.z) * 0.85)
							builder.add_vertex(vertex)
				previous = section
	var material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.albedo_texture = preload("res://textures/nature/lavender.svg")
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for tile in builders:
		var builder: SurfaceTool = builders[tile]
		builder.index()
		builder.generate_normals()
		var node = MeshInstance3D.new()
		node.name = "LavenderBands_%d_%d" % [tile.x, tile.y]
		node.mesh = builder.commit()
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stage.add_child(node)
	stage.woodland_details.LavenderBands = lavender_count

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
			center.y = stage.terrain_surface_height(center)
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
				if blocked or not cemetery_clear(p, 2.0) or not crop_clear(p) or paved_at(p, 2.0) or stage.road_distance(p) < 8.0:
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
			if blocked or not cemetery_clear(p, 2.0) or not crop_clear(p) or paved_at(p, 2.0) or stage.road_distance(p) < 8.0:
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
	for area in interior_footprints:
		var local: Vector3 = area.inverse * p
		if absf(local.x) <= area.half.x + padding and absf(local.z) <= area.half.y + padding:
			return false
	for obstacle in obstacles:
		var pose = _relative_pose(obstacle.body)
		var local = pose.affine_inverse() * p
		var half: Vector3 = obstacle.half + Vector3.ONE * padding
		if absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z:
			return false
	return true

func cemetery_clear(p: Vector3, padding: float = 0.0) -> bool:
	# The lawn is 32 x 24 m. Reserve its corners and an extra crown margin.
	if cemetery_center == Vector3.ZERO:
		return true
	var offset = p - cemetery_center
	return absf(offset.x) > 18.0 + padding or absf(offset.z) > 14.0 + padding

func _forest_spot_allowed(p: Vector3, padding: float = 0.0) -> bool:
	if absf(p.x) > 196.0 - padding:
		return false
	if not crop_clear(p, 6.0 + padding) or paved_at(p, padding):
		return false
	if not cemetery_clear(p, padding):
		return false
	var s = stage.road_s(p)
	if s < VILLAGE_START - 55.0 or s > VILLAGE_END + 55.0:
		return false
	var distance = stage.road_distance(p)
	var minimum = 8.0 if stage.village_forest_detour(s) else (48.0 if stage.village(s) else 92.0)
	if distance < minimum + padding or distance > (185.0 if stage.village_forest_detour(s) else 145.0):
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
	for i in range(15000):
		if cooperative and i % 200 == 0:
			await get_tree().process_frame
		var s = forest_rng.randf_range(VILLAGE_START - 52.0, VILLAGE_END + 52.0)
		var side_value = -1.0 if forest_rng.randi() % 2 == 0 else 1.0
		# Close the gaps near the gravel stretch; outside it preserve village spacing.
		var lateral = forest_rng.randf_range(12.0, 185.0) if stage.village_forest_detour(s) else forest_rng.randf_range(48.0, 142.0)
		var p = stage.at(s) + stage.side(s) * side_value * lateral + stage.direction(s) * forest_rng.randf_range(-4.0, 4.0)
		if not _forest_spot_allowed(p, 2.0):
			continue
		p.y = stage.terrain_surface_height(p) - 0.03
		tree_positions.append(p)
		tree_data.append({
			"position": p,
			"height": forest_rng.randf_range(6.0, 17.0),
			"shade": forest_rng.randf_range(-0.025, 0.045),
		})
		mixed_tree_count += 1
		if mixed_tree_count >= 3000:
			break
	# A non-colliding distant silhouette hides the square edge of the playable
	# terrain. Separate instances let visibility culling retain the near forest.
	var horizon_rng = RandomNumberGenerator.new()
	horizon_rng.seed = 71020269
	var horizon_trees: Array = []
	for attempt in range(900):
		if horizon_trees.size() >= 240:
			break
		var z = horizon_rng.randf_range(-560.0, -310.0)
		var x = (188.0 + horizon_rng.randf_range(-3.5, 3.5)) * (-1.0 if attempt % 2 == 0 else 1.0)
		var point = Vector3(x, 0, z)
		if stage.road_distance(point) < 20.0 or not cemetery_clear(point, 4.0):
			continue
		point.y = stage.terrain_surface_height(point) - 0.05
		horizon_trees.append({"position": point, "height": horizon_rng.randf_range(13.0, 22.0), "shade": horizon_rng.randf_range(-0.08, 0.02)})
	for layer in range(4):
		var horizon_poses: Array = []
		var horizon_colors: Array = []
		for tree in horizon_trees:
			horizon_poses.append(stage.shared_tree_pose(tree.position, float(tree.height), layer))
			horizon_colors.append(stage.shared_tree_color(layer, float(tree.shade), false))
		stage._detail_batch("VillageHorizonTreeLayer%d" % layer, stage.shared_tree_mesh(layer), horizon_poses, horizon_colors)
	for layer in range(4):
		var poses: Array = []
		var colors: Array = []
		for tree in tree_data:
			poses.append(stage.shared_tree_pose(tree.position, float(tree.height), layer))
			colors.append(stage.shared_tree_color(layer, float(tree.shade), false))
		stage._detail_batch("VillageForestTreeLayer%d" % layer, stage.shared_tree_mesh(layer), poses, colors)

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
	for i in range(1400):
		if cooperative and i % 200 == 0:
			await get_tree().process_frame
		var s = forest_rng.randf_range(VILLAGE_START - 50.0, VILLAGE_END + 50.0)
		var side_value = -1.0 if forest_rng.randi() % 2 == 0 else 1.0
		var center = stage.at(s) + stage.side(s) * side_value * forest_rng.randf_range(50.0, 136.0)
		if not _forest_spot_allowed(center, 1.0) or not stage.rock_hit(center, center, 0.8, false).is_empty():
			continue
		center.y = stage.terrain_surface_height(center)
		var size = forest_rng.randf_range(0.55, 1.35)
		var bearing = forest_rng.randf() * TAU
		var berry_bush = forest_rng.randf() < 0.40
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
		if forest_bush_count >= 220 and forest_berry_bush_count >= 120:
			break
	var bush_mesh = stage.NATURE_BUSH
	var berry_mesh = stage.NATURE_BERRY
	stage._detail_batch("VillageForestBushes", bush_mesh, bush_poses, bush_colors)
	stage._detail_batch("VillageForestBerryBushes", bush_mesh, berry_bush_poses, berry_bush_colors)
	stage._detail_batch("VillageForestBerries", berry_mesh, berry_poses, berry_colors)
	# Generate the floor from the actual canopy, after rocks and bushes exist.
	if cooperative:
		await _village_forest_floor(bush_poses + berry_bush_poses, true)
	else:
		_village_forest_floor(bush_poses + berry_bush_poses)


func _village_forest_floor(bushes: Array, cooperative: bool = false) -> void:
	var exclusions = {}
	for tree in tree_positions:
		var cell = Vector2i(floori(tree.x / 4.0), floori(tree.z / 4.0))
		if not exclusions.has(cell):
			exclusions[cell] = []
		exclusions[cell].append({"pos": tree, "radius": 0.7})
	for pose in bushes:
		var point: Vector3 = pose.origin
		var cell = Vector2i(floori(point.x / 4.0), floori(point.z / 4.0))
		if not exclusions.has(cell):
			exclusions[cell] = []
		exclusions[cell].append({"pos": point, "radius": maxf(pose.basis.x.length(), pose.basis.z.length()) * 0.6})
	var random = RandomNumberGenerator.new()
	random.seed = 71020272
	for kind in ["Grass", "Stones"]:
		var poses: Array = []
		var colors: Array = []
		var limit = 6000 if kind == "Grass" else 1000
		for attempt in range(limit * 4):
			if poses.size() >= limit or tree_positions.is_empty():
				break
			if cooperative and attempt % 100 == 0:
				await get_tree().process_frame
			var center = tree_positions[attempt % tree_positions.size()]
			var angle = random.randf() * TAU
			var point = center + Vector3(cos(angle), 0, sin(angle)) * random.randf_range(1.5, 8.0)
			var size = random.randf_range(0.35, 0.75) if kind == "Grass" else random.randf_range(0.15, 0.38)
			var radius = size * 0.5 if kind == "Grass" else size
			if absf(point.x) > 196.0 - radius or stage.road_distance(point) < stage.road_width(stage.road_s(point)) * 0.5 + radius + 1.0 or paved_at(point, radius) or not crop_clear(point, 6.0 + radius) or not cemetery_clear(point, radius) or not _point_clear_of_obstacles(point, radius + 0.5):
				continue
			point.y = stage.terrain_surface_height(point)
			if not stage.rock_hit(point, point, radius, false).is_empty():
				continue
			var blocked = false
			for spot in stage.clearings:
				blocked = blocked or stage.flat(point).distance_to(stage.flat(spot)) < 12.0 + radius
			var cell = Vector2i(floori(point.x / 4.0), floori(point.z / 4.0))
			for x in range(-1, 2):
				for z in range(-1, 2):
					for object in exclusions.get(cell + Vector2i(x, z), []):
						blocked = blocked or stage.flat(point).distance_to(stage.flat(object.pos)) < radius + object.radius
			if blocked:
				continue
			var yaw = random.randf() * TAU
			if kind == "Grass":
				poses.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(size * 1.8, size, size * 1.8)), point - Vector3.UP * 0.015))
				colors.append(stage.shared_grass_color(random.randf()))
			else:
				poses.append(stage.shared_stone_pose(point + Vector3.UP * size * 0.35, size, yaw))
				colors.append(stage.shared_stone_color(random.randf_range(-0.1, 0.12)))
		if kind == "Grass":
			forest_grass_count = poses.size()
		else:
			forest_stone_count = poses.size()
		stage._detail_batch("VillageForest" + kind, stage._grass_mesh() if kind == "Grass" else stage.shared_stone_mesh(), poses, colors)

func _gravel_detail_allowed(p: Vector3, padding: float, boulder: bool = false) -> bool:
	if boulder:
		return _forest_spot_allowed(p, padding)
	var station = stage.road_s(p)
	return stage.village_forest_detour(station) and stage.road_distance(p) > stage.road_width(station) * 0.5 + 0.75 + padding and not paved_at(p, padding) and cemetery_clear(p, padding) and crop_clear(p, padding + 1.0) and _point_clear_of_obstacles(p, padding + 0.5)

func _gravel_forest_details(cooperative: bool = false) -> void:
	# Keep the road and its shoulders clear; fill the nearby woodland on both sides.
	var random = RandomNumberGenerator.new()
	random.seed = 71020270
	for kind in ["Grass", "Stones", "Boulders"]:
		var poses: Array = []
		var colors: Array = []
		var limit = 800 if kind == "Grass" else (140 if kind == "Stones" else 4)
		for attempt in range(2400):
			if poses.size() >= limit:
				break
			if cooperative and attempt % 100 == 0:
				await get_tree().process_frame
			var station = random.randf_range(392.0, 478.0)
			var side_value = -1.0 if attempt % 2 == 0 else 1.0
			var lateral = random.randf_range(10.0, 26.0) if kind == "Boulders" else random.randf_range(3.5, 10.0)
			var point = stage.at(station) + stage.side(station) * side_value * lateral
			var radius = random.randf_range(0.9, 1.5) if kind == "Boulders" else 0.4
			if not _gravel_detail_allowed(point, radius, kind == "Boulders") or not stage.rock_hit(point, point, radius + 0.3, false).is_empty():
				continue
			point.y = stage.terrain_surface_height(point)
			var yaw = random.randf() * TAU
			if kind == "Grass":
				var size = random.randf_range(0.3, 0.65)
				poses.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(size * 1.8, size, size * 1.8)), point - Vector3.UP * 0.03))
				colors.append(stage.shared_grass_color(random.randf()))
			elif kind == "Stones":
				radius = random.randf_range(0.12, 0.35)
				poses.append(stage.shared_stone_pose(point + Vector3.UP * radius * 0.22, radius, yaw))
				colors.append(stage.shared_stone_color(random.randf_range(-0.1, 0.12)))
			else:
				var height = random.randf_range(1.0, 1.8)
				poses.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(radius * 2.0, height, radius * 1.65)), point + Vector3.UP * height * 0.35))
				colors.append(Color("697064").lightened(random.randf_range(-0.12, 0.12)))
				stage.rocks.append({"pos": point, "radius": radius, "height": height * 0.9, "forest": true, "gravel_detail": true})
		var mesh = stage._grass_mesh() if kind == "Grass" else (stage.shared_stone_mesh() if kind == "Stones" else stage.NATURE_BOULDER)
		stage._detail_batch("VillageGravel" + kind, mesh, poses, colors)

func village_detail_allowed(p: Vector3) -> bool:
	var nearest = stage.village_main_nearest(p)
	var s = float(nearest.s)
	if not stage.village(s):
		return false
	if paved_at(p, 0.9):
		return false
	var distance = float(nearest.distance)
	if stage.road_distance(p) <= stage.road_width(stage.road_s(p)) * 0.5 + 0.9:
		return false
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
	for i in range(4400):
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
		if village_grass_count >= 1200:
			break
	for i in range(2400):
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
		if village_stone_count >= 260:
			break
	stage._detail_batch("VillageGrass", stage._grass_mesh(), grass_poses, grass_colors)
	stage._detail_batch("VillageStones", stage.shared_stone_mesh(), stone_poses, stone_colors)


func _crop_ground_clear(p: Vector3, radius: float) -> bool:
	if stage.road_distance(p) < stage.WIDTH * 0.5 + radius + 0.8 or paved_at(p, radius) or not _point_clear_of_obstacles(p, radius + 0.4):
		return false
	for spot in stage.clearings:
		if stage.flat(p).distance_to(stage.flat(spot)) < 10.0 + radius:
			return false
	var key = Vector2i(floori(p.x / 8.0), floori(p.z / 8.0))
	for x in range(-1, 2):
		for z in range(-1, 2):
			for plant in crop_ground_cells.get(key + Vector2i(x, z), []):
				var offset = p - plant.pos
				if absf(offset.dot(plant.side)) < plant.half.x + radius and absf(offset.dot(plant.direction)) < plant.half.y + radius:
					return false
	return true

func _crop_ground_details(cooperative: bool = false) -> void:
	var random = RandomNumberGenerator.new()
	random.seed = 71020271
	var occupied = {}
	for kind in ["Grass", "Stones"]:
		var poses: Array = []
		var colors: Array = []
		for region in [Vector2(22, 280), Vector2(592, 816)]:
			for attempt in range(2400 if kind == "Grass" else 500):
				if cooperative and attempt % 100 == 0:
					await get_tree().process_frame
				var station = random.randf_range(region.x, region.y)
				var lateral = 15.0 + random.randi_range(0, 16) * 4.0 + random.randf_range(-0.25, 0.25)
				var p = stage.village_main_at(station) + stage.village_main_side(station) * lateral * (-1.0 if attempt % 2 == 0 else 1.0)
				var size = random.randf_range(0.20, 0.40) if kind == "Grass" else random.randf_range(0.10, 0.22)
				var radius = size * 0.6 if kind == "Grass" else size
				p.y = stage.terrain_surface_height(p)
				if not _crop_ground_clear(p, radius) or stage.obstacle_hit(p, p, radius) >= 0 or not stage.rock_hit(p, p, radius, false).is_empty():
					continue
				var cell = Vector2i(floori(p.x), floori(p.z))
				var blocked = false
				for x in range(-1, 2):
					for z in range(-1, 2):
						for detail in occupied.get(cell + Vector2i(x, z), []):
							blocked = blocked or stage.flat(p).distance_to(stage.flat(detail.pos)) < radius + detail.radius
				if blocked:
					continue
				if not occupied.has(cell):
					occupied[cell] = []
				occupied[cell].append({"pos": p, "radius": radius})
				var yaw = random.randf() * TAU
				if kind == "Grass":
					poses.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(size * 1.8, size, size * 1.8)), p - Vector3.UP * 0.015))
					colors.append(stage.shared_grass_color(random.randf()))
				else:
					poses.append(stage.shared_stone_pose(p + Vector3.UP * size * 0.35, size, yaw))
					colors.append(stage.shared_stone_color(random.randf_range(-0.1, 0.12)))
		stage._detail_batch("CropGround" + kind, stage._grass_mesh() if kind == "Grass" else stage.shared_stone_mesh(), poses, colors)

func _forest_mushrooms() -> void:
	var random = RandomNumberGenerator.new()
	random.seed = 71020266
	var caps = {"edible": [], "fly_agaric": [], "toadstool": []}
	var colors = {"edible": [], "fly_agaric": [], "toadstool": []}
	var stems = []
	var stem_colors = []
	for i in range(380):
		# Attempts generate clusters; cap individual mushrooms as well.
		if caps.edible.size() + caps.fly_agaric.size() + caps.toadstool.size() >= 380:
			break
		var s = random.randf_range(290, 610)
		var p = stage.at(s) + stage.side(s) * random.randf_range(12, 140) * (-1 if i % 2 else 1)
		if not _forest_spot_allowed(p, 0.5) or not stage.rock_hit(p, p, 0.5, false).is_empty():
			continue
		for j in range(3):
			var at = p + Vector3(random.randf_range(-0.4, 0.4), 0, random.randf_range(-0.4, 0.4))
			if not _forest_spot_allowed(at, 0.2):
				continue
			at.y = stage.terrain_surface_height(at)
			var size = random.randf_range(0.12, 0.24)
			var species = "fly_agaric" if i % 10 == 4 else ("toadstool" if i % 10 == 7 else "edible")
			var layer = "FlyAgaricCaps" if species == "fly_agaric" else ("ToadstoolCaps" if species == "toadstool" else "MushroomCaps")
			stage.collectibles.append({"kind": "mushrooms", "species": species, "name": "мухомор" if species == "fly_agaric" else ("поганка" if species == "toadstool" else "гриб"), "pos": at, "quantity": 1, "parts": {layer: [caps[species].size()], "MushroomStems": [stems.size()]}})
			caps[species].append(Transform3D(Basis.from_scale(Vector3(size * 1.4, size * 0.55, size * 1.4)), at + Vector3.UP * size))
			colors[species].append(Color("b87743") if species == "edible" else Color.WHITE)
			stems.append(Transform3D(Basis.from_scale(Vector3(size * 0.2, size, size * 0.2)), at + Vector3.UP * size * 0.5))
			stem_colors.append(Color("c5baa1"))
	stage._detail_batch("MushroomCaps", stage.NATURE_MUSHROOM_CAP, caps.edible, colors.edible)
	stage._detail_batch("FlyAgaricCaps", stage.NATURE_MUSHROOM_CAP, caps.fly_agaric, colors.fly_agaric)
	stage._detail_batch("ToadstoolCaps", stage.NATURE_MUSHROOM_CAP, caps.toadstool, colors.toadstool)
	stage._detail_batch("MushroomStems", stage.NATURE_MUSHROOM_STEM, stems, stem_colors)

func _landscape() -> void:
	var root = Node3D.new()
	root.name = "VineyardLandscape"
	stage.add_child(root)
	for s in range(40, 820, 32):
		for side_value in [-1.0, 1.0]:
			var p = stage.village_main_at(s) + stage.village_main_side(s) * side_value * 100
			if not crop_clear(p, 6.0) or paved_at(p, 2.0) or stage.road_distance(p) < 8.0:
				continue
			p.y = stage.ground(p)
			Props.cylinder(root, p + Vector3(0, 3.5, 0), 0.10, 0.06, 7, Color("795e44"), 8)
			Props.cylinder(root, p + Vector3(0, 5, 0), 1.5, 0.08, 8, Color("426345"), 10)
	for i in range(18):
		var p = Vector3((-1.0 if i % 2 else 1.0) * (900 + i % 3 * 80), -20, -i * 55)
		Props.cylinder(root, p, 150, 0, 100 + i % 4 * 16, Color("84917a"), 12)
	_batch(root, Transform3D.IDENTITY)

# Use each paved area's real local frame: cross streets are rotated relative
# to the route, so a station-only test misses their far ends.
func paved_at(p: Vector3, padding: float = 0.0) -> bool:
	var nearest = stage.village_main_nearest(p)
	if nearest.s >= VILLAGE_START - padding and nearest.s <= VILLAGE_END + padding and nearest.distance <= 6.65 + padding:
		return true
	for area in paved_areas:
		var local = area.pose.affine_inverse() * p
		if absf(local.x) <= area.half.x + padding and absf(local.z) <= area.half.y + padding:
			return true
	return false

# Landmark groups add variety without creating additional full-size buildings.
# All objects remain off the rally road, pavements and cemetery.
# Distinct rural landmarks, built from small reusable details rather than solid boxes.
# Keep furniture visually rich but batch it with the existing city renderer.
func _landmark_crate(parent: Node3D, origin: Vector3, yaw: float = 0.0) -> void:
	var crate = Node3D.new()
	parent.add_child(crate)
	crate.position = origin
	crate.rotation.y = yaw
	_solid(crate, Vector3(0, 0.42, 0), Vector3(0.94, 0.84, 0.86), "landmark")
	var timber = Color("a27b51")
	for y in [0.10, 0.42, 0.72]:
		for z in [-0.42, 0.42]:
			Props.box(crate, Vector3(0, y, z), Vector3(0.94, 0.12, 0.08), timber)
		for x in [-0.45, 0.45]:
			Props.box(crate, Vector3(x, y, 0), Vector3(0.08, 0.12, 0.83), timber)
	for x in [-0.43, 0.43]:
		for z in [-0.39, 0.39]:
			Props.box(crate, Vector3(x, 0.42, z), Vector3(0.09, 0.78, 0.09), Color("705037"))
	for x in [-0.25, 0.0, 0.25]:
		Props.box(crate, Vector3(x, 0.04, 0), Vector3(0.20, 0.08, 0.86), timber.darkened(0.13))

func _landmark_barrel(parent: Node3D, origin: Vector3) -> void:
	var barrel = Node3D.new()
	parent.add_child(barrel)
	barrel.position = origin
	_solid(barrel, Vector3(0, 0.54, 0), Vector3(0.89, 1.08, 0.89), "landmark")
	Props.cylinder(barrel, Vector3(0, 0.54, 0), 0.43, 0.38, 1.08, Color("815337"), 12)
	for height in [0.16, 0.47, 0.84, 1.04]:
		Props.cylinder(barrel, Vector3(0, height, 0), 0.445, 0.445, 0.045, Color("444c4b"), 12)
	for angle_index in range(10):
		var angle = angle_index * TAU / 10.0
		var stave = Props.box(barrel, Vector3(cos(angle) * 0.40, 0.56, sin(angle) * 0.40), Vector3(0.10, 0.98, 0.035), Color("a3754f"))
		stave.rotation.y = -angle

func _landmark_cafe_chair(parent: Node3D, origin: Vector3, yaw: float) -> void:
	var chair = Node3D.new()
	parent.add_child(chair)
	chair.position = origin
	chair.rotation.y = yaw
	_solid(chair, Vector3(0, 0.55, 0), Vector3(0.69, 1.1, 0.69), "landmark")
	var iron = Color("303f3e")
	for x in [-0.29, 0.29]:
		for z in [-0.29, 0.29]:
			Props.cylinder(chair, Vector3(x, 0.28, z), 0.035, 0.035, 0.56, iron, 6)
	Props.box(chair, Vector3(0, 0.57, 0), Vector3(0.68, 0.075, 0.68), Color("9a7352"))
	for y in [0.78, 1.02]:
		Props.box(chair, Vector3(0, y, 0.32), Vector3(0.69, 0.085, 0.06), Color("9a7352"))
	for x in [-0.30, 0.30]:
		Props.cylinder(chair, Vector3(x, 0.87, 0.32), 0.035, 0.035, 0.66, iron, 6)

func _landmark_cafe_table(parent: Node3D, origin: Vector3) -> void:
	var table = Node3D.new()
	parent.add_child(table)
	table.position = origin
	_solid(table, Vector3(0, 0.48, 0), Vector3(1.36, 0.96, 1.36), "landmark")
	Props.cylinder(table, Vector3(0, 0.91, 0), 0.68, 0.68, 0.07, Color("ae8764"), 16)
	Props.cylinder(table, Vector3(0, 0.85, 0), 0.60, 0.60, 0.05, Color("5b5247"), 16)
	Props.cylinder(table, Vector3(0, 0.43, 0), 0.055, 0.055, 0.85, Color("303f3e"), 8)
	Props.cylinder(table, Vector3(0, 0.055, 0), 0.37, 0.37, 0.07, Color("303f3e"), 10)
	Props.cylinder(table, Vector3(0.22, 1.01, 0.14), 0.10, 0.08, 0.17, Color("f1e2c9"), 10)
	Props.cylinder(table, Vector3(-0.19, 1.02, -0.13), 0.075, 0.07, 0.19, Color("70916a"), 10)
	for side_value in [-1.0, 1.0]:
		_landmark_cafe_chair(table, Vector3(side_value * 1.16, 0, 0), side_value * PI / 2.0)

func _village_landmarks() -> void:
	var wood = Color("84634a")
	var farm = Node3D.new()
	farm.name = "VillageFarmyard"
	stage.add_child(farm)
	farm.position = stage.village_main_at(545.0) + stage.village_main_side(545.0) * -32.0
	farm.position.y = stage.ground(farm.position)
	# Lean-to vineyard storage shelter with pitched roof and exposed timber frame.
	for x in [-4.5, 4.5]:
		for z in [-2.0, 2.0]:
			_solid(farm, Vector3(x, 1.55, z), Vector3(0.19, 3.1, 0.19), "landmark")
			Props.box(farm, Vector3(x, 1.55, z), Vector3(0.19, 3.1, 0.19), Color("68503a"))
	for z in [-2.0, 2.0]:
		for side_value in [-1.0, 1.0]:
			var sloped = Props.box(farm, Vector3(side_value * 2.25, 3.45, z), Vector3(4.9, 0.18, 0.17), Color("66503f"))
			sloped.rotation.z = -side_value * 0.12
	for side_value in [-1.0, 1.0]:
		var roof = Props.box(farm, Vector3(side_value * 2.3, 3.69, 0), Vector3(4.95, 0.14, 4.8), Color("86624d"))
		roof.rotation.z = -side_value * 0.12
	for index in range(6):
		_landmark_crate(farm, Vector3(-3.0 + (index % 3) * 1.12, 0, -1.3 + int(index / 3) * 0.89), float(index % 3) * 0.045)
	for x in [1.8, 3.0]:
		_landmark_barrel(farm, Vector3(x, 0, -1.1))
	# Low detailed vineyard cart: planked deck, high rails, axles and towbar.
	var trailer = Node3D.new()
	trailer.name = "FarmTrailer"
	farm.add_child(trailer)
	trailer.position = Vector3(1.5, 0, 5.0)
	_solid(trailer, Vector3(0, 0.95, 0), Vector3(3.6, 1.9, 2.6), "landmark")
	for plank in range(6):
		Props.box(trailer, Vector3(-1.4 + plank * 0.56, 0.88, 0), Vector3(0.52, 0.12, 2.4), Color("86694e"))
	for side_value in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			Props.box(trailer, Vector3(side_value * 1.65, 1.34, z), Vector3(0.12, 0.95, 0.12), wood)
		Props.box(trailer, Vector3(side_value * 1.65, 1.35, 0), Vector3(0.10, 0.18, 2.6), wood)
		for z in [-0.8, 0.8]:
			var wheel = Props.cylinder(trailer, Vector3(side_value * 1.7, 0.48, z), 0.47, 0.47, 0.18, Color("242d2d"), 12)
			wheel.rotation.z = PI / 2
			var hub = Props.cylinder(trailer, Vector3(side_value * 1.81, 0.48, z), 0.21, 0.21, 0.19, Color("b2afa2"), 10)
			hub.rotation.z = PI / 2
	Props.box(trailer, Vector3(0, 0.78, -2.1), Vector3(0.14, 0.14, 2.3), Color("5e6157"))
	Props.cylinder(trailer, Vector3(0, 0.78, -3.1), 0.16, 0.16, 0.08, Color("3b4241"), 10)
	_batch(farm, farm.transform)

	var cafe = Node3D.new()
	cafe.name = "VillageCafeTerrace"
	stage.add_child(cafe)
	cafe.position = stage.village_main_at(335.0) + stage.village_main_side(335.0) * -12.0
	cafe.position.y = stage.ground(cafe.position)
	cafe.rotation.y = atan2(-stage.village_main_direction(335.0).x, -stage.village_main_direction(335.0).z)
	for index in range(2):
		_landmark_cafe_table(cafe, Vector3(0, 0, float(index) * 2.8 - 1.4))
	# Striped fabric awning, with a light support frame.
	for x in [-2.25, 2.25]:
		_solid(cafe, Vector3(x, 1.84, 0), Vector3(0.10, 3.7, 0.10), "landmark")
		Props.box(cafe, Vector3(x, 1.84, 0), Vector3(0.10, 3.7, 0.10), Color("5e635f"))
	var awning = Node3D.new()
	cafe.add_child(awning)
	awning.position.y = 3.65
	awning.rotation.z = -0.06
	for stripe in range(8):
		var color = Color("e5d1b0") if stripe % 2 == 0 else Color("9a4e47")
		var strip = Props.box(awning, Vector3(-1.96 + stripe * 0.56, 0, 0), Vector3(0.56, 0.07, 6.9), color)
	for z in [-3.1, 3.1]:
		Props.box(cafe, Vector3(0, 3.66, z), Vector3(4.6, 0.1, 0.11), Color("635b4f"))
	for x in [-1.8, 1.8]:
		var pot = Vector3(x, 0, 4.0)
		Props.cylinder(cafe, pot + Vector3(0, 0.35, 0), 0.38, 0.48, 0.7, Color("a76b4f"), 10)
		Props.cylinder(cafe, pot + Vector3(0, 0.70, 0), 0.30, 0.30, 0.08, Color("4b382e"), 10)
		for flower in range(5):
			var angle = flower * TAU / 5.0
			Props.box(cafe, pot + Vector3(cos(angle) * 0.2, 1.0, sin(angle) * 0.2), Vector3(0.13, 0.16, 0.13), Color("c6726c"))
	_batch(cafe, cafe.transform)
	village_prop_count += 8

func _village_props() -> void:
	for station in [335.0, 405.0, 465.0, 540.0]:
		for side_value in [-1.0, 1.0]:
			if station == 335.0 and side_value == -1.0:
				continue # Cafe furniture occupies this frontage.
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

# Floors are queried only for walkers, never for road/car suspension.
# The height limit prevents a roof or an overlapping stair flight teleporting
# a person underneath it upwards. Surfaces remain static and deterministic.
func walking_floor(pos: Vector3, feet_height: float) -> float:
	var result = -INF
	for surface in walk_surfaces:
		if absf(pos.x - surface.pose.origin.x) > surface.reach or absf(pos.z - surface.pose.origin.z) > surface.reach:
			continue
		var local: Vector3 = surface.inverse * pos
		if absf(local.x) > surface.half.x or absf(local.z) > surface.half.y:
			continue
		var progress = clampf(local.z / (surface.half.y * 2.0) + 0.5, 0.0, 1.0)
		var steps = int(surface.get("steps", 0))
		if steps > 0:
			progress = ceilf(progress * steps) / steps
		var height: float = surface.pose.origin.y + surface.rise * progress
		if height <= feet_height + 0.45:
			result = maxf(result, height)
	return result if is_finite(result) else stage.ground(pos)
