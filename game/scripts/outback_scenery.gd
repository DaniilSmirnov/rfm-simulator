extends RefCounted
# Scenery of «Майншафт» (mineshaft.gd): open eucalyptus woodland on red earth
# and golden tussock grass, granite tors and termite mounds, the old mine
# headframe at the giant jump, a homestead with a windmill and water tank, and
# kangaroo warning signs. Everything is deterministic: placement uses its own
# seeded generator, so every room member builds the same bush.
const Props = preload("res://scripts/props.gd")
const Records = preload("res://scripts/stage_records.gd")
const DetailLayer = preload("res://scripts/detail_layer.gd")
const MeshMerge = preload("res://scripts/mesh_merge.gd")

const TIMBER = Color("8a6a48")
const IRON = Color("858b8e")
const RED_IRON = Color("7e3427")
const SIGN_YELLOW = Color("f2c230")
const SIGN_BLACK = Color("1d1c1a")
# Stations of the kangaroo warning signs and the side of the road they stand on.
const KANGAROO_SIGNS = [[14.0, 1.0], [236.0, -1.0], [610.0, 1.0], [818.0, -1.0]]

var stage
var biome
var rng = RandomNumberGenerator.new()
var counts := {}

func build(owner_stage, owner_biome) -> void:
	stage = owner_stage
	biome = owner_biome
	rng.seed = 20261013
	_eucalypts()
	_ground_cover()
	_granite_tors()
	_termite_mounds()
	_mine_headframe()
	_homestead()
	_kangaroo_signs()
	_jump_sign()
	for node_name in ["MineHeadframe", "Homestead", "KangarooSigns", "MineshaftSign"]:
		var node = stage.get_node_or_null(node_name)
		if node != null:
			MeshMerge.bake(node)

# Open ground away from the road, spectators, parks and buildings.
func open_ground(p: Vector3, road: float, padding: float) -> bool:
	if stage.road_distance(p) < road or stage.parks.contains(p, 4.0) or biome.reserved(p, padding):
		return false
	for c in stage.clearings:
		if Vector2(p.x - c.x, p.z - c.z).length() < 9.0 + padding:
			return false
	return true

func random_point() -> Vector3:
	return Vector3(rng.randf_range(-185, 185), 0, rng.randf_range(-stage.LENGTH - 60, 50))

func surface(p: Vector3) -> Vector3:
	p.y = stage.terrain_surface_height(p)
	return p

# ---------------------------------------------------------------- vegetation

# Gum trees: pale, leaning trunks with a few sparse grey-green clumps of leaves.
# They grow in loose groves and stop cars like any other tree.
func _eucalypts() -> void:
	var stick = CylinderMesh.new()
	stick.top_radius = 0.32
	stick.bottom_radius = 0.5
	stick.height = 1.0
	stick.radial_segments = 6
	stick.rings = 1
	var clump = SphereMesh.new()
	clump.radial_segments = 7
	clump.rings = 3
	var gums: Array = []
	for grove in range(70):
		var center = random_point()
		if not open_ground(center, 12.0, 4.0):
			continue
		for k in range(rng.randi_range(2, 8)):
			var p = center + Vector3(rng.randf_range(-11, 11), 0, rng.randf_range(-11, 11))
			if not open_ground(p, 9.5, 2.0):
				continue
			gums.append({"base": surface(p) - Vector3.UP * 0.05, "height": rng.randf_range(9.0, 17.0), "yaw": rng.randf() * TAU, "shade": rng.randf_range(-0.05, 0.06)})
	stage.woodland.tree_layers("GumTree", gums, [
		{"mesh": stick, "scale": Vector3(0.028, 0.7, 0.028), "y": 0.35, "tilt": 0.06, "color": "bdb39e"},
		{"mesh": clump, "scale": Vector3(0.15, 0.12, 0.14), "y": 0.6, "dx": 0.15, "color": "5d6b48"},
		{"mesh": clump, "scale": Vector3(0.14, 0.11, 0.14), "y": 0.66, "dx": -0.14, "color": "65724c"},
		{"mesh": clump, "scale": Vector3(0.18, 0.14, 0.17), "y": 0.76, "dx": 0.05, "color": "6c7a53"},
		{"mesh": clump, "scale": Vector3(0.13, 0.1, 0.12), "y": 0.84, "dx": -0.09, "color": "5f6d4a"},
		{"mesh": clump, "scale": Vector3(0.12, 0.1, 0.12), "y": 0.93, "dx": 0.02, "color": "75825a"},
	])
	counts["gums"] = gums.size()

