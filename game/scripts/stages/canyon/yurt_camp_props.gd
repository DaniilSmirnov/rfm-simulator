extends RefCounted
# Static yard furnishings, grounded individually and merged with the camp.
const Props = preload("res://scripts/core/props.gd")
const WOOD = Color("795535")
const RED = Color("783e35")
const CREAM = Color("d8bf91")

static func pole(parent: Node3D, a: Vector3, b: Vector3, radius: float, color: Color) -> void:
	var stick = Props.cylinder(parent, (a + b) * 0.5, radius, radius, a.distance_to(b), color, 6)
	# Straight rope/wood segments need no intermediate height rings.
	stick.mesh = stick.mesh.duplicate()
	stick.mesh.rings = 0
	stick.quaternion = Quaternion(Vector3.UP, (b - a).normalized())

static func ground(stage, parent: Node3D, at: Vector3, lift: float = 0) -> Vector3:
	var world = parent.to_global(at)
	world.y = stage.terrain_surface_height(world) + lift
	return parent.to_local(world)

static func build(stage, parent: Node3D) -> void:
	# Leave a clear approach to the shared cauldron and all three doorways.
	for side in [-1, 1]:
		var at = Vector3(side * 4.5, 0, 2.6)
		_rug(stage, parent, at)
		_table(stage, parent, at)
		for offset in [Vector3(-1.15, 0, -0.65), Vector3(1.15, 0, 0.65), Vector3(-0.65, 0, 0.92)]:
			var cushion = Props.faceted(parent, ground(stage, parent, at + offset, 0.13), Vector3(0.50, 0.23, 0.43), RED.lightened(absf(offset.x) * 0.06), 8, 4)
			cushion.rotation.y = offset.x * 0.2
	_storage(stage, parent)
	_firewood(stage, parent, Vector3(-3.2, 0, -3.0))
	_hitching_rail(stage, parent, Vector3(9.0, 0, 3.0))

static func _rug(stage, parent: Node3D, at: Vector3) -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_patch(st, stage, parent, at, Vector2(3.25, 2.45), RED.darkened(0.18), 0.018)
	_patch(st, stage, parent, at, Vector2(2.98, 2.18), CREAM, 0.021)
	_patch(st, stage, parent, at, Vector2(2.80, 2.00), RED, 0.024)
	# Simple woven diamonds and border stitches, without national insignia.
	for x in [-1.1, 0, 1.1]:
		for z in [-0.75, 0.75]:
			st.set_color(CREAM)
			for p in [Vector3(x, 0, z - 0.16), Vector3(x + 0.15, 0, z), Vector3(x, 0, z + 0.16), Vector3(x, 0, z - 0.16), Vector3(x, 0, z + 0.16), Vector3(x - 0.15, 0, z)]:
				st.add_vertex(ground(stage, parent, at + p, 0.028))
	for x in range(-7, 8):
		for side in [-1, 1]:
			_patch(st, stage, parent, at + Vector3(x * 0.20, 0, side * 1.25), Vector2(0.025, 0.13), CREAM, 0.019)
	st.generate_normals()
	var rug = MeshInstance3D.new()
	rug.name = "WovenRug"
	rug.mesh = st.commit()
	rug.material_override = Props.material(Color.WHITE)
	rug.material_override.vertex_color_use_as_albedo = true
	rug.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	parent.add_child(rug)
	rug.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rug.set_meta("unbatched", true)

static func _patch(st: SurfaceTool, stage, parent: Node3D, at: Vector3, size: Vector2, color: Color, lift: float) -> void:
	st.set_color(color)
	var a = at + Vector3(-size.x, 0, -size.y) * 0.5
	var b = at + Vector3(size.x, 0, -size.y) * 0.5
	var c = at + Vector3(size.x, 0, size.y) * 0.5
	var d = at + Vector3(-size.x, 0, size.y) * 0.5
	for point in [a, b, c, a, c, d]:
		st.add_vertex(ground(stage, parent, point, lift))

