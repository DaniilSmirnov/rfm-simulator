extends "res://tests/harness.gd"
const Stage = preload("res://scripts/stages/stage.gd")
const Props = preload("res://scripts/core/props.gd")
class FakeRoom extends Node:
	var sent: Array
	var connected = false
	func submit(action: String, _placement: Dictionary = {}) -> bool:
		sent.append(action)
		return true

func _initialize() -> void: call_deferred("run")
func run() -> void:
	var stage = Stage.new(1)
	var point = stage.at(180) + stage.side(180) * 12.0
	var key = stage.snow.polygon(stage, point)
	point = Vector3(key.x + key.z * 0.25, 0, key.y + key.z * 0.25)
	point.y = stage.terrain_surface_height(point)
	var original = stage.terrain_surface_height(point)
	get_root().add_child(stage)
	stage._attach_solids()
	stage.solids.physics_ground(point, 1.0)
	var tile_key = Vector2i(floori(point.x / 16.0), floori(point.z / 16.0))
	var heights: PackedFloat32Array = stage.solids.prop_ground.tiles[tile_key].get_child(0).shape.map_data
	var lowest = Array(heights).min()
	check(stage.snow.dig(stage, point), "shovel clears one snow triangle")
	check(not stage.snow.dig(stage, point), "same triangle cannot be dug twice")
	check(stage.snow.loose_depth(stage, point) == 0, "cleared ground has no snow resistance")
	check(stage.ground(point) < original - 0.3 and is_equal_approx(stage.vehicle_ground(point), stage.ground(point)), "walking and car support match excavation floor")
	heights = stage.solids.prop_ground.tiles[tile_key].get_child(0).shape.map_data
	check(Array(heights).min() < lowest - 0.05 and Array(heights).min() <= stage.ground(point) + 0.05, "prop physics ground built before digging follows the pit, so furniture placed there does not fall through")
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
	var colors: PackedColorArray = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	check(colors[0].r > 0.85 and colors[0].g > 0.85 and colors[0].b > 0.85, "excavated snow floor remains white")
	check(vertices.size() > 6 and vertices[0].y < stage.terrain_vertex_height(key.x, key.y) - 0.3, "dug polygon has lowered floor and snow side walls")
	check(is_equal_approx(vertices[4].y, stage.terrain_vertex_height(key.x + key.z, key.y + key.z)), "neighbour polygon mesh stays untouched")
	# A tree standing on the snow keeps a trunk down to the floor of a pit dug under it.
	var tree_base = stage.at(260) + stage.side(260) * 14.0
	var tree_key = stage.snow.polygon(stage, tree_base)
	tree_base = Vector3(tree_key.x + tree_key.z * 0.3, 0, tree_key.y + tree_key.z * 0.3)
	tree_base.y = stage.terrain_surface_height(tree_base) - 0.03
	stage.trees.append(tree_base)
	stage.forest_data.append({"height": 8.0})
	stage._rebuild_tree_index()
	check(stage.snow.can_dig(stage, tree_base) and stage.snow.dig(stage, tree_base), "snow under a tree can be dug")
	stage.snow.update(0.5)
	var stumps: MultiMeshInstance3D = stage.get_node_or_null("SnowTrunkStumps")
	check(stumps != null and stumps.multimesh.instance_count == 1, "dug tree gets one trunk piece through the pit")
	# The headless renderer keeps no instance transforms: check the planned pieces.
	var planned: Array = stage.snow.SnowStumps.collect(stage, stage.snow)
	check(planned.size() == 1 and planned[0].floor <= stage.snow.floor_height(stage, tree_base) + 0.001 and is_equal_approx(planned[0].base.y, tree_base.y), "trunk reaches from the pit floor up to the tree, so it does not hang in the air")
	check(planned.size() == 1 and Vector2(planned[0].base.x, planned[0].base.z).is_equal_approx(Vector2(tree_base.x, tree_base.z)) and is_equal_approx(planned[0].radius, 0.2), "trunk piece stands under the tree and matches the forest trunk")
	check(is_equal_approx(stage.trees[stage.trees.size() - 1].y, tree_base.y), "the tree itself is not moved: the forest above the snow looks the same")
	var tree_guest = Stage.new(1)
	get_root().add_child(tree_guest)
	tree_guest.trees.append(tree_base)
	tree_guest.forest_data.append({"height": 8.0})
	tree_guest._rebuild_tree_index()
	tree_guest.snow.authoritative = false
	tree_guest.snow.apply_dug_snapshot(stage.snow.dug_snapshot(), tree_guest)
	tree_guest.snow.update(0.5)
	var guest_stumps: MultiMeshInstance3D = tree_guest.get_node_or_null("SnowTrunkStumps")
	check(guest_stumps != null and guest_stumps.multimesh.instance_count == 1, "guest also extends the trunk into a pit the host dug")
	tree_guest.free()
	var root = Node3D.new()
	var shovel = Props.gear_box(root, "shovel")
	check(Props.CARGO_KINDS.has("shovel") and shovel.has_node("Blade") and shovel.has_node("Shaft") and shovel.has_node("Grip"), "cargo shovel has blade shaft and handle geometry")
	var cargo = preload("res://scripts/cars/car_cargo.gd").new()
	var poses = [[cargo.SHOVEL_POSITION, cargo.SHOVEL_ROTATION]]
	for pose in cargo.DIG_POSES: poses.append([pose[0], pose[1]])
	var samples: Array = []
	for phase in range(poses.size() - 1):
		var from = Quaternion.from_euler(poses[phase][1])
		var to = Quaternion.from_euler(poses[phase + 1][1])
		for step in range(17):
			var weight = step / 16.0
			samples.append([poses[phase][0].lerp(poses[phase + 1][0], weight), from.slerp(to, weight).get_euler()])
	for aspect in [1280.0 / 720, 844.0 / 390, 390.0 / 844]:
		var fits = true
		for pose in samples:
			var transform = Transform3D(Basis.from_euler(pose[1]), pose[0])
			for part in shovel.get_children():
				var bounds: AABB = part.get_aabb()
				for corner in range(8):
					var vertex: Vector3 = transform * (part.transform * bounds.get_endpoint(corner))
					fits = fits and vertex.z < -0.05 and absf(vertex.y) < -vertex.z * tan(deg_to_rad(68.0 / 2)) and absf(vertex.x) < -vertex.z * tan(deg_to_rad(68.0 / 2)) * aspect
		check(fits, "whole shovel stays in camera frame throughout digging, aspect %.2f" % aspect)
	var tween_owner = Node3D.new()
	get_root().add_child(tween_owner)
	cargo.game = tween_owner
	cargo.hand_box = shovel
	cargo.hand_kind = "shovel"
	cargo.animate_shovel()
	check(cargo.shovel_busy(), "digging animation starts")
	var active_swing = cargo.shovel_swing
	cargo.animate_shovel()
	check(cargo.shovel_swing == active_swing, "repeated input cannot stack digging animations")
	for tick in range(24): cargo.shovel_swing.custom_step(0.05)
	check(shovel.position.is_equal_approx(cargo.SHOVEL_POSITION) and shovel.quaternion.angle_to(Quaternion.from_euler(cargo.SHOVEL_ROTATION)) < 0.001, "digging animation returns to full-length resting pose")
	check(not shovel.get_node("SnowLoad").visible, "thrown snow leaves the blade empty at rest")
	var rest = Transform3D(Basis.from_euler(cargo.SHOVEL_ROTATION), cargo.SHOVEL_POSITION)
	var grip_point: Vector3 = rest * Vector3(0, 0.545, 0)
	var blade_point: Vector3 = rest * Vector3(0, -0.49, 0)
	check(grip_point.z > blade_point.z + 0.7 and grip_point.x > blade_point.x and blade_point.y / -blade_point.z > grip_point.y / -grip_point.z, "grip is held near the camera with the blade on the snow ahead")
	var plunge: Array = cargo.DIG_POSES[1]
	var plunge_tip: Vector3 = Transform3D(Basis.from_euler(plunge[1]), plunge[0]) * Vector3(0, -0.49, 0)
	check(plunge_tip.y < blade_point.y - 0.2 and plunge[3], "plunge drives the blade down into the drift and scoops snow")
	tween_owner.free()
	var game = preload("res://scripts/core/game.gd").new()
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
	# Walking into an untouched drift sinks the player and points them to the shovel.
	game.toast_label = Label.new()
	game.walker = stage.at(400) + stage.side(400) * 12.0
	game.walker.y = stage.walking_ground(game.walker)
	check(game.snow_wading() > 0.8, "player wades deep in an untouched drift")
	game._snow_hint(0.1)
	check("лопату" in game.toast_label.text and "багажник" in game.toast_label.text, "drift tells an empty-handed player to fetch the shovel")
	game.toast_label.text = ""
	game._snow_hint(0.1)
	check(game.toast_label.text == "", "drift hint is not repeated every frame")
	game.walker = stage.at(400)
	game.walker.y = stage.walking_ground(game.walker)
	game._snow_hint(30.0)
	check(game.snow_wading() == 0.0 and game.toast_label.text == "", "ploughed road neither slows nor warns")
	game.cargo.held["local"] = {"kind": "shovel", "owner": "local", "returning": false}
	game.walker = stage.at(400) + stage.side(400) * 12.0
	game._snow_hint(0.1)
	check("F" in game.toast_label.text, "player holding the shovel is told how to dig")
	# The shovel never blocks another action: starting one puts it back in the trunk.
	game.cargo.game = game
	var sent: Array = []
	game.room = FakeRoom.new()
	game.room.sent = sent
	var fake_room = game.room
	check(not game.cargo.blocks("local"), "a held shovel does not block sitting, drinking or eating")
	game.cargo.stow_shovel()
	check(not game.cargo.held.has("local") and sent == ["stow_shovel"], "starting another action teleports the shovel back to the trunk and tells the host")
	game.cargo.held["local"] = {"kind": "table", "owner": "local", "returning": false}
	game.cargo.stow_shovel()
	check(game.cargo.blocks("local") and game.cargo.held.has("local"), "a carried box still blocks actions and is never stowed automatically")
	game.cargo.held.erase("local")
	game.room = null
	fake_room.free()
	check("stow_shovel" in preload("res://scripts/net/net_protocol.gd").actions(), "guests can ask the host to stow their shovel")
	game.toast_label.free()
	game.stage = null
	game.free()
	stage.free()
	guest.free()
	node.free()
	root.free()
	finish()
