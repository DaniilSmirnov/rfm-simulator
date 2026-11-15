extends RefCounted
# The guest yurt of the steppe camp: the one with its door standing open.
# Inside is a lived-in Kazakh киіз үй in the yurt's own frame (door at +z,
# the place of honour, the төр, opposite it at -z), unscaled like yurt.gd:
#   - a reed-mat lining over the red lattice wall (кереге), a woven band
#     (басқұр) round its top, red roof poles (уық) rising to the crown;
#   - felt (текемет) on the floor, patterned carpets over it;
#   - the төр: painted chests with the day's quilts, blankets and pillows
#     stacked on them (жүк), an embroidered wall hanging (тұс киіз) behind;
#   - a low round table (дастарқан) with bowls, bread and a teapot, thin
#     mattresses (көрпе) and cushions round it;
#   - the iron stove with its pipe out through the crown, a kettle on it;
#   - on the right as you come in, the kitchen: a dish cupboard (асадал), a
#     samovar, a leather kumys bag (саба) with its churn stick, a water can;
#   - on the left, the host's side: a carved bed, a saddle on its rack and a
#     dombra and a whip hanging on the lattice;
#   - a lantern under the crown that lights the room at night.
# Walls are solid for walkers and cars except the doorway (walls()).
const Props = preload("res://scripts/core/props.gd")
const Furnishings = preload("res://scripts/stages/canyon/yurt_camp_props.gd")
const NightLights = preload("res://scripts/core/night_lights.gd")

const INNER = 3.02
const WALL = 1.9
# Half the doorway in angle round the wall: the two felt panels left out.
const DOOR_ANGLE = TAU / 24.0
const LATTICE = Color("a8442c")
const POLE = Color("b5482d")
const REED = Color("cdb98d")
const REED_DARK = Color("a99067")
const ROOF = Color("ddd3bf")
const FELT = Color("bfae8e")
const CRIMSON = Color("9a2b25")
const DEEP_RED = Color("6e1d1f")
const OCHRE = Color("d39a3a")
const IVORY = Color("efe4cc")
const TEAL = Color("2f6b6a")
const NAVY = Color("27385a")
const WOOD = Color("7a4e2c")
const DARK_WOOD = Color("4d2f1b")
const IRON = Color("2d2a28")
const BRASS = Color("b98b3c")
const LEATHER = Color("5b3520")

static func build(stage, yurt: Node3D) -> void:
	_lining(yurt)
	_lattice(yurt)
	_roof_poles(yurt)
	_floor(stage, yurt)
	_tor(stage, yurt)
	_table(stage, yurt)
	_stove(stage, yurt)
	_kitchen(stage, yurt)
	_host_side(stage, yurt)
	_lantern(yurt)

# The heavy furniture a walker goes round, as [centre, size, yaw] boxes in
# the yurt frame: the stove, the chests and bedding of the төр, the dish
# cupboard and the bed. Cushions, the low table and the rest are stepped over.
static func solids() -> Array:
	var cupboard = wall_point(PI * 0.55, 0.65, 0.32)
	return [
		[Vector3(0, 0.5, 0.35), Vector3(0.6, 1.0, 0.7), 0.0],
		[Vector3(0, 0.6, -INNER + 0.44), Vector3(1.8, 1.2, 0.6), 0.0],
		[cupboard, Vector3(1.04, 1.3, 0.44), atan2(cupboard.x, cupboard.z)],
		[wall_point(-PI * 0.5, 0.35, 0.5), Vector3(0.84, 0.7, 1.94), 0.0],
	]

# Whether a point on the wall at `angle` (0 at the door) is in the doorway.
static func in_doorway(angle: float) -> bool:
	return absf(wrapf(angle, -PI, PI)) < DOOR_ANGLE - 0.001

# A point on the inside of the wall at `angle`, `inset` metres in.
static func wall_point(angle: float, height: float, inset: float = 0.0) -> Vector3:
	return Vector3(sin(angle), 0, cos(angle)) * (INNER - inset) + Vector3.UP * height

# Looks from `at` to the middle of the room.
static func _face_middle(node: Node3D, at: Vector3) -> void:
	node.rotation.y = atan2(at.x, at.z)

# ---------------------------------------------------------------- shell

