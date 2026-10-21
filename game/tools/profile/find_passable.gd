extends SceneTree
# Diagnostic: visible scenery a car or a walker passes through, and colliders
# with nothing drawn where they stand (invisible walls).
# Needs a real renderer for MultiMesh transforms, e.g. under xvfb-run:
# --path game --rendering-method gl_compatibility --script res://tools/profile/find_passable.gd -- --stage=N
# Objects lower than STEP above the ground are driven and stepped over.
const STEP = 0.35
const SAMPLE = 0.3

var stage
var game

func _initialize() -> void:
	call_deferred("run")

func arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name): return a.split("=")[1]
	return fallback

func run() -> void:
	var index = int(arg("stage", "0"))
	game = load("res://scripts/core/game.gd").new()
	game.defer_world = false
	root.add_child(game)
	await process_frame
	game.select_stage(index)
	game.rng.seed = 20261008
	await game.start_game()
	game.paused = false
	for i in range(int(arg("frames", "120"))):
		await physics_frame
	stage = game.stage
	var bounds: Rect2 = stage.biome.world_bounds()
	var pieces: Array = []
	for node in game.find_children("*", "GeometryInstance3D", true, false):
		if not node.is_visible_in_tree(): continue
		var path = str(game.get_path_to(node))
		if _ignored(path): continue
		var owner_name = _owner(node)
		if node is MultiMeshInstance3D and node.multimesh != null and node.multimesh.mesh != null:
			var box: AABB = node.multimesh.mesh.get_aabb()
			var count = node.multimesh.visible_instance_count if node.multimesh.visible_instance_count >= 0 else node.multimesh.instance_count
			for i in range(count):
				var t: Transform3D = node.global_transform * node.multimesh.get_instance_transform(i)
				_piece(pieces, path, owner_name, t * box, bounds)
		elif node is MeshInstance3D and node.mesh != null:
			var box: AABB = node.global_transform * node.get_aabb()
			if box.size.x < 4 and box.size.z < 4:
				_piece(pieces, path, owner_name, box, bounds)
				continue
			for part in _components(node.mesh):
				var first = true
				var b = AABB()
				for v in part:
					var p: Vector3 = node.global_transform * v
					if first: b = AABB(p, Vector3.ZERO); first = false
					else: b = b.expand(p)
				_piece(pieces, path, owner_name, b, bounds)
	print("STAGE %d pieces=%d solids=%d rocks=%d trees=%d" % [index, pieces.size(), stage.solids.obstacles.size(), stage.rocks.size(), stage.trees.size()])
	_report_passable(pieces)
	_report_invisible(pieces)
	quit()

func _ignored(path: String) -> bool:
	for word in ["TerrainTile", "Terrain", "Road", "Sky", "Horizon", "Cloud"]:
		if word in path: return true
	return path.get_file() in ["Water", "Lake", "LakeWater", "Lakes"]

# Soft or moving things: plants, people, animals and cars collide elsewhere.
func _soft(path: String, owner_name: String) -> bool:
	if _plant(path): return true
	for word in ["PlayerCar", "Police", "Crew", "Wheel", "Villager", "Arm/", "Leg/", "Head/", "Torso", "Forearm", "Shin", "Ambulance", "Racer", "Remote"]:
		if word in path: return true
	for word in ["character", "car", "medic", "camel", "kangaroo", "people", "spectator", "official", "radio", "bird"]:
		if word in owner_name: return true
	return false

func _plant(path: String) -> bool:
	for word in ["Grass", "Flower", "Bush", "Pebble", "Reed", "Shrub", "Saltbush", "Tussock", "Wormwood", "Berr", "Mushroom", "FlyAgaric", "Leaves", "Grapes", "Sunflower", "Smoke", "Steam", "Laundry", "Flag", "Decal", "Shadow", "Dust", "Track", "Puddle", "Snowbank", "Tamarisk", "Twigs"]:
		if word in path: return true
	return false

func _owner(node: Node) -> String:
	var n = node
	while n != null and n != game:
		var script = n.get_script()
		if script != null: return script.resource_path.get_file().get_basename()
		n = n.get_parent()
	return "-"

func _piece(pieces: Array, path: String, owner_name: String, box: AABB, bounds: Rect2) -> void:
	var c = box.get_center()
	if not bounds.has_point(Vector2(c.x, c.z)): return
	var ground: float = stage.ground(c)
	var parts = path.split("/")
	var name = "/".join(parts.slice(-2)) if parts[-1].begins_with("Baked") or parts[-1].begins_with("@") else parts[-1]
	name = name.get_slice("_Tile", 0)
	for i in range(10): name = name.replace(str(i), "")
	var reach = absf(c.x) < 186 and box.end.y > ground + STEP and box.position.y < ground + 1.6
	pieces.append({"key": "%s:%s" % [owner_name, name], "box": box, "ground": ground, "solid": reach and not _soft(path, owner_name), "hard": not _plant(path), "path": "/".join(path.split("/").slice(-3))})

func _blocked(p: Vector3) -> String:
	var g: float = stage.ground(p)
	var at = Vector3(p.x, g, p.z)
	var e = Vector3(0.01, 0, 0)
	if not stage.solids.hit(at - e, at + e, SAMPLE, false).is_empty(): return "solid"
	if not stage.rock_hit(at - e, at + e, SAMPLE, false).is_empty(): return "rock"
	if stage.obstacle_hit(at - e, at + e, SAMPLE) >= 0: return "tree"
	if stage.biome.walk_blocked(at, g - 0.5): return "walk"
	return ""

