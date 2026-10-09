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
	point.y = stage.terrain_surface_height(point) - 0.035 + height * pow(sin(PI * fraction), 2.0) * taper
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

static func build(stage) -> void:
	var material = StandardMaterial3D.new()
	material.albedo_color = Color("e1edf1")
	material.roughness = 1.0
	for edge in [-1.0, 1.0]:
		var node = MeshInstance3D.new()
		node.name = "SnowbankLeft" if edge < 0 else "SnowbankRight"
		node.mesh = mesh(stage, edge)
		node.material_override = material
		stage.add_child(node)