# Inward-facing skin: reed mats on the wall, light felt on the roof cone.
static func _lining(yurt: Node3D) -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides = 48
	var roof = [Vector2(INNER, WALL), Vector2(INNER - 0.18, WALL + 0.2), Vector2(0.62, 3.36)]
	for i in range(sides):
		var a = i * TAU / sides
		var b = (i + 1) * TAU / sides
		var middle = (a + b) * 0.5
		var stripe = REED if i % 2 == 0 else REED.darkened(0.05)
		if not in_doorway(middle):
			_quad(st, wall_point(b, -0.3), wall_point(b, WALL), wall_point(a, WALL), wall_point(a, -0.3), stripe)
		else:
			# Over the door frame the wall is closed again.
			_quad(st, wall_point(b, 1.82), wall_point(b, WALL), wall_point(a, WALL), wall_point(a, 1.82), stripe)
		for r in range(roof.size() - 1):
			var lo: Vector2 = roof[r]
			var hi: Vector2 = roof[r + 1]
			var tone = ROOF.darkened(0.05 if i % 2 == 0 else 0.0)
			_quad(st, Vector3(sin(b) * lo.x, lo.y, cos(b) * lo.x), Vector3(sin(b) * hi.x, hi.y, cos(b) * hi.x), Vector3(sin(a) * hi.x, hi.y, cos(a) * hi.x), Vector3(sin(a) * lo.x, lo.y, cos(a) * lo.x), tone)
	st.generate_normals()
	var mesh = MeshInstance3D.new()
	mesh.name = "YurtLining"
	mesh.mesh = st.commit()
	mesh.material_override = Props.material(Color.WHITE)
	mesh.material_override.vertex_color_use_as_albedo = true
	yurt.add_child(mesh)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	st.set_color(color)
	for v in [a, b, c, a, c, d]:
		st.add_vertex(v)

# The red lattice: crossed laths on the reed mats, the woven band at the
# top and narrow mat seams.
static func _lattice(yurt: Node3D) -> void:
	var count = 40
	var lean = 0.2
	for i in range(count):
		var a = i * TAU / count
		for direction in [-1.0, 1.0]:
			var top = a + direction * lean
			if in_doorway(a) or in_doorway(top) or in_doorway((a + top) * 0.5):
				continue
			Furnishings.pole(yurt, wall_point(a, 0.05, 0.05), wall_point(top, WALL - 0.12, 0.05), 0.018, LATTICE.darkened(0.06 if direction > 0 else 0.0))
	# The woven band (басқұр): red with an ochre and ivory border.
	var segments = 48
	for i in range(segments):
		var a = i * TAU / segments
		var b = (i + 1) * TAU / segments
		if in_doorway((a + b) * 0.5):
			continue
		for band in [[1.58, 0.16, CRIMSON], [1.67, 0.03, OCHRE], [1.5, 0.025, IVORY], [1.75, 0.025, IVORY]]:
			var p = (wall_point(a, band[0], 0.08) + wall_point(b, band[0], 0.08)) * 0.5
			var piece = Props.box(yurt, p, Vector3(wall_point(a, 0).distance_to(wall_point(b, 0)) + 0.01, band[1], 0.012), band[2])
			piece.rotation.y = (a + b) * 0.5
		# Tassels hang from the band between the roof poles.
		if i % 4 == 2:
			var tassel = wall_point(a, 1.42, 0.09)
			Furnishings.pole(yurt, tassel + Vector3.UP * 0.08, tassel - Vector3.UP * 0.12, 0.012, OCHRE)
			Props.faceted(yurt, tassel - Vector3.UP * 0.16, Vector3(0.05, 0.1, 0.05), CRIMSON, 6, 3)

# Red roof poles from the top of the lattice to the crown, just under the
# felt; the crown's inner ring and its bent cross-bars over them.
static func _roof_poles(yurt: Node3D) -> void:
	var count = 36
	for i in range(count):
		var a = (i + 0.5) * TAU / count
		var foot = Vector3(sin(a) * (INNER - 0.06), WALL - 0.08, cos(a) * (INNER - 0.06))
		var knee = Vector3(sin(a) * (INNER - 0.24), WALL + 0.12, cos(a) * (INNER - 0.24))
		var head = Vector3(sin(a) * 0.6, 3.3, cos(a) * 0.6)
		Furnishings.pole(yurt, foot, knee, 0.026, POLE)
		Furnishings.pole(yurt, knee, head, 0.026, POLE)
	var ring = MeshInstance3D.new()
	ring.name = "ShanyrakInner"
	ring.mesh = TorusMesh.new()
	ring.mesh.inner_radius = 0.5
	ring.mesh.outer_radius = 0.62
	ring.mesh.rings = 24
	ring.mesh.ring_segments = 6
	ring.material_override = Props.material(POLE.darkened(0.2))
	yurt.add_child(ring)
	ring.position.y = 3.34

