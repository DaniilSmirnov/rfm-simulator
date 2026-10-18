extends "res://tests/harness.gd"
const Registry = preload("res://scripts/core/prop_registry.gd")
const Props = preload("res://scripts/core/props.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.start_game()
	game.in_car = false
	var props = game.movable_props
	props.refresh()
	check(not props.records.is_empty(), "NPC camps and service equipment register as movable")
	var node = Node3D.new()
	game.add_child(node)
	var pos = game.stage.at(200)
	pos.y = game.stage.ground(pos)
	node.position = pos
	Props.box(node, Vector3(0, 0.4, 0), Vector3(0.6, 0.8, 0.6), Color.RED)
	node.set_meta("servings", 7)
	Registry.register(game.stage.solids, node, 15, false, "test:prop")
	props.refresh()
	var helper = {"pos": game.room.a(pos + Vector3(2, 0, 0)), "in_car": false, "tow": true}
	var occupied = props.update({"local": helper}, {}, 0.05)
	await physics_frame
	await physics_frame
	await process_frame
	check(occupied.has("local") and node.position.x > pos.x, "holding T moves the nearest prop")
	check(node.get_meta("servings") == 7, "dragging preserves gameplay state on the same node")

	var friend = helper.duplicate(true)
	props.update({"friend": friend, "local": helper}, {}, 0.05)
	check(props.grips.has("local") and not props.grips.has("friend"), "an existing grip cannot be stolen by player iteration order")
	helper.tow = false
	props.update({"local": helper}, {}, 0.05)
	check(props.grips.is_empty(), "releasing T releases the prop")
	for i in range(120): await physics_frame
	var walk_start: Vector3 = node.global_position
	game.walker = walk_start + Vector3.RIGHT * 1.5
	game.view_yaw = PI / 2
	Input.action_press("forward")
	for i in range(90):
		game.player.walk_step(1.0 / 60.0)
		game._update_tow(1.0 / 60.0)
		await physics_frame
	Input.action_release("forward")
	await process_frame
	check(node.global_position.distance_to(walk_start) > 0.05, "walking into a sleeping prop wakes and pushes it through actual player movement")
	var hit = game.stage.solids.hit(pos + Vector3(-3, 0.4, 0), node.position + Vector3(0, 0.4, 0), 0.1)
	check(hit.get("prop", "") == "test:prop", "collision follows the moving prop")
	var data = props.snapshot()
	var saved = node.global_position
	var shifted: Array = data.duplicate(true)
	for item in shifted:
		if item.key == "test:prop": item.pos[0] += 40
	props.apply_snapshot(shifted)
	var moved: Vector3 = node.position + Vector3.UP * 0.4
	check(game.stage.solids.hit(moved - Vector3.RIGHT * 2, moved + Vector3.RIGHT * 2, 0.1).get("prop", "") == "test:prop", "replication updates collision across spatial cells in the same frame")
	check(game.stage.solids.hit(saved - Vector3.RIGHT * 2, saved + Vector3.RIGHT * 2, 0.1).get("prop", "") != "test:prop", "moving an indexed prop leaves no collision at its former position")
	props.apply_snapshot(data)
	check(node.global_position.distance_to(saved) < 0.01, "network snapshot restores prop transform")
	var placed: Vector3 = saved + Vector3(4, 0, 0)
	game.camp_actions.ground_item(node, placed, 0.3)
	await physics_frame
	await physics_frame
	await process_frame
	check(node.global_position.distance_to(placed) < 0.1 and props.records["test:prop"].body.global_position.distance_to(node.global_position) < 0.02, "explicit placement moves both the existing gameplay node and physics body")
	props.records["test:prop"].anchored = true
	check(not props.knock("test:prop", Vector3(1, 0, 0)), "small contact cannot uproot an anchored prop")
	check(props.knock("test:prop", Vector3(10, 0, 0)), "vehicle impact releases anchored prop")
	check(not props.records["test:prop"].anchored, "released prop can be dragged")
	helper.tow = true
	helper.in_car = true
	props.update({"local": helper}, {}, 0.05)
	check(props.grips.is_empty(), "driver cannot drag props")

	var before = node.position
	props.records["test:prop"].velocity = Vector3(10, 0, 0)
	props.records["test:prop"].spin = Vector3.ZERO
	var wall = Node3D.new()
	game.stage.add_child(wall)
	wall.position = before + Vector3(0.8, 0, 0)
	game.stage.solids.solid(wall, Vector3.UP, Vector3(0.2, 2, 4), "wall")
	for i in range(20):
		props.update({}, {}, 0.05)
		await physics_frame
	check(node.position.x < wall.position.x, "drag/impact motion cannot pass through a wall")
	game.room.connected = true
	game.room.is_host = false
	check(not props.knock("test:prop", Vector3(10, 0, 0)), "guest cannot authoritatively knock a prop")
	game.room.connected = false
	var key = "test:prop"
	node.queue_free()
	await process_frame
	props.refresh()
	check(not props.records.has(key), "removed props leave no stale registry entry")
	await tree_and_lamp(game)
	await guest_camp(game)
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	finish()

func tree_and_lamp(game) -> void:
	var stage = game.stage
	var props = game.movable_props
	var point: Vector3 = stage.at(300)
	point.y = stage.ground(point)
	stage.trees[0] = point
	stage._rebuild_tree_index()
	stage.fell(0, Vector3.FORWARD)
	stage.update_fallen(1.3)
	props.refresh()
	check(props.records.has("tree:0"), "fallen instanced tree exposes a drag target")
	var tree: Dictionary = props.records["tree:0"]
	check(not tree.body.sleeping, "a newly fallen tree checks native support before sleeping")
	var helper = {"pos": game.room.a(props.center(tree) + Vector3(2, 0, 0)), "in_car": false, "tow": true}
	for i in range(30):
		props.update({"local": helper}, {}, 1.0 / 60.0)
		await physics_frame
	await process_frame
	check(tree.body.linear_velocity.x > 0.1 and stage.trees[0].distance_to(point) > 0.01 and stage.trees[0].is_equal_approx(tree.node.position), "dragging changes tree collision and rendering origin together")
	var snapshot: Array = stage.tree_snapshot()
	var moved: Vector3 = stage.trees[0]
	stage.trees[0] = point
	stage.apply_trees(snapshot)
	check(stage.trees[0].distance_to(moved) < 0.001, "tree snapshot carries the dragged origin")
	props.update({}, {}, 0.05)
	var lamp_point: Vector3 = stage.at(400)
	var lamp = stage.solids.lamp(lamp_point, 0)
	var index = stage.solids.lamps.size() - 1
	stage.solids.knock_lamp(index, Vector3.RIGHT * 10)
	props.refresh()
	check(props.records.has("lamp:%d" % index), "knocked lamp exposes a drag target")
	lamp.linear_velocity = Vector3.ZERO
	helper.pos = game.room.a(lamp_point + Vector3(2, 0, 0))
	props.update({"local": helper}, {}, 0.05)
	check(lamp.linear_velocity.x > 0, "dragging drives the existing lamp physics body")

func guest_camp(host) -> void:
	var guest = load("res://main.tscn").instantiate()
	root.add_child(guest)
	await process_frame
	guest.set_process(false)
	guest.room.set_process(false)
	guest.start_game()
	guest.room.connected = true
	guest.room.is_host = false
	guest.room.player_id = "guest"
	host.grill = Props.grill(host)
	host.grill.position = host.stage.at(500)
	host.grill.set_meta("gear_owner", "local")
	host.cooking = true
	host.camp_grill.servings = 7
	host.movable_props.refresh()
	var key = str(host.grill.get_meta("prop_key"))
	host.movable_props.knock(key, Vector3(8, 0, 0))
	host.movable_props.update({}, {}, 0.05)
	var world: Dictionary = host.room.world_state()
	guest.room.apply_world(world)
	guest.room.apply_world(world)
	check(guest.grill != null and guest.grill.global_position.distance_to(host.grill.global_position) < 0.01, "late guest receives moved camp equipment")
	check(guest.camp_grill.servings == 7 and guest.grill.get_meta("gear_owner") == "local", "replication preserves grill food and equipment ownership")
	check(guest.grill.global_rotation.distance_to(host.grill.global_rotation) < 0.01, "prop rotation survives repeated camp snapshots")
	var fallen_pose: Transform3D = guest.grill.global_transform
	var camp_only = world.duplicate(true)
	camp_only.erase("movable_props")
	guest.room.apply_world(camp_only)
	check(guest.grill.global_transform == fallen_pose, "a camp update without a prop snapshot never stands up moved equipment")
	check(not host.grill.get_children().any(func(n): return n.has_meta("prop_key")), "tabletop and equipment detail has no independent movement")
	await guest._shutdown_audio()
	guest.queue_free()
	await process_frame
