extends RefCounted
# The rock forms of the Valley of Castles (canyon_scenery.gd places them). In
# the real valley no two «castles» are alike: the soft red claystone weathers
# into fluted towers, ribbed fins and stepped bastions, while the grey
# conglomerate above it holds out as flat caps and overhanging hats. Each form
# here is a column of rings — a cross-section (round, oval or a long fin, with
# vertical flutes) swept up a radius profile (ledges, a debris skirt, a neck
# under a cap) — coloured by the same strata as the walls, darker in the
# flutes and grey where the caprock is.
#
#   bastion  a massive stepped block against the wall, turrets on its top
#   tower    a fluted column, tapering, with a grey cap that overhangs
#   hoodoo   a thin neck under a wide grey hat
#   fin      a long narrow wall of rock, its crest broken into pinnacles
#   needle   a slender spire ending in a point
#   dome     a rounded beehive of thin terraced beds

const KINDS = ["bastion", "tower", "hoodoo", "fin", "needle", "dome"]
const SECTORS = 10
const CAPROCK = Color("b9ab94")
const CLAY = Color("b4643c")

# Builds one form into `st` with its foot at `origin` and returns the circles
# that stop people and cars: [{"pos": Vector3, "radius": float}].
static func build(st: SurfaceTool, biome, origin: Vector3, kind: String, height: float, radius: float, yaw: float, seed_index: int) -> Array:
	var spec = {"biome": biome, "origin": origin, "height": height, "radius": radius, "yaw": yaw, "seed": seed_index, "aspect": 1.0, "cap": 2.0, "kind": kind}
	match kind:
		"bastion":
			spec.aspect = 1.35
			spec.cap = 0.9
			_column(st, spec)
			for i in range(2 + seed_index % 3):
				var angle = seed_index * 1.7 + i * 2.3
				var at = origin + Vector3(cos(angle), 0.0, sin(angle)) * radius * (0.18 + 0.12 * (i % 2)) + Vector3.UP * height * 0.97
				build(st, biome, at, "tower" if i % 2 == 0 else "needle", height * (0.22 + 0.1 * ((seed_index + i) % 3)), radius * 0.2, yaw + i, seed_index + i * 7)
			return [{"pos": origin, "radius": radius * 1.05}]
		"fin":
			spec.aspect = 2.6 + (seed_index % 3) * 0.6
			spec.cap = 0.93
			_column(st, spec)
			var circles: Array = []
			var along = Vector3(cos(yaw), 0.0, -sin(yaw))
			var reach = radius * spec.aspect * 0.62
			var count = 3 + seed_index % 3
			for i in range(count):
				var f = lerpf(-1.0, 1.0, float(i) / (count - 1))
				var at = origin + along * f * reach + Vector3.UP * height * (0.9 - absf(f) * 0.12)
				build(st, biome, at, "needle" if (i + seed_index) % 2 == 0 else "tower", height * (0.18 + 0.08 * ((i * 5 + seed_index) % 3)), radius * 0.42, yaw + f, seed_index + i * 3)
				circles.append({"pos": origin + along * f * reach, "radius": radius * 0.85})
			return circles
		"tower":
			spec.cap = 0.86
		"hoodoo":
			spec.cap = 0.74
		"dome":
			spec.aspect = 1.15
	_column(st, spec)
	return [{"pos": origin, "radius": radius * (0.6 if kind == "hoodoo" else 0.85)}]

