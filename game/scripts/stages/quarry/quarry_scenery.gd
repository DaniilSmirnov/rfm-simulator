extends RefCounted
# Scenery of «Асбестовский карьер» (quarry.gd), placed on the land that
# quarry_form.gd describes: the rock windrow along the open edge of the haul
# road, boulder bunds on the berms and fallen blocks at the foot of every
# face, the shovel loading a BelAZ on the floor with another waiting its turn,
# a third BelAZ by the spectators on the rim, a blast-hole drill on the far
# rim, the green water of the sump, birch scrub on the old dumps and a sign at
# the top of the haul road. Placement uses its own seeded generator, so every
# room member builds the same pit and stage.rng is never disturbed.
const Props = preload("res://scripts/core/props.gd")
const Records = preload("res://scripts/stages/stage_records.gd")
const DetailLayer = preload("res://scripts/stages/detail_layer.gd")
const MeshMerge = preload("res://scripts/core/mesh_merge.gd")
const LoadPacer = preload("res://scripts/core/load_pacer.gd")
const Movable = preload("res://scripts/core/prop_registry.gd")
const Form = preload("res://scripts/stages/quarry/quarry_form.gd")
const Machines = preload("res://scripts/stages/quarry/quarry_machines.gd")

# The shovel works the east face of the floor, the loaded truck stands on its
# north side and an empty one waits south of it (world x, z; heading of the
# front as a world direction).
const SHOVEL = [-22.0, -522.0, Vector3(1, 0, 0)]
const LOADING = [-21.0, -507.5, Vector3(-1, 0, 0)]
const WAITING = [-30.0, -560.0, Vector3(0, 0, 1)]
const DRILL = [-168.0, -470.0, Vector3(0, 0, -1)]
# The BelAZ the spectators on the rim climb on: station offset from the top of
# the haul road, side and distance.
const RIM_TRUCK = [-46.0, 1.0, 22.0]
# Where the haul road's windrow stands: this far past the road edge.
const WINDROW_OFFSET = 1.7
const WINDROW_SPACING = 1.5

var stage
var biome
var rng = RandomNumberGenerator.new()
var counts := {}
var shovel: Node3D
var machines: Array[Node3D] = []

func configure(owner_stage, owner_biome) -> void:
	stage = owner_stage
	biome = owner_biome
	for spot in [SHOVEL, LOADING, WAITING, DRILL]:
		biome.reserved_spots.append({"pos": _floor_spot(spot), "radius": 9.0})
	biome.reserved_spots.append({"pos": rim_truck_spot(), "radius": 9.0})

func _floor_spot(spot: Array) -> Vector3:
	return Vector3(spot[0], 0.0, spot[1])

func rim_truck_spot() -> Vector3:
	var s = biome.ramp_begin + float(RIM_TRUCK[0])
	return stage.at(s) + stage.side(s) * float(RIM_TRUCK[1]) * float(RIM_TRUCK[2])

func build(cooperative: bool = false) -> void:
	rng.seed = 20261022
	_machines()
	await _windrow(cooperative)
	await _bunds(cooperative)
	await _talus(cooperative)
	await _dump_cover(cooperative)
	_birches()
	_sump()
	_ramp_sign()

func surface(p: Vector3) -> Vector3:
	p.y = stage.terrain_surface_height(p)
	return p

func random_point() -> Vector3:
	var bounds: Rect2 = biome.world_bounds()
	return Vector3(rng.randf_range(bounds.position.x + 8.0, bounds.end.x - 8.0), 0, rng.randf_range(bounds.position.y + 10.0, bounds.end.y - 20.0))

# Open ground away from the road, the spectator areas, the parks and machines.
func open_ground(p: Vector3, road: float, padding: float) -> bool:
	if stage.road_distance(p, road) < road or stage.parks.contains(p, 6.0) or biome.reserved(p, padding):
		return false
	for c in stage.clearings:
		if Vector2(p.x - c.x, p.z - c.z).length() < 10.0 + padding:
			return false
	return true

# The side of the road the pit lies on at station s (+1 right, -1 left).
func pit_side(s: float) -> float:
	var p = stage.at(s)
	var towards = Vector3(Form.AXIS_X - p.x, 0.0, clampf(p.z, Form.SOUTH_Z, Form.NORTH_Z) - p.z)
	return 1.0 if stage.side(s).dot(towards) > 0.0 else -1.0

# ---------------------------------------------------------------- machines