# ---------------------------------------------------------------- floor

# Felt over the whole floor, carpets laid on it: a long red one from the
# door to the төр and smaller ones under the table and by the bed.
static func _floor(stage, yurt: Node3D) -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings = [0.0, 1.0, 2.0, INNER - 0.02]
	var sides = 24
	for r in range(rings.size() - 1):
		for i in range(sides):
			var a = i * TAU / sides
			var b = (i + 1) * TAU / sides
			var points = [Vector3(sin(a), 0, cos(a)) * rings[r], Vector3(sin(a), 0, cos(a)) * rings[r + 1], Vector3(sin(b), 0, cos(b)) * rings[r + 1], Vector3(sin(b), 0, cos(b)) * rings[r]]
			st.set_color(FELT.darkened(0.03 * (r % 2)))
			for index in [0, 2, 1, 0, 3, 2]:
				st.add_vertex(Furnishings.ground(stage, yurt, points[index], 0.03))
	_carpet(st, stage, yurt, Vector3(0, 0, 0.2), Vector2(1.3, 4.6), CRIMSON, NAVY, 0.05)
	_carpet(st, stage, yurt, Vector3(0, 0, -1.25), Vector2(2.4, 1.7), TEAL, OCHRE, 0.07)
	_carpet(st, stage, yurt, Vector3(-1.75, 0, 0.35), Vector2(1.1, 1.9), DEEP_RED, IVORY, 0.06)
	st.generate_normals()
	var mesh = MeshInstance3D.new()
	mesh.name = "YurtFloor"
	mesh.mesh = st.commit()
	mesh.material_override = Props.material(Color.WHITE)
	mesh.material_override.vertex_color_use_as_albedo = true
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	yurt.add_child(mesh)

# A carpet draped on the floor: border, field and a row of medallions.
static func _carpet(st: SurfaceTool, stage, yurt: Node3D, at: Vector3, size: Vector2, field: Color, border: Color, lift: float) -> void:
	_patch(st, stage, yurt, at, size, border, lift)
	_patch(st, stage, yurt, at, size - Vector2(0.16, 0.16), IVORY.darkened(0.1), lift + 0.003)
	_patch(st, stage, yurt, at, size - Vector2(0.24, 0.24), field, lift + 0.006)
	var long = size.y > size.x
	var count = maxi(1, int((size.y if long else size.x) / 0.8))
	for i in range(count):
		var t = (i + 0.5) / count - 0.5
		var center = at + (Vector3(0, 0, t * size.y) if long else Vector3(t * size.x, 0, 0))
		var half = minf(size.x, size.y) * 0.28
		_diamond(st, stage, yurt, center, half, border, lift + 0.009)
		_diamond(st, stage, yurt, center, half * 0.45, IVORY, lift + 0.012)

static func _patch(st: SurfaceTool, stage, yurt: Node3D, at: Vector3, size: Vector2, color: Color, lift: float) -> void:
	st.set_color(color)
	var corners = [at + Vector3(-size.x, 0, -size.y) * 0.5, at + Vector3(size.x, 0, -size.y) * 0.5, at + Vector3(size.x, 0, size.y) * 0.5, at + Vector3(-size.x, 0, size.y) * 0.5]
	for index in [0, 1, 2, 0, 2, 3]:
		st.add_vertex(Furnishings.ground(stage, yurt, corners[index], lift))

static func _diamond(st: SurfaceTool, stage, yurt: Node3D, at: Vector3, half: float, color: Color, lift: float) -> void:
	st.set_color(color)
	var points = [at + Vector3(0, 0, -half), at + Vector3(half, 0, 0), at + Vector3(0, 0, half), at + Vector3(-half, 0, 0)]
	for index in [0, 1, 2, 0, 2, 3]:
		st.add_vertex(Furnishings.ground(stage, yurt, points[index], lift))

# ---------------------------------------------------------------- төр

