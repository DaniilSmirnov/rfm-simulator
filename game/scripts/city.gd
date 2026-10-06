extends Node3D
const Props = preload("res://scripts/props.gd")
const CROSS_Z = [-50.0, -100.0, -150.0, -200.0, -250.0, -280.0]
var stage: Node3D
var obstacles: Array[Dictionary] = []
var lamps: Array[Dictionary] = []
var lamp_targets: Dictionary = {}
var batches: Dictionary = {}
var meshes: Dictionary = {}

func build() -> void:
	var floor_body = StaticBody3D.new()
	floor_body.name = "CityPhysicsGround"
	stage.add_child(floor_body)
	floor_body.position = Vector3(20, 1.75, -170)
	var floor_shape = CollisionShape3D.new()
	var floor_box = BoxShape3D.new()
	floor_box.size = Vector3(420, 0.5, 960)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	for x in [-24.0, 24.0, 120.0]:
		_street(Vector3(x, 2, -150), 9, 300, 0, "CityBoulevard_%d" % int(x))
	for z in CROSS_Z:
		_street(Vector3(24, 2, z), 9, 220, PI / 2, "CityCrossStreet_%03d" % int(-z))
	_square()
	# Adjacent 10 m townhouses, with an opening at every intersecting street.
	for x in [-24.0, 24.0, 120.0]:
		for z in range(-15, -301, -10):
			for side in [-1.0, 1.0]:
				var p = Vector3(x + side * 17, 2, z)
				if _site_clear(p):
					_building(p, 0, side, int(absf(x) * 0.5 + absf(z) / 10 + side * 3))
	for z in CROSS_Z:
		for x in range(-75, 131, 10):
			for side in [-1.0, 1.0]:
				var p = Vector3(x, 2, z + side * 17)
				if _site_clear(p):
					_building(p, PI / 2, -side, int(absf(x) / 10 + absf(z) * 0.1 + side * 5))
	# Enclose the square with townhouses instead of ending it in empty grass.
	for x in range(-55, 56, 10):
		var p = Vector3(x, 2, -370)
		if _site_clear(p):
			_building(p, PI / 2, 1, int((x + 55) / 10) + 2)
	for x in [-50.0, 50.0]:
		for z in range(-305, -356, -10):
			var p = Vector3(x, 2, z)
			if _site_clear(p):
				_building(p, 0, signf(x), int(-z / 10 + x / 10))
	_decorate_exposed_walls()
	# Street lamps are actual rigid bodies; visual meshes remain attached to them.
	for x in [-24.0, 24.0, 120.0]:
		for z in range(-15, -300, -24):
			for side in [-1.0, 1.0]:
				var p = Vector3(x + side * 6.6, 2, z)
				if Vector2(p.x, p.z + 320).length() > 34 and _away_from_crossing(p, 7):
					_lamp(p, side)
	_flush_batches()

func _site_clear(p: Vector3) -> bool:
	for parking in stage.clearings:
		if Vector2(p.x - parking.x, p.z - parking.z).length() < 15:
			return false
	for object in obstacles:
		if object.kind == "building":
			var other: Vector3 = object.body.get_parent().position
			if absf(p.x - other.x) < 9.9 and absf(p.z - other.z) < 9.9:
				return false
	return stage.road_distance(p) > 13.0 and Vector2(p.x, p.z + 320).length() > 39

func _away_from_crossing(p: Vector3, margin: float) -> bool:
	for z in CROSS_Z:
		if absf(p.z - z) < margin:
			return false
	return true