func _anchor(node: Node3D, at: Vector3, front: Vector3) -> Node3D:
	stage.add_child(node)
	node.position = surface(at)
	node.rotation.y = atan2(-front.x, -front.z)
	return node

func _machines() -> void:
	shovel = _anchor(Machines.shovel(), _floor_spot(SHOVEL), SHOVEL[2])
	shovel.name = "QuarryShovel"
	MeshMerge.bake(shovel, "quarry_shovel")
	_solid(shovel, Vector3(0, 2.2, 0), Vector3(7.2, 4.4, 8.6))
	_solid(shovel, Vector3(0, 5.2, 1.2), Vector3(6.4, 4.4, 8.4))
	var loading = _anchor(Machines.belaz(true), _floor_spot(LOADING), LOADING[2])
	loading.name = "QuarryBelazLoading"
	var waiting = _anchor(Machines.belaz(), _floor_spot(WAITING), WAITING[2])
	waiting.name = "QuarryBelazWaiting"
	var rim = rim_truck_spot()
	var rim_s = biome.ramp_begin + float(RIM_TRUCK[0])
	var parked = _anchor(Machines.belaz(), rim, stage.direction(rim_s))
	parked.name = "QuarryBelazRim"
	for truck in [loading, waiting, parked]:
		MeshMerge.bake(truck, "belaz_loaded" if truck == loading else "belaz")
		_solid(truck, Vector3(0, 3.2, 0.2), Vector3(Machines.BELAZ_SIZE.x, 6.4, Machines.BELAZ_SIZE.z))
		machines.append(truck)
	var drill = _anchor(Machines.drill(), _floor_spot(DRILL), DRILL[2])
	drill.name = "QuarryDrill"
	MeshMerge.bake(drill, "quarry_drill")
	_solid(drill, Vector3(0, 2.0, 0), Vector3(4.6, 4.0, 7.4))
	_solid(drill, Vector3(0, 9.5, -4.1), Vector3(1.6, 17.0, 1.6))
	machines.append_array([shovel, drill])
	_power_cable()

# A static box obstacle in the machine's frame, and its footprint as rocks so
# crews, gravel and the walkers' quick test also meet it.
func _solid(machine: Node3D, center: Vector3, size: Vector3) -> void:
	stage.solids.solid(machine, center, size, "landmark")
	if center.y - size.y * 0.5 < 1.0:
		stage.rocks.append_array(Records.footprint(machine.to_global(Vector3(0, 0, center.z)), machine.basis.x, size.x, size.z, size.y))

# The shovel runs on 6 kV: a cable lies over the floor from the pole line on
# the toe of the face to the transformer skid and on to the machine's back.
func _power_cable() -> void:
	var line = Node3D.new()
	line.name = "QuarryPowerLine"
	stage.add_child(line)
	var skid = surface(Vector3(-9.0, 0.0, -540.0))
	Props.box(line, skid + Vector3(0, 1.1, 0), Vector3(2.4, 2.2, 3.2), Machines.dusted(Color("8c9a84")))
	Props.box(line, skid + Vector3(0, 2.3, 0), Vector3(2.6, 0.2, 3.4), Machines.dusted(Machines.STEEL))
	stage.rocks.append_array(Records.footprint(skid, Vector3.RIGHT, 2.4, 3.2, 2.2))
	var tail = shovel.to_global(Vector3(0, 0, 5.0))
	var points = [skid + Vector3(1.4, 0, 0), skid.lerp(tail, 0.35) + Vector3(-2.0, 0, 1.0), skid.lerp(tail, 0.7) + Vector3(1.0, 0, -1.0), tail]
	for i in range(points.size() - 1):
		var a = surface(points[i]) + Vector3.UP * 0.1
		var b = surface(points[i + 1]) + Vector3.UP * 0.1
		Props.car_beam(line, a, b, 0.12, Color("1d1e1e"))
	var z = -420.0
	var last := Vector3.INF
	while z > -560.0:
		var pole = surface(Vector3(-4.0, 0.0, z))
		Props.cylinder(line, pole + Vector3.UP * 4.5, 0.16, 0.12, 9.0, Color("6e5d48"), 6)
		Props.box(line, pole + Vector3.UP * 8.6, Vector3(1.8, 0.14, 0.14), Color("5b4c3b"))
		stage.rocks.append(Records.rock(pole, 0.18, 9.0, Records.POST))
		if last != Vector3.INF:
			for x in [-0.8, 0.0, 0.8]:
				Props.car_beam(line, last + Vector3(x, 8.75, 0), pole + Vector3(x, 8.75, 0), 0.03, Color("2a2a2a"))
		last = pole
		z -= 35.0
	Props.car_beam(line, last + Vector3(0, 8.6, 0), skid + Vector3(0, 2.3, 0), 0.05, Color("1d1e1e"))
	MeshMerge.bake(line)