static func _tor(stage, yurt: Node3D) -> void:
	# The embroidered hanging on the wall behind the chests.
	var segments = 10
	for i in range(segments):
		var a = PI - 0.62 + i * 1.24 / segments
		var b = a + 1.24 / segments
		var p = (wall_point(a, 1.0, 0.09) + wall_point(b, 1.0, 0.09)) * 0.5
		var width = wall_point(a, 0).distance_to(wall_point(b, 0)) + 0.01
		for layer in [[0.0, Vector2(1.1, 0.012), DEEP_RED], [0.008, Vector2(0.9, 0.012), CRIMSON]]:
			var panel = Props.box(yurt, p + (Vector3(sin(a), 0, cos(a)) * -layer[0]), Vector3(width, layer[1].x, layer[1].y), layer[2])
			panel.rotation.y = (a + b) * 0.5
		# Ram's-horn scrolls (қошқар мүйіз) in ochre and ivory.
		var motif = (wall_point(a, 1.0, 0.115) + wall_point(b, 1.0, 0.115)) * 0.5
		for y in [-0.24, 0.24]:
			var curl = Props.box(yurt, motif + Vector3.UP * y, Vector3(width * 0.6, 0.06, 0.01), OCHRE if i % 2 == 0 else IVORY)
			curl.rotation = Vector3(0, (a + b) * 0.5, 0.6 if i % 2 == 0 else -0.6)
		var hook = Props.box(yurt, motif, Vector3(0.1, 0.1, 0.01), IVORY)
		hook.rotation = Vector3(0, (a + b) * 0.5, PI * 0.25)
	# Two painted chests side by side, bedding stacked on them.
	for side in [-0.48, 0.48]:
		var at = Vector3(side, 0, -INNER + 0.42)
		var foot = Furnishings.ground(stage, yurt, at)
		var chest = Node3D.new()
		yurt.add_child(chest)
		chest.position = foot
		Props.box(chest, Vector3(0, 0.3, 0), Vector3(0.88, 0.5, 0.52), Color("8e3a22"))
		Props.box(chest, Vector3(0, 0.05, 0), Vector3(0.92, 0.1, 0.56), DARK_WOOD)
		for x in [-0.3, 0.0, 0.3]:
			Props.box(chest, Vector3(x, 0.32, 0.262), Vector3(0.05, 0.46, 0.012), BRASS)
		Props.box(chest, Vector3(0, 0.32, 0.263), Vector3(0.84, 0.04, 0.012), BRASS)
		for x in [-0.15, 0.15]:
			Props.box(chest, Vector3(x, 0.32, 0.264), Vector3(0.2, 0.2, 0.01), Color("2f5e86"))
		Props.box(chest, Vector3(0, 0.25, 0.27), Vector3(0.07, 0.09, 0.02), IRON)
	var stack = Furnishings.ground(stage, yurt, Vector3(0, 0, -INNER + 0.44)) + Vector3.UP * 0.55
	var colors = [CRIMSON, TEAL, OCHRE, NAVY, DEEP_RED, Color("5c7c3a"), CRIMSON.lightened(0.15)]
	var y = 0.0
	for i in range(colors.size()):
		var thick = 0.1 + (i % 3) * 0.02
		var fold = Props.box(yurt, stack + Vector3((i % 2) * 0.03 - 0.015, y + thick * 0.5, 0), Vector3(1.7 - (i % 2) * 0.06, thick, 0.48), colors[i])
		Props.box(fold, Vector3(0, 0, 0.243), Vector3(1.6, thick * 0.4, 0.01), IVORY if i % 2 == 0 else OCHRE)
		y += thick
	for x in [-0.55, 0.0, 0.55]:
		var pillow = Props.faceted(yurt, stack + Vector3(x, y + 0.1, 0.02), Vector3(0.5, 0.2, 0.36), IVORY.darkened(0.05) if x == 0.0 else CRIMSON.lightened(0.1), 10, 4)
		pillow.rotation.y = x * 0.2
	# Covered with a lace-edged throw (жүк аяқ).
	Props.box(yurt, stack + Vector3(0, y + 0.02, 0.26), Vector3(1.75, 0.3, 0.01), IVORY)

# ---------------------------------------------------------------- дастарқан

