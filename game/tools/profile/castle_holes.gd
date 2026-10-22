extends SceneTree
# Diagnostic: ground inside the canyon castles (stage 3) that no rock record
# covers, where a walker or a car would stand inside the drawn rock, and open
# ground the records block far from any rock (invisible walls). Samples 1 m
# above the ground on a 1 m grid; headless works, about a minute:
# godot --headless --path game --script res://tools/profile/castle_holes.gd
const Stage = preload("res://scripts/stages/stage.gd")
const STEP = 1.0
const WALKER = 0.3

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var stage = Stage.new(3)
	root.add_child(stage)
	stage.build()
	var inside = 0
	var holes = 0
	var blocked: Array = []
	var rock: Dictionary = {}
	var worst: Array = []
	for node in stage.get_node("CanyonValleyTowers").get_children():
		var mesh = _index(node.mesh.get_faces())
		var box: AABB = node.mesh.get_aabb()
		var x = box.position.x
		while x < box.end.x:
			var z = box.position.z
			while z < box.end.z:
				var p = Vector3(x, 0.0, z)
				p.y = stage.terrain_surface_height(p) + 1.0
				var gap = _gap(stage, p)
				if not _inside(mesh, p):
					if gap == 0.0 and _walkable(stage, p): blocked.append(p)
				else:
					rock[Vector2i(roundi(x), roundi(z))] = true
					inside += 1
					if gap > WALKER and _walkable(stage, p):
						holes += 1
						worst.append([gap, p])
				z += STEP
			x += STEP
	worst.sort_custom(func(a, b): return a[0] > b[0])
	print("CASTLE HOLES: %d of %d inside points uncovered on walkable ground (%.1f%%), rocks=%d" % [holes, inside, 100.0 * holes / maxi(inside, 1), stage.rocks.size()])
	var far = [0, 0, 0]
	for p in blocked:
		var cell = Vector2i(roundi(p.x), roundi(p.z))
		for i in range(3):
			var reach = [1, 2, 3][i]
			var near = false
			for dx in range(-reach, reach + 1):
				for dz in range(-reach, reach + 1):
					near = near or rock.has(cell + Vector2i(dx, dz))
			if not near:
				far[i] += 1
	for i in range(mini(12, worst.size())):
		print("  %.1f m from a collider at %s" % worst[i])
	print("BLOCKED ON OPEN GROUND: %d points, more than 1/2/3 m from rock: %s (talus boulders included)" % [blocked.size(), far])
	stage.free()
	quit()

# Triangles by the 1 m rows of z they span.
func _index(faces: PackedVector3Array) -> Dictionary:
	var rows: Dictionary = {}
	for i in range(0, faces.size(), 3):
		var tri = [faces[i], faces[i + 1], faces[i + 2]]
		for row in range(floori(minf(minf(tri[0].z, tri[1].z), tri[2].z)), floori(maxf(maxf(tri[0].z, tri[1].z), tri[2].z)) + 1):
			if not rows.has(row): rows[row] = []
			rows[row].append(tri)
	return rows

# Inside the rock: more faces entered than left on the way along x (the
# towers of a castle overlap).
func _inside(rows: Dictionary, p: Vector3) -> bool:
	var crossings: Array = []
	for tri in rows.get(floori(p.z), []):
		var hit = Geometry3D.ray_intersects_triangle(Vector3(p.x - 400.0, p.y, p.z), Vector3.RIGHT, tri[0], tri[1], tri[2])
		if hit != null and hit.x < p.x:
			crossings.append((tri[2] - tri[0]).cross(tri[1] - tri[0]).x)
	var depth = 0
	for facing in crossings:
		depth += 1 if facing < 0.0 else -1
	return depth > 0

# Ground a walker can stand on, not the face of a cliff.
func _walkable(stage, p: Vector3) -> bool:
	var h = stage.terrain_surface_height(p)
	for o in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		if absf(stage.terrain_surface_height(p + o) - h) > 1.0: return false
	return true

# How far p is outside the nearest rock circle (0 when it is covered).
func _gap(stage, p: Vector3) -> float:
	var best = INF
	var flat = Vector2(p.x, p.z)
	for rock in stage.rocks_in_bounds(flat - Vector2.ONE * 40.0, flat + Vector2.ONE * 40.0):
		if rock.has("actor") or p.y - 1.0 > rock.pos.y + rock.height: continue
		best = minf(best, Vector2(rock.pos.x, rock.pos.z).distance_to(flat) - float(rock.radius))
	return maxf(best, 0.0)

