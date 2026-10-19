extends RefCounted
const Props = preload("res://scripts/core/props.gd")

static func build(parent: Node3D, recipe: String = "plov") -> Node3D:
	var root = Node3D.new()
	root.name = "Cauldron"
	root.set_meta("recipe", recipe)
	parent.add_child(root)
	# Three-legged stand and hollow tapered bowl; the inside stays visible when empty.
	for i in range(3):
		var angle = i * TAU / 3
		var a = Vector3(cos(angle) * 0.68, 0.05, sin(angle) * 0.68)
		var b = Vector3(cos(angle) * 0.50, 1.24, sin(angle) * 0.50)
		var leg = Props.cylinder(root, (a + b) / 2, 0.025, 0.025, a.distance_to(b), Color("444c50"), 6)
		leg.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
	var vertices = PackedVector3Array()
	var rim_vertices = PackedVector3Array()
	for i in range(16):
		var a = i * TAU / 16
		var b = (i + 1) * TAU / 16
		var rings = [Vector2(0.16, 0.84), Vector2(0.32, 0.88), Vector2(0.46, 1.02), Vector2(0.53, 1.18), Vector2(0.55, 1.28)]
		for r in range(rings.size() - 1):
			var low_a = Vector3(cos(a) * rings[r].x, rings[r].y, sin(a) * rings[r].x)
			var low_b = Vector3(cos(b) * rings[r].x, rings[r].y, sin(b) * rings[r].x)
			var high_a = Vector3(cos(a) * rings[r + 1].x, rings[r + 1].y, sin(a) * rings[r + 1].x)
			var high_b = Vector3(cos(b) * rings[r + 1].x, rings[r + 1].y, sin(b) * rings[r + 1].x)
			vertices.append_array(PackedVector3Array([low_a, high_a, high_b, low_a, high_b, low_b]))
		var high_a = Vector3(cos(a) * 0.55, 1.28, sin(a) * 0.55)
		var high_b = Vector3(cos(b) * 0.55, 1.28, sin(b) * 0.55)
		var inner_a = Vector3(cos(a) * 0.50, 1.28, sin(a) * 0.50)
		var inner_b = Vector3(cos(b) * 0.50, 1.28, sin(b) * 0.50)
		rim_vertices.append_array(PackedVector3Array([high_a, inner_a, inner_b, high_a, inner_b, high_b]))
	var metal = Props.material(Color("303a40"))
	metal.cull_mode = BaseMaterial3D.CULL_DISABLED
	for data in [vertices, rim_vertices]:
		var bowl = MeshInstance3D.new()
		bowl.mesh = Props.panel_mesh(data)
		bowl.material_override = metal
		root.add_child(bowl)
	Props.cylinder(root, Vector3(0, 0.88, 0), 0.32, 0.32, 0.025, Color("151d22"), 16).name = "EmptyBottom"
	for side in [-1, 1]:
		var handle = MeshInstance3D.new()
		handle.mesh = TorusMesh.new()
		handle.mesh.inner_radius = 0.065
		handle.mesh.outer_radius = 0.10
		handle.mesh.rings = 12
		handle.mesh.ring_segments = 6
		handle.material_override = metal
		handle.position = Vector3(side * 0.59, 1.20, 0)
		handle.rotation.z = PI * 0.5
		root.add_child(handle)
	var rice = Node3D.new()
	rice.name = "Rice"
	root.add_child(rice)
	var surface = Props.cylinder(rice, Vector3.ZERO, 0.36, 0.465, 0.26, (Color("6b3b25") if recipe == "kuyrdak" else Color("e1ba64")), 16)
	surface.name = "FoodSurface"
	Props.unique_material(surface)
	for i in range(Props.FOOD_PORTIONS):
		var portion = Node3D.new()
		portion.name = "Portion_%02d" % i
		rice.add_child(portion)
		var angle = i * 2.4
		var radius = 0.12 + (i % 3) * 0.12
		portion.position = Vector3(cos(angle) * radius, 0.145, sin(angle) * radius)
		if recipe == "kuyrdak":
			# Roasted meat, darker liver, golden potatoes and curved onion strips.
			for j in range(3):
				var piece = Props.faceted(portion, Vector3((j - 1) * 0.055, 0.035 + j * 0.012, 0), Vector3(0.115, 0.085, 0.095), Color("713d27") if j % 2 == 0 else Color("44291f"), 6, 3)
				piece.rotation = Vector3(i * 0.31, j * 1.2 + i, j * 0.23)
			Props.faceted(portion, Vector3(0.01, 0.04, 0.085), Vector3(0.10, 0.07, 0.09), Color("c89445"), 5, 3)
			for j in range(4):
				var onion_angle = j * 0.65
				var onion = Props.box(portion, Vector3(cos(onion_angle) * 0.07, 0.085, sin(onion_angle) * 0.07), Vector3(0.05, 0.018, 0.02), Color("e2c68c"))
				onion.rotation.y = -onion_angle + PI * 0.5
		else:
			for j in range(4):
				var grain = Props.box(portion, Vector3((j % 2) * 0.035, 0.008, (j / 2) * 0.035), Vector3(0.026, 0.020, 0.055), Color("f5d994"))
				grain.rotation.y = j * 0.7
			Props.box(portion, Vector3(-0.03, 0.015, 0), Vector3(0.045, 0.035, 0.06), Color("d87e2f"))
			Props.box(portion, Vector3(0.03, 0.027, -0.025), Vector3(0.06, 0.05, 0.045), Color("895033"))
	var bubbles = Node3D.new()
	bubbles.name = "Bubbles"
	root.add_child(bubbles)
	for i in range(4):
		Props.faceted(bubbles, Vector3(cos(i * 2.3) * 0.28, 1.18, sin(i * 2.3) * 0.28), Vector3.ONE * 0.045, Color("fff0bb"), 6, 3)
	var steam = Node3D.new()
	steam.name = "Steam"
	root.add_child(steam)
	for i in range(5):
		Props.faceted(steam, Vector3.ZERO, Vector3.ONE * 0.13, Color("dbe0d6"), 6, 3)
	pose(root, "empty", 0, 0, 0)
	return load("res://scripts/player/perches.gd").mark(root, false)

