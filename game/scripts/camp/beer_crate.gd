extends RefCounted
# The beer crate on a camp table: a cardboard tray of 24 cans (the player's own
# camp table and every spectators' table carry one). A can leaves the crate the
# moment a fan starts drinking it; an empty crate gives no more beer. The host
# keeps the count of every crate (`left`, source -> cans; -1 is the player's
# camp, 0.. the spectators' groups) and sends it with the camp snapshot; a
# guest takes a can through the "take_beer" command and shows it gone at once.
#   BeerCrate.build(table, spot, yaw)  # the model, from TableModel.build
#   crates.take(source)                # authority: one can out, false if empty
const P = preload("res://scripts/core/props.gd")
const MeshMerge = preload("res://scripts/core/mesh_merge.gd")
const SIZE = 24
const COLUMNS = 6
const PITCH = 0.068
# The same can the fan drinks (Props.beer_hand) at half its size: gold body,
# silver lids, the dark green label band.
const CAN_SCALE = 0.5
const CAN_RADIUS = 0.065 * CAN_SCALE
const CAN_HEIGHT = 0.23 * CAN_SCALE
const CARDBOARD = Color("b58a55")
const PRINT = Color("2f6b3f")
static var _can_mesh: Mesh

var game
var left: Dictionary = {}

static func build(table: Node3D, spot: Vector3, yaw: float) -> Node3D:
	var crate = Node3D.new()
	crate.name = "BeerCrate"
	table.add_child(crate)
	crate.position = spot
	crate.rotation.y = yaw
	var rows = SIZE / COLUMNS
	var inner = Vector2(COLUMNS * PITCH, rows * PITCH)
	# An open cardboard tray: the floor, low walls and the brewery's print.
	P.box(crate, Vector3(0, 0.004, 0), Vector3(inner.x + 0.012, 0.008, inner.y + 0.012), CARDBOARD)
	for side in [-1.0, 1.0]:
		P.box(crate, Vector3(0, 0.035, side * (inner.y * 0.5 + 0.003)), Vector3(inner.x + 0.012, 0.062, 0.006), CARDBOARD)
		P.box(crate, Vector3(side * (inner.x * 0.5 + 0.003), 0.035, 0), Vector3(0.006, 0.062, inner.y), CARDBOARD)
		P.box(crate, Vector3(0, 0.038, side * (inner.y * 0.5 + 0.0065)), Vector3(inner.x * 0.6, 0.03, 0.001), PRINT)
	MeshMerge.bake(crate, "beer_crate", ["Cans"])
	if _can_mesh == null:
		_can_mesh = can_mesh()
	var cans = MultiMeshInstance3D.new()
	cans.name = "Cans"
	var multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _can_mesh
	multimesh.instance_count = SIZE
	# Row by row from the far corner, so the crate empties from one end.
	for i in range(SIZE):
		var x = (i % COLUMNS - (COLUMNS - 1) * 0.5) * PITCH
		var z = (i / COLUMNS - (rows - 1) * 0.5) * PITCH
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(x, 0.008 + CAN_HEIGHT * 0.5, z)))
	cans.multimesh = multimesh
	crate.add_child(cans)
	return crate

static func can_mesh() -> Mesh:
	var root = Node3D.new()
	var k = CAN_SCALE
	P.cylinder(root, Vector3.ZERO, 0.065 * k, 0.065 * k, 0.23 * k, Color("dbb54e"), 10)
	for y in [0.12 * k, -0.12 * k]:
		P.cylinder(root, Vector3(0, y, 0), 0.062 * k, 0.062 * k, 0.008 * k, Color("c4cac5"), 10)
	P.box(root, Vector3(0, 0, 0.064 * k), Vector3(0.095 * k, 0.12 * k, 0.006 * k), Color("35482c"))
	P.box(root, Vector3(0, 0.128 * k, 0.015 * k), Vector3(0.025 * k, 0.006 * k, 0.045 * k), Color("888f89"))
	var mesh: Mesh = MeshMerge.bake(root, "crate_can").mesh
	root.free()
	return mesh

static func show_cans(table: Node3D, count: int) -> void:
	if table == null or not is_instance_valid(table):
		return
	var cans = table.get_node_or_null("BeerCrate/Cans") as MultiMeshInstance3D
	if cans != null:
		cans.multimesh.visible_instance_count = clampi(count, 0, SIZE)

func count(source: int) -> int:
	return int(left.get(source, SIZE))

func table(source: int) -> Node3D:
	if source == -1:
		return game.camp
	if game.spectators != null and source >= 0 and source < game.spectators.groups.size():
		return game.spectators.groups[source].table
	return null

# One can out of the crate at `source`; false when it is empty or not there.
func take(source: int) -> bool:
	if table(source) == null or count(source) <= 0:
		return false
	left[source] = count(source) - 1
	show_cans(table(source), left[source])
	return true

func refresh() -> void:
	show_cans(game.camp, count(-1))
	if game.spectators != null:
		for i in range(game.spectators.groups.size()):
			show_cans(game.spectators.groups[i].table, count(i))

# Only the crates that are no longer full go over the wire.
func snapshot() -> Dictionary:
	var out = {}
	for source in left:
		out[str(source)] = int(left[source])
	return out

func apply_snapshot(value) -> void:
	left.clear()
	if value is Dictionary:
		for key in value:
			if str(key).is_valid_int():
				left[int(key)] = clampi(int(value[key]), 0, SIZE)
	refresh()
