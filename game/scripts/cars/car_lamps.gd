extends RefCounted
# Lamps that light up at night. Models mark their headlamp and tail-lamp
# meshes (mark()); Props.bake_car() copies the marked meshes, a hair proud of
# the body, into one hidden unshaded mesh per car ("LampGlow", shared by
# identical cars). Under it hang the beams: a soft cone of light ahead of each
# headlamp ("LampBeams", additive, fading with distance), so every car on the
# stage visibly drives with its lights on, wherever the player stands. At
# night sky_weather.gd shows the glow on every car in GROUP: two draw calls a
# car and no light. Only the player's and the room members' cars also get a
# real SpotLight3D (SkyWeather.headlights()), placed at their own headlamps.
const MeshMerge = preload("res://scripts/core/mesh_merge.gd")
const GROUP = &"car_lamps"
const NODE = "LampGlow"
const COLORS = {"head": Color("fff4d8"), "tail": Color("ff2f22")}
const PROUD = 0.006 # towards the viewer, so the copy never shares a depth with the lens
const BEAMS = "LampBeams"
# Beam cone: length (m), radius at the far end (m), downward pitch (rad), the
# alpha it starts with at the lamp and the sides of the cone.
const BEAM = {"length": 9.0, "radius": 1.7, "pitch": 0.1, "alpha": 0.12, "sides": 12, "color": Color("fff1cf")}
# Past this distance a beam is a few pixels: not drawn.
const BEAM_VISIBLE = 260.0
static var _material: StandardMaterial3D
static var _beam_material: StandardMaterial3D
static var _beam_meshes: Dictionary = {}

static func mark(node: Node3D, kind: String) -> Node3D:
	node.set_meta("lamp", kind)
	return node

# Call before the car's own bake: the glow node stays hidden, so the body bake
# leaves it alone.
static func build(car: Node3D, cache_key: String) -> void:
	var glow = Node3D.new()
	glow.name = NODE
	_copy(car, car, Transform3D.IDENTITY, glow)
	if glow.get_child_count() == 0:
		glow.free()
		return
	var heads = head_lamps(glow)
	car.add_child(glow)
	var mesh = MeshMerge.bake(glow, cache_key + ":glow", [], "LampGlowMesh")
	mesh.material_override = material()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not heads.is_empty():
		car.set_meta("head_lamp", front_of(heads))
		var beams = MeshInstance3D.new()
		beams.name = BEAMS
		beams.mesh = _beam_mesh(cache_key, heads)
		beams.material_override = beam_material()
		beams.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beams.visibility_range_end = BEAM_VISIBLE
		glow.add_child(beams)
	glow.hide()
	car.add_to_group(GROUP)

# The headlamps of a car as (centre in car space) for each side of the car:
# lamps left and right of the middle each make one beam, a lamp in the middle
# (a helicopter's) one of its own.
static func head_lamps(glow: Node3D) -> Array:
	var sides = {}
	for copy in glow.get_children():
		if copy is MeshInstance3D and copy.material_override.albedo_color == COLORS.head:
			var box: AABB = copy.transform * copy.mesh.get_aabb()
			var centre = box.get_center()
			# The front face of the lamp, where the light leaves it.
			centre.z = box.position.z
			var key = signi(int(round(centre.x * 10.0)))
			if not sides.has(key):
				sides[key] = []
			sides[key].append(centre)
	var lamps = []
	for key in sides:
		var sum = Vector3.ZERO
		var front = INF
		for point in sides[key]:
			sum += point
			front = minf(front, point.z)
		var centre = sum / sides[key].size()
		centre.z = front
		lamps.append(centre)
	return lamps

# Midpoint of the headlamps: where a car's own SpotLight3D sits.
static func front_of(heads: Array) -> Vector3:
	var sum = Vector3.ZERO
	var front = INF
	for point in heads:
		sum += point
		front = minf(front, point.z)
	var centre = sum / heads.size()
	return Vector3(0.0, centre.y, front)

static func _beam_mesh(cache_key: String, heads: Array) -> ArrayMesh:
	if _beam_meshes.has(cache_key):
		return _beam_meshes[cache_key]
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides: int = BEAM.sides
	var bright: Color = BEAM.color
	bright.a = BEAM.alpha
	var dark: Color = BEAM.color
	dark.a = 0.0
	for lamp in heads:
		# Lamps aim a little outwards, so two beams fan apart as on a road.
		var outward = clampf(lamp.x, -1.0, 1.0) * 0.06
		var axis = Basis(Vector3.UP, -outward) * Basis(Vector3.RIGHT, -float(BEAM.pitch))
		var start = lamp + Vector3(0, 0, -0.02)
		var tip = start + axis * Vector3(0, 0, -float(BEAM.length))
		for i in range(sides):
			var a = TAU * i / sides
			var b = TAU * (i + 1) / sides
			var near_a = start + axis * Vector3(cos(a), sin(a), 0) * 0.07
			var near_b = start + axis * Vector3(cos(b), sin(b), 0) * 0.07
			var far_a = tip + axis * Vector3(cos(a), sin(a) * 0.55, 0) * float(BEAM.radius)
			var far_b = tip + axis * Vector3(cos(b), sin(b) * 0.55, 0) * float(BEAM.radius)
			for point in [[near_a, bright], [far_a, dark], [far_b, dark], [near_a, bright], [far_b, dark], [near_b, bright]]:
				st.set_color(point[1])
				st.add_vertex(point[0])
	var mesh = st.commit()
	if _beam_meshes.size() < MeshMerge.CACHE_LIMIT:
		_beam_meshes[cache_key] = mesh
	return mesh

# Additive and unlit: the beam brightens what is behind it and never darkens.
static func beam_material() -> StandardMaterial3D:
	if _beam_material == null:
		_beam_material = StandardMaterial3D.new()
		_beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_beam_material.vertex_color_use_as_albedo = true
		_beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_beam_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_beam_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_beam_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return _beam_material

static func _copy(node: Node, car: Node3D, xform: Transform3D, glow: Node3D) -> void:
	for child in node.get_children():
		if not child is Node3D or not child.visible:
			continue
		var local: Transform3D = xform * child.transform
		if child is MeshInstance3D and child.mesh != null and child.has_meta("lamp"):
			var kind = str(child.get_meta("lamp"))
			var copy = MeshInstance3D.new()
			copy.mesh = child.mesh
			copy.transform = local
			# Panels built in car space sit at the origin: judge by the mesh itself.
			copy.position.z += -PROUD if (local * child.mesh.get_aabb()).get_center().z < 0.0 else PROUD
			var paint = StandardMaterial3D.new()
			paint.albedo_color = COLORS.get(kind, COLORS.head)
			copy.material_override = paint
			glow.add_child(copy)
		_copy(child, car, local, glow)

static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.vertex_color_use_as_albedo = true
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _material

static func set_lit(car: Node3D, lit: bool) -> void:
	var glow = car.get_node_or_null(NODE)
	if glow != null:
		glow.visible = lit