static func _table(stage, yurt: Node3D) -> void:
	var at = Vector3(0, 0, -1.2)
	var foot = Furnishings.ground(stage, yurt, at)
	var top = foot + Vector3.UP * 0.32
	Props.cylinder(yurt, top, 0.58, 0.58, 0.05, WOOD.lightened(0.08), 20)
	for i in range(4):
		var a = i * TAU / 4 + 0.4
		var leg = foot + Vector3(sin(a), 0, cos(a)) * 0.42
		Furnishings.pole(yurt, leg, leg + Vector3.UP * 0.3, 0.03, DARK_WOOD)
	# A cloth, bowls (кесе) of tea, a dish of fried dough (бауырсақ), bread
	# and a teapot.
	Props.cylinder(yurt, top + Vector3.UP * 0.028, 0.5, 0.5, 0.006, IVORY, 20)
	for i in range(6):
		var a = i * TAU / 6 + 0.3
		var cup = top + Vector3(sin(a), 0, cos(a)) * 0.4 + Vector3.UP * 0.06
		Props.cylinder(yurt, cup, 0.032, 0.05, 0.06, Color("f1efe8"), 10)
		Props.cylinder(yurt, cup + Vector3.UP * 0.026, 0.044, 0.044, 0.01, Color("9a5a2a"), 10)
		Props.cylinder(yurt, cup + Vector3.UP * 0.02, 0.051, 0.051, 0.008, Color("2f5e86"), 10)
	var dish = top + Vector3(0.12, 0.05, 0.06)
	Props.cylinder(yurt, dish, 0.14, 0.2, 0.05, Color("e9e4d6"), 14)
	for i in range(9):
		var a = i * 2.4
		Props.faceted(yurt, dish + Vector3(sin(a) * 0.09 * (i % 3) * 0.6, 0.05 + (i % 2) * 0.03, cos(a) * 0.09 * (i % 3) * 0.6), Vector3(0.06, 0.05, 0.06), Color("c58a3e").lightened((i % 3) * 0.05), 6, 3)
	for i in range(2):
		var bread = Props.cylinder(yurt, top + Vector3(-0.22, 0.05 + i * 0.035, -0.12), 0.13, 0.12, 0.03, Color("d29a4f"), 14)
		bread.rotation.y = i
	var pot = top + Vector3(-0.16, 0.1, 0.22)
	Props.faceted(yurt, pot, Vector3(0.17, 0.14, 0.17), Color("f1efe8"), 10, 5)
	Props.faceted(yurt, pot + Vector3.UP * 0.005, Vector3(0.175, 0.03, 0.175), Color("2f5e86"), 10, 3)
	Furnishings.pole(yurt, pot + Vector3(0.06, 0, 0), pot + Vector3(0.14, 0.06, 0), 0.012, Color("f1efe8"))
	Props.cylinder(yurt, pot + Vector3.UP * 0.075, 0.03, 0.02, 0.03, Color("2f5e86"), 8)
	# Thin mattresses (көрпе) on three sides and a cushion on each.
	for spot in [[Vector3(-0.95, 0, -1.2), PI * 0.5], [Vector3(0.95, 0, -1.2), -PI * 0.5], [Vector3(0, 0, -2.1), 0.0]]:
		var mat_at = Furnishings.ground(stage, yurt, spot[0], 0.05)
		var korpe = Node3D.new()
		yurt.add_child(korpe)
		korpe.position = mat_at
		korpe.rotation.y = spot[1]
		Props.box(korpe, Vector3.ZERO, Vector3(1.5, 0.08, 0.62), CRIMSON)
		Props.box(korpe, Vector3(0, 0.003, 0), Vector3(1.4, 0.08, 0.5), Color("3f5f8f") if spot[1] == 0.0 else TEAL)
		for x in [-0.4, 0.4]:
			var cushion = Props.faceted(korpe, Vector3(x, 0.12, -0.12), Vector3(0.42, 0.18, 0.34), OCHRE if x < 0 else IVORY.darkened(0.08), 10, 4)
			cushion.rotation.x = -0.25

# ---------------------------------------------------------------- stove