func _ground_cover() -> void:
	var tussock_p: Array = []
	var tussock_c: Array = []
	var shrub_p: Array = []
	var shrub_c: Array = []
	var shrubs = [Color("7b7f4f"), Color("6a7550"), Color("8f8656")]
	for i in range(9000):
		var p = random_point()
		if not open_ground(p, 6.5, 0.0):
			continue
		p = surface(p)
		var yaw = rng.randf() * TAU
		if i % 9 == 0:
			var size = rng.randf_range(0.5, 1.4)
			shrub_p.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(size, size * rng.randf_range(0.5, 0.8), size)), p))
			shrub_c.append(shrubs[i % 3])
		else:
			var size = rng.randf_range(0.7, 1.5)
			tussock_p.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(size, rng.randf_range(0.6, 1.3), size)), p))
			tussock_c.append(Color("d2b46a").lerp(Color("a49a58"), rng.randf()))
	stage.detail_batch("OutbackTussocks", stage.NATURE_GRASS, tussock_p, tussock_c, DetailLayer.tiled(170.0))
	stage.detail_batch("OutbackSaltbush", stage.NATURE_BUSH, shrub_p, shrub_c, DetailLayer.tiled(220.0))
	counts["tussocks"] = tussock_p.size()

# Rounded granite boulders piled into tors on the hills; large ones are solid.
func _granite_tors() -> void:
	var poses: Array = []
	var colors: Array = []
	for tor in range(26):
		var center = random_point()
		if not open_ground(center, 14.0, 5.0):
			continue
		for k in range(rng.randi_range(3, 7)):
			var p = center + Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4))
			var radius = rng.randf_range(0.8, 2.6) * (1.3 if k == 0 else 1.0)
			p = surface(p) + Vector3.UP * radius * 0.35
			var yaw = rng.randf() * TAU
			poses.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(radius * 1.2, radius * 0.85, radius)), p))
			colors.append(Color("a39d92").lerp(Color("8c857a"), rng.randf()))
			if radius > 1.2:
				stage.rocks.append(Records.rock(p, radius * 0.9, radius * 1.4, Records.FOREST))
	stage.detail_batch("GraniteTors", stage.NATURE_BOULDER, poses, colors, DetailLayer.tiled(320.0))
	counts["boulders"] = poses.size()

# Red earth termite mounds: knobbly cones up to head height.
func _termite_mounds() -> void:
	var cone = CylinderMesh.new()
	cone.top_radius = 0.22
	cone.bottom_radius = 0.5
	cone.height = 1.0
	cone.radial_segments = 6
	cone.rings = 2
	var poses: Array = []
	var colors: Array = []
	for i in range(220):
		var p = random_point()
		if not open_ground(p, 8.0, 1.5):
			continue
		var height = rng.randf_range(0.8, 2.4)
		var width = height * rng.randf_range(0.45, 0.7)
		p = surface(p) - Vector3.UP * 0.1
		poses.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(width, height, width * 0.85)), p + Vector3.UP * height * 0.5))
		colors.append(Color("6e3a24").lerp(Color("85492c"), rng.randf()))
		stage.rocks.append(Records.rock(p, width * 0.45, height))
	stage.detail_batch("TermiteMounds", cone, poses, colors, DetailLayer.tiled(240.0))
	counts["termite_mounds"] = poses.size()

# ---------------------------------------------------------------- buildings

func _anchor(name: String, at: Vector3, facing: Vector3) -> Node3D:
	var node = Node3D.new()
	node.name = name
	stage.add_child(node)
	node.position = at
	node.rotation.y = atan2(facing.x, facing.z)
	return node

