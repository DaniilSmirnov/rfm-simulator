extends "res://tests/harness.gd"
const Stage = preload("res://scripts/stage.gd")
const Architecture = preload("res://scripts/village_architecture.gd")
const Interior = preload("res://scripts/village_interiors.gd")
const Distance = preload("res://scripts/draw_distance.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var stage = Stage.new(2)
	root.add_child(stage)
	var kit = Architecture.new(stage.village)
	stage.village.architecture = kit
	kit._register_meshes()
	var church = Node3D.new()
	stage.add_child(church)
	Interior.church(kit, church)
	var backs = 0
	for node in church.get_children():
		if node is MeshInstance3D and node.mesh is BoxMesh and node.mesh.size.is_equal_approx(Vector3(2.4, 0.8, 0.15)):
			backs += 1
			var row = roundf((node.position.z + 5.3) / 2.5) * 2.5 - 5.0
			check(node.position.z < row, "pew back is behind the seat facing the altar at +Z")
	check(backs == 10, "all ten church pews face the altar")
	var roof_clear = true
	for node in church.get_node("NaveRoof").get_children():
		if node is MeshInstance3D:
			var aabb = node.get_aabb() if node.mesh == null else node.mesh.get_aabb()
			for corner in range(8):
				var point = church.to_local(node.to_global(aabb.get_endpoint(corner)))
				roof_clear = roof_clear and point.z > -8.1
	check(roof_clear, "nave roof and tile courses leave the tower stairwell clear")
	var cage = 0
	for node in church.get_children():
		if node is MeshInstance3D and node.position.y > 28.0 and node.position.y < 31.5 and node.mesh is BoxMesh and node.mesh.size.x < 0.1:
			cage += 1
	check(cage >= 8, "the tower is crowned by a Provençal wrought-iron bell cage")
	church.free()
	stage.solids.obstacles.clear()
	# Square, café terrace and domaine yard: furniture keeps real collisions.
	kit._square()
	kit._cafe()
	kit._domaine()
	var square = stage.get_node("VillageSquare")
	check(square.get_node_or_null("Fountain") != null and square.get_node_or_null("Paving") != null, "the square has a fountain on cobbled paving")
	var fountain: Vector3 = stage.village.anchors.fountain
	check(not stage.solids.hit(fountain + Vector3(-4, 0.2, 0), fountain + Vector3(4, 0.2, 0), 0.3).is_empty(), "walking cannot pass through the fountain basin")
	var seats: Array = stage.village.anchors.cafe_seats
	check(seats.size() == 8, "four café tables each have two chairs")
	var table: Vector3 = seats[0].table
	check(not stage.solids.hit(table + Vector3(-3, -0.4, 0), table + Vector3(3, -0.4, 0), 0.3).is_empty(), "café tables block walkers")
	check(stage.village.anchors.benches.size() == 3, "benches around the fountain are recorded for the old men")
	var bodies = stage.find_children("*", "StaticBody3D", true, false)
	# Fountain, three benches, four tables with eight chairs, stalls and the yard.
	check(bodies.size() >= 20, "square, terrace and domaine furniture retain collision bodies after batching")
	var signs = stage.find_children("ShopSign", "Label3D", true, false)
	check(signs.size() >= 1 and signs[0].text == "CAFÉ DE LA PLACE", "the café carries its sign")
	# The distant horizon is batched without a culling range on every preset.
	kit.batcher.flush(stage)
	stage.village.landscape = preload("res://scripts/village_landscape.gd").new(stage.village)
	stage.village.landscape._horizon()
	stage.village.batcher.flush(stage)
	# Ridges stand beyond the terrain edge (|x| > 300 m): 64 m cells 5+ or -6-.
	var ridges: Array = []
	for tile in stage.find_children("VillageDetail_cylinder_*", "MultiMeshInstance3D", false, false):
		if absf(tile.position.x) > 300.0:
			ridges.append(tile)
	check(ridges.size() >= 4, "horizon ridges are batched beyond both terrain edges")
	var setting = Distance.new()
	for mode in [Distance.NEAR, Distance.MEDIUM, Distance.FAR]:
		setting.mode = mode
		setting.apply(stage)
		check(ridges.all(func(tile): return tile.visibility_range_end == 0), "horizon ridges survive culling in every draw-distance preset")
	stage.free()
	finish()