static func _stove(stage, yurt: Node3D) -> void:
	var foot = Furnishings.ground(stage, yurt, Vector3(0, 0, 0.35))
	Props.box(yurt, foot + Vector3.UP * 0.02, Vector3(0.8, 0.04, 0.8), Color("8d867b"))
	Props.box(yurt, foot + Vector3.UP * 0.33, Vector3(0.52, 0.5, 0.62), IRON)
	for x in [-0.22, 0.22]:
		for z in [-0.26, 0.26]:
			Props.box(yurt, foot + Vector3(x, 0.06, z), Vector3(0.05, 0.12, 0.05), IRON)
	Props.box(yurt, foot + Vector3(0, 0.32, 0.312), Vector3(0.26, 0.2, 0.02), Color("1d1b1a"))
	var glow = Props.box(yurt, foot + Vector3(0, 0.27, 0.318), Vector3(0.2, 0.06, 0.01), Color("ff7a2a"))
	Props.unique_material(glow)
	glow.material_override.emission_enabled = true
	glow.material_override.emission = Color("ff6a1a")
	glow.material_override.emission_energy_multiplier = 1.4
	# The pipe climbs straight up and out through the crown.
	Props.cylinder(yurt, foot + Vector3(0, 0.58 + (3.9 - 0.58) * 0.5, -0.18), 0.065, 0.065, 3.9 - 0.58 - foot.y, Color("3a3734"), 10)
	var kettle = foot + Vector3(0, 0.66, 0.1)
	Props.faceted(yurt, kettle, Vector3(0.24, 0.2, 0.24), Color("8b8f8c"), 10, 5)
	Furnishings.pole(yurt, kettle + Vector3(0.09, 0.0, 0), kettle + Vector3(0.2, 0.08, 0), 0.02, Color("8b8f8c"))
	Furnishings.pole(yurt, kettle + Vector3(0, 0.1, -0.08), kettle + Vector3(0, 0.1, 0.08), 0.012, IRON)
	# A neat pile of dried dung and saxaul by the stove.
	for i in range(5):
		var log_piece = Props.cylinder(yurt, Furnishings.ground(stage, yurt, Vector3(0.62 + (i % 3) * 0.1, 0, 0.55), 0.06 + int(i / 3.0) * 0.1), 0.05, 0.04, 0.5, Color("6e5a42"), 6)
		log_piece.rotation = Vector3(PI * 0.5, 0.3, 0)

# ---------------------------------------------------------------- kitchen

