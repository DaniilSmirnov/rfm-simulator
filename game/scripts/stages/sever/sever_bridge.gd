extends RefCounted
# The log bridge where the road crosses the stream gully. Cars drive on the
# road surface itself, which stays level across the gully (sever.gd); the
# bridge dresses it: plank deck boards, kerb logs, railings beyond the edges
# of the carriageway (the only parts that collide), log stringers and cross
# beams under the deck, log-crib abutments and a crib pier (ряжи) standing on
# the frozen stream bed.
const Props = preload("res://scripts/core/props.gd")
const Carpentry = preload("res://scripts/stages/sever/sever_carpentry.gd")
const LOGS = Color("5f5346")
const DECK = Color("7a6650")

static func build(stage, biome, root: Node3D, batch: Callable) -> Node3D:
	var s0 = biome.BRIDGE_S - biome.BRIDGE_HALF_LENGTH
	var s1 = biome.BRIDGE_S + biome.BRIDGE_HALF_LENGTH
	var half = biome.road_width(biome.BRIDGE_S) * 0.5
	var frame = Node3D.new()
	frame.name = "LogBridge"
	root.add_child(frame)
	frame.position = stage.at(biome.BRIDGE_S)
	var along = stage.direction(biome.BRIDGE_S)
	frame.rotation.y = atan2(along.x, along.z)
	var length = s1 - s0
	# Deck boards across the carriageway, following the road surface.
	var boards: Array = []
	var colors: Array = []
	var s = s0 - 0.6
	var shade = 0
	while s <= s1 + 0.6:
		var p = stage.at(s)
		p.y = stage.base_ground(p)
		var basis = Basis(stage.side(s) * (half * 2.0 + 0.9), Vector3.UP * 0.05, stage.direction(s) * 0.3)
		boards.append(Transform3D(basis, p + Vector3.UP * 0.02))
		colors.append(DECK.lerp(Color("c3cbcd"), 0.12).lightened(0.05 * sin(shade * 2.3)))
		shade += 1
		s += 0.34
	batch.call(root, "BridgeDeck", boards, colors)
	var deck_y = 0.0
	var bed = -biome.GULLY_DEPTH - 0.4
	for sx in [-1.0, 1.0]:
		# Kerb log along the deck edge, railing posts and two rails beyond it.
		Carpentry.log_between(frame, Vector3(sx * (half + 0.2), deck_y + 0.16, -length * 0.5 - 0.8), Vector3(sx * (half + 0.2), deck_y + 0.16, length * 0.5 + 0.8), 0.16, LOGS)
		var rail_x = sx * (half + 0.55)
		for i in range(9):
			var z = -length * 0.5 + length * i / 8.0
			Props.box(frame, Vector3(rail_x, deck_y + 0.55, z), Vector3(0.16, 1.1, 0.16), LOGS)
		for y in [0.55, 1.05]:
			Carpentry.log_between(frame, Vector3(rail_x, deck_y + y, -length * 0.5 - 0.1), Vector3(rail_x, deck_y + y, length * 0.5 + 0.1), 0.07, LOGS.lightened(0.08))
		var guard = Node3D.new()
		guard.name = "BridgeRail"
		frame.add_child(guard)
		stage.solids.solid(guard, Vector3(rail_x, deck_y + 0.6, 0), Vector3(0.3, 1.2, length + 0.4), "wall")
		# Stringers under the deck edges.
		Carpentry.log_between(frame, Vector3(sx * half * 0.7, deck_y - 0.4, -length * 0.5 - 1.2), Vector3(sx * half * 0.7, deck_y - 0.4, length * 0.5 + 1.2), 0.22, LOGS.darkened(0.1))
	Carpentry.log_between(frame, Vector3(0, deck_y - 0.4, -length * 0.5 - 1.2), Vector3(0, deck_y - 0.4, length * 0.5 + 1.2), 0.22, LOGS.darkened(0.1))
	for i in range(13):
		var z = -length * 0.5 + length * i / 12.0
		Carpentry.log_between(frame, Vector3(-half - 0.55, deck_y - 0.12, z), Vector3(half + 0.55, deck_y - 0.12, z), 0.12, LOGS)
	# Log cribs at both banks and a pier in the middle of the stream.
	for z in [-length * 0.5 + 0.9, length * 0.5 - 0.9]:
		Carpentry.log_frame(frame, Vector3(0, bed, z), half * 2.0 + 1.4, 1.8, -bed - 0.62, LOGS.darkened(0.05))
	Carpentry.log_frame(frame, Vector3(0, bed, 0), half * 2.0 + 0.8, 1.4, -bed - 0.62, LOGS.darkened(0.05))
	_frozen_stream(stage, biome, root)
	return frame

# The frozen stream: a pale, glossy ice ribbon along the gully bed.
static func _frozen_stream(stage, biome, root: Node3D) -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step = 2.0
	var t = -150.0
	while t < 150.0:
		var quad: Array = []
		for k in [t, t + step]:
			var center = biome.stream_origin + biome.stream_across * k + biome.stream_along * biome.meander(k)
			for edge in [-1.0, 1.0]:
				var p = center + biome.stream_along * edge * biome.GULLY_BED * 0.9
				p.y = stage.terrain_surface_height(p) + 0.04
				quad.append(p)
		for v in [quad[0], quad[2], quad[1], quad[1], quad[2], quad[3]]:
			st.set_color(Color(0.8, 0.88, 0.92))
			st.add_vertex(v)
		t += step
	st.generate_normals()
	var ice = MeshInstance3D.new()
	ice.name = "FrozenStream"
	ice.mesh = st.commit()
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.15
	mat.metallic_specular = 0.7
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ice.material_override = mat
	ice.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ice.set_meta("unbatched", true)
	root.add_child(ice)