# ---------------------------------------------------------------- rock

# Rocks pushed up in a windrow along the open edge of the haul road: what
# keeps a truck, and a rally car, from going over onto the berm below.
func _windrow(cooperative: bool = false) -> void:
	var poses: Array = []
	var colors: Array = []
	var s = biome.ramp_begin + 8.0
	while s < biome.ramp_end - 12.0:
		if cooperative and int(s) % 40 == 0: await LoadPacer.tick(stage.get_tree())
		var side = pit_side(s)
		var p = stage.at(s) + stage.side(s) * side * (stage.road_width(s) * 0.5 + WINDROW_OFFSET)
		p.y = stage.RoadCut.ground(stage, p)
		var radius = rng.randf_range(0.75, 1.0)
		poses.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(radius * 1.3, radius * 0.75, radius * 1.1)), p + Vector3.UP * radius * 0.2))
		colors.append(Machines.dusted(biome.rock_color(p), 0.45).lightened(rng.randf_range(-0.05, 0.05)))
		stage.rocks.append(Records.rock(p, 0.7, 1.2, Records.BARRIER))
		s += WINDROW_SPACING
	stage.detail_batch("HaulWindrow", stage.NATURE_BOULDER, poses, colors, DetailLayer.tiled(240.0))
	counts["windrow"] = poses.size()

# A line of boulders along the crest of every berm, and blocks fallen from
# the faces lying at their feet. Out of reach of the road: scenery only,
# except blocks on the floor, which are solid.
func _bunds(cooperative: bool = false) -> void:
	var poses: Array = []
	var colors: Array = []
	for bench in range(Form.BENCHES - 1):
		var reach = Form.FLOOR + bench * Form.BENCH_RUN + Form.FACE_RUN + 1.2
		var perimeter = 2.0 * (Form.NORTH_Z - Form.SOUTH_Z) + TAU * reach
		var count = int(perimeter / 2.6)
		for i in range(count):
			if cooperative and i % 120 == 0: await LoadPacer.tick(stage.get_tree())
			var p = _outline(float(i) / count, reach)
			if not open_ground(p, 12.0, 0.0):
				continue
			p = surface(p)
			var radius = rng.randf_range(0.45, 0.85)
			poses.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(radius * 1.3, radius * 0.7, radius)), p + Vector3.UP * radius * 0.15))
			colors.append(Machines.dusted(biome.rock_color(p), 0.5))
	stage.detail_batch("BermBunds", stage.NATURE_BOULDER, poses, colors, DetailLayer.tiled(300.0))
	counts["bund_rocks"] = poses.size()

# A point on the pit outline `reach` from the axis, `t` of the way round.
func _outline(t: float, reach: float) -> Vector3:
	var straight = Form.NORTH_Z - Form.SOUTH_Z
	var perimeter = 2.0 * straight + TAU * reach
	var d = t * perimeter
	if d < straight:
		return Vector3(Form.AXIS_X + reach, 0.0, Form.NORTH_Z - d)
	d -= straight
	if d < PI * reach:
		var a = d / reach
		return Vector3(Form.AXIS_X + reach * cos(a), 0.0, Form.SOUTH_Z - reach * sin(a))
	d -= PI * reach
	if d < straight:
		return Vector3(Form.AXIS_X - reach, 0.0, Form.SOUTH_Z + d)
	var a = (d - straight) / reach
	return Vector3(Form.AXIS_X - reach * cos(a), 0.0, Form.NORTH_Z + reach * sin(a))