static func _kitchen(stage, yurt: Node3D) -> void:
	# The dish cupboard (асадал) against the lattice at the right.
	var at = wall_point(PI * 0.55, 0.0, 0.32)
	var cupboard = Node3D.new()
	yurt.add_child(cupboard)
	cupboard.position = Furnishings.ground(stage, yurt, at)
	_face_middle(cupboard, at)
	Props.box(cupboard, Vector3(0, 0.6, 0), Vector3(1.0, 1.2, 0.4), Color("8a4a2a"))
	Props.box(cupboard, Vector3(0, 1.22, 0), Vector3(1.06, 0.05, 0.44), DARK_WOOD)
	for x in [-0.25, 0.25]:
		Props.box(cupboard, Vector3(x, 0.35, -0.205), Vector3(0.44, 0.6, 0.02), Color("a35a32"))
		Props.box(cupboard, Vector3(x, 0.35, -0.218), Vector3(0.3, 0.42, 0.01), OCHRE)
		Props.box(cupboard, Vector3(x * 0.2, 0.35, -0.225), Vector3(0.03, 0.08, 0.015), BRASS)
	Props.box(cupboard, Vector3(0, 0.9, -0.05), Vector3(0.94, 0.03, 0.3), DARK_WOOD)
	for i in range(4):
		var plate = Props.cylinder(cupboard, Vector3(-0.33 + i * 0.22, 1.02, 0.05), 0.09, 0.09, 0.015, Color("f1efe8") if i % 2 == 0 else Color("2f5e86"), 14)
		plate.rotation.x = PI * 0.5 - 0.25
	for i in range(3):
		Props.cylinder(cupboard, Vector3(-0.2 + i * 0.2, 1.3, 0), 0.05, 0.07, 0.1, Color("f1efe8"), 10)
	# A brass samovar on a low stand beside it.
	var samovar_at = wall_point(PI * 0.43, 0.0, 0.42)
	var base = Furnishings.ground(stage, yurt, samovar_at)
	Props.box(yurt, base + Vector3.UP * 0.12, Vector3(0.42, 0.24, 0.42), DARK_WOOD)
	var body = base + Vector3.UP * 0.42
	Props.cylinder(yurt, body - Vector3.UP * 0.12, 0.09, 0.12, 0.06, BRASS.darkened(0.15), 12)
	Props.faceted(yurt, body + Vector3.UP * 0.04, Vector3(0.26, 0.3, 0.26), BRASS, 12, 6)
	Props.cylinder(yurt, body + Vector3.UP * 0.22, 0.05, 0.07, 0.06, BRASS.darkened(0.1), 10)
	Props.faceted(yurt, body + Vector3.UP * 0.3, Vector3(0.13, 0.1, 0.13), Color("f1efe8"), 10, 4)
	var spout_dir = Vector3(-samovar_at.x, 0, -samovar_at.z).normalized()
	Furnishings.pole(yurt, body + spout_dir * 0.12, body + spout_dir * 0.2 - Vector3.UP * 0.03, 0.015, BRASS.darkened(0.2))
	for side in [-1.0, 1.0]:
		var handle = body + spout_dir.cross(Vector3.UP) * side * 0.14 + Vector3.UP * 0.08
		Props.box(yurt, handle, Vector3(0.04, 0.05, 0.04), DARK_WOOD)
	# The leather kumys bag (саба) on its rack, its churn stick standing in it.
	var saba_at = wall_point(PI * 0.32, 0.0, 0.45)
	var saba_foot = Furnishings.ground(stage, yurt, saba_at)
	for x in [-0.25, 0.25]:
		for z in [-0.18, 0.18]:
			Furnishings.pole(yurt, saba_foot + Vector3(x, 0, z), saba_foot + Vector3(x * 0.8, 0.42, z * 0.8), 0.022, WOOD)
	var bag = saba_foot + Vector3.UP * 0.66
	Props.faceted(yurt, bag, Vector3(0.5, 0.56, 0.4), LEATHER, 10, 6)
	Props.cylinder(yurt, bag + Vector3.UP * 0.32, 0.07, 0.09, 0.12, LEATHER.darkened(0.15), 8)
	Furnishings.pole(yurt, bag + Vector3.UP * 0.1, bag + Vector3(0.05, 0.85, 0.02), 0.018, Color("c9a77a"))
	Props.cylinder(yurt, bag + Vector3(0.0, -0.06, 0), 0.258, 0.258, 0.05, Color("b98b3c"), 10)
	# A galvanised water can and a ladle hanging on the lattice.
	var can = Furnishings.ground(stage, yurt, wall_point(PI * 0.22, 0.0, 0.35))
	Props.cylinder(yurt, can + Vector3.UP * 0.2, 0.15, 0.13, 0.4, Color("9ea3a2"), 12)
	Props.cylinder(yurt, can + Vector3.UP * 0.41, 0.07, 0.07, 0.03, Color("7e8382"), 10)
	var ladle = wall_point(PI * 0.27, 1.25, 0.08)
	Furnishings.pole(yurt, ladle, ladle - Vector3.UP * 0.32, 0.012, WOOD)
	Props.faceted(yurt, ladle - Vector3.UP * 0.38, Vector3(0.11, 0.06, 0.11), WOOD, 8, 3)

# ---------------------------------------------------------------- host's side

