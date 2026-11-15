extends RefCounted
# Keeps rain and snow out of sheltered places (sky_weather.gd's falling drops).
# The drops are GPU particles that know nothing of the scenery, so their
# material (shaders/weather_drop.gdshader) hides every drop below a roof:
#  - a height map of roofs around the falling box: tree crowns (the cone
#    view_clearance.gd uses), the tops of the stage solids (houses, tents,
#    walls, furniture) and hollow interiors under their roofs, redrawn when the
#    box has moved on or a few times a second;
#  - the cars next to the camera, given every frame as boxes, so a driver
#    sees no rain in his own cabin however fast the car goes.
const ViewClearance = preload("res://scripts/player/view_clearance.gd")
const CarHitbox = preload("res://scripts/cars/car_hitbox.gd")
const CarLamps = preload("res://scripts/cars/car_lamps.gd")
const SHADER = preload("res://shaders/weather_drop.gdshader")
# Height map: cells per side, metres per cell; redrawn once the box is this far
# from the map's centre or this many seconds passed (a felled tree, a moved tent).
const CELLS = 96
const CELL = 0.5
const RECENTRE = 6.0
const REFRESH = 1.0
# No roof: far below anything on a stage.
const OPEN = -100000.0
# Cars given to the shader each frame (the uniform arrays' size) and how far
# from the camera they are looked for.
const CARS = 4
const CAR_REACH = 14.0
# A hollow interior without solids inside its walls gets a roof this high.
const ROOF = 6.0

var heights = PackedFloat32Array()
var image: Image
var texture: ImageTexture
var centre = Vector2(INF, INF)
var _clock = 0.0

func _init() -> void:
	heights.resize(CELLS * CELLS)
	heights.fill(OPEN)
	image = Image.create_from_data(CELLS, CELLS, false, Image.FORMAT_RF, heights.to_byte_array())
	texture = ImageTexture.create_from_image(image)

# The drops' material: the look of a raindrop or a snowflake plus the shelter.
func material(color: Color, flake: Texture2D, upright: bool) -> ShaderMaterial:
	var mat = ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("upright", upright)
	if flake != null:
		mat.set_shader_parameter("flake", flake)
	mat.set_shader_parameter("roof", texture)
	_place(mat)
	_cars(mat, [])
	return mat

# Called every frame with the falling box's centre.
func update(mat: ShaderMaterial, stage: Node3D, at: Vector3, camera: Vector3, cars: Array, delta: float) -> void:
	_clock -= delta
	var flat = Vector2(at.x, at.z)
	if stage != null and (_clock <= 0.0 or flat.distance_to(centre) > RECENTRE):
		_clock = REFRESH
		redraw(stage, flat)
		_place(mat)
	_cars(mat, nearest_cars(cars, camera))

# Height of the lowest open air over the cell holding p (OPEN without a roof).
func roof_at(p: Vector3) -> float:
	var cell = _cell(Vector2(p.x, p.z))
	if cell.x < 0 or cell.y < 0 or cell.x >= CELLS or cell.y >= CELLS:
		return OPEN
	return heights[cell.y * CELLS + cell.x]

func redraw(stage: Node3D, at: Vector2) -> void:
	centre = (at / CELL).round() * CELL
	heights.fill(OPEN)
	var half = CELLS * CELL * 0.5
	var low = centre - Vector2(half, half)
	var high = centre + Vector2(half, half)
	_trees(stage, low, high)
	if stage.get("solids") != null:
		_solids(stage, low, high)
	image.set_data(CELLS, CELLS, false, Image.FORMAT_RF, heights.to_byte_array())
	texture.update(image)

func _cell(p: Vector2) -> Vector2i:
	var origin = centre - Vector2.ONE * CELLS * CELL * 0.5
	return Vector2i(floori((p.x - origin.x) / CELL), floori((p.y - origin.y) / CELL))

func _raise(cell: Vector2i, height: float) -> void:
	if cell.x >= 0 and cell.y >= 0 and cell.x < CELLS and cell.y < CELLS:
		var i = cell.y * CELLS + cell.x
		heights[i] = maxf(heights[i], height)

# Under a crown: up to where the cone narrows to the cell's distance from the trunk.
func _trees(stage: Node3D, low: Vector2, high: Vector2) -> void:
	if stage.trees.is_empty():
		return
	for index in stage.trees_near(low, high, 0.0):
		if stage.fallen.has(index):
			continue
		var base: Vector3 = stage.trees[index]
		var height = float(stage.forest_data[index].height) if index < stage.forest_data.size() else 8.0
		var radius = height * ViewClearance.CROWN_RADIUS
		var bottom = base.y + height * ViewClearance.CROWN_BOTTOM
		var top = base.y + height * ViewClearance.CROWN_TOP
		var foot = Vector2(base.x, base.z)
		if foot.x + radius < low.x or foot.x - radius > high.x or foot.y + radius < low.y or foot.y - radius > high.y:
			continue
		var first = _cell(foot - Vector2(radius, radius))
		var last = _cell(foot + Vector2(radius, radius))
		for x in range(first.x, last.x + 1):
			for z in range(first.y, last.y + 1):
				var origin = centre - Vector2.ONE * CELLS * CELL * 0.5
				var distance = foot.distance_to(origin + (Vector2(x, z) + Vector2(0.5, 0.5)) * CELL)
				if distance < radius:
					_raise(Vector2i(x, z), lerpf(top, bottom, distance / radius))

