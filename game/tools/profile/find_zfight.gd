extends SceneTree
# Diagnostic: faces that flicker (z-fighting). Two triangles that face the
# same way, lie within GAP metres of each other and overlap, drawn in
# different colours, swap in the depth buffer as the camera moves: with the
# camera's near plane of 0.1 m a 24-bit depth buffer resolves about 2.5 cm
# at 200 m and 10 cm at 400 m, so cm-thin trims flicker from across the pit.
# --path game --script res://tools/profile/find_zfight.gd -- --stage=N [--gap=0.06] [--min-area=0.02]
# MultiMesh transforms need a real renderer, so for scenery batches run it
# under xvfb-run with --rendering-method gl_compatibility.
const CELL = 16.0
const BAND = 0.1

var gap := 0.06
var min_area := 0.02
# Triangles: world vertices, unit normal, plane offset, colour, owner path.
var tris: Array = []
var buckets: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name): return a.split("=")[1]
	return fallback

func run() -> void:
	var index = int(arg("stage", "0"))
	gap = float(arg("gap", "0.06"))
	min_area = float(arg("min-area", "0.02"))
	var game = load("res://scripts/core/game.gd").new()
	game.defer_world = false
	root.add_child(game)
	await process_frame
	game.select_stage(index)
	game.rng.seed = 20261008
	await game.start_game()
	for i in range(10):
		await process_frame
	for node in game.find_children("*", "GeometryInstance3D", true, false):
		if not node.is_visible_in_tree(): continue
		var path = str(game.get_path_to(node))
		if node is MultiMeshInstance3D and node.multimesh != null and node.multimesh.mesh != null:
			var mm: MultiMesh = node.multimesh
			var count = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			for i in range(count):
				_collect(mm.mesh, node, node.global_transform * mm.get_instance_transform(i), "%s#%d" % [path, i])
		elif node is MeshInstance3D and node.mesh != null:
			_collect(node.mesh, node, node.global_transform, path)
	var hits: Dictionary = {}
	for key in buckets:
		var here: Array = buckets[key]
		var above: Array = buckets.get(Vector4i(key.x, key.y, key.z, key.w + 1), [])
		for i in range(here.size()):
			for j in range(i + 1, here.size()):
				_compare(here[i], here[j], hits)
			for other in above:
				_compare(here[i], other, hits)
	var rows: Array = hits.values()
	rows.sort_custom(func(a, b): return a.area > b.area)
	print("STAGE %d triangles=%d flickering pairs=%d (gap < %.3f m, overlap > %.3f m2)" % [index, tris.size(), rows.size(), gap, min_area])
	for row in rows.slice(0, int(arg("limit", "60"))):
		print("ZFIGHT gap=%.3f area=%.2f at %s\n  %s\n  %s" % [row.gap, row.area, row.at.snapped(Vector3.ONE * 0.1), row.a, row.b])
	print("ZFIGHT RESULT: %d" % rows.size())
	quit()

func _color(node: GeometryInstance3D, mesh: Mesh, surface: int) -> Color:
	var material = node.material_override
	if material == null and node is MeshInstance3D: material = node.get_active_material(surface)
	if material == null: material = mesh.surface_get_material(surface)
	return material.albedo_color if material is BaseMaterial3D else Color.WHITE

func _collect(mesh: Mesh, node: GeometryInstance3D, t: Transform3D, path: String) -> void:
	for s in range(mesh.get_surface_count()):
		var arrays = mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors = arrays[Mesh.ARRAY_COLOR]
		var indices = arrays[Mesh.ARRAY_INDEX]
		var base = _color(node, mesh, s)
		var count = indices.size() if indices != null and indices.size() > 0 else verts.size()
		for k in range(0, count - 2, 3):
			var ids = [indices[k], indices[k + 1], indices[k + 2]] if indices != null and indices.size() > 0 else [k, k + 1, k + 2]
			var a: Vector3 = t * verts[ids[0]]
			var b: Vector3 = t * verts[ids[1]]
			var c: Vector3 = t * verts[ids[2]]
			var cross = (b - a).cross(c - a)
			if cross.length() < 0.002: continue
			var color = base
			if colors != null and colors.size() > 0:
				color = base * ((colors[ids[0]] + colors[ids[1]] + colors[ids[2]]) / 3.0)
			# Godot's front faces wind clockwise; only the direction matters here.
			var n = cross.normalized()
			_insert({"v": [a, b, c], "n": n, "d": n.dot(a), "color": color, "path": path, "id": tris.size()})