func _talus(cooperative: bool = false) -> void:
	var poses: Array = []
	var colors: Array = []
	for i in range(1600):
		if cooperative and i % 120 == 0: await LoadPacer.tick(stage.get_tree())
		var bench = rng.randi_range(0, Form.BENCHES - 1)
		var reach = Form.FLOOR + bench * Form.BENCH_RUN - rng.randf_range(0.2, 2.6)
		var p = _outline(rng.randf(), reach)
		if not open_ground(p, 9.0, 0.0):
			continue
		p = surface(p)
		var radius = rng.randf_range(0.3, 1.5)
		poses.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(radius * 1.2, radius * 0.8, radius)), p + Vector3.UP * radius * 0.25))
		colors.append(Machines.dusted(biome.rock_color(p + Vector3.UP * 3.0), 0.3).lightened(rng.randf_range(-0.06, 0.06)))
		if bench == 0 and radius > 0.9:
			stage.rocks.append(Records.rock(p, radius * 0.85, radius * 1.4, Records.FOREST))
	stage.detail_batch("FaceTalus", stage.NATURE_BOULDER, poses, colors, DetailLayer.tiled(260.0))
	counts["talus"] = poses.size()

# ---------------------------------------------------------------- plants

# Grass and willow-herb on the land round the pit, birch and willow scrub
# taking hold on the old dumps, bare grey spoil where trucks still tip.
func _dump_cover(cooperative: bool = false) -> void:
	var grass_p: Array = []
	var grass_c: Array = []
	var bush_p: Array = []
	var bush_c: Array = []
	var stone_p: Array = []
	var stone_c: Array = []
	for i in range(16000):
		if cooperative and i % 200 == 0: await LoadPacer.tick(stage.get_tree())
		var p = random_point()
		if Form.in_pit(p, 4.0) or not open_ground(p, 6.0, 0.0):
			continue
		p = surface(p)
		var yaw = rng.randf() * TAU
		var spoil = Form.dump_height(p) > 0.5
		if i % 6 == 0:
			var size = rng.randf_range(0.5, 1.5)
			bush_p.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(size, size * rng.randf_range(0.7, 1.2), size)), p))
			bush_c.append(Color("6f7d4c").lerp(Color("8a9356"), rng.randf()))
		elif spoil or i % 5 == 0:
			var radius = rng.randf_range(0.15, 0.5)
			stone_p.append(stage.woodland.shared_stone_pose(p, radius, yaw))
			stone_c.append(Machines.dusted(biome.rock_color(p), 0.45))
		else:
			var size = rng.randf_range(0.7, 1.4)
			grass_p.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(size, rng.randf_range(0.8, 1.6), size)), p))
			grass_c.append(Color("9a9a64").lerp(Color("7f8c52"), rng.randf()))
	stage.detail_batch("DumpGrass", stage.NATURE_GRASS, grass_p, grass_c, DetailLayer.tiled(160.0))
	stage.detail_batch("DumpScrub", stage.NATURE_BUSH, bush_p, bush_c, DetailLayer.tiled(220.0))
	stage.detail_batch("DumpStones", stage.NATURE_STONE, stone_p, stone_c, DetailLayer.tiled(200.0))
	counts["scrub"] = bush_p.size()

# Birches: white trunks and light crowns, in copses on the land and up the
# flanks of the old dumps. They stop cars like any other tree.
func _birches() -> void:
	var stick = CylinderMesh.new()
	stick.top_radius = 0.3
	stick.bottom_radius = 0.5
	stick.height = 1.0
	stick.radial_segments = 6
	stick.rings = 1
	var crown = SphereMesh.new()
	crown.radial_segments = 8
	crown.rings = 4
	var birches: Array = []
	for copse in range(60):
		var center = random_point()
		if Form.in_pit(center, 20.0) or not open_ground(center, 14.0, 4.0):
			continue
		for k in range(rng.randi_range(3, 9)):
			var p = center + Vector3(rng.randf_range(-12, 12), 0, rng.randf_range(-12, 12))
			if Form.in_pit(p, 12.0) or not open_ground(p, 10.0, 2.0):
				continue
			birches.append({"base": surface(p) - Vector3.UP * 0.05, "height": rng.randf_range(7.0, 14.0), "yaw": rng.randf() * TAU, "shade": rng.randf_range(-0.05, 0.06)})
	stage.woodland.tree_layers("Birch", birches, [
		{"mesh": stick, "scale": Vector3(0.022, 0.8, 0.022), "y": 0.4, "tilt": 0.04, "color": "e3e1d8"},
		{"mesh": crown, "scale": Vector3(0.26, 0.42, 0.26), "y": 0.6, "dx": 0.03, "color": "6f8a45"},
		{"mesh": crown, "scale": Vector3(0.2, 0.3, 0.2), "y": 0.66, "dx": -0.1, "color": "7b974d"},
		{"mesh": crown, "scale": Vector3(0.16, 0.26, 0.16), "y": 0.82, "dx": 0.05, "color": "86a156"},
	])
	counts["birches"] = birches.size()