# The old timber headframe of the mine the stage is named after, with its
# winding wheel, a tin shed and a spoil heap of red rock.
func _mine_headframe() -> void:
	var s: float = biome.MINE[0]
	var mine = _anchor("MineHeadframe", biome.mine, stage.at(s) - biome.mine)
	var height = 15.0
	for corner in [Vector3(-2.2, 0, -2.2), Vector3(2.2, 0, -2.2), Vector3(-2.2, 0, 2.2), Vector3(2.2, 0, 2.2)]:
		var leg = Props.box(mine, corner * 0.75 + Vector3.UP * height * 0.5, Vector3(0.35, height, 0.35), TIMBER)
		leg.rotation = Vector3(-corner.z * 0.035, 0, corner.x * 0.035)
	for level in [3.5, 7.5, 11.5]:
		for side in [-1.0, 1.0]:
			Props.box(mine, Vector3(0, level, side * 1.55), Vector3(3.6, 0.22, 0.22), TIMBER.darkened(0.1))
			Props.box(mine, Vector3(side * 1.55, level, 0), Vector3(0.22, 0.22, 3.6), TIMBER.darkened(0.1))
	# Raking back-leg that takes the pull of the hoist rope.
	var strut = Props.box(mine, Vector3(0, height * 0.45, -5.0), Vector3(0.35, height * 1.05, 0.35), TIMBER)
	strut.rotation.x = -0.42
	Props.box(mine, Vector3(0, height + 0.2, 0), Vector3(3.8, 0.4, 3.8), TIMBER.darkened(0.15))
	var wheel = Props.cylinder(mine, Vector3(0, height + 1.9, 0), 1.7, 1.7, 0.18, Color("4a4440"), 14)
	wheel.rotation.z = PI * 0.5
	var axle = Props.cylinder(mine, Vector3(0, height + 1.9, 0), 0.3, 0.3, 0.5, Color("2f2b28"), 8)
	axle.rotation.z = PI * 0.5
	# Collar of the shaft and the hoist house behind it.
	Props.box(mine, Vector3(0, 0.25, 0), Vector3(3.2, 0.5, 3.2), Color("5c4a3a"))
	Props.box(mine, Vector3(0, 1.6, -9.0), Vector3(5.0, 3.2, 4.0), Color("8e3f26"))
	var roof = Props.box(mine, Vector3(0, 3.45, -9.0), Vector3(5.6, 0.12, 4.6), IRON)
	roof.rotation.x = 0.08
	stage.rocks.append(Records.rock(biome.mine, 3.0, height, Records.BUILDING))
	stage.rocks.append(Records.rock(mine.to_global(Vector3(0, 0, -9.0)), 3.0, 3.4, Records.BUILDING))
	var heap = mine.to_global(Vector3(7.5, 0, -6.0))
	heap.y = stage.terrain_surface_height(heap) - 0.4
	Props.cylinder(stage, heap + Vector3.UP * 2.2, 6.5, 1.2, 4.4, Color("9b4f30"), 9)
	stage.rocks.append(Records.rock(heap, 5.5, 4.0))
	_flag(mine, Vector3(3.4, 0, 2.6))

# Simplified Australian flag on a pole: blue field, Southern Cross, Union corner.
func _flag(parent: Node3D, at: Vector3) -> void:
	Props.cylinder(parent, at + Vector3.UP * 3.5, 0.05, 0.04, 7.0, Color("d8d8d2"), 6)
	var cloth = at + Vector3(0.95, 6.3, 0)
	Props.box(parent, cloth, Vector3(1.8, 0.9, 0.03), Color("1f3f8f"))
	Props.box(parent, cloth + Vector3(-0.45, 0.22, 0.02), Vector3(0.9, 0.08, 0.02), Color("f4f4f0"))
	Props.box(parent, cloth + Vector3(-0.45, 0.22, 0.03), Vector3(0.9, 0.04, 0.02), Color("c8202c"))
	Props.box(parent, cloth + Vector3(-0.45, 0.22, 0.02), Vector3(0.08, 0.45, 0.02), Color("f4f4f0"))
	Props.box(parent, cloth + Vector3(-0.45, 0.22, 0.03), Vector3(0.04, 0.45, 0.02), Color("c8202c"))
	for star in [Vector2(0.45, 0.25), Vector2(0.3, 0.0), Vector2(0.6, 0.05), Vector2(0.45, -0.28), Vector2(-0.45, -0.25)]:
		Props.box(parent, cloth + Vector3(star.x, star.y, 0.02), Vector3(0.08, 0.08, 0.02), Color("f4f4f0"))

