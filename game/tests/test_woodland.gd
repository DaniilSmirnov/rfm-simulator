extends SceneTree
const Stage = preload("res://scripts/stage.gd")
class UnboundedStage:
	extends "res://scripts/stage.gd"
	func _trail_near(_pos: Vector3, _trail: Dictionary, _padding: float) -> bool:
		return true
var failures = 0
func check(ok: bool, title: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + title)
	if not ok:
		failures += 1
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var stage = Stage.new()
	root.add_child(stage)
	stage.build()
	var unbounded = UnboundedStage.new()
	unbounded.clearings = stage.clearings
	unbounded.trails = stage.trails
	var random = RandomNumberGenerator.new()
	random.seed = 101608
	var heights_match = true
	for sample in range(300):
		var point = Vector3(random.randf_range(-180, 180), 0, random.randf_range(-840, 0))
		heights_match = heights_match and absf(stage.ground(point)-unbounded.ground(point)) < 0.00001
	for trail in stage.trails:
		for point in trail.points:
			for offset in [Vector3.ZERO, Vector3(1,0,1), Vector3(2.2,0,0), Vector3(4,0,0)]:
				heights_match = heights_match and absf(stage.ground(point+offset)-unbounded.ground(point+offset)) < 0.00001
	check(heights_match, "trail broadphase preserves terrain height in forest and around trail boundaries")
	unbounded.free()
	var preserved = stage.forest_chunk_slots.size() == stage.trees.size()
	for layer in stage.forest_layers:
		var count = 0
		for mm in layer:
			count += mm.instance_count
		preserved = preserved and count == stage.trees.size() and layer.size() > 1
	var unique: Dictionary = {}
	for slot in stage.forest_chunk_slots:
		unique[slot] = true
	check(preserved and unique.size() == stage.trees.size(), "forest chunks preserve every tree once per layer and global collision IDs")
	check(stage.trees.size() > 5000, "forest has a dense canopy with more than 5000 trees")
	check(stage.woodland_details.get("ForestGrass", 0) > 20000, "forest floor contains more than 20000 instanced grass tufts")
	check(stage.woodland_details.get("MushroomCaps", 0) > 300 and stage.woodland_details.get("AntHills", 0) > 30, "mushroom clusters and ant hills populate the woods")
	check(stage.woodland_details.get("ForestBoulders", 0) > 150 and stage.woodland_details.get("ForestPebbles", 0) > 1000, "boulders and small stones populate the woods")
	check(stage.woodland_details.get("ForestBushes", 0) > 1000 and stage.woodland_details.get("ForestBerryBushes", 0) > 400, "ordinary and berry-bearing undergrowth populate the forest")
	check(stage.woodland_details.get("ForestBerries", 0) > 1200, "berry bushes have visible fruit")
	var boulders = 0
	var reserved = true
	for rock in stage.rocks:
		if rock.get("forest", false):
			boulders += 1
			reserved = reserved and stage.woodland_spot(rock.pos, rock.radius)
			check(not stage.rock_hit(rock.pos, rock.pos, 0.3, false).is_empty(), "forest boulder has collision")
	check(boulders > 150 and reserved, "forest boulders preserve roads, clearings and footpaths")
	var same = Stage.new()
	for p in [Vector3(80, 0, -270), Vector3(-75, 0, -500)]:
		check(stage.ground(p) == same.ground(p), "forest relief is deterministic for multiplayer")
		check(absf(stage.forest_relief(p, 70)) > 0.1, "forest ground has local hill relief")
	var road = stage.at(80)
	check(absf(stage.forest_relief(road, 0)) < 0.001, "forest relief leaves rally lane unchanged")
	var ditch = stage.at(80) + stage.side(80) * 6.4
	check(stage.forest_relief(ditch, 6.4) < -0.6, "roadside drainage ditch lowers ground")
	var clear = true
	for c in stage.clearings:
		clear = clear and absf(stage.ground(c) - c.y) < 0.01
	for trail in stage.trails:
		for p in trail.points:
			clear = clear and absf(stage.ground(p) - p.y) < 0.15
	check(clear, "clearings and trail centers remain level and walkable")
	var undergrowth_clear = true
	var undergrowth_tiles = 0
	for child in stage.get_children():
		if str(child.name).begins_with("ForestBushes_Tile") or str(child.name).begins_with("ForestBerryBushes_Tile"):
			undergrowth_tiles += 1
			for i in range(child.multimesh.instance_count):
				var spot: Vector3 = child.position + child.multimesh.get_instance_transform(i).origin
				undergrowth_clear = undergrowth_clear and stage.woodland_spot(spot)
	check(undergrowth_clear and undergrowth_tiles > 10, "spatially batched bushes leave picnic clearings and footpaths open")
	var grass_tiles = 0
	for child in stage.get_children():
		if str(child.name).begins_with("GrassTile"):
			grass_tiles += 1
			check(child is MultiMeshInstance3D and child.visibility_range_end == 160, "grass uses bounded-distance instancing")
	check(grass_tiles > 10 and grass_tiles < 100, "grass is split into spatial batches")
	same.free()
	stage.free()
	for variant in [1, 2]:
		var other = Stage.new(variant)
		root.add_child(other)
		other.build()
		var forest_layers_absent = true
		for layer in ["ForestGrass", "MushroomCaps", "AntHills", "ForestBoulders", "ForestPebbles", "ForestBushes", "ForestBerryBushes", "ForestBerries"]:
			forest_layers_absent = forest_layers_absent and other.woodland_details.get(layer, 0) == 0
		check(forest_layers_absent, "forest decoration stays off winter and vineyard stages")
		if variant == 2:
			check(other.woodland_details.get("VineyardLeaves", 0) > 0 and other.woodland_details.get("VineyardGrapes", 0) > 0, "vineyard keeps its own leaves and collectible grapes")
		other.free()
	print("WOODLAND RESULT: %d failures" % failures)
	quit(1 if failures else 0)