# ---------------------------------------------------------------- water and signs

# Pit water gathers in the sump: milky green, as in the flooded pits of Asbest.
func _sump() -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center = Vector3(Form.SUMP[0], Form.FLOOR_LEVEL - 0.55, Form.SUMP[1])
	var radius = float(Form.SUMP[2]) * 0.82
	for i in range(18):
		var a = i * TAU / 18.0
		var b = (i + 1) * TAU / 18.0
		for v in [center, center + Vector3(cos(b), 0, sin(b)) * radius, center + Vector3(cos(a), 0, sin(a)) * radius]:
			st.set_color(Color(0.42, 0.66, 0.6, 0.86))
			st.add_vertex(v)
	st.generate_normals()
	var node = MeshInstance3D.new()
	node.name = "QuarrySump"
	node.mesh = st.commit()
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.15
	mat.metallic_specular = 0.7
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(node)

# A board at the top of the haul road: the pit's name and the grade.
func _ramp_sign() -> void:
	var s = biome.ramp_begin - 16.0
	var side = -pit_side(s)
	var p = stage.at(s) + stage.side(s) * side * (stage.road_width(s) * 0.5 + 3.0)
	p.y = stage.RoadCut.ground(stage, p)
	var sign = Node3D.new()
	sign.name = "QuarrySign"
	stage.add_child(sign)
	sign.position = p
	var facing = -stage.direction(s)
	sign.rotation.y = atan2(facing.x, facing.z)
	for x in [-1.9, 1.9]:
		Props.cylinder(sign, Vector3(x, 1.4, 0), 0.08, 0.08, 2.8, Color("7d8285"), 6)
	Props.box(sign, Vector3(0, 2.45, 0), Vector3(4.6, 1.3, 0.08), Color("2f5d8c"))
	# Layers stand several cm apart: thinner ones flicker from a distance.
	Props.box(sign, Vector3(0, 2.45, 0.065), Vector3(4.4, 1.1, 0.05), Color("f0f0ea"))
	Props.box(sign, Vector3(0, 2.45, 0.105), Vector3(4.3, 1.0, 0.03), Color("2f5d8c"))
	Props.label_3d(sign, Vector3(0, 2.68, 0.15), "АСБЕСТОВСКИЙ КАРЬЕР", 64, 0.005, Color("f4f4ee"))
	Props.label_3d(sign, Vector3(0, 2.25, 0.15), "СПУСК 9%", 48, 0.005, Color("f4f4ee"))
	Movable.register(stage.solids, sign, 20, true)

# ---------------------------------------------------------------- horizon

# Low wooded ridges of the Middle Urals all round, and the stacks of the
# mill beyond the dumps to the north-east.
func horizon() -> void:
	for i in range(18):
		var side = -1 if i % 2 == 0 else 1
		var p = Vector3(side * stage.rng.randf_range(250, 360), 46, -i * 60.0 + 40.0)
		RallyProps.cylinder(stage, p, stage.rng.randf_range(140, 200), 0, stage.rng.randf_range(50, 80), Color("5f7466"), 6)
	for i in range(5):
		var p = Vector3(stage.rng.randf_range(-260, 260), 46, -1080.0 - stage.rng.randf_range(0, 120))
		RallyProps.cylinder(stage, p, stage.rng.randf_range(160, 220), 0, stage.rng.randf_range(50, 80), Color("6d7f75"), 6)
	var mill = Node3D.new()
	mill.name = "QuarryMill"
	stage.add_child(mill)
	mill.position = Vector3(250, 58, 160)
	Props.box(mill, Vector3(0, 14, 0), Vector3(60, 28, 34), Color("9fa39c"))
	Props.box(mill, Vector3(-48, 9, 10), Vector3(34, 18, 22), Color("8d918a"))
	Props.box(mill, Vector3(30, 22, -24), Vector3(12, 44, 12), Color("a7aaa3"))
	for x in [-14.0, 6.0]:
		Props.cylinder(mill, Vector3(x, 40, -6), 3.0, 2.2, 80, Color("b2aea6"), 10)
		Props.cylinder(mill, Vector3(x, 78, -6), 2.4, 2.4, 4, Color("a2463a"), 10)
	var gallery = Props.box(mill, Vector3(-30, 24, -40), Vector3(4, 4, 70), Color("8e928a"))
	gallery.rotation.x = 0.35
	MeshMerge.bake(mill)
