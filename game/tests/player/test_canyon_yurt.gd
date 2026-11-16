extends "res://tests/harness.gd"
# The guest yurt of the steppe camp on «Чарынский каньон»: its door stands
# open, a fan walks in onto the felt floor, the round wall holds them inside,
# and the room is furnished.
const Interior = preload("res://scripts/stages/canyon/yurt_interior.gd")

func _initialize() -> void:
	call_deferred("run")

func walk_to(game, target: Vector3, seconds: float) -> void:
	Input.action_press("forward")
	for i in range(int(seconds * 30.0)):
		var to = target - game.walker
		to.y = 0
		if to.length() < 0.15:
			break
		game.view_yaw = atan2(-to.x, -to.z)
		game.player.walk(1.0 / 30.0)
	Input.action_release("forward")

# Faces of different colours that face the same way, lie within GAP of each
# other and overlap flicker as the camera moves (z-fighting). Scans the baked
# camp mesh in the guest yurt's frame, inside its wall: "colour @ point" rows.
const GAP = 0.005

func flickering(mesh: Mesh, to_yurt: Transform3D) -> Array:
	var tris: Array = []
	var buckets: Dictionary = {}
	for surface in range(mesh.get_surface_count()):
		var arrays = mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors = arrays[Mesh.ARRAY_COLOR]
		var indices = arrays[Mesh.ARRAY_INDEX]
		var count = indices.size() if indices != null and indices.size() > 0 else verts.size()
		for k in range(0, count - 2, 3):
			var ids = [indices[k], indices[k + 1], indices[k + 2]] if indices != null and indices.size() > 0 else [k, k + 1, k + 2]
			var v = [to_yurt * verts[ids[0]], to_yurt * verts[ids[1]], to_yurt * verts[ids[2]]]
			var middle: Vector3 = (v[0] + v[1] + v[2]) / 3.0
			var cross: Vector3 = (v[1] - v[0]).cross(v[2] - v[0])
			if Vector2(middle.x, middle.z).length() > 3.2 or cross.length() < 0.0004:
				continue
			var n = cross.normalized()
			var tri = {"v": v, "n": n, "m": middle, "c": colors[ids[0]] if colors != null and colors.size() > 0 else Color.WHITE}
			var key = Vector4i(roundi(n.x * 20), roundi(n.y * 20), roundi(n.z * 20), roundi(n.dot(middle) / 0.05))
			if not buckets.has(key):
				buckets[key] = []
			buckets[key].append(tri)
			tris.append(tri)
	var rows: Array = []
	for key in buckets:
		var group: Array = buckets[key]
		for other_key in [key, key + Vector4i(0, 0, 0, 1)]:
			var others: Array = buckets.get(other_key, [])
			for a in group:
				for b in others:
					if a == b or a.n.dot(b.n) < 0.999 or absf(a.c.r - b.c.r) + absf(a.c.g - b.c.g) + absf(a.c.b - b.c.b) < 0.06:
						continue
					if absf(a.n.dot(b.m - a.v[0])) < GAP and (_inside(a, b.m) or _inside(b, a.m)):
						rows.append("%s/%s @ %s" % [a.c.to_html(false), b.c.to_html(false), a.m.snapped(Vector3.ONE * 0.01)])
	return rows

static func _inside(tri: Dictionary, p: Vector3) -> bool:
	var v: Array = tri.v
	var n: Vector3 = tri.n
	for i in range(3):
		if n.dot((v[(i + 1) % 3] - v[i]).cross(p - v[i])) < 0.0:
			return false
	return true

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.select_stage(3)
	await game.start_game()
	game.in_car = false
	var stage = game.stage
	var camp: Node3D = stage.get_node_or_null("SteppeYurtCamp")
	var guest: Node3D = camp.get_node_or_null("GuestYurt") if camp != null else null
	check(guest != null, "the steppe camp has a guest yurt with its door open")
	if guest == null:
		print("CANYON YURT RESULT: %d failures" % failures)
		finish()
		return
	var pose: Transform3D = camp.transform * guest.transform
	var parts: Dictionary = camp.get_meta("baked_parts", {})
	for part in ["YurtLining", "YurtFloor", "ShanyrakInner"]:
		check(parts.has(part), "the guest yurt is furnished: %s" % part)
	check(guest.get_node_or_null("YurtLantern") != null and guest.get_node("YurtLantern").has_meta("night_light"), "a lantern lights the room at night")
	var baked: MeshInstance3D = camp.get_node_or_null("Baked")
	var fighting = flickering(baked.mesh, pose.affine_inverse() * camp.transform) if baked != null else ["no baked mesh"]
	check(fighting != null and fighting.is_empty(), "nothing in the guest yurt flickers: no two differently coloured faces share a plane (%d: %s)" % [fighting.size(), "; ".join(fighting.slice(0, 20))])
	var other = camp.get_node_or_null("Yurt")
	check(other != null and other.get_node_or_null("YurtLantern") == null, "the other yurts stay closed")

	# Walk in from the yard through the doorway.
	var outside = pose * Vector3(0, 0, 6.0)
	game.walker = Vector3(outside.x, stage.ground(outside), outside.z)
	walk_to(game, pose * Vector3(0, 0, 1.6), 6.0)
	walk_to(game, pose * Vector3(-1.2, 0, 0.4), 3.0)
	var local = pose.affine_inverse() * game.walker
	check(Vector2(local.x, local.z).length() < 2.6, "a fan walks through the door into the yurt (%.2f m from the middle)" % Vector2(local.x, local.z).length())
	# The wall holds them in, wherever they walk.
	var inside = true
	for angle in [PI * 0.5, PI, -PI * 0.5, PI * 0.75]:
		game.walker = pose * Vector3(0.6, 0, 1.6)
		game.walker.y = stage.ground(game.walker)
		walk_to(game, pose * (Vector3(sin(angle), 0, cos(angle)) * 6.0), 4.0)
		local = pose.affine_inverse() * game.walker
		inside = inside and Vector2(local.x, local.z).length() < 3.2
	check(inside, "the round wall stops a walker inside the yurt")
	# From outside the felt wall is solid too, away from the door.
	game.walker = pose * Vector3(-6.0, 0, -1.0)
	game.walker.y = stage.ground(game.walker)
	walk_to(game, pose * Vector3(0, 0, -1.0), 4.0)
	local = pose.affine_inverse() * game.walker
	check(Vector2(local.x, local.z).length() > 3.3, "nobody walks into the yurt through its wall")
	check(not stage.solids.clear(pose * Vector3(0.5, 0, -1.0), 0.0), "scenery and camps keep out of the room")
	print("CANYON YURT RESULT: %d failures" % failures)
	finish()
