extends RefCounted
# Bounded, shared compaction field. Only the host stamps; prediction reads it.
const CELL = 2.0
const MAX_CELLS = 768
const MAX_DUG = 256
var dug: Dictionary = {}
var cells: Dictionary = {}
var dirty: Dictionary = {}
var chunks: Dictionary = {}
var authoritative = true
var refresh_clock = 0.0

static func depth(stage, point: Vector3) -> float:
	if not stage.winter: return 0.0
	var outside: float = stage.road_distance(point) - (stage.WIDTH * 0.5 + 0.15 + 1.9)
	var result = smoothstep(0.0, 3.0, outside) * (0.78 + sin(point.x * 0.041 + point.z * 0.029) * 0.10)
	for clearing in stage.clearings:
		result *= smoothstep(7.0, 13.0, Vector2(point.x - clearing.x, point.z - clearing.z).length())
	return result

func packed(point: Vector3) -> float:
	var coordinate = Vector2(point.x, point.z) / CELL
	var cell = Vector2i(floori(coordinate.x), floori(coordinate.y))
	var fraction = coordinate - Vector2(cell)
	return lerpf(lerpf(float(cells.get(cell, 0)), float(cells.get(cell + Vector2i.RIGHT, 0)), fraction.x), lerpf(float(cells.get(cell + Vector2i.DOWN, 0)), float(cells.get(cell + Vector2i.ONE, 0)), fraction.x), fraction.y)

func mark(cell: Vector2i) -> void:
	for x in [-CELL, CELL]:
		for z in [-CELL, CELL]:
			dirty[Vector2i(floori((cell.x * CELL + x) / 64.0), floori((cell.y * CELL + z) / 64.0))] = true

func stamp(stage, point: Vector3, pressure: float) -> void:
	if not authoritative or loose_depth(stage, point) < 0.02: return
	var center = Vector2i(roundi(point.x / CELL), roundi(point.z / CELL))
	for x in range(-1, 2):
		for z in range(-1, 2):
			var cell = center + Vector2i(x, z)
			var distance = Vector2(cell.x * CELL - point.x, cell.y * CELL - point.z).length()
			var weight = maxf(0.0, 1.0 - distance / 2.2)
			if weight <= 0: continue
			var value = minf(1.0, float(cells.get(cell, 0)) + pressure * weight)
			if value == float(cells.get(cell, 0)): continue
			if not cells.has(cell) and cells.size() >= MAX_CELLS:
				var oldest = cells.keys()[0]
				cells.erase(oldest)
				mark(oldest)
			cells[cell] = value
			mark(cell)

func contact(stage, point: Vector3) -> float:
	if is_dug(stage, point): return floor_height(stage, point)
	var thickness = depth(stage, point)
	if thickness <= 0.001: return stage.ground(point)
	var compression = packed(point)
	# The visible surface drops with compaction, while tyre support gets firmer.
	return stage.terrain_surface_height(point) - thickness * (0.28 * compression + lerpf(0.65, 0.08, compression))

func register_chunk(stage, tile: Vector2i, node: MeshInstance3D) -> void:
	var arrays = node.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var depths = PackedFloat32Array()
	for vertex in vertices: depths.append(depth(stage, vertex))
	var borders: Dictionary = {}
	for i in range(vertices.size()):
		var point = vertices[i]
		var x = floorf(point.x / 4.0) * 4.0
		var z = floorf(point.z / 4.0) * 4.0
		var a = point
		var b = point
		if not is_equal_approx(point.x, x) and is_equal_approx(point.z, z) and maxf(stage.terrain_tile_step(x, z - 4), stage.terrain_tile_step(x, z)) == 4:
			a.x = x
			b.x = x + 4
		elif not is_equal_approx(point.z, z) and is_equal_approx(point.x, x) and maxf(stage.terrain_tile_step(x - 4, z), stage.terrain_tile_step(x, z)) == 4:
			a.z = z
			b.z = z + 4
		else: continue
		borders[i] = [a, b, depth(stage, a), depth(stage, b)]
	chunks[tile] = {"node": node, "arrays": arrays, "depths": depths, "borders": borders, "stage": weakref(stage)}
	if not cells.is_empty() or not dug.is_empty(): dirty[tile] = true