func _street(p: Vector3, width: float, length: float, yaw: float, title: String) -> void:
	var root = Node3D.new()
	root.name = title
	stage.add_child(root)
	root.position = p
	root.rotation.y = yaw
	Props.box(root, Vector3(0, 0.03, 0), Vector3(width, 0.06, length), Color("454b50"))
	var vertical = title.begins_with("CityBoulevard")
	var cuts: Array[float] = [-length / 2]
	var crossings: Array[float] = []
	if vertical:
		for z in CROSS_Z:
			crossings.append(z - p.z)
	else:
		for x in [-24.0, 24.0, 120.0]:
			crossings.append(-(x - p.x))
	crossings.sort()
	for crossing in crossings:
		cuts.append(maxf(-length / 2, crossing - 7))
		cuts.append(minf(length / 2, crossing + 7))
	cuts.append(length / 2)
	for i in range(0, cuts.size() - 1, 2):
		var segment_length = cuts[i + 1] - cuts[i]
		if segment_length <= 0:
			continue
		var z = (cuts[i] + cuts[i + 1]) / 2
		for side in [-1.0, 1.0]:
			Props.box(root, Vector3(side * (width / 2 + 1.25), 0.13, z), Vector3(2.5, 0.20, segment_length), Color("adafa9"))
			Props.box(root, Vector3(side * (width / 2 + 0.08), 0.11, z), Vector3(0.16, 0.18, segment_length), Color("d9d8cb"))
			Props.box(root, Vector3(side * (width / 2 - 0.25), 0.07, z), Vector3(0.10, 0.012, segment_length), Color("dddac7"))
	for i in range(int(length / 7)):
		var local = Vector3(0, 0.071, -length / 2 + i * 7 + 3)
		var world = root.transform * local
		var in_crossing = false
		for crossing in crossings:
			in_crossing = in_crossing or absf(local.z - crossing) < 7
		if in_crossing or Vector2(world.x, world.z + 320).length() < 33:
			continue
		Props.box(root, local, Vector3(0.12, 0.012, 3), Color("e6e3d2"))
	if title.begins_with("CityCrossStreet"):
		for x in [-24.0, 24.0, 120.0]:
			for approach in [-1.0, 1.0]:
				for stripe in range(7):
					var world = Vector3(x - 3 + stripe, 2.085, p.z + approach * 6.4)
					var local = root.transform.affine_inverse() * world
					Props.box(root, local, Vector3(2.4, 0.015, 0.5), Color("ece9da"))
	_batch(root, root.transform)

func _building(p: Vector3, yaw: float, side: float, seed_value: int) -> void:
	var root = Node3D.new()
	root.name = "ParisPragueBuilding_%d" % stage.get_child_count()
	stage.add_child(root)
	root.position = p
	root.rotation.y = yaw
	root.set_meta("front_side", side)
	var style = posmod(seed_value, 5)
	var height = 8.5 + style * 1.25
	var width = 10.0
	var depth = 10.0
	var face = -side * (width / 2 + 0.02)
	var body_color = [Color("426956"), Color("d4d4c9"), Color("984d47"), Color("d7b58a"), Color("667989")][style]
	var trim = Color("e5dfcd")
	Props.box(root, Vector3(0, height / 2, 0), Vector3(width, height, depth), body_color)
	for y in [0.22, 2.65, 5.25, 7.85, height]:
		if y <= height:
			Props.box(root, Vector3(face - side * 0.10, y, 0), Vector3(0.22, 0.15, depth + 0.3), trim)
	for z in [-4.6, 4.6]:
		Props.box(root, Vector3(face - side * 0.08, height / 2, z), Vector3(0.15, height, 0.30), trim)
	for floor in range(int(height / 2.6)):
		for z in [-3.1, 0.0, 3.1]:
			var y = 1.4 + floor * 2.6
			Props.box(root, Vector3(face - side * 0.045, y, z), Vector3(0.08, 1.6, 1.35), Color("668595"))
			for dz in [-0.78, 0.78]:
				Props.box(root, Vector3(face - side * 0.12, y, z + dz), Vector3(0.17, 1.86, 0.16), trim)
			for dy in [-0.88, 0.88]:
				Props.box(root, Vector3(face - side * 0.12, y + dy, z), Vector3(0.17, 0.15, 1.7), trim)
			Props.box(root, Vector3(face - side * 0.15, y + 0.2, z), Vector3(0.06, 0.075, 1.35), trim)
			Props.box(root, Vector3(face - side * 0.15, y, z), Vector3(0.06, 1.6, 0.07), trim)
			if floor > 0 and style == 4:
				for dz in [-0.7, -0.35, 0.0, 0.35, 0.7]:
					Props.box(root, Vector3(face - side * 0.6, y - 0.6, z + dz), Vector3(0.06, 0.55, 0.04), Color("303b40"))
				Props.box(root, Vector3(face - side * 0.6, y - 0.35, z), Vector3(0.07, 0.06, 1.6), Color("303b40"))
				Props.box(root, Vector3(face - side * 0.32, y - 0.95, z), Vector3(0.8, 0.14, 1.8), trim)
	# Recessed-looking shopfront, a canopy, and tall entrance steps.
	Props.box(root, Vector3(face - side * 0.05, 1.1, 0), Vector3(0.10, 2.2, 1.45), Color("283c40"))
	Props.box(root, Vector3(face - side * 0.6, 2.5, 0), Vector3(1.25, 0.16, 2.2), trim)
	Props.box(root, Vector3(face - side * 0.45, 0.12, 0), Vector3(1, 0.22, 2.1), Color("b6b4ab"))
	Props.box(root, Vector3(face - side * 0.24, 0.30, 0), Vector3(0.6, 0.20, 1.8), Color("c4c1b6"))
	for z in [-3.1, 3.1]:
		Props.box(root, Vector3(face - side * 0.04, 1.1, z), Vector3(0.12, 1.8, 1.9), Color("4d727c"))
		Props.box(root, Vector3(face - side * 0.25, 2.25, z), Vector3(0.5, 0.18, 2.15), Color("8d6252") if style % 2 else Color("344f42"))
	var roof = MeshInstance3D.new()
	var key = "roof%d" % (style % 2)
	if not meshes.has(key):
		meshes[key] = _roof_mesh(style % 2)
	roof.mesh = meshes[key]
	roof.set_meta("batch_key", key)
	roof.material_override = Props.material(Color("4f5360") if style % 2 else Color("a55842"))
	root.add_child(roof)
	roof.position = Vector3(0, height, 0)
	roof.scale = Vector3(width + 0.45, 2.8 + style * 0.22, depth + 0.35)
	for z in [-3.0, 3.0]:
		Props.box(root, Vector3(-side * 3.5, height + 1.1, z), Vector3(1.1, 1.5, 1.3), trim)
		Props.box(root, Vector3(-side * 4.09, height + 1.15, z), Vector3(0.06, 0.8, 0.8), Color("5d7e92"))
	for x in [-2.2, 2.2]:
		Props.box(root, Vector3(x, height + 2.7, 1.8), Vector3(0.55, 1.5, 0.7), Color("9a8b80"))
	if seed_value % 7 == 0:
		Props.box(root, Vector3(face - side * 0.10, 2.65, 0), Vector3(0.12, 0.35, 3.1), Color("324e63"))
		Props.label_3d(root, Vector3(face - side * 0.18, 2.65, 0), ["BOULANGERIE", "CAFE", "LIBRAIRIE"][style % 3], 28, 0.0035, Color("eee7ce"), -side * PI / 2)
	_solid(root, Vector3(0, height / 2, 0), Vector3(width, height, depth), "building")
	_batch(root, root.transform)

