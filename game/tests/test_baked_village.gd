extends SceneTree
const Stage = preload("res://scripts/stage.gd")
const Baked = preload("res://scripts/baked_village.gd")
var failures = 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func render_signature(stage: Node3D) -> Array:
	var result = []
	for node in stage.find_children("*", "MultiMeshInstance3D", true, false):
		if DisplayServer.get_name() != "headless":
			var actual = node.multimesh.buffer
			var expected = node.get_meta("baked_instances")
			var same = actual.size() == expected.size()
			for i in range(mini(actual.size(), expected.size())):
				# Compatibility stores instance colors in half precision.
				var tolerance = 0.001 if i % 16 >= 12 else 0.000001
				same = same and absf(actual[i] - expected[i]) < tolerance
			check(same, "actual GPU buffer preserves every prepared transform and color")
		result.append([str(node.name), node.position, node.multimesh.instance_count, hash(node.get_meta("baked_instances")), node.cast_shadow, node.visibility_range_end])
	for node in stage.find_children("TerrainTile_*", "MeshInstance3D", true, false):
		result.append([str(node.name), node.mesh.get_aabb(), hash(node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])])
	return result

func run() -> void:
	var generated = Stage.new(2)
	generated.capture_bake_buffers = true
	root.add_child(generated)
	var before = Time.get_ticks_usec()
	generated.build(false)
	var generated_us = Time.get_ticks_usec() - before
	var baked = Stage.new(2)
	baked.capture_bake_buffers = true
	root.add_child(baked)
	before = Time.get_ticks_usec()
	baked.build()
	var loaded_us = Time.get_ticks_usec() - before
	check(baked.loaded_baked, "village uses prepared scene")
	check(render_signature(generated) == render_signature(baked), "terrain, spatial blocks and every MultiMesh transform survive serialization")
	check(generated.collectibles == baked.collectibles and generated.trees == baked.trees and generated.rocks.size() == baked.rocks.size(), "deterministic collectible/tree/rock identities survive loading")
	check(generated.city.walk_surfaces == baked.city.walk_surfaces and generated.city.viewpoints == baked.city.viewpoints, "stairs, roof support and viewpoints survive loading")
	check(generated.city.obstacles.size() == baked.city.obstacles.size(), "all static collision volumes and lamps survive loading")
	var random = RandomNumberGenerator.new()
	random.seed = 64810
	for i in range(500):
		var p = Vector3(random.randf_range(-130, 170), random.randf_range(1, 29), random.randf_range(-650, -250))
		var end = p + Vector3(random.randf_range(-20, 20), 0, random.randf_range(-20, 20))
		check(generated.city.hit(p, end, 0.4) == baked.city.hit(p, end, 0.4), "loaded swept collision agrees with generator")
		check(is_equal_approx(generated.city.walking_floor(p, p.y), baked.city.walking_floor(p, p.y)), "loaded walking support agrees with generator")
	var other = Stage.new(2)
	other.capture_bake_buffers = true
	root.add_child(other)
	var reports = []
	await other.build_async(func(title, amount):
		reports.append([title, amount])
		await process_frame)
	check(other.loaded_baked and reports.size() >= 3, "asynchronous load reports progress before gameplay")
	var id = -1
	for i in range(baked.collectibles.size()):
		if baked.collectibles[i].get("name", "") == "виноград":
			id = i
			break
	check(id >= 0 and baked.harvest(id), "loaded vineyard can be harvested")
	if id >= 0:
		var index = baked.collectibles[id].parts.VineyardGrapes[0]
		var part = baked.collectible_parts.VineyardGrapes[index]
		var connected = false
		for node in baked.find_children("VineyardGrapes*", "MultiMeshInstance3D", true, false):
			connected = connected or node.multimesh == part.mesh
		if DisplayServer.get_name() != "headless":
			check(part.mesh.get_instance_transform(part.instance).basis.determinant() == 0, "real renderer hides harvested grapes")
		check(connected and part.hidden and part.pose.basis.determinant() == 0, "harvest hides the rendered instance")
		var fresh = other.collectible_parts.VineyardGrapes[index]
		check(not fresh.hidden and fresh.pose.basis.determinant() != 0 and fresh.mesh != part.mesh, "separate scenes do not share mutable harvest state")
	check(baked.city.knock_lamp(0, Vector3.RIGHT) and not other.city.lamps[0].fallen, "lamps remain dynamic and independent")
	check(baked.city.bell.pull(baked.city.bell.handle_position()) and baked.city.bell.audio.playing, "bell references and sound survive loading")
	check(other.city.bell.serial == 0 and other.city.bell.pivot != baked.city.bell.pivot, "bell animation state is independent")
	await process_frame
	check(baked.city.bell.pivot.rotation.z != 0, "loaded bell animates after pulling")
	var empty = Stage.new(2)
	root.add_child(empty)
	check(not Baked.load_into(empty, "res://generated/missing.scn") and empty.get_child_count() == 0, "missing bake permits procedural fallback")
	var invalid = Node3D.new()
	invalid.set_meta("baked_schema", -1)
	var packed = PackedScene.new()
	packed.pack(invalid)
	check(not Baked._apply(empty, packed) and empty.get_child_count() == 0, "wrong schema does not partially modify the stage")
	invalid.free()
	var stale = Node3D.new()
	stale.set_meta("baked_schema", Baked.SCHEMA)
	stale.set_meta("source_fingerprint", "old geometry")
	var stale_packed = PackedScene.new()
	stale_packed.pack(stale)
	check(not Baked._apply(empty, stale_packed) and empty.get_child_count() == 0, "editor rejects bake after source changes")
	stale.free()
	print("BAKED_VILLAGE generated_ms=", generated_us / 1000.0, " loaded_ms=", loaded_us / 1000.0, " failures=", failures)
	for stage in [generated, baked, other, empty]:
		stage.free()
	quit(1 if failures else 0)
