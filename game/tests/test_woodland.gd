extends SceneTree
const Stage = preload("res://scripts/stage.gd")
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
	check(stage.trees.size() > 5000, "forest has a dense canopy with more than 5000 trees")
	check(stage.woodland_details.get("ForestGrass", 0) > 8000, "forest floor contains instanced grass")
	check(stage.woodland_details.get("MushroomCaps", 0) > 300 and stage.woodland_details.get("AntHills", 0) > 30, "mushroom clusters and ant hills populate the woods")
	check(stage.woodland_details.get("ForestBoulders", 0) > 50 and stage.woodland_details.get("ForestPebbles", 0) > 200, "boulders and small stones populate the woods")
	var boulders = 0
	var reserved = true
	for rock in stage.rocks:
		if rock.get("forest", false):
			boulders += 1
			reserved = reserved and stage.woodland_spot(rock.pos, rock.radius)
			check(not stage.rock_hit(rock.pos, rock.pos, 0.3, false).is_empty(), "forest boulder has collision")
	check(boulders > 50 and reserved, "forest boulders preserve roads, clearings and footpaths")
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
		check(other.woodland_details.is_empty(), "forest decoration stays off winter and urban stage")
		other.free()
	print("WOODLAND RESULT: %d failures" % failures)
	quit(1 if failures else 0)
