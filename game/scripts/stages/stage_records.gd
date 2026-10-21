extends RefCounted
# The record shapes kept in stage.rocks[] and stage.collectibles[]. They stay
# Dictionaries because baked scenes (baked_village.gd) and room snapshots store
# them as plain data, but every record is made here, so the field set lives in
# one place and a misspelt key cannot appear at a single call site.

# Kinds of solid round obstacles; a kind adds its flag to the record.
const ROCK = ""
const FOREST = "forest"       # boulders and outcrops among trees
const BARRIER = "barrier"     # roadside posts and stones (alpine barriers)
const BUILDING = "building"   # house footprints approximated by circles
const OFFICIAL = "official"   # course officials' stands; rebuilt after baking
const POST = "post"           # sign and fence posts, stakes, thin trunks

# Records spaced at most `spacing` apart strictly between a and b, so a run of
# posts, rails or pickets leaves no gap a walker (0.3 m) or a car slips through.
static func row(a: Vector3, b: Vector3, radius: float, height: float, kind: String, spacing: float) -> Array:
	var records: Array = []
	var count = ceili(Vector2(b.x - a.x, b.z - a.z).length() / spacing)
	for i in range(1, count):
		records.append(rock(a.lerp(b, float(i) / count), radius, height, kind))
	return records

# Rectangular footprints (w along `across`, d deep) as a row of circles that
# stay inside the walls: the solid box over the footprint covers the corners.
static func footprint(center: Vector3, across: Vector3, w: float, d: float, height: float) -> Array:
	var records: Array = []
	var circles = maxi(1, ceili(w / d))
	for i in range(circles):
		var offset = (float(i) - (circles - 1) * 0.5) * (w / circles)
		records.append(rock(center + across * offset, minf(w / circles, d) * 0.5, height, BUILDING))
	return records

# A vertical cylinder that stops cars, walkers, gravel and furniture.
static func rock(pos: Vector3, radius: float, height: float, kind: String = ROCK) -> Dictionary:
	var record = {"pos": pos, "radius": radius, "height": height}
	if kind != ROCK:
		record[kind] = true
	return record

# Something to pick up: `parts` maps detail layers (stage.detail_batch names) to
# the instance indices hidden when it is harvested.
static func collectible(kind: String, pos: Vector3, quantity: int, parts: Dictionary, title: String = "", species: String = "") -> Dictionary:
	var record = {"kind": kind}
	if species != "":
		record.species = species
	if title != "":
		record.name = title
	record.pos = pos
	record.quantity = quantity
	record.parts = parts
	return record