func _insert(tri: Dictionary) -> void:
	tris.append(tri)
	var nk = Vector3i((tri.n * 40.0).round())
	var band = int(floor(tri.d / BAND))
	var box = AABB(tri.v[0], Vector3.ZERO).expand(tri.v[1]).expand(tri.v[2])
	var lo = Vector3i((box.position / CELL).floor())
	var hi = Vector3i((box.end / CELL).floor())
	if (hi - lo).length_squared() > 12: return  # huge triangles: ground planes, skip
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				var key = Vector4i(nk.x * 1000003 + nk.y * 1009 + nk.z, x * 100003 + y, z, band)
				if not buckets.has(key): buckets[key] = []
				buckets[key].append(tri)

func _compare(a: Dictionary, b: Dictionary, hits: Dictionary) -> void:
	var separation = absf(a.d - b.d)
	if separation > gap or a.n.dot(b.n) < 0.999: return
	var ca: Color = a.color
	var cb: Color = b.color
	if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) < 0.06: return
	var area = _overlap(a, b)
	if area < min_area: return
	var only = arg("filter", "")
	if only != "" and not (only in a.path or only in b.path): return
	if arg("detail", "") != "":
		print("PAIR gap=%.3f area=%.2f %s n=%s %s / %s  %s | %s" % [separation, area, ((a.v[0] + a.v[1] + a.v[2]) / 3.0).snapped(Vector3.ONE * 0.01), a.n.snapped(Vector3.ONE * 0.01), ca.to_html(false), cb.to_html(false), a.path, b.path])
	var key = a.path + " | " + b.path if a.path < b.path else b.path + " | " + a.path
	var row = hits.get(key)
	if row == null:
		row = {"a": a.path, "b": b.path, "gap": separation, "area": 0.0, "at": (a.v[0] + a.v[1] + a.v[2]) / 3.0}
		hits[key] = row
	row.gap = minf(row.gap, separation)
	row.area += area

# Overlap of two near-coplanar triangles, estimated by sampling one inside the other.
func _overlap(a: Dictionary, b: Dictionary) -> float:
	var n: Vector3 = a.n
	var u = n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var w = n.cross(u)
	var pa = a.v.map(func(p): return Vector2(p.dot(u), p.dot(w)))
	var pb = b.v.map(func(p): return Vector2(p.dot(u), p.dot(w)))
	var ra = Rect2(pa[0], Vector2.ZERO).expand(pa[1]).expand(pa[2])
	var rb = Rect2(pb[0], Vector2.ZERO).expand(pb[1]).expand(pb[2])
	if not ra.intersects(rb): return 0.0
	var area_a = absf((pa[1] - pa[0]).cross(pa[2] - pa[0])) * 0.5
	var area_b = absf((pb[1] - pb[0]).cross(pb[2] - pb[0])) * 0.5
	var small = pa if area_a <= area_b else pb
	var big = pb if area_a <= area_b else pa
	var inside = 0
	var samples = 0
	for i in range(1, 6):
		for j in range(1, 6 - i):
			var s = float(i) / 6.0
			var t = float(j) / 6.0
			var p = small[0] + (small[1] - small[0]) * s + (small[2] - small[0]) * t
			samples += 1
			if Geometry2D.point_is_inside_triangle(p, big[0], big[1], big[2]): inside += 1
	return minf(area_a, area_b) * inside / maxf(samples, 1)