func _report_passable(pieces: Array) -> void:
	var objects = {}
	for piece in pieces:
		if not piece.solid: continue
		var box: AABB = piece.box
		var footprint = Vector2(box.size.x, box.size.z)
		if footprint.x < 0.08 and footprint.y < 0.08: continue
		var hits = 0
		var total = 0
		var c = box.get_center()
		for fx in [0.5, 0.25, 0.75]:
			for fz in [0.5, 0.25, 0.75]:
				var p = Vector3(box.position.x + box.size.x * fx, 0, box.position.z + box.size.z * fz)
				total += 1
				if _blocked(p) != "": hits += 1
		var key = "%s" % piece.key
		if hits > 0:
			if footprint.x < 2.0 or footprint.y < 2.0: continue
			var inner = 0
			for fx in [0.3, 0.4, 0.5, 0.6, 0.7]:
				for fz in [0.3, 0.4, 0.5, 0.6, 0.7]:
					if _blocked(Vector3(box.position.x + box.size.x * fx, 0, box.position.z + box.size.z * fz)) != "": inner += 1
			if inner >= 12: continue
			key = "PARTIAL %d/25 %s" % [inner, key]
		var cell = Vector3i(roundi(c.x), 0, roundi(c.z))
		var near = stage.route_nearest(c)
		var edge = float(near.distance) - stage.road_width(float(near.s)) * 0.5
		if edge > 60: continue
		if OS.get_cmdline_user_args().has("--sizes"):
			var dims = [snappedf(box.size.x, 0.1), snappedf(box.size.y, 0.1), snappedf(box.size.z, 0.1)]
			dims.sort()
			key = "%s %s" % [key, dims]
		if not objects.has(key): objects[key] = []
		objects[key].append("%s %s h=%.1f w=%.1fx%.1f edge=%.0f" % [piece.path, cell, box.end.y - piece.ground, box.size.x, box.size.z, edge])
	print("PASSABLE kinds=%d" % objects.size())
	var keys = objects.keys()
	keys.sort()
	for key in keys:
		print("  %4d  %s  e.g. %s" % [objects[key].size(), key, " ; ".join(objects[key].slice(0, 3))])

func _report_invisible(pieces: Array) -> void:
	var cells = {}
	for i in range(pieces.size()):
		var box: AABB = pieces[i].box
		for x in range(floori(box.position.x / 8), floori(box.end.x / 8) + 1):
			for z in range(floori(box.position.z / 8), floori(box.end.z / 8) + 1):
				var k = Vector2i(x, z)
				if not cells.has(k): cells[k] = []
				cells[k].append(i)
	var found = 0
	print("INVISIBLE")
	var solids = stage.solids
	for object in solids.obstacles:
		if not is_instance_valid(object.body): continue
		var pose: Transform3D = solids.relative_pose(object.body)
		var box: AABB = (stage.global_transform * pose) * AABB(-object.half, object.half * 2.0)
		if not _covered(box.grow(0.05), pieces, cells):
			found += 1
			print("  solid %s kind=%s at %s size %s path=%s" % [found, object.kind, Vector3i(box.get_center()), box.size, game.get_path_to(object.body)])
	for rock in stage.rocks:
		var r = float(rock.radius)
		var box = AABB(rock.pos - Vector3(r, 0.5, r), Vector3(r * 2, float(rock.height) + 0.5, r * 2))
		if rock.has("actor"): continue
		if not _covered(box, pieces, cells):
			found += 1
			print("  rock r=%.2f h=%.2f at %s flags=%s" % [r, float(rock.height), Vector3i(rock.pos), rock.keys()])
	print("INVISIBLE total=%d" % found)

func _covered(box: AABB, pieces: Array, cells: Dictionary) -> bool:
	for x in range(floori(box.position.x / 8), floori(box.end.x / 8) + 1):
		for z in range(floori(box.position.z / 8), floori(box.end.z / 8) + 1):
			for i in cells.get(Vector2i(x, z), []):
				if pieces[i].hard and pieces[i].box.intersects(box): return true
	return false

# Merged meshes hold many objects: split them by shared vertex positions.
func _components(mesh: Mesh) -> Array:
	var faces = mesh.get_faces()
	if faces.size() > 600000: return []
	var ids = {}
	var parent = PackedInt32Array()
	var points = PackedVector3Array()
	var tri_ids = PackedInt32Array()
	for v in faces:
		var q = Vector3i(v * 200)
		if not ids.has(q):
			ids[q] = points.size()
			points.append(v)
			parent.append(points.size() - 1)
		tri_ids.append(ids[q])
	for i in range(0, tri_ids.size(), 3):
		var a = _root(parent, tri_ids[i])
		for j in [1, 2]:
			var b = _root(parent, tri_ids[i + j])
			if a != b: parent[b] = a
	var groups = {}
	for i in range(points.size()):
		var r = _root(parent, i)
		if not groups.has(r): groups[r] = PackedVector3Array()
		groups[r].append(points[i])
	return groups.values()

func _root(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i
