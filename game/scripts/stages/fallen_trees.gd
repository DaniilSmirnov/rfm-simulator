extends RefCounted
# Felled trees: the angle a trunk comes to rest at and its rendered pose.

# How far a felled trunk turns from upright: it comes to rest along the ground
# it falls onto, past level downhill and short of it uphill, instead of lying
# level and being left to a rigid body that rolled it down the slope.
const MAX_LIE_PITCH = 0.7
static func lie_angle(stage, base: Vector3, direction: Vector3, length: float) -> float:
	var rise: float = stage.ground(base + direction * length) - stage.ground(base)
	return PI * 0.5 - clampf(atan2(rise, length), -MAX_LIE_PITCH, MAX_LIE_PITCH)

# Turns the rendered trunk and crown of every felled tree to its pose.
static func update(stage, delta: float) -> void:
	for index in stage.fallen:
		var tree_data: Dictionary = stage.forest_data[index]
		var f: Dictionary = stage.fallen[index]
		f.age = minf(1.3, f.age + delta)
		var basis = stage.fallen_basis(index)
		if f.get("rendered_age", -1.0) == f.age and f.get("basis", Basis.IDENTITY).is_equal_approx(basis):
			continue
		f.rendered_age = f.age
		f.basis = basis
		if stage.detail_tree_visuals.has(index):
			for part in stage.detail_tree_visuals[index]:
				var pose: Transform3D = part.pose
				pose.origin = stage.trees[index] + basis * (pose.origin - f.origin) - part.center
				pose.basis = basis * pose.basis
				part.mesh.set_instance_transform(part.instance, pose)
			continue
		var h: float = tree_data.height
		for layer in range(stage.forest_layers.size()):
			var radius = 0.2 if layer == 0 else h * (0.28 - (layer - 1) * 0.055)
			var height = h * (0.64 if layer == 0 else 0.49)
			var y = h * (0.32 if layer == 0 else 0.47 + (layer - 1) * 0.18)
			var slot: Vector2i = stage.forest_chunk_slots[index]
			stage.forest_layers[layer][slot.x].set_instance_transform(slot.y, Transform3D(basis * Basis.from_scale(Vector3(radius, height, radius)), stage.trees[index] - stage.forest_chunk_centers[slot.x] + Vector3(0, 0.2, 0) + basis * Vector3(0, y, 0)))

# ---------------------------------------------------------------- shared state

# The most felled trees a stage keeps. Past it the authority stands the oldest
# one nobody is near back up, so the shared snapshot stays bounded.
const LIMIT = 256
# Metres a tree, standing or felled, keeps from every player, car and camp
# item when it is stood back up: nobody sees it happen or gets caught in it.
const RAISE_CLEARANCE = 80.0

# One wire entry per felled tree: [id, heading, lie, age], plus the base
# [x, y, z] once a drag moved it off the stump (about 25 bytes a tree).
static func snapshot(stage) -> Array:
	var result: Array = []
	for index in stage.fallen:
		var f: Dictionary = stage.fallen[index]
		var entry = [index, snappedf(atan2(f.direction.x, f.direction.z), 0.001), snappedf(float(f.get("lie", PI * 0.5)), 0.001), snappedf(f.age, 0.01)]
		var base: Vector3 = stage.trees[index]
		if not base.is_equal_approx(f.get("origin", base)):
			entry.append_array([snappedf(base.x, 0.01), snappedf(base.y, 0.01), snappedf(base.z, 0.01)])
		result.append(entry)
	return result

# A guest takes the host's felled trees and stands up any it no longer lists,
# except the ones in `keep` (its own falls the host has not confirmed yet).
static func apply(stage, entries: Array, keep: Dictionary = {}) -> void:
	var listed: Dictionary = {}
	for entry in entries:
		var index = int(entry[0])
		if index < 0 or index >= stage.trees.size():
			continue
		listed[index] = true
		var direction = Vector3(sin(float(entry[1])), 0, cos(float(entry[1])))
		stage.fell(index, direction)
		var f: Dictionary = stage.fallen[index]
		f.direction = direction
		f.age = maxf(f.age, float(entry[3]))
		f.lie = float(entry[2])
		var base: Vector3 = Vector3(entry[4], entry[5], entry[6]) if entry.size() >= 7 else f.get("origin", stage.trees[index])
		if not stage.trees[index].is_equal_approx(base):
			stage.trees[index] = base
			f.erase("rendered_age")
	for index in stage.fallen.keys():
		if not listed.has(index) and not keep.has(index):
			raise(stage, index)
	stage._rebuild_tree_index()
	update(stage, 0)

# Stands a felled tree back up on its stump: trunk, crown and collision.
static func raise(stage, index: int) -> void:
	if not stage.fallen.has(index):
		return
	var origin: Vector3 = stage.fallen[index].get("origin", stage.trees[index])
	stage.fallen.erase(index)
	stage.trees[index] = origin
	stage.indexed_tree_count = -1
	if stage.detail_tree_visuals.has(index):
		for part in stage.detail_tree_visuals[index]:
			var pose: Transform3D = part.pose
			pose.origin -= part.center
			part.mesh.set_instance_transform(part.instance, pose)
	elif index < stage.forest_chunk_slots.size():
		var h: float = stage.forest_data[index].height
		var slot: Vector2i = stage.forest_chunk_slots[index]
		for layer in range(stage.forest_layers.size()):
			var pose: Transform3D = stage.woodland.shared_tree_pose(origin, h, layer)
			pose.origin -= stage.forest_chunk_centers[slot.x]
			stage.forest_layers[layer][slot.x].set_instance_transform(slot.y, pose)
	if stage.solids != null and stage.solids.prop_ground != null:
		stage.solids.prop_ground.stand(index)

# The authority (host or solo) keeps at most LIMIT felled trees: one frame
# stands up at most one, the oldest that has settled, is not held, and lies
# out of everyone's sight. `players`: the states Recovery.update works with.
static func recycle(game, players: Dictionary) -> void:
	var stage = game.stage
	if stage.fallen.size() <= LIMIT:
		return
	var near: Array = []
	for id in players:
		if players[id].get("pos") is Array:
			near.append(game.room.v(players[id].pos))
		var car = game.Recovery.car_position(game, str(id))
		if car != null:
			near.append(car)
	for racer in game.racers:
		near.append(racer.node.position)
	near.append_array(game.park_traffic.car_positions())
	for item in game.packing.items():
		if is_instance_valid(item.node):
			near.append(item.node.global_position)
	var held: Array = game.movable_props.grips.values()
	for index in stage.fallen:
		if stage.fallen[index].age < 1.3 or held.has("tree:%d" % index):
			continue
		var spots: Array = [stage.flat(stage.trees[index]), stage.flat(stage.fallen[index].get("origin", stage.trees[index]))]
		var clear = true
		for pos in near:
			for spot in spots:
				clear = clear and spot.distance_to(stage.flat(pos)) > RAISE_CLEARANCE
		if clear:
			raise(stage, index)
			stage._rebuild_tree_index()
			return
