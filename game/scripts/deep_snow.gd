extends RefCounted
# Bounded, shared compaction field. Only the host stamps; prediction reads it.
const CELL = 2.0
const MAX_CELLS = 768
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
	if not authoritative or depth(stage, point) < 0.02: return
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
	chunks[tile] = {"node": node, "arrays": arrays, "depths": depths, "borders": borders}
	if not cells.is_empty(): dirty[tile] = true

func update(delta: float) -> void:
	refresh_clock += delta
	if refresh_clock < 0.5: return
	refresh_clock = 0.0
	var count = 0
	for tile in dirty.keys():
		dirty.erase(tile)
		if not chunks.has(tile): continue
		var chunk: Dictionary = chunks[tile]
		var arrays: Array = chunk.arrays.duplicate()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX].duplicate()
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR].duplicate()
		for i in range(vertices.size()):
			var compression = packed(vertices[i])
			var depression: float = chunk.depths[i] * 0.28 * compression
			if chunk.borders.has(i):
				var border: Array = chunk.borders[i]
				depression = (border[2] * packed(border[0]) + border[3] * packed(border[1])) * 0.14
			vertices[i].y -= depression
			colors[i] = colors[i].darkened(compression * 0.10)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_COLOR] = colors
		var mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var surface = SurfaceTool.new()
		surface.create_from(mesh, 0)
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