static func _table(stage, parent: Node3D, at: Vector3) -> void:
	var top = ground(stage, parent, at).y + 0.48
	for x in [-0.61, 0.61]:
		for z in [-0.28, 0.28]:
			top = maxf(top, ground(stage, parent, at + Vector3(x, 0, z)).y + 0.48)
	for x in [-0.61, 0.61]:
		for z in [-0.28, 0.28]:
			var foot = ground(stage, parent, at + Vector3(x, 0, z))
			Props.box(parent, Vector3(foot.x, (foot.y + top) * 0.5, foot.z), Vector3(0.07, top - foot.y, 0.07), WOOD)
	var center = Vector3(at.x, top, at.z)
	Props.box(parent, center, Vector3(1.55, 0.065, 0.85), WOOD.lightened(0.10))
	Props.box(parent, center + Vector3(0.22, 0.038, 0), Vector3(0.65, 0.008, 0.65), CREAM)
	for x in [-0.53, 0.53]:
		for z in [-0.23, 0.23]:
			var bowl = center + Vector3(x, 0.07, z)
			Props.cylinder(parent, bowl, 0.06, 0.105, 0.06, Color("d1c1a3"), 12)
			Props.cylinder(parent, bowl + Vector3.UP * 0.025, 0.092, 0.092, 0.01, Color("583822"), 12)
	Props.faceted(parent, center + Vector3(0.20, 0.10, 0), Vector3(0.34, 0.10, 0.27), Color("c99754"), 10, 4)
	var kettle = center + Vector3(-0.24, 0.15, 0)
	Props.faceted(parent, kettle, Vector3(0.26, 0.23, 0.24), Color("777e79"), 10, 5)
	Props.cylinder(parent, kettle + Vector3.UP * 0.12, 0.10, 0.05, 0.045, Color("515852"), 10)
	pole(parent, kettle + Vector3(0.08, 0, 0), kettle + Vector3(0.22, 0.10, 0), 0.025, Color("777e79"))
	for side in [-1, 1]:
		pole(parent, kettle + Vector3(0, 0, side * 0.10), kettle + Vector3(0, 0.24, side * 0.10), 0.015, Color("393d38"))
	pole(parent, kettle + Vector3(0, 0.24, -0.10), kettle + Vector3(0, 0.24, 0.10), 0.018, Color("393d38"))

static func _storage(stage, parent: Node3D) -> void:
	var at = ground(stage, parent, Vector3(-6.5, 0, -3.5))
	Props.box(parent, at + Vector3.UP * 0.28, Vector3(1.05, 0.56, 0.56), WOOD)
	Props.box(parent, at + Vector3.UP * 0.58, Vector3(1.11, 0.07, 0.60), WOOD.lightened(0.14))
	for x in [-0.36, 0.36]:
		Props.box(parent, at + Vector3(x, 0.29, 0.29), Vector3(0.06, 0.56, 0.025), Color("3f3b32"))
	for i in range(3):
		var roll_at = ground(stage, parent, Vector3(-6.5 + (0.19 if i == 2 else i * 0.38), 0, -2.6), 0.15 + (0.26 if i == 2 else 0.0))
		var roll = Props.cylinder(parent, roll_at, 0.15, 0.15, 1.0, CREAM.darkened(i * 0.045), 12)
		roll.rotation.z = PI * 0.5
		for x in [-0.33, 0.33]:
			var band = Props.cylinder(parent, roll_at + Vector3.RIGHT * x, 0.157, 0.157, 0.035, RED, 12)
			band.rotation.z = PI * 0.5
	for i in range(2):
		var jar = ground(stage, parent, Vector3(7.0 + i * 0.55, 0, -1.4), 0.25)
		Props.faceted(parent, jar, Vector3(0.34, 0.50, 0.34), Color("ad7952"), 12, 6)
		Props.cylinder(parent, jar + Vector3.UP * 0.24, 0.085, 0.085, 0.12, Color("996442"), 12)
		Props.cylinder(parent, jar + Vector3.UP * 0.30, 0.062, 0.062, 0.01, Color("40342a"), 12)

static func _firewood(stage, parent: Node3D, at: Vector3) -> void:
	for row in range(3):
		for i in range(3 - row):
			var center = ground(stage, parent, at + Vector3(i * 0.20 + row * 0.10, 0, 0), 0.09 + row * 0.17)
			var log_piece = Props.cylinder(parent, center, 0.09, 0.075, 1.1, WOOD, 7)
			log_piece.rotation.x = PI * 0.5

static func _hitching_rail(stage, parent: Node3D, at: Vector3) -> void:
	var left = ground(stage, parent, at + Vector3(-2.1, 0, 0))
	var right = ground(stage, parent, at + Vector3(2.1, 0, 0))
	pole(parent, left, left + Vector3.UP * 1.40, 0.075, WOOD)
	pole(parent, right, right + Vector3.UP * 1.40, 0.075, WOOD)
	pole(parent, left + Vector3.UP * 1.25, right + Vector3.UP * 1.25, 0.065, WOOD)
