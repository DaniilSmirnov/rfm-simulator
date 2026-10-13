extends RefCounted
# Shared indexed rings keep both edges continuous through bends and elevation.
const STRIPS = 10
const SPACING = 2.0
const WIDTH = 1.9
const ROAD_MARGIN = 0.15

static func vertex(stage, station: float, edge: float, fraction: float) -> Vector3:
	var offset: float = stage.road_width(station) * 0.5 + ROAD_MARGIN + WIDTH * fraction
	var point: Vector3 = stage.at(station) + stage.side(station) * edge * offset
	var taper = smoothstep(0.0, 6.0, station) * (1.0 - smoothstep(stage.LENGTH - 6.0, stage.LENGTH, station))
	var height = 0.90 + sin(station * 0.055 + edge * 0.8) * 0.06 + sin(station * 0.019) * 0.04
	# A squared sine meets the landscape with a horizontal tangent at both toes.
	point.y = stage.terrain_surface_height(point) - 0.035 + height * pow(sin(PI * fraction), 2.0) * taper * stage.DeepSnow.camp_mask(stage, point)
	return point

static func mesh(stage, edge: float) -> ArrayMesh:
	var stations = PackedFloat32Array([0.0])
	for i in range(int(stage.LENGTH)):
		var length: float = stage.at(i).distance_to(stage.at(i + 1.0))
		var divisions = maxi(1, ceili(length / SPACING))
		for j in range(1, divisions + 1):
			stations.append(i + float(j) / divisions)
	var surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for station in stations:
		for strip in range(STRIPS + 1):
			surface.add_vertex(vertex(stage, station, edge, float(strip) / STRIPS))
	for row in range(stations.size() - 1):
		for strip in range(STRIPS):
			var a = row * (STRIPS + 1) + strip
			var b = a + 1
			var c = a + STRIPS + 1
			var d = c + 1
			for index in ([a, c, b, b, c, d] if edge > 0 else [a, b, c, b, d, c]):
				surface.add_index(index)
	surface.generate_normals()
	return surface.commit()

static func surface_height(stage, point: Vector3) -> float:
	var result = -INF
	var cell = Vector2i(floori(point.x / 4.0), floori(point.z / 4.0))
	for triangle in stage.snowbank_cells.get(cell, []):
		var a: Vector3 = triangle[0]
		var b: Vector3 = triangle[1]
		var c: Vector3 = triangle[2]
		var ab = Vector2(b.x - a.x, b.z - a.z)
		var ac = Vector2(c.x - a.x, c.z - a.z)
		var ap = Vector2(point.x - a.x, point.z - a.z)
		var determinant = ab.cross(ac)
		if absf(determinant) < 0.000001: continue
		var u = ap.cross(ac) / determinant
		var v = ab.cross(ap) / determinant
		if u >= -0.00001 and v >= -0.00001 and u + v <= 1.00001:
			result = maxf(result, a.y + (b.y - a.y) * u + (c.y - a.y) * v)
	return result

static func index_surface(stage, mesh: ArrayMesh) -> void:
	var arrays = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in range(0, indices.size(), 3):
		var triangle = [vertices[indices[i]], vertices[indices[i + 1]], vertices[indices[i + 2]]]
		var low = Vector2(INF, INF)
		var high = Vector2(-INF, -INF)
		for p in triangle:
			low = low.min(Vector2(p.x, p.z))
			high = high.max(Vector2(p.x, p.z))
		for x in range(floori(low.x / 4), floori(high.x / 4) + 1):
			for z in range(floori(low.y / 4), floori(high.y / 4) + 1):
				var key = Vector2i(x, z)
				if not stage.snowbank_cells.has(key): stage.snowbank_cells[key] = []
				stage.snowbank_cells[key].append(triangle)

static func build(stage) -> void:
	stage.snowbank_cells.clear()
	var material = StandardMaterial3D.new()
	material.albedo_color = Color("e1edf1")
	material.roughness = 1.0
	for edge in [-1.0, 1.0]:
		var node = MeshInstance3D.new()
		node.name = "SnowbankLeft" if edge < 0 else "SnowbankRight"
		node.mesh = mesh(stage, edge)
		index_surface(stage, node.mesh)
		node.material_override = material
		stage.add_child(node)