# Homestead: a tin-roofed shed, a corrugated water tank and a windmill pump.
func _homestead() -> void:
	var s: float = biome.HOMESTEAD[0]
	var home = _anchor("Homestead", biome.homestead, stage.at(s) - biome.homestead)
	Props.box(home, Vector3(0, 1.0, 0), Vector3(10.0, 3.6, 7.0), Color("a8916c"))
	for sign in [-1.0, 1.0]:
		var slab = Props.box(home, Vector3(0, 3.35, sign * 1.85), Vector3(10.6, 0.1, 4.0), RED_IRON)
		slab.rotation.x = sign * 0.32
	Props.box(home, Vector3(0, 2.1, 4.0), Vector3(10.0, 0.1, 1.8), RED_IRON.lightened(0.06))
	for x in [-4.6, -1.5, 1.5, 4.6]:
		Props.cylinder(home, Vector3(x, 1.05, 4.8), 0.07, 0.07, 2.1, Color("e8e3d6"), 5)
	Props.box(home, Vector3(-2.5, 1.0, 3.52), Vector3(1.0, 2.0, 0.06), Color("355a43"))
	Props.box(home, Vector3(2.0, 1.4, 3.52), Vector3(1.4, 1.0, 0.06), Color("3b4a52"))
	stage.rocks.append(Records.rock(biome.homestead, 5.6, 3.6, Records.BUILDING))
	var tank = Vector3(7.5, 0, 1.0)
	Props.cylinder(home, tank + Vector3.UP * 1.3, 1.7, 1.7, 2.6, Color("8f9599"), 14)
	for ring in [0.5, 1.1, 1.7, 2.3]:
		Props.cylinder(home, tank + Vector3.UP * ring, 1.74, 1.74, 0.08, Color("7a8084"), 14)
	Props.cylinder(home, tank + Vector3.UP * 2.75, 1.75, 0.2, 0.35, Color("80868a"), 14)
	stage.rocks.append(Records.rock(home.to_global(tank), 1.8, 2.9, Records.BUILDING))
	_windmill(home, Vector3(10.5, 0, -4.0))

func _windmill(parent: Node3D, at: Vector3) -> void:
	var height = 9.0
	for corner in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1)]:
		var leg = Props.box(parent, at + corner * 0.55 + Vector3.UP * height * 0.5, Vector3(0.1, height, 0.1), Color("6f706c"))
		leg.rotation = Vector3(-corner.z * 0.06, 0, corner.x * 0.06)
	for level in [2.5, 5.0, 7.5]:
		Props.box(parent, at + Vector3.UP * level, Vector3(1.2 - level * 0.08, 0.06, 1.2 - level * 0.08), Color("6f706c"))
	var hub = Node3D.new()
	hub.name = "WindmillRotor"
	parent.add_child(hub)
	hub.position = at + Vector3(0, height + 0.3, 0.45)
	# The rotor keeps its own nodes so outback_life.gd can turn it in the wind.
	hub.set_meta("unbatched", true)
	for blade in range(12):
		var vane = Props.box(hub, Vector3.ZERO, Vector3(0.28, 1.7, 0.03), Color("d9dcd8"))
		vane.rotation.z = blade * TAU / 12.0
		vane.position = Vector3(-sin(vane.rotation.z), cos(vane.rotation.z), 0) * 0.95
	MeshMerge.bake(hub)
	Props.box(parent, at + Vector3(0, height + 0.3, -1.2), Vector3(0.05, 0.9, 1.4), Color("c23b2b"))
	stage.rocks.append(Records.rock(parent.to_global(at), 0.9, height, Records.BUILDING))

