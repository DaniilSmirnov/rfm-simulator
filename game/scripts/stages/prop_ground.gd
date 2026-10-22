extends Node3D
# Shared collision tiles for the sampled terrain, rocks and instanced trunks.
const RoadCut = preload("res://scripts/stages/road_cut.gd")
const TILE = 16
const STEP = 0.5
var stage
var tiles: Dictionary = {}
var trunks: Dictionary = {}
var rock_bodies: Dictionary = {}
var floors: Dictionary = {}

func ensure_at(at: Vector3, reach: float) -> void:
	var low = Vector2i(floori((at.x - reach) / TILE), floori((at.z - reach) / TILE))
	var high = Vector2i(floori((at.x + reach) / TILE), floori((at.z + reach) / TILE))
	for x in range(low.x, high.x + 1):
		for z in range(low.y, high.y + 1):
			var key = Vector2i(x, z)
			if not tiles.has(key): _tile(key)
	# Standing trunks never move: only felled ones are posed (setting a pose,
	# even the same one, wakes every prop leaning on the trunk).
	for index in trunks.keys():
		if index < stage.trees.size() and not stage.fallen.has(index):
			continue
		if index >= stage.trees.size() or stage.fallen.get(index, {}).get("dynamic", false):
			trunks[index].queue_free()
			trunks.erase(index)
			continue
		var trunk: StaticBody3D = trunks[index]
		var base: Vector3 = stage.trees[index]
		var length = float(stage.forest_data[index].height) * 0.64 if index < stage.forest_data.size() else 8.0
		var axis: Vector3 = stage.fallen_basis(index) * Vector3.UP
		var pose = Transform3D(Basis(Quaternion(Vector3.UP, axis)), base + axis * length * 0.5)
		if not trunk.global_transform.is_equal_approx(pose):
			trunk.global_transform = pose

# The ground under built tiles changed (a shovel dug the snow): a stale tile
# kept the old snow surface, and a prop placed in the pit sat below it and fell
# through the world.
func reshape(area: Rect2) -> void:
	area = area.grow(STEP)
	for x in range(floori(area.position.x / TILE), floori(area.end.x / TILE) + 1):
		for z in range(floori(area.position.y / TILE), floori(area.end.y / TILE) + 1):
			var key = Vector2i(x, z)
			if tiles.has(key):
				tiles[key].get_child(0).shape.map_data = _heights(_origin(key))

func _origin(key: Vector2i) -> Vector3:
	return Vector3(key.x * TILE + TILE / 2, 0, key.y * TILE + TILE / 2)

# Beside the road the land is drawn below ground() (road_cut.gd): a prop
# knocked onto the verge rests on what is drawn, not in the air above it.
# On snowy stages the verge is a snowbank, drawn where ground() puts it.
func _heights(origin: Vector3) -> PackedFloat32Array:
	var count = int(TILE / STEP) + 1
	var heights = PackedFloat32Array()
	var cut: bool = stage.has_method("route_nearest") and not stage.has_snow
	var memo: Dictionary = {}
	for z in range(count):
		for x in range(count):
			var p = origin + Vector3(x * STEP - TILE / 2, 0, z * STEP - TILE / 2)
			heights.append(stage.ground(p) - (RoadCut.under(stage, p, memo) if cut else 0.0))
	return heights

func _tile(key: Vector2i) -> void:
	var origin = _origin(key)
	var count = int(TILE / STEP) + 1
	var shape = HeightMapShape3D.new()
	shape.map_width = count
	shape.map_depth = count
	shape.map_data = _heights(origin)
	var tile = _collider(shape, Vector3.ZERO)
	tile.scale = Vector3(STEP, 1, STEP)
	tile.global_position = origin
	tiles[key] = tile
	var tile_bounds = AABB(origin - Vector3(TILE / 2, 10000, TILE / 2), Vector3(TILE, 20000, TILE))
	for index in range(stage.rocks.size()):
		var rock: Dictionary = stage.rocks[index]
		if rock_bodies.has(index) or rock.has("actor"): continue
		var p: Vector3 = rock.pos
		var radius = float(rock.radius)
		if not tile_bounds.intersects(AABB(p - Vector3(radius, 0, radius), Vector3(radius * 2, rock.height, radius * 2))): continue
		var cylinder = CylinderShape3D.new()
		cylinder.radius = radius
		cylinder.height = maxf(0.03, rock.height)
		rock_bodies[index] = _collider(cylinder, p + Vector3.UP * float(rock.height) * 0.5)
	for index in range(stage.solids.walk_surfaces.size()):
		var surface: Dictionary = stage.solids.walk_surfaces[index]
		if floors.has(index): continue
		var half: Vector2 = surface.half
		var bounds: AABB = surface.pose * AABB(Vector3(-half.x, -0.16, -half.y), Vector3(half.x * 2, maxf(0.16, surface.rise), half.y * 2))
		if not tile_bounds.intersects(bounds): continue
		floors[index] = true
		var steps = maxi(1, int(surface.get("steps", 0)))
		for i in range(steps):
			var box = BoxShape3D.new()
			box.size = Vector3(half.x * 2, 0.16, half.y * 2 / steps)
			var offset = Vector3(0, surface.rise * float(i + 1) / steps - 0.08, -half.y + half.y * (2 * i + 1) / steps)
			var floor_body = _collider(box, Vector3.ZERO)
			floor_body.global_transform = surface.pose * Transform3D(Basis.IDENTITY, offset)
	# Tiles and the stage's tree cells share one 16 m grid: only this cell's trees.
	if stage.indexed_tree_count != stage.trees.size():
		stage._rebuild_tree_index()
	for index in stage.tree_cells.get(key, []):
		var p: Vector3 = stage.trees[index]
		if trunks.has(index) or stage.fallen.get(index, {}).get("dynamic", false) or Vector2i(floori(p.x / TILE), floori(p.z / TILE)) != key: continue
		_trunk(index)

func _trunk(index: int) -> void:
	var shape_tree = CapsuleShape3D.new()
	shape_tree.radius = 0.2
	shape_tree.height = float(stage.forest_data[index].height) * 0.64 if index < stage.forest_data.size() else 8.0
	trunks[index] = _collider(shape_tree, stage.trees[index] + Vector3.UP * shape_tree.height * 0.5)

# A felled tree stood back up (fallen_trees.gd raise) gets its upright trunk
# again where its tile is already built; an unbuilt tile adds it when built.
func stand(index: int) -> void:
	if trunks.has(index):
		trunks[index].queue_free()
		trunks.erase(index)
	var p: Vector3 = stage.trees[index]
	if tiles.has(Vector2i(floori(p.x / TILE), floori(p.z / TILE))):
		_trunk(index)

func _collider(shape: Shape3D, at: Vector3) -> StaticBody3D:
	var body = StaticBody3D.new()
	body.collision_layer = 1 << 12
	body.collision_mask = 1
	var collider = CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	add_child(body)
	body.global_position = at
	return body