static func _host_side(stage, yurt: Node3D) -> void:
	# A carved wooden bed along the lattice on the left.
	var at = wall_point(-PI * 0.5, 0.0, 0.5)
	var bed = Node3D.new()
	yurt.add_child(bed)
	bed.position = Furnishings.ground(stage, yurt, at)
	Props.box(bed, Vector3(0, 0.3, 0), Vector3(0.8, 0.1, 1.9), WOOD)
	for z in [-0.9, 0.9]:
		for x in [-0.36, 0.36]:
			Props.box(bed, Vector3(x, 0.15, z), Vector3(0.07, 0.3, 0.07), DARK_WOOD)
		# Carved head and foot boards with an ochre scroll.
		Props.box(bed, Vector3(0, 0.55, z), Vector3(0.82, 0.5 if z < 0 else 0.34, 0.05), Color("8e3a22"))
		Props.box(bed, Vector3(0, 0.6 if z < 0 else 0.55, z + signf(z) * 0.03), Vector3(0.5, 0.12, 0.01), OCHRE)
	Props.box(bed, Vector3(0, 0.4, 0), Vector3(0.74, 0.12, 1.78), IVORY.darkened(0.05))
	Props.box(bed, Vector3(0, 0.47, 0.15), Vector3(0.78, 0.05, 1.3), NAVY)
	Props.box(bed, Vector3(0, 0.475, 0.15), Vector3(0.6, 0.05, 1.1), CRIMSON)
	Props.faceted(bed, Vector3(0, 0.55, -0.7), Vector3(0.55, 0.16, 0.32), IVORY, 10, 4)
	# The saddle on its rack by the door, its felt cloth under it.
	var rack_at = wall_point(-PI * 0.22, 0.0, 0.45)
	var rack = Node3D.new()
	yurt.add_child(rack)
	rack.position = Furnishings.ground(stage, yurt, rack_at)
	_face_middle(rack, rack_at)
	for x in [-0.3, 0.3]:
		Furnishings.pole(rack, Vector3(x, 0, -0.2), Vector3(x, 0.55, 0), 0.03, WOOD)
		Furnishings.pole(rack, Vector3(x, 0, 0.2), Vector3(x, 0.55, 0), 0.03, WOOD)
	Furnishings.pole(rack, Vector3(-0.32, 0.56, 0), Vector3(0.32, 0.56, 0), 0.035, WOOD)
	Props.box(rack, Vector3(0, 0.6, 0), Vector3(0.62, 0.02, 0.62), CRIMSON)
	Props.box(rack, Vector3(0, 0.52, 0), Vector3(0.64, 0.12, 0.012), OCHRE)
	Props.faceted(rack, Vector3(0, 0.68, 0), Vector3(0.36, 0.16, 0.55), LEATHER, 10, 4)
	Props.box(rack, Vector3(0, 0.8, -0.24), Vector3(0.14, 0.18, 0.08), LEATHER.darkened(0.2))
	Props.box(rack, Vector3(0, 0.76, 0.26), Vector3(0.2, 0.12, 0.06), LEATHER.darkened(0.2))
	for x in [-0.22, 0.22]:
		Furnishings.pole(rack, Vector3(x, 0.66, 0), Vector3(x * 1.25, 0.25, 0), 0.008, IRON)
		Props.box(rack, Vector3(x * 1.25, 0.22, 0), Vector3(0.08, 0.04, 0.1), Color("6f6a64"))
	# A dombra and a whip (қамшы) hang on the lattice above the bed.
	var neck_top = wall_point(-PI * 0.62, 1.42, 0.1)
	var neck_low = wall_point(-PI * 0.62 + 0.18, 0.95, 0.1)
	Furnishings.pole(yurt, neck_low, neck_top, 0.02, DARK_WOOD)
	var bowl = neck_low.lerp(neck_top, -0.25)
	var dombra = Props.faceted(yurt, bowl, Vector3(0.24, 0.34, 0.1), Color("a8662e"), 10, 5)
	dombra.rotation = Vector3(0, -PI * 0.62, -0.35)
	var whip = wall_point(-PI * 0.4, 1.38, 0.1)
	Furnishings.pole(yurt, whip, whip - Vector3.UP * 0.32, 0.016, DARK_WOOD)
	var lash = whip - Vector3.UP * 0.32
	Furnishings.pole(yurt, lash, lash - Vector3.UP * 0.42 + (wall_point(-PI * 0.37, 0, 0.1) - wall_point(-PI * 0.4, 0, 0.1)), 0.008, LEATHER)

# ---------------------------------------------------------------- lantern

# A brass lantern hung on a chain from the crown; at night it lights the
# room (NightLights "lamp" kind) and glows through the open door.
static func _lantern(yurt: Node3D) -> void:
	var at = Vector3(0.0, 2.45, -0.75)
	Furnishings.pole(yurt, at + Vector3.UP * 0.18, Vector3(0, 3.3, -0.55), 0.008, IRON)
	Props.cylinder(yurt, at + Vector3.UP * 0.15, 0.03, 0.09, 0.05, BRASS, 10)
	Props.cylinder(yurt, at - Vector3.UP * 0.13, 0.08, 0.08, 0.04, BRASS, 10)
	var glass = Props.cylinder(yurt, at, 0.06, 0.06, 0.22, Color("ffe2a4"), 10)
	Props.unique_material(glass)
	glass.material_override.emission_enabled = true
	glass.material_override.emission = Color("ffc66e")
	glass.material_override.emission_energy_multiplier = 0.6
	var light = Node3D.new()
	light.name = "YurtLantern"
	yurt.add_child(light)
	light.position = at
	NightLights.mark(light, "lamp")