# ---------------------------------------------------------------- signs

# Yellow diamond "kangaroos next X km" signs with a black kangaroo silhouette.
func _kangaroo_signs() -> void:
	var signs = Node3D.new()
	signs.name = "KangarooSigns"
	stage.add_child(signs)
	for item in KANGAROO_SIGNS:
		var s: float = item[0]
		var p = stage.at(s) + stage.side(s) * float(item[1]) * (stage.road_width(s) * 0.5 + 1.6)
		p.y = stage.ground(p)
		var post = Node3D.new()
		signs.add_child(post)
		post.position = p
		var direction = stage.direction(s)
		post.rotation.y = atan2(-direction.x, -direction.z)
		_kangaroo_sign(post)
		stage.rocks.append(Records.rock(p, 0.15, 2.4, Records.BARRIER))

func _kangaroo_sign(post: Node3D) -> void:
	Props.box(post, Vector3(0, 1.1, 0), Vector3(0.08, 2.2, 0.08), Color("8f9497"))
	var plate = Props.box(post, Vector3(0, 2.15, 0.06), Vector3(0.9, 0.9, 0.04), SIGN_YELLOW)
	plate.rotation.z = PI * 0.25
	var border = Props.box(post, Vector3(0, 2.15, 0.035), Vector3(0.98, 0.98, 0.02), SIGN_BLACK)
	border.rotation.z = PI * 0.25
	var front = 0.09
	# Body, head, ears, tail and the big hind legs of a hopping kangaroo.
	var body = Props.box(post, Vector3(0.0, 2.2, front), Vector3(0.18, 0.34, 0.01), SIGN_BLACK)
	body.rotation.z = -0.55
	Props.box(post, Vector3(0.14, 2.42, front), Vector3(0.12, 0.08, 0.01), SIGN_BLACK)
	Props.box(post, Vector3(0.12, 2.5, front), Vector3(0.03, 0.08, 0.01), SIGN_BLACK)
	var tail = Props.box(post, Vector3(-0.2, 2.03, front), Vector3(0.36, 0.05, 0.01), SIGN_BLACK)
	tail.rotation.z = 0.35
	var leg = Props.box(post, Vector3(-0.02, 1.98, front), Vector3(0.26, 0.07, 0.01), SIGN_BLACK)
	leg.rotation.z = 0.2
	Props.box(post, Vector3(0.1, 2.25, front), Vector3(0.1, 0.03, 0.01), SIGN_BLACK)
	# Distance plate below: "NEXT 14 km" style, kept as a short caption.
	Props.box(post, Vector3(0, 1.4, 0.06), Vector3(0.8, 0.26, 0.04), SIGN_YELLOW)
	Props.label_3d(post, Vector3(0, 1.4, 0.085), "NEXT 14 km", 40, 0.004, SIGN_BLACK)

# A weathered timber sign at the start of the straight names the jump.
func _jump_sign() -> void:
	var s = biome.LIP - 120.0
	var side = 1.0
	var p = stage.at(s) + stage.side(s) * side * (stage.road_width(s) * 0.5 + 3.0)
	p.y = stage.ground(p)
	var sign = _anchor("MineshaftSign", p, -stage.direction(s))
	for x in [-1.6, 1.6]:
		Props.cylinder(sign, Vector3(x, 1.3, 0), 0.12, 0.12, 2.6, TIMBER, 6)
		stage.rocks.append(Records.rock(sign.to_global(Vector3(x, 0, 0)), 0.2, 2.6, Records.BARRIER))
	Props.box(sign, Vector3(0, 2.2, 0), Vector3(4.2, 0.9, 0.12), Color("6b4b30"))
	Props.label_3d(sign, Vector3(0, 2.25, 0.07), "MINESHAFT", 96, 0.006, Color("f0dcae"))
	Props.label_3d(sign, Vector3(0, 1.92, 0.07), "ТРАМПЛИН 120 м", 48, 0.005, Color("f0dcae"))
	Props.label_3d(sign, Vector3(0, 2.25, -0.07), "MINESHAFT", 96, 0.006, Color("f0dcae"), PI)
