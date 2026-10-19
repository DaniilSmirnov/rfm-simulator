extends RefCounted
# The rock forms of the Valley of Castles (canyon_scenery.gd places them). The
# real «castles» are massive blocks of red claystone and sandstone: flat
# topped, cut by vertical cracks into towers of different heights, stepped
# where a softer bed has weathered back, striped by thin horizontal beds, and
# here and there a slab that has broken off and leans. Each form here is a
# stack of rings with a squarish cross-section (a rounded rectangle with
# cracks in it) swept up a profile of ledges, coloured by the strata of the
# walls with a fine banding of its own.
#
#   castle   a row of blocky towers of different heights, gaps between them
#   bastion  a massive stepped block against the wall, smaller blocks on top
#   block    a single flat-topped tower
#   fin      a long narrow wall of rock with a broken crest
#   slab     a layered block that has toppled and leans
#   hoodoo   a squat neck under a flat grey cap (rare)

const KINDS = ["castle", "bastion", "block", "fin", "slab", "hoodoo"]
const SECTORS = 16
const CAPROCK = Color("b9ab94")
const CLAY = Color("b0603a")
# Spacing of the towers of a castle, in tower radii.
const TOWER_SPAN = 1.6

# Builds one form into `st` with its foot at `origin` and returns the circles
# that stop people and cars: [{"pos": Vector3, "radius": float}].
static func build(st: SurfaceTool, biome, origin: Vector3, kind: String, height: float, radius: float, yaw: float, seed_index: int) -> Array:
	var spec = {"biome": biome, "origin": origin, "height": height, "radius": radius, "yaw": yaw, "seed": seed_index, "aspect": 1.0 + float(seed_index % 4) * 0.12, "kind": kind, "tilt": 0.0, "ledges": 2 + seed_index % 3, "crown": 0.04}
	var along = Vector3(cos(yaw), 0.0, -sin(yaw))
	match kind:
		"castle":
			# Towers side by side along the wall, split by deep cracks.
			var circles: Array = []
			var count = _towers(seed_index)
			var span = radius * TOWER_SPAN
			for i in range(count):
				var f = (float(i) - (count - 1) * 0.5) * span
				var tall = height * (0.62 + 0.38 * _hash(seed_index * 7 + i))
				var wide = radius * (0.75 + 0.35 * _hash(seed_index * 3 + i))
				var at = origin + along * f
				var tower = spec.duplicate()
				tower.merge({"origin": at, "height": tall, "radius": wide, "aspect": 0.9 + 0.3 * _hash(i + seed_index), "seed": seed_index * 11 + i, "kind": "block", "ledges": 1 + (seed_index + i) % 3}, true)
				_column(st, tower)
				circles.append({"pos": at, "radius": wide})
			return circles
		"bastion":
			spec.aspect = 1.6
			spec.ledges = 3
			_column(st, spec)
			# Smaller blocks left standing on its top.
			for i in range(1 + seed_index % 2):
				var top = spec.duplicate()
				var at = origin + along * radius * (0.5 - 0.9 * i) + Vector3.UP * height * 0.96
				top.merge({"origin": at, "height": height * (0.2 + 0.12 * _hash(seed_index + i)), "radius": radius * 0.42, "seed": seed_index * 5 + i, "kind": "block", "ledges": 1}, true)
				_column(st, top)
			return [{"pos": origin, "radius": radius * 1.2}]
		"fin":
			spec.aspect = 3.2 + float(seed_index % 3) * 0.5
			spec.crown = 0.16
			_column(st, spec)
			var circles: Array = []
			for f in [-0.6, 0.0, 0.6]:
				circles.append({"pos": origin + along * f * radius * spec.aspect, "radius": radius * 1.1})
			return circles
		"slab":
			# Leaning across its long axis, as a block that broke off the wall.
			spec.aspect = 1.5 + 0.4 * _hash(seed_index)
			spec.tilt = (0.3 + 0.25 * _hash(seed_index * 13)) * (1.0 if seed_index % 2 == 0 else -1.0)
			spec.ledges = 1
			# Sunk by the tilt so its low edge stays buried.
			spec.origin = origin - Vector3.UP * radius * absf(sin(float(spec.tilt))) * 1.2
			_column(st, spec)
			return [{"pos": origin, "radius": radius * 1.2}]
	_column(st, spec)
	return [{"pos": origin, "radius": radius * (0.7 if kind == "hoodoo" else 1.0)}]

# How far a form reaches along its long axis from its centre, in metres.
static func reach(kind: String, radius: float, seed_index: int) -> float:
	match kind:
		"castle": return (float(_towers(seed_index) - 1) * 0.5 * TOWER_SPAN + 1.1) * radius
		"fin": return radius * (3.2 + float(seed_index % 3) * 0.5) * 1.25
		"bastion": return radius * 1.6 * 1.25
	return radius * 1.3

static func _towers(seed_index: int) -> int:
	return 3 + seed_index % 3

# A repeatable number in 0..1 for the n-th choice of a form.
static func _hash(n: int) -> float:
	return fposmod(sin(float(n) * 12.9898) * 43758.5453, 1.0)