func _decorate_exposed_walls() -> void:
	for object in obstacles:
		if object.kind != "building":
			continue
		var root = object.body.get_parent()
		var height: float = object.half.y * 2
		var front_side: float = root.get_meta("front_side")
		_secondary_facade(root, Vector3(front_side * 5.03, 0, 0), front_side * PI / 2, height)
		for side in [-1.0, 1.0]:
			var neighbor = root.transform * Vector3(0, 0, side * 10)
			var exposed = true
			for other in obstacles:
				if other.kind == "building" and other != object and other.body.get_parent().position.distance_to(neighbor) < 0.2:
					exposed = false
					break
			if exposed:
				_secondary_facade(root, Vector3(0, 0, side * 5.03), 0 if side > 0 else PI, height)
		_batch(root, root.transform)

func _secondary_facade(parent: Node3D, p: Vector3, yaw: float, height: float) -> void:
	var wall = Node3D.new()
	parent.add_child(wall)
	wall.position = p
	wall.rotation.y = yaw
	var trim = Color("ded8c9")
	for floor in range(int(height / 2.6)):
		var y = 1.4 + floor * 2.6
		Props.box(wall, Vector3(0, y + 1.25, 0.08), Vector3(10.1, 0.14, 0.16), trim)
		for x in [-3.1, 0.0, 3.1]:
			Props.box(wall, Vector3(x, y, 0.02), Vector3(1.35, 1.6, 0.08), Color("658390"))
			for dx in [-0.78, 0.78]:
				Props.box(wall, Vector3(x + dx, y, 0.10), Vector3(0.14, 1.86, 0.14), trim)
			for dy in [-0.88, 0.88]:
				Props.box(wall, Vector3(x, y + dy, 0.10), Vector3(1.7, 0.15, 0.14), trim)
			Props.box(wall, Vector3(x, y, 0.14), Vector3(0.07, 1.6, 0.08), trim)

