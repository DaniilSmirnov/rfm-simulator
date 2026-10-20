extends SceneTree
# Diagnostic: lists scenery whose lowest point hangs above the drawn surface.
# --headless --path game --script res://tools/profile/find_floating.gd -- --stage=N
const LIMIT = 0.08

var stage

func _initialize() -> void:
	call_deferred("run")

func arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name): return a.split("=")[1]
	return fallback

func surface(p: Vector3) -> float:
	var h: float = stage.terrain_surface_height(p)
	var s = stage.road_s(p)
	if stage.road_distance(p) < stage.road_width(s) * 0.5 + 0.2:
		h = maxf(h, stage.ground(p) + 0.04)
	return h

func run() -> void:
	var index = int(arg("stage", "0"))
	var game = load("res://scripts/core/game.gd").new()
	game.defer_world = false
	root.add_child(game)
	await process_frame
	game.select_stage(index)
	game.rng.seed = 20261008
	await game.start_game()
	game.paused = false
	for i in range(int(arg("frames", "240"))):
		await physics_frame
	stage = game.stage
	var bounds: Rect2 = stage.biome.world_bounds()
	var pieces: Array = []
	for node in game.find_children("*", "GeometryInstance3D", true, false):
		if not node.is_visible_in_tree(): continue
		var path = str(game.get_path_to(node))
		if "TerrainTile" in path or "Road" in path or "Sky" in path or _skipped(path): continue
		if node is MultiMeshInstance3D and node.multimesh != null and node.multimesh.mesh != null:
			var verts = _unique(node.multimesh.mesh.get_faces())
			var count = node.multimesh.visible_instance_count if node.multimesh.visible_instance_count >= 0 else node.multimesh.instance_count
			for i in range(count):
				var t: Transform3D = node.global_transform * node.multimesh.get_instance_transform(i)
				_piece(pieces, path, t, verts, bounds)
		elif node is MeshInstance3D and node.mesh != null:
			var box: AABB = node.global_transform * node.get_aabb()
			if box.size.x > 80 or box.size.z > 80: continue
			for part in _components(node.mesh):
				_piece(pieces, path, node.global_transform, part, bounds)
	# Touching pieces form one object (a roof on its walls, a pot on a table).
	var parent = PackedInt32Array()
	var cells = {}
	for i in range(pieces.size()):
		parent.append(i)
		var box: AABB = pieces[i].box.grow(0.03)
		for x in range(floori(box.position.x / 4), floori(box.end.x / 4) + 1):
			for z in range(floori(box.position.z / 4), floori(box.end.z / 4) + 1):
				var c = Vector2i(x, z)
				if not cells.has(c): cells[c] = []
				for j in cells[c]:
					if pieces[j].box.grow(0.03).intersects(box):
						var a = _root(parent, i)
						var b = _root(parent, j)
						if a != b: parent[b] = a
				cells[c].append(i)
	var objects = {}
	for i in range(pieces.size()):
		var r = _root(parent, i)
		if not objects.has(r): objects[r] = {"gap": INF, "names": {}, "size": 0, "top": -INF}
		var o = objects[r]
		o.size += 1
		o.names[pieces[i].key] = true
		o.top = maxf(o.top, pieces[i].top)
		if pieces[i].gap < o.gap:
			o.gap = pieces[i].gap
			o.at = pieces[i].at
	var list = []
	var buried = []
	for o in objects.values():
		if o.gap > LIMIT and o.gap < 6.0: list.append(o)
		if o.top < 0.03: buried.append(o)
	print("BURIED stage=%d count=%d" % [index, buried.size()])
	for o in buried.slice(0, 30):
		print("  top %.3f m at %s %s" % [o.top, o.at, " | ".join(o.names.keys().slice(0, 2))])
	list.sort_custom(func(a, b): return a.gap > b.gap)
	print("FLOATING stage=%d pieces=%d objects=%d floating=%d" % [index, pieces.size(), objects.size(), list.size()])
	for o in list:
		var q = Vector3(o.at)
		print("  %.3f m at %s parts=%d ground-drawn=%.2f past_edge=%.1f %s" % [o.gap, o.at, o.size, stage.ground(q) - stage.terrain_surface_height(q), float(stage.route_nearest(q).distance) - stage.road_width(float(stage.route_nearest(q).s)) * 0.5, " | ".join(o.names.keys().slice(0, 2))])
	quit()

# Tree layers stand on the drawn land by construction; their crowns and
# steam, smoke or laundry hang in the air on purpose.
func _skipped(path: String) -> bool:
	for word in ["Tree", "Spruce", "Birch", "Cypress", "Oak", "Pine", "ForestLayer", "Steam", "Laundry", "Smoke"]:
		if word in path: return true
	return false

func _piece(pieces: Array, key: String, t: Transform3D, verts: PackedVector3Array, bounds: Rect2) -> void:
	var gap = INF
	var top = -INF
	var at = Vector3.ZERO
	var box = AABB()
	var first = true
	for v in verts:
		var p: Vector3 = t * v
		if not bounds.has_point(Vector2(p.x, p.z)): return
		if first:
			box = AABB(p, Vector3.ZERO)
			first = false
		else:
			box = box.expand(p)
		var g = p.y - surface(p)
		top = maxf(top, g)
		if g < gap:
			gap = g
			at = p
	if first: return
	pieces.append({"key": "/".join(key.split("/").slice(-4)), "box": box, "gap": gap, "top": top, "at": Vector3i(at)})

func _unique(faces: PackedVector3Array) -> PackedVector3Array:
	var seen = {}
	var out = PackedVector3Array()
	for v in faces:
		var q = Vector3i(v * 1000)
		if seen.has(q): continue
		seen[q] = true
		out.append(v)
	return out

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