# A solid box shelters the ground under its top; a hollow interior all the
# way up to the highest solid inside its walls.
func _solids(stage: Node3D, low: Vector2, high: Vector2) -> void:
	var solids = stage.solids
	var world: Transform3D = stage.global_transform
	var mid = Vector3((low.x + high.x) * 0.5, 0, (low.y + high.y) * 0.5)
	var ids: Array = solids.candidates(mid, mid, (high.x - low.x) * 0.75)
	var tops: Array = []
	for id in ids:
		var object: Dictionary = solids.obstacles[id]
		if not is_instance_valid(object.body) or not object.has("collision_pose"):
			continue
		var pose: Transform3D = world * (solids.relative_pose(object.body) if object.body is RigidBody3D else object.collision_pose)
		var half: Vector3 = object.half
		tops.append([pose, half])
		_box(pose, half, pose.origin.y + absf(pose.basis.y.y) * half.y + absf(pose.basis.x.y) * half.x + absf(pose.basis.z.y) * half.z)
	for area in solids.interior_footprints:
		var pose: Transform3D = world * area.inverse.affine_inverse()
		var roof = pose.origin.y + ROOF
		for entry in tops:
			var local: Vector3 = area.inverse * (world.affine_inverse() * entry[0].origin)
			if absf(local.x) <= area.half.x + 0.5 and absf(local.z) <= area.half.y + 0.5:
				roof = maxf(roof, entry[0].origin.y + entry[1].y)
		_box(pose, Vector3(area.half.x, 0.0, area.half.y), roof)

func _box(pose: Transform3D, half: Vector3, top: float) -> void:
	var reach = Vector2(half.x, half.z).length()
	var foot = Vector2(pose.origin.x, pose.origin.z)
	var inverse = pose.affine_inverse()
	var first = _cell(foot - Vector2(reach, reach))
	var last = _cell(foot + Vector2(reach, reach))
	var origin = centre - Vector2.ONE * CELLS * CELL * 0.5
	for x in range(maxi(first.x, 0), mini(last.x, CELLS - 1) + 1):
		for z in range(maxi(first.y, 0), mini(last.y, CELLS - 1) + 1):
			var p = origin + (Vector2(x, z) + Vector2(0.5, 0.5)) * CELL
			var local = inverse * Vector3(p.x, pose.origin.y, p.y)
			if absf(local.x) <= half.x + CELL * 0.5 and absf(local.z) <= half.z + CELL * 0.5:
				_raise(Vector2i(x, z), top)

func _place(mat: ShaderMaterial) -> void:
	var size = CELLS * CELL
	mat.set_shader_parameter("roof_area", Vector3(centre.x - size * 0.5, centre.y - size * 0.5, 1.0 / size))

# The closest cars to the camera: the player's own and whoever drives past.
static func nearest_cars(cars: Array, camera: Vector3) -> Array:
	var near: Array = []
	for car in cars:
		if car is Node3D and is_instance_valid(car) and car.is_inside_tree() and car.global_position.distance_to(camera) < CAR_REACH:
			near.append(car)
	near.sort_custom(func(a, b): return a.global_position.distance_squared_to(camera) < b.global_position.distance_squared_to(camera))
	return near.slice(0, CARS)

# Every car's hitbox (car_hitbox.gd) as its inverse pose and half size.
static func _cars(mat: ShaderMaterial, cars: Array) -> void:
	var inverses: Array = []
	var boxes: Array = []
	for i in range(CARS):
		if i < cars.size():
			var car: Node3D = cars[i]
			var box: AABB = CarHitbox.bounds(car)
			var pose = car.global_transform * Transform3D(Basis(), box.get_center())
			inverses.append(Projection(pose.affine_inverse()))
			boxes.append(Vector4(box.size.x * 0.5, box.size.y * 0.5, box.size.z * 0.5, 1.0))
		else:
			inverses.append(Projection())
			boxes.append(Vector4.ZERO)
	mat.set_shader_parameter("car_inverse", inverses)
	mat.set_shader_parameter("car_box", boxes)

static func cars_in(tree: SceneTree) -> Array:
	return tree.get_nodes_in_group(CarLamps.GROUP)