func _roof_mesh(style: int) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a = Vector3(-0.5, 0, -0.5)
	var b = Vector3(0.5, 0, -0.5)
	var c = Vector3(0.5, 0, 0.5)
	var d = Vector3(-0.5, 0, 0.5)
	var vertices: Array = []
	if style == 0:
		var left = Vector3(-0.5, 1, 0)
		var right = Vector3(0.5, 1, 0)
		vertices = [a, b, right, a, right, left, d, left, right, d, right, c, a, left, d, b, c, right]
	else:
		var e = Vector3(-0.30, 0.85, -0.30)
		var f = Vector3(0.30, 0.85, -0.30)
		var g = Vector3(0.30, 0.85, 0.30)
		var h = Vector3(-0.30, 0.85, 0.30)
		vertices = [a, b, f, a, f, e, b, c, g, b, g, f, c, d, h, c, h, g, d, a, e, d, e, h, e, f, g, e, g, h]
	for v in vertices:
		st.add_vertex(v)
	st.generate_normals()
	return st.commit()

func _square() -> void:
	var root = Node3D.new()
	root.name = "CityCentralSquare"
	stage.add_child(root)
	root.position = Vector3(0, 2, -320)
	Props.box(root, Vector3(0, 0.01, -15), Vector3(120, 0.02, 100), Color("b6b1a4"))
	# Annulus, not a disk: the carriageway never cuts through the monument.
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(96):
		var a = i * TAU / 96
		var b = (i + 1) * TAU / 96
		for v in [Vector3(cos(a) * 18.0, 0.08, sin(a) * 18.0), Vector3(cos(a) * 30.5, 0.08, sin(a) * 30.5), Vector3(cos(b) * 18.0, 0.08, sin(b) * 18.0), Vector3(cos(b) * 18.0, 0.08, sin(b) * 18.0), Vector3(cos(a) * 30.5, 0.08, sin(a) * 30.5), Vector3(cos(b) * 30.5, 0.08, sin(b) * 30.5)]:
			st.add_vertex(v)
	st.generate_normals()
	var ring = MeshInstance3D.new()
	root.add_child(ring)
	ring.mesh = st.commit()
	ring.material_override = Props.material(Color("454b50"))
	var island = Props.cylinder(root, Vector3(0, 0.1, 0), 17.6, 17.6, 0.2, Color("879074"), 48)
	island.name = "MonumentIsland"
	for i in range(32):
		var a = i * TAU / 32
		var p = Vector3(cos(a), 0, sin(a)) * 18.1
		var curb = Props.box(root, p + Vector3(0, 0.12, 0), Vector3(0.35, 0.24, 3.5), Color("d9d7c7"))
		curb.rotation.y = -a
		var stripe = Props.box(root, Vector3(cos(a) * 24, 0.10, sin(a) * 24), Vector3(0.12, 0.015, 1.8), Color("e6e2cc"))
		stripe.rotation.y = -a
	var monument = Node3D.new()
	root.add_child(monument)
	monument.name = "VictoryColumn"
	Props.box(monument, Vector3(0, 0.65, 0), Vector3(6.0, 1.3, 6.0), Color("bbb5a4"))
	Props.box(monument, Vector3(0, 1.45, 0), Vector3(4.8, 0.3, 4.8), Color("e2d6c0"))
	Props.box(monument, Vector3(0, 2.6, 0), Vector3(3.2, 2.0, 3.2), Color("bdb8a8"))
	for side in [-1.0, 1.0]:
		Props.box(monument, Vector3(side * 1.62, 2.6, 0), Vector3(0.06, 1.0, 1.2), Color("7a826c"))
	Props.cylinder(monument, Vector3(0, 8.6, 0), 1.1, 0.85, 10, Color("c6c1af"), 16)
	Props.cylinder(monument, Vector3(0, 13.85, 0), 1.35, 1.35, 0.5, Color("ded5bf"), 16)
	var bronze = Color("617969")
	Props.cylinder(monument, Vector3(0, 15.3, 0), 0.75, 0.38, 2.4, bronze, 8)
	Props.cylinder(monument, Vector3(0, 16.85, 0), 0.35, 0.35, 0.7, bronze, 8)
	for side in [-1.0, 1.0]:
		var arm = Props.box(monument, Vector3(side * 0.85, 16.0, 0), Vector3(1.6, 0.20, 0.24), bronze)
		arm.rotation.z = side * 0.5
		var wing = Props.box(monument, Vector3(side * 1.35, 15.9, 0.3), Vector3(2.2, 0.9, 0.15), bronze)
		wing.rotation.z = side * 0.55
	_solid(root, Vector3(0, 9.0, 0), Vector3(6.0, 18.0, 6.0), "monument")
	_solid(root, Vector3(0, 0.05, 0), Vector3(25, 0.2, 25), "island")
	for i in range(8):
		var a = i * TAU / 8
		var p = root.position + Vector3(cos(a) * 42, 0, sin(a) * 42)
		if stage.road_distance(p) > 5.2:
			_lamp(p, 1)
	_batch(root, root.transform)