# Radius of the form at fraction t of its height, as a share of its radius.
static func profile(kind: String, t: float, seed_index: int) -> float:
	var skirt = 1.0 + 0.55 * exp(-t * 9.0)
	match kind:
		"bastion":
			return skirt * (1.0 - 0.18 * t) * _ledges(t, 3, 0.3, seed_index) * _rounded(t, 0.96)
		"fin":
			return skirt * (1.0 - 0.45 * t) * _ledges(t, 4, 0.2, seed_index) * _rounded(t, 0.94)
		"hoodoo":
			if t < 0.7:
				return skirt * (0.75 - 0.37 * smoothstep(0.05, 0.7, t))
			if t < 0.78:
				return lerpf(0.38, 1.05, smoothstep(0.7, 0.78, t))
			return 1.05 * sqrt(maxf(0.0, 1.0 - pow((t - 0.78) / 0.22, 2.0)))
		"needle":
			return skirt * pow(1.0 - t, 0.85) * (1.0 + 0.08 * sin(t * 23.0 + seed_index)) + 0.02
		"dome":
			return skirt * sqrt(maxf(0.0, 1.0 - t * t)) * _ledges(t, 5, 0.12, seed_index) + 0.02
	# tower: a taper, ledges where the softer beds weather back, an overhanging cap
	var cap = 1.0 + 0.14 * smoothstep(0.84, 0.88, t)
	return skirt * (1.0 - 0.38 * t) * _ledges(t, 4, 0.22, seed_index) * cap * _rounded(t, 0.97)

# Sharp steps inward where one bed ends and a softer one begins.
static func _ledges(t: float, beds: int, depth: float, seed_index: int) -> float:
	var k = t * beds + float(seed_index % 7) * 0.13
	var step = floorf(k) + smoothstep(0.82, 1.0, k - floorf(k))
	return 1.0 - depth * step / beds

# A flat top with its edge rounded off over the last few percent.
static func _rounded(t: float, from: float) -> float:
	return sqrt(maxf(0.0, 1.0 - pow(maxf(0.0, t - from) / (1.0 - from), 2.0)))

# The vertical flutes: deep gullies between ribs, irregular round the form.
static func _flute(angle: float, seed_index: int, kind: String) -> float:
	var depth = 0.1 if kind == "dome" else 0.22
	return 1.0 + sin(angle * 5.0 + seed_index) * depth + cos(angle * 9.0 - seed_index * 0.4) * depth * 0.5 + sin(angle * 13.0 + seed_index * 2.1) * depth * 0.25

static func _column(st: SurfaceTool, spec: Dictionary) -> void:
	var height: float = spec.height
	# Fine enough rings for a ledge or the flare of a hat to show.
	var rings = clampi(int(height / 1.6), 14 if spec.kind == "hoodoo" else 9, 20)
	var basis = Basis(Vector3.UP, float(spec.yaw))
	var previous: Array = []
	for ring in range(rings + 1):
		var t = float(ring) / rings
		var r = float(spec.radius) * profile(spec.kind, t, spec.seed)
		var row: Array = []
		for sector in range(SECTORS):
			var angle = sector * TAU / SECTORS
			var groove = _flute(angle, spec.seed, spec.kind)
			var local = Vector3(cos(angle) * groove * r * float(spec.aspect), t * height, sin(angle) * groove * r)
			var v: Vector3 = spec.origin + basis * local
			row.append([v, _color(spec, v, t, groove)])
		if not previous.is_empty():
			for sector in range(SECTORS):
				var next = (sector + 1) % SECTORS
				_quad(st, previous[sector], previous[next], row[sector], row[next])
		previous = row
	var top: Vector3 = spec.origin + Vector3.UP * height * (1.0 if spec.kind in ["needle", "dome", "hoodoo"] else 1.005)
	var top_color: Color = previous[0][1]
	for sector in range(SECTORS):
		_triangle(st, previous[sector], previous[(sector + 1) % SECTORS], [top, top_color.lightened(0.05)])

# The strata of the walls, toned towards the clay; grey caprock on top; the
# flutes in shade.
static func _color(spec: Dictionary, v: Vector3, t: float, groove: float) -> Color:
	var stone: Color = spec.biome.rock_color(v).lerp(CLAY, 0.35 + 0.1 * float(int(spec.seed) % 3))
	stone = stone.lerp(CAPROCK, smoothstep(float(spec.cap) - 0.02, float(spec.cap) + 0.03, t))
	return stone.darkened(clampf((1.05 - groove) * 0.5, 0.0, 0.18))

static func _quad(st: SurfaceTool, a: Array, b: Array, c: Array, d: Array) -> void:
	_triangle(st, a, b, c)
	_triangle(st, b, d, c)

static func _triangle(st: SurfaceTool, a: Array, b: Array, c: Array) -> void:
	for corner in [a, b, c]:
		st.set_color(corner[1])
		st.add_vertex(corner[0])