func update(delta: float) -> void:
	refresh_clock += delta
	if refresh_clock < 0.5: return
	refresh_clock = 0.0
	var count = 0
	for tile in dirty.keys():
		dirty.erase(tile)
		if not chunks.has(tile): continue
		var chunk: Dictionary = chunks[tile]
		var stage = chunk.stage.get_ref()
		var arrays: Array = chunk.arrays.duplicate()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX].duplicate()
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR].duplicate()
		var excavated = false
		for i in range(vertices.size()):
			if i % 3 == 0:
				excavated = is_dug(stage, (vertices[i] + vertices[i + 1] + vertices[i + 2]) / 3.0)
			var compression = packed(vertices[i])
			var depression: float = chunk.depths[i] * 0.28 * compression
			if chunk.borders.has(i):
				var border: Array = chunk.borders[i]
				depression = (border[2] * packed(border[0]) + border[3] * packed(border[1])) * 0.14
			if excavated:
				depression = chunk.depths[i]
				colors[i] = Color("62594b")
			vertices[i].y -= depression
			colors[i] = colors[i].darkened(compression * 0.10)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_COLOR] = colors
		var surface = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(vertices.size()):
			surface.set_color(colors[i])
			surface.add_vertex(vertices[i])
		for i in range(0, vertices.size(), 3):
			var original: PackedVector3Array = chunk.arrays[Mesh.ARRAY_VERTEX]
			if not is_dug(stage, (original[i] + original[i + 1] + original[i + 2]) / 3.0): continue
			for edge in range(3):
				var a = i + edge
				var b = i + (edge + 1) % 3
				var middle = (original[a] + original[b]) * 0.5
				var center = (original[i] + original[i + 1] + original[i + 2]) / 3.0
				if is_dug(stage, middle + (middle - center).normalized() * 0.02): continue
				var top_a = original[a]
				var top_b = original[b]
				top_a.y -= chunk.depths[a] * 0.28 * packed(top_a)
				top_b.y -= chunk.depths[b] * 0.28 * packed(top_b)
				for point in [top_a, vertices[a], vertices[b], top_a, vertices[b], top_b, top_a, vertices[b], vertices[a], top_a, top_b, vertices[b]]:
					surface.set_color(Color("cbd4d8"))
					surface.add_vertex(point)
		surface.generate_normals()
		chunk.node.mesh = surface.commit()
		count += 1
		if count >= 2: break

func snapshot() -> Array:
	var result: Array = []
	for cell in cells: result.append([cell.x, cell.y, roundi(cells[cell] * 255)])
	return result

func apply_snapshot(rows: Array) -> void:
	var next: Dictionary = {}
	for row in rows.slice(0, MAX_CELLS):
		if row is Array and row.size() == 3:
			var cell = Vector2i(int(row[0]), int(row[1]))
			next[cell] = clampf(float(row[2]) / 255.0, 0, 1)
	for cell in cells:
		if not next.has(cell): mark(cell)
	for cell in next:
		if absf(float(next[cell]) - float(cells.get(cell, 0))) > 0.005: mark(cell)
	cells = next

func polygon(stage, point: Vector3) -> Vector4i:
	var cx = floorf(point.x / 4.0) * 4.0
	var cz = floorf(point.z / 4.0) * 4.0
	var step = int(stage.terrain_tile_step(cx, cz))
	var x = cx + floorf((point.x - cx) / step) * step
	var z = cz + floorf((point.z - cz) / step) * step
	return Vector4i(int(x), int(z), step, 0 if (point.x - x + point.z - z) / step <= 1.0 else 1)

func is_dug(stage, point: Vector3) -> bool:
	return stage.winter and not dug.is_empty() and dug.has(polygon(stage, point))

func loose_depth(stage, point: Vector3) -> float:
	return 0.0 if is_dug(stage, point) else depth(stage, point)

func floor_height(stage, point: Vector3) -> float:
	var key = polygon(stage, point)
	var u = (point.x - key.x) / key.z
	var v = (point.z - key.y) / key.z
	var a = Vector3(key.x, 0, key.y)
	var b = a + Vector3(key.z, 0, 0)
	var c = a + Vector3(0, 0, key.z)
	var d = a + Vector3(key.z, 0, key.z)
	if key.w == 0:
		return stage.terrain_surface_height(point) - (depth(stage, a) * (1 - u - v) + depth(stage, b) * u + depth(stage, c) * v)
	return stage.terrain_surface_height(point) - (depth(stage, d) * (u + v - 1) + depth(stage, c) * (1 - u) + depth(stage, b) * (1 - v))

func visible_height(stage, point: Vector3) -> float:
	return floor_height(stage, point) if is_dug(stage, point) else stage.terrain_surface_height(point) - depth(stage, point) * 0.28 * packed(point)

func can_dig(stage, point: Vector3) -> bool:
	return stage.winter and depth(stage, point) > 0.02 and not is_dug(stage, point) and dug.size() < MAX_DUG

func dirty_polygon(key: Vector4i) -> void:
	for x in [key.x - 1, key.x + key.z + 1]:
		for z in [key.y - 1, key.y + key.z + 1]:
			dirty[Vector2i(floori(x / 64.0), floori(z / 64.0))] = true

func dig(stage, point: Vector3) -> bool:
	if not authoritative or not can_dig(stage, point): return false
	var key = polygon(stage, point)
	dug[key] = true
	dirty_polygon(key)
	refresh_clock = 0.5
	return true

func dug_snapshot() -> Array:
	var rows: Array = []
	for key in dug: rows.append([key.x, key.y, key.z, key.w])
	return rows

func apply_dug_snapshot(rows: Array) -> void:
	var next: Dictionary = {}
	for row in rows.slice(0, MAX_DUG):
		if row is Array and row.size() == 4 and int(row[2]) in [2, 4] and int(row[3]) in [0, 1]:
			next[Vector4i(int(row[0]), int(row[1]), int(row[2]), int(row[3]))] = true
	for key in dug:
		if not next.has(key): dirty_polygon(key)
	for key in next:
		if not dug.has(key): dirty_polygon(key)
	dug = next