func _solid(parent: Node3D, center: Vector3, size: Vector3, kind: String) -> void:
	var body = StaticBody3D.new()
	parent.add_child(body)
	body.position = center
	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	obstacles.append({"body": body, "half": size / 2, "kind": kind, "id": -1})

func _lamp(p: Vector3, side: float) -> void:
	var body = RigidBody3D.new()
	body.name = "CityLamp_%d" % lamps.size()
	stage.add_child(body)
	body.position = p + Vector3(0, 2.25, 0)
	body.mass = 28
	body.freeze = true
	body.continuous_cd = true
	var material = PhysicsMaterial.new()
	material.friction = 0.75
	material.bounce = 0.08
	body.physics_material_override = material
	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(0.34, 4.5, 0.34)
	shape.shape = box
	body.add_child(shape)
	Props.cylinder(body, Vector3(0, -2.0, 0), 0.25, 0.18, 0.5, Color("424b4d"), 8)
	Props.cylinder(body, Vector3.ZERO, 0.075, 0.055, 4.0, Color("3d4b50"), 8)
	var arm = Props.box(body, Vector3(side * 0.55, 1.85, 0), Vector3(1.2, 0.08, 0.1), Color("3d4b50"))
	arm.rotation.z = -side * 0.2
	Props.box(body, Vector3(side * 1.0, 1.8, 0), Vector3(0.48, 0.35, 0.48), Color("33454c"))
	var glass = Props.box(body, Vector3(side * 1.0, 1.75, 0), Vector3(0.38, 0.25, 0.38), Color("eadca0"))
	glass.material_override.emission_enabled = true
	glass.material_override.emission = Color("baa86d")
	glass.material_override.emission_energy_multiplier = 0.3
	lamps.append({"body": body, "fallen": false})
	obstacles.append({"body": body, "half": Vector3(0.17, 2.25, 0.17), "kind": "lamp", "id": lamps.size() - 1})

func _relative_pose(node: Node3D) -> Transform3D:
	var pose = node.transform
	var parent = node.get_parent()
	while parent != stage and parent is Node3D:
		pose = parent.transform * pose
		parent = parent.get_parent()
	return pose

func hit(start: Vector3, end: Vector3, radius: float, escape: bool = true, center_offset: Vector3 = Vector3(0, 0.35, 0)) -> Dictionary:
	var result = {}
	var earliest = INF
	for object in obstacles:
		var pose = _relative_pose(object.body)
		var inverse = pose.affine_inverse()
		var a: Vector3 = inverse * (start + center_offset)
		var b: Vector3 = inverse * (end + center_offset)
		var half: Vector3 = object.half + Vector3.ONE * radius
		var travel = b - a
		var inside = absf(a.x) < half.x and absf(a.y) < half.y and absf(a.z) < half.z
		if inside and escape and b.length_squared() > a.length_squared() + 0.0000001 and a.dot(travel) >= 0:
			continue
		var near = 0.0
		var far = 1.0
		var normal = Vector3.ZERO
		var valid = true
		for axis in range(3):
			if absf(travel[axis]) < 0.0000001:
				if absf(a[axis]) > half[axis]:
					valid = false
					break
				continue
			var first = (-half[axis] - a[axis]) / travel[axis]
			var last = (half[axis] - a[axis]) / travel[axis]
			var n = Vector3.ZERO
			n[axis] = -signf(travel[axis])
			if first > last:
				var swap = first
				first = last
				last = swap
			if first > near:
				near = first
				normal = n
			far = minf(far, last)
			if near > far:
				valid = false
				break
		if not valid or near < 0 or near > 1 or near >= earliest:
			continue
		if normal.length_squared() < 0.1:
			normal = -travel.normalized() if travel.length_squared() > 0.000001 else Vector3.RIGHT
		normal = (pose.basis * normal).normalized()
		earliest = near
		result = {"position": start.lerp(end, near) + normal * 0.035, "normal": normal, "kind": object.kind, "id": object.id}
	return result

