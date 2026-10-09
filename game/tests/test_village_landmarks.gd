extends SceneTree
const Stage = preload("res://scripts/stage.gd")
const Village = preload("res://scripts/vineyard.gd")
const Interior = preload("res://scripts/village_interiors.gd")
const Distance = preload("res://scripts/draw_distance.gd")
var failures = 0
func check(ok: bool, title: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + title)
	if not ok: failures += 1
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var stage = Stage.new(2)
	root.add_child(stage)
	var city = Village.new()
	city.stage = stage
	stage.city = city
	stage.add_child(city)
	var church = Node3D.new()
	stage.add_child(church)
	Interior.church(city, church)
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
			var aabb = node.mesh.get_aabb()
			for corner in range(8):
				var point = church.to_local(node.to_global(aabb.get_endpoint(corner)))
				roof_clear = roof_clear and point.z > -8.1
	check(roof_clear, "nave roof and tile courses leave the tower stairwell clear")
	church.free()
	city.obstacles.clear()
	city._village_landmarks()
	var trailer = stage.get_node("VillageFarmyard/FarmTrailer")
	check(not city.hit(trailer.global_position + Vector3(-4, 0.9, 0), trailer.global_position + Vector3(4, 0.9, 0), 0.3).is_empty(), "walking cannot pass through the farm trailer")
	var landmark_bodies = stage.find_children("*", "StaticBody3D", true, false)
	check(landmark_bodies.size() >= 20, "farm and cafe furniture retain collision bodies after batching")
	stage.capture_bake_buffers = true
	stage._detail_batch("VillageHorizonTreeLayer0", stage.shared_tree_mesh(0), [Transform3D(Basis.IDENTITY, Vector3(188, 0, -435)), Transform3D(Basis.IDENTITY, Vector3(-188, 0, -435))], [Color.WHITE, Color.WHITE])
	var setting = Distance.new()
	for mode in [Distance.NEAR, Distance.MEDIUM, Distance.FAR]:
		setting.mode = mode
		setting.apply(stage)
		var sides = [false, false]
		for tile in stage.find_children("VillageHorizonTreeLayer0_Tile_*", "MultiMeshInstance3D", false, false):
			sides[0 if tile.position.x < 0 else 1] = true
			check(tile.visibility_range_end == 0 or tile.visibility_range_end > 250, "horizon survives culling from the central street in every preset")
		check(sides[0] and sides[1], "horizon includes both terrain edges")
	stage.free()
	quit(1 if failures else 0)
