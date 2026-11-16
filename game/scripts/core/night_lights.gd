extends RefCounted
# Light sources at night: campfires, lit grills and the roof beacons of the
# police, ambulance and course cars light the ground around them.
# Models mark the node a light hangs on (mark()); at night sky_weather.gd lights
# only the ones nearest the camera, within a small budget per kind: every
# light costs another pass over the meshes it reaches in the Compatibility
# renderer. A light is a child of its node, so it hides with it: a cold grill
# (GrillFire hidden) is dark, a flashing beacon flashes the light too.
const GROUP = &"night_light"
# Colour, energy, range (m), height above the node (m), flicker, budget group.
const KINDS = {
	"fire": {"color": Color("ff9a45"), "energy": 2.4, "range": 11.0, "height": 0.8, "flicker": true, "budget": "fire"},
	"grill": {"color": Color("ff7c32"), "energy": 1.3, "range": 6.0, "height": 1.1, "flicker": true, "budget": "fire"},
	"beacon_blue": {"color": Color("3f7dff"), "energy": 3.0, "range": 13.0, "height": 0.25, "flicker": false, "budget": "beacon"},
	"beacon_red": {"color": Color("ff3b30"), "energy": 3.0, "range": 13.0, "height": 0.25, "flicker": false, "budget": "beacon"},
	"beacon_amber": {"color": Color("ffae35"), "energy": 1.6, "range": 9.0, "height": 0.25, "flicker": false, "budget": "beacon"},
	# A room lamp behind window glass (village_rooms.gd): lights the room and
	# spills out through the windows onto the street.
	"lamp": {"color": Color("ffc879"), "energy": 1.8, "range": 8.0, "height": 0.0, "flicker": false, "budget": "home"},
}
const BUDGET = {"fire": 6, "beacon": 4, "home": 3}
# Meshes shown only at night (a lamp shade's glow), hidden by day.
const GLOW = &"night_glow"
const PICK_SECONDS = 0.3
const LIGHT_NAME = "NightLight"

var _clock = 0.0
var _time = 0.0
var _lit: Array[OmniLight3D] = []
var _glow_state = ""
static var _glow_material: StandardMaterial3D

static func mark(node: Node, kind: String) -> void:
	# Persistent groups survive baked scenes (the village is a PackedScene).
	node.add_to_group(GROUP, true)
	node.set_meta("night_light", kind)

# A mesh that glows by night only (hidden until update() sees the night).
static func glow(node: Node3D) -> void:
	node.add_to_group(GLOW, true)
	node.hide()

static func glow_material() -> StandardMaterial3D:
	if _glow_material == null:
		_glow_material = StandardMaterial3D.new()
		_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow_material.albedo_color = Color("ffdf9e")
	return _glow_material

# Called every frame by sky_weather.gd; `at` is the camera position.
func update(tree: SceneTree, night: bool, at: Vector3, delta: float) -> void:
	_time += delta
	var glow_state = "%s:%d" % [night, tree.get_node_count_in_group(GLOW)]
	if glow_state != _glow_state:
		_glow_state = glow_state
		for node in tree.get_nodes_in_group(GLOW):
			node.visible = night
	if not night:
		if not _lit.is_empty():
			clear()
		return
	_clock -= delta
	if _clock <= 0.0:
		_clock = PICK_SECONDS
		_pick(tree, at)
	for light in _lit:
		if is_instance_valid(light) and light.has_meta("flicker"):
			var seed = float(light.get_meta("flicker"))
			light.light_energy = float(light.get_meta("energy")) * (0.82 + 0.1 * sin(_time * 9.0 + seed) + 0.08 * sin(_time * 23.0 + seed * 2.0))

func _pick(tree: SceneTree, at: Vector3) -> void:
	var by_budget: Dictionary = {}
	for node in tree.get_nodes_in_group(GROUP):
		if not node is Node3D or not node.is_inside_tree() or not KINDS.has(str(node.get_meta("night_light", ""))):
			continue
		var spec: Dictionary = KINDS[node.get_meta("night_light")]
		var distance = node.global_position.distance_squared_to(at)
		if distance > 120.0 * 120.0:
			continue
		by_budget.get_or_add(spec.budget, []).append([distance, node])
	var keep: Dictionary = {}
	for budget in by_budget:
		var list: Array = by_budget[budget]
		list.sort_custom(func(a, b): return a[0] < b[0])
		for i in range(mini(list.size(), BUDGET[budget])):
			keep[list[i][1]] = true
	var lit: Array[OmniLight3D] = []
	for light in _lit:
		if is_instance_valid(light) and keep.has(light.get_parent()):
			lit.append(light)
		elif is_instance_valid(light):
			light.queue_free()
	for node in keep:
		if node.get_node_or_null(LIGHT_NAME) == null:
			lit.append(_light(node))
	_lit = lit

func _light(node: Node3D) -> OmniLight3D:
	var spec: Dictionary = KINDS[node.get_meta("night_light")]
	var light = OmniLight3D.new()
	light.name = LIGHT_NAME
	light.position = Vector3(0, spec.height, 0)
	light.light_color = spec.color
	light.light_energy = spec.energy
	light.omni_range = spec.range
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	light.set_meta("energy", spec.energy)
	if spec.flicker:
		light.set_meta("flicker", float(node.get_instance_id() % 97))
	node.add_child(light)
	return light

func clear() -> void:
	for light in _lit:
		if is_instance_valid(light):
			light.queue_free()
	_lit.clear()
