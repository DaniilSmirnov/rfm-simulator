extends SceneTree
const Stage = preload("res://scripts/stage.gd")
const Props = preload("res://scripts/props.gd")
var failures = 0
func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok: failures += 1
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var stage = Stage.new(1)
	var point = stage.at(180) + stage.side(180) * 12.0
	var key = stage.snow.polygon(stage, point)
	point = Vector3(key.x + key.z * 0.25, 0, key.y + key.z * 0.25)
	point.y = stage.terrain_surface_height(point)
	var original = stage.terrain_surface_height(point)
	check(stage.snow.dig(stage, point), "shovel clears one snow triangle")
	check(not stage.snow.dig(stage, point), "same triangle cannot be dug twice")
	check(stage.snow.loose_depth(stage, point) == 0, "cleared ground has no snow resistance")
	check(stage.ground(point) < original - 0.3 and is_equal_approx(stage.vehicle_ground(point), stage.ground(point)), "walking and car support match excavation floor")
	var neighbour = Vector3(key.x + key.z * 0.75, 0, key.y + key.z * 0.75)
	check(not stage.snow.is_dug(stage, neighbour), "other triangle in same square remains snow")
	var guest = Stage.new(1)
	guest.snow.authoritative = false
	guest.snow.apply_dug_snapshot(stage.snow.dug_snapshot())
	check(is_equal_approx(guest.ground(point), stage.ground(point)) and not guest.snow.dig(guest, neighbour), "guest reproduces holes without digging authoritatively")
	var surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for offset in [Vector3.ZERO, Vector3(key.z, 0, 0), Vector3(0, 0, key.z), Vector3(key.z, 0, 0), Vector3(key.z, 0, key.z), Vector3(0, 0, key.z)]:
		var v = Vector3(key.x, 0, key.y) + offset
		v.y = stage.terrain_vertex_height(v.x, v.z)
		surface.set_color(Color.WHITE)
		surface.add_vertex(v)
	surface.generate_normals()
	var node = MeshInstance3D.new()
	node.mesh = surface.commit()
	var tile = Vector2i(floori(point.x / 64), floori(point.z / 64))
	stage.snow.register_chunk(stage, tile, node)
	stage.snow.update(0.5)
	var vertices: PackedVector3Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(vertices.size() > 6 and vertices[0].y < stage.terrain_vertex_height(key.x, key.y) - 0.3, "dug polygon has lowered floor and snow side walls")
	check(is_equal_approx(vertices[4].y, stage.terrain_vertex_height(key.x + key.z, key.y + key.z)), "neighbour polygon mesh stays untouched")
	var root = Node3D.new()
	var shovel = Props.gear_box(root, "shovel")
	check(Props.CARGO_KINDS.has("shovel") and shovel.get_child_count() == 5, "cargo shovel has blade shaft and handle geometry")
	var game = preload("res://scripts/game.gd").new()
	game.stage = stage
	check(not game.valid_furniture_spot(neighbour, "table"), "furniture cannot be placed in untouched snow")
	for x in range(-2, 3):
		for z in range(-2, 3):
			var support = point + Vector3(x * 0.5, 0, z * 0.5)
			stage.snow.dig(stage, support)
	# Clear obstacles only for this placement contract.
	stage.trees.clear()
	stage.rocks.clear()
	check(game.valid_furniture_spot(point, "table"), "cleared footprint accepts furniture")
	game.stage = null
	game.free()
	stage.free()
	guest.free()
	node.free()
	root.free()
	quit(failures)