func knock_lamp(index: int, direction: Vector3) -> bool:
	if index < 0 or index >= lamps.size() or lamps[index].fallen:
		return false
	lamps[index].fallen = true
	var body: RigidBody3D = lamps[index].body
	body.freeze = false
	body.sleeping = false
	var dir = Vector3(direction.x, 0, direction.z).normalized()
	if dir.length_squared() < 0.1:
		dir = Vector3.RIGHT
	body.apply_impulse(dir * 160 + Vector3(0, 25, 0), Vector3(0, 1.8, 0))
	return true

func _physics_process(delta: float) -> void:
	var game = stage.get_parent()
	var simulate = true
	if game != null and game.has_method("player_position"):
		simulate = game.playing and not game.paused and not game.dead and not game.finished and (not game.room.connected or game.room.is_host)
	for i in range(lamps.size()):
		var lamp = lamps[i]
		lamp.body.freeze = not (simulate and lamp.fallen)
		if not simulate and lamp_targets.has(i):
			var target = lamp_targets[i]
			var weight = 1.0 - exp(-delta * 16.0)
			lamp.body.position = lamp.body.position.lerp(target.pos, weight)
			for axis in range(3):
				lamp.body.rotation[axis] = lerp_angle(lamp.body.rotation[axis], target.rot[axis], weight)

func snapshot() -> Array:
	var result = []
	for i in range(lamps.size()):
		if not lamps[i].fallen:
			continue
		var body = lamps[i].body
		result.append({"id": i, "pos": [body.position.x, body.position.y, body.position.z], "rot": [body.rotation.x, body.rotation.y, body.rotation.z]})
	return result

func apply_snapshot(data: Array) -> void:
	for item in data:
		var i = int(item.id)
		if i < 0 or i >= lamps.size():
			continue
		var first = not lamps[i].fallen
		lamps[i].fallen = true
		var body = lamps[i].body
		body.freeze = true
		var target = {"pos": Vector3(item.pos[0], item.pos[1], item.pos[2]), "rot": Vector3(item.rot[0], item.rot[1], item.rot[2])}
		lamp_targets[i] = target
		if first:
			body.position = target.pos
			body.rotation = target.rot

func _batch(parent: Node3D, pose: Transform3D) -> void:
	for child in parent.get_children():
		if child is RigidBody3D or child is StaticBody3D:
			continue
		if child is MeshInstance3D:
			var key = ""
			var scale = Vector3.ONE
			if child.mesh is BoxMesh:
				key = "box"
				scale = child.mesh.size
				if not meshes.has(key):
					var mesh = BoxMesh.new()
					mesh.size = Vector3.ONE
					meshes[key] = mesh
			elif child.mesh is CylinderMesh:
				var mesh = child.mesh
				var ratio = mesh.top_radius / maxf(mesh.bottom_radius, 0.001)
				key = "cylinder_%d_%d" % [mesh.radial_segments, int(ratio * 1000)]
				scale = Vector3(mesh.bottom_radius, mesh.height, mesh.bottom_radius)
				if not meshes.has(key):
					var unit = CylinderMesh.new()
					unit.bottom_radius = 1
					unit.top_radius = ratio
					unit.height = 1
					unit.radial_segments = mesh.radial_segments
					unit.rings = 1
					meshes[key] = unit
			elif child.has_meta("batch_key"):
				key = child.get_meta("batch_key")
			if key != "":
				var transform = pose * child.transform
				transform.basis = transform.basis * Basis.from_scale(scale)
				var cell = Vector2i(floori(transform.origin.x / 64), floori(transform.origin.z / 64))
				var tile = "%s_%d_%d" % [key, cell.x, cell.y]
				if not batches.has(tile):
					batches[tile] = {"key": key, "poses": [], "colors": [], "center": Vector3(cell.x * 64 + 32, 0, cell.y * 64 + 32)}
				batches[tile].poses.append(transform)
				batches[tile].colors.append(child.material_override.albedo_color)
				child.free()
		elif child is Node3D:
			_batch(child, pose * child.transform)

func _flush_batches() -> void:
	var material = Props.material(Color.WHITE)
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for title in batches:
		var data = batches[title]
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = meshes[data.key]
		mm.instance_count = data.poses.size()
		for i in range(data.poses.size()):
			var pose: Transform3D = data.poses[i]
			pose.origin -= data.center
			mm.set_instance_transform(i, pose)
			mm.set_instance_color(i, data.colors[i])
		var node = MultiMeshInstance3D.new()
		node.name = "CityDetail_" + title
		stage.add_child(node)
		node.position = data.center
		node.multimesh = mm
		node.material_override = material
	batches.clear()