static func pose(root: Node3D, phase: String, progress: float, servings: int, time: float) -> void:
	root.set_meta("phase", phase)
	root.set_meta("servings", servings)
	var rice = root.get_node("Rice")
	var visible = phase == "cooking" or (phase == "ready" and servings > 0)
	rice.visible = visible
	var fraction = lerpf(0.15, 1.0, clampf(progress, 0, 1)) if phase == "cooking" else float(servings) / Props.FOOD_PORTIONS
	rice.scale = Vector3(lerpf(0.70, 1.0, fraction), maxf(0.05, fraction), lerpf(0.70, 1.0, fraction))
	rice.position.y = 0.95 + 0.13 * fraction
	var surface = rice.get_node("FoodSurface")
	surface.material_override.albedo_color = Color("eee3b5").lerp(Color("e1ba64"), clampf(progress, 0, 1)) if phase == "cooking" else (Color("6b3b25") if root.get_meta("recipe", "plov") == "kuyrdak" else Color("e1ba64"))
	for i in range(Props.FOOD_PORTIONS):
		rice.get_node("Portion_%02d" % i).visible = phase == "cooking" or i < servings
	var bubbles = root.get_node("Bubbles")
	bubbles.visible = phase == "cooking"
	for i in range(bubbles.get_child_count()):
		var bubble = bubbles.get_child(i)
		bubble.position.y = rice.position.y + 0.13 * fraction + 0.03 + sin(time * 8 + i) * 0.014
		bubble.scale = Vector3.ONE * (0.7 + sin(time * 7 + i * 2) * 0.3)
	var steam = root.get_node("Steam")
	steam.visible = visible
	for i in range(steam.get_child_count()):
		var puff = steam.get_child(i)
		var cycle = fposmod(time * 0.45 + i * 0.2, 1.0)
		puff.position = Vector3(sin(time + i) * 0.16, 1.30 + cycle * 0.65, cos(time * 0.7 + i) * 0.16)
		puff.scale = Vector3.ONE * sin(cycle * PI)
