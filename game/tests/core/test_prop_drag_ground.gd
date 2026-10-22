extends "res://tests/harness.gd"
# A prop a walker drags over the land never ends up under it: a crate dragged
# across a hillside and over the road verge, a felled trunk dragged up and
# down the slope, and whatever the physics still squeezes through the terrain
# tiles (or buries, for a trunk that cannot pitch) comes straight back up.
const Registry = preload("res://scripts/core/prop_registry.gd")
const Props = preload("res://scripts/core/props.gd")

func _initialize() -> void:
	call_deferred("run")

# The steepest off-road spot along the route, its downhill direction and the
# way to the road.
func steep(stage) -> Dictionary:
	var best = {"slope": -1.0}
	for s in range(80, int(stage.length) - 80, 20):
		for side in [-1.0, 1.0]:
			var p: Vector3 = stage.at(s) + stage.side(s) * side * (stage.road_width(s) * 0.5 + 9.0)
			if stage.water != null and stage.water.depth(p) > 0.0: continue
			var gx = stage.ground(p + Vector3(1, 0, 0)) - stage.ground(p - Vector3(1, 0, 0))
			var gz = stage.ground(p + Vector3(0, 0, 1)) - stage.ground(p - Vector3(0, 0, 1))
			var slope = Vector2(gx, gz).length() * 0.5
			if slope > best.slope:
				p.y = stage.ground(p)
				best = {"slope": slope, "pos": p, "down": -Vector3(gx, 0, gz).normalized(), "road": -stage.side(s) * side}
	return best

func trunk_points(stage, index: int, turn := Basis.IDENTITY) -> Array:
	var axis: Vector3 = turn * (stage.fallen_basis(index) * Vector3.UP)
	var length: float = stage.forest_data[index].height * 0.64
	var points: Array = []
	for i in range(9):
		points.append(stage.trees[index] + axis * length * i / 8.0)
	return points

# How far the middle of a prop (the centre line of a trunk) is above the land
# at its lowest.
func clearance(game, r: Dictionary, turn := Basis.IDENTITY) -> float:
	var stage = game.stage
	if r.has("tree"):
		var worst = INF
		for p in trunk_points(stage, r.tree, turn):
			worst = minf(worst, p.y + 0.2 - stage.ground(p))
		return worst
	var c: Vector3 = r.node.global_transform * r.box.get_center()
	return c.y - stage.ground(c)

# A walker pulling the prop along `legs`, each for the same share of the time.
# At tick `sink_at` the prop is pushed under the land, as the solver did.
func drag(game, r: Dictionary, seconds: float, legs: Array, sink_at := -1) -> float:
	var props = game.movable_props
	var worst = INF
	var ticks = int(seconds * 60.0)
	for i in range(ticks):
		var heading: Vector3 = legs[i * legs.size() / ticks].normalized()
		var pos = props.center(r) + heading * 2.4
		pos.y = game.stage.ground(pos)
		props.update({"local": {"pos": game.room.a(pos), "in_car": false, "tow": true}}, {}, 1.0 / 60.0)
		if i == sink_at:
			r.body.global_position.y -= 4.0
		await physics_frame
		if i > sink_at:
			worst = minf(worst, clearance(game, r))
	for i in range(30):
		props.update({}, {}, 1.0 / 60.0)
		await physics_frame
	return minf(worst, clearance(game, r))

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.start_game()
	game.in_car = false
	var stage = game.stage
	var props = game.movable_props
	var spot: Dictionary = steep(stage)
	var down: Vector3 = spot.down
	var across: Vector3 = down.cross(Vector3.UP)
	check(spot.slope > 0.5, "the test finds a steep hillside (%.2f)" % spot.slope)

	var node = Node3D.new()
	game.add_child(node)
	var pos: Vector3 = spot.pos + across * 6.0
	pos.y = stage.ground(pos)
	node.position = pos
	Props.box(node, Vector3(0, 0.4, 0), Vector3(0.6, 0.8, 0.6), Color.RED)
	Registry.register(stage.solids, node, 6, false, "test:crate")
	props.refresh()
	var crate: Dictionary = props.records["test:crate"]
	var worst = await drag(game, crate, 8.0, [-down, across, down, -across])
	check(node.position.distance_to(pos) > 2.0 and worst > 0.15, "a crate dragged up, down and across a hillside stays on it (moved %.1f m, lowest middle %.2f m)" % [node.position.distance_to(pos), worst])
	worst = await drag(game, crate, 8.0, [spot.road])
	check(worst > 0.15, "a crate dragged down the verge onto the road stays on the land (lowest middle %.2f m)" % worst)
	worst = await drag(game, crate, 4.0, [-down, across], 60)
	check(worst > 0.15, "a crate squeezed under the land while dragged is back on it at once (lowest middle %.2f m)" % worst)

	stage.trees[0] = spot.pos
	stage._rebuild_tree_index()
	stage.fell(0, down)
	stage.update_fallen(1.3)
	props.refresh()
	var tree: Dictionary = props.records["tree:0"]
	worst = await drag(game, tree, 8.0, [-down, across, down])
	check(stage.trees[0].distance_to(spot.pos) > 0.5 and worst > -0.15, "a felled trunk dragged over the hillside stays on it (lowest %.2f m)" % worst)
	# Turned round without pitching, the trunk's top end is deep in the hill.
	var turn = Basis(Vector3.UP, PI)
	var buried: float = clearance(game, tree, turn)
	tree.body.global_transform = Transform3D(turn * tree.body.global_basis, tree.body.global_position)
	worst = await drag(game, tree, 3.0, [across])
	check(buried < -1.0 and worst > -0.15, "a trunk with an end buried in the hill is laid along the land as soon as it is dragged (%.1f m under, then lowest %.2f m)" % [buried, worst])
	var released: Vector3 = stage.trees[0]
	for i in range(60):
		props.update({}, {}, 1.0 / 60.0)
		await physics_frame
	check(stage.trees[0].distance_to(released) < 0.05, "a trunk set back on the land stays where it was let go")

	var lamp_point: Vector3 = spot.pos - across * 6.0
	lamp_point.y = stage.ground(lamp_point)
	var lamp = stage.solids.lamp(lamp_point, 0)
	stage.solids.knock_lamp(stage.solids.lamps.size() - 1, down)
	for i in range(60):
		await physics_frame
	lamp.global_position.y -= 4.0
	await physics_frame
	await physics_frame
	check(lamp.global_position.y > stage.ground(lamp.global_position) - 0.2, "a fallen post pushed under its ground patch is put back on it")
	finish()