# Size of the cross-section at fraction t of the height, as a share of the
# form's radius: a debris apron, a slight taper, ledges, a rounded top edge.
static func profile(spec: Dictionary, t: float) -> float:
	var apron = 1.0 + 0.3 * exp(-t * 16.0)
	if spec.kind == "hoodoo":
		if t < 0.68:
			return apron * (0.62 - 0.12 * t)
		return lerpf(0.55, 1.0, smoothstep(0.68, 0.74, t)) * _rounded(t, 0.9)
	var taper = 1.0 - (0.06 + 0.06 * _hash(int(spec.seed))) * t
	return apron * taper * _ledges(t, int(spec.ledges), 0.16, int(spec.seed)) * _rounded(t, 0.97)

# Sharp steps inward where one bed ends and a softer one begins.
static func _ledges(t: float, beds: int, depth: float, seed_index: int) -> float:
	var k = t * beds + float(seed_index % 7) * 0.11
	var step = floorf(k) + smoothstep(0.86, 1.0, k - floorf(k))
	return 1.0 - depth * step / beds

# A flat top with its edge rounded off over the last few percent.
static func _rounded(t: float, from: float) -> float:
	return sqrt(maxf(0.0, 1.0 - pow(maxf(0.0, t - from) / (1.0 - from), 2.0)))

# A rounded rectangle: flat faces with blunt corners, and the odd vertical
# crack running down a face.
static func _section(angle: float, seed_index: int) -> Vector2:
	var c = cos(angle)
	var s = sin(angle)
	var edge = Vector2(signf(c) * pow(absf(c), 0.4), signf(s) * pow(absf(s), 0.4))
	var crack = 1.0 - 0.14 * pow(maxf(0.0, sin(angle * 3.0 + seed_index * 1.3)), 16.0)
	var face = 1.0 + 0.04 * sin(angle * 7.0 + seed_index)
	return edge * crack * face

static func _column(st: SurfaceTool, spec: Dictionary) -> void:
	var height: float = spec.height
	var rings = clampi(int(height / 1.5), 8, 24)
	var basis = Basis(Vector3.UP, float(spec.yaw)) * Basis(Vector3.RIGHT, float(spec.tilt))
	var previous: Array = []
	for ring in range(rings + 1):
		var t = float(ring) / rings
		var r = float(spec.radius) * profile(spec, t)
		# Every third bed is softer and weathers back into a groove.
		if (ring + int(spec.seed)) % 3 == 0 and t > 0.08 and t < 0.94:
			r *= 0.94
		var row: Array = []
		for sector in range(SECTORS):
			var angle = sector * TAU / SECTORS
			var edge = _section(angle, spec.seed)
			# The crest is not quite level: broken where the cracks reach it.
			var top = 1.0 - float(spec.crown) * smoothstep(0.85, 1.0, t) * _hash(int(spec.seed) * 17 + sector)
			var local = Vector3(edge.x * r * float(spec.aspect), t * height * top, edge.y * r)
			var v: Vector3 = spec.origin + basis * local
			row.append([v, _color(spec, v, t, edge.length())])
		if not previous.is_empty():
			for sector in range(SECTORS):
				var next = (sector + 1) % SECTORS
				_quad(st, previous[sector], previous[next], row[sector], row[next])
		previous = row
	var centre: Vector3 = spec.origin + basis * Vector3(0.0, height * (1.0 - float(spec.crown) * 0.5), 0.0)
	var top_color: Color = previous[0][1].lightened(0.06)
	for sector in range(SECTORS):
		_triangle(st, previous[sector], previous[(sector + 1) % SECTORS], [centre, top_color])

# The strata of the walls toned towards the clay, with thin beds of their own
# a metre or so apart; cracks in shade; grey caprock only on a hoodoo's cap.
static func _color(spec: Dictionary, v: Vector3, t: float, edge: float) -> Color:
	var stone: Color = spec.biome.rock_color(v).lerp(CLAY, 0.45)
	var phase = fposmod(v.y * 0.62 + float(int(spec.seed) % 5) * 0.2, 1.0)
	var bed = 0.09 * (smoothstep(0.1, 0.18, phase) - smoothstep(0.42, 0.5, phase)) - 0.07 * (smoothstep(0.6, 0.66, phase) - smoothstep(0.8, 0.86, phase))
	stone = stone.lightened(bed) if bed > 0.0 else stone.darkened(-bed)
	if spec.kind == "hoodoo":
		stone = stone.lerp(CAPROCK, smoothstep(0.66, 0.72, t))
	return stone.darkened(clampf((1.0 - edge) * 0.9, 0.0, 0.16))

static func _quad(st: SurfaceTool, a: Array, b: Array, c: Array, d: Array) -> void:
	_triangle(st, a, b, c)
	_triangle(st, b, d, c)

static func _triangle(st: SurfaceTool, a: Array, b: Array, c: Array) -> void:
	for corner in [a, b, c]:
		st.set_color(corner[1])
		st.add_vertex(corner[0])
