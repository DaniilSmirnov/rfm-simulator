extends RefCounted
# A handheld walkie-talkie: the room radio a fan holds to the mouth while on
# air, and the one a marshal wears on the chest. Built from a few boxes and
# cylinders like the other props; one shared mesh/material set for every copy.
# The origin is the grip: the body rises along +Y to the antenna, the speaker
# faces +Z. Sizes are real ones scaled up like the other hand props (a beer
# can is 23 cm tall here) so it reads next to the big cartoon heads.

const BODY = Vector3(0.058, 0.118, 0.032)
const SCALE = 1.8
const DARK = Color("2b3134")
const TRIM = Color("e8771f")
const RUBBER = Color("151819")
const GRILLE = Color("4a5357")
const BUTTON = Color("e0a72e")
const LED_OFF = Color("4b1d1a")
const LED_ON = Color("ff3a26")

static var _meshes: Dictionary = {}
static var _materials: Dictionary = {}

static func _material(color: Color, glow: bool = false) -> StandardMaterial3D:
	var key = [color, glow]
	if not _materials.has(key):
		var m = StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.7
		if glow:
			m.emission_enabled = true
			m.emission = color
			m.emission_energy_multiplier = 2.5
		_materials[key] = m
	return _materials[key]

static func _part(parent: Node3D, name: String, mesh_key: String, make: Callable, pos: Vector3, color: Color) -> MeshInstance3D:
	if not _meshes.has(mesh_key):
		_meshes[mesh_key] = make.call()
	var node = MeshInstance3D.new()
	node.name = name
	node.mesh = _meshes[mesh_key]
	node.material_override = _material(color)
	node.position = pos
	parent.add_child(node)
	return node

static func _box(size: Vector3) -> Callable:
	return func():
		var mesh = BoxMesh.new()
		mesh.size = size
		return mesh

static func _rod(radius: float, height: float) -> Callable:
	return func():
		var mesh = CylinderMesh.new()
		mesh.top_radius = radius * 0.8
		mesh.bottom_radius = radius
		mesh.height = height
		mesh.radial_segments = 8
		return mesh

static func create() -> Node3D:
	var radio = Node3D.new()
	radio.name = "Radio"
	radio.scale = Vector3.ONE * SCALE
	var half = BODY.y * 0.5
	_part(radio, "Body", "body", _box(BODY), Vector3(0, half, 0), DARK)
	# Orange bumpers on the sides and a band under the top: visible against
	# dark clothes and forest.
	for side in [-1.0, 1.0]:
		_part(radio, "Bumper%d" % int(side), "bumper", _box(Vector3(0.006, BODY.y * 0.9, BODY.z + 0.004)), Vector3(side * (BODY.x * 0.5 + 0.002), half, 0), TRIM)
	_part(radio, "TopBand", "band", _box(Vector3(BODY.x + 0.004, 0.014, BODY.z + 0.004)), Vector3(0, BODY.y - 0.012, 0), TRIM)
	# Rubber antenna on the left shoulder of the body, channel knob on the right.
	_part(radio, "Antenna", "antenna", _rod(0.0065, 0.085), Vector3(-0.016, BODY.y + 0.0425, -0.004), RUBBER)
	_part(radio, "Knob", "knob", _rod(0.007, 0.014), Vector3(0.015, BODY.y + 0.007, -0.004), RUBBER)
	# Speaker slots on the front face, push-to-talk bar on the side.
	for i in range(4):
		_part(radio, "Grille%d" % i, "grille", _box(Vector3(0.038, 0.005, 0.004)), Vector3(0, half + 0.022 - i * 0.011, BODY.z * 0.5 + 0.001), GRILLE)
	_part(radio, "TalkButton", "button", _box(Vector3(0.008, 0.032, 0.016)), Vector3(BODY.x * 0.5 + 0.007, half + 0.012, 0), BUTTON)
	var led = _part(radio, "Led", "led", _box(Vector3(0.008, 0.005, 0.008)), Vector3(0.002, BODY.y + 0.0025, 0.009), LED_OFF)
	led.set_meta("on", false)
	return radio

# In the right hand, upright along the forearm so it reaches the mouth with the hand.
static func attach_to_hand(forearm: Node3D, grip: Vector3) -> Node3D:
	var radio = create()
	forearm.add_child(radio)
	# The forearm points down its -Y axis to the hand: turn the antenna that way.
	radio.set_meta("grip", grip + Vector3(0, -0.02, -0.025))
	radio.position = radio.get_meta("grip")
	radio.rotation = Vector3(PI, 0, 0)
	radio.hide()
	return radio

# Raised to the mouth the radio stands upright, antenna up and speaker turned
# to the face, whatever the forearm's angle; `weight` blends from lying along
# the forearm (0) to upright (1). The hand holds it around the middle.
static func hold_upright(radio: Node3D, avatar: Node3D, weight: float) -> void:
	var forearm: Node3D = radio.get_parent()
	var along: Quaternion = (forearm.global_basis * Basis.from_euler(Vector3(PI, 0, 0))).get_rotation_quaternion()
	var upright: Quaternion = (avatar.global_basis * Basis(Vector3.UP, -PI / 2)).get_rotation_quaternion()
	var rotation = along.slerp(upright, clampf(weight, 0.0, 1.0)).normalized()
	var grip: Vector3 = forearm.global_transform * radio.get_meta("grip")
	var up = Basis(rotation) * Vector3.UP
	radio.global_transform = Transform3D(Basis(rotation).scaled(Vector3.ONE * SCALE), grip - up * BODY.y * SCALE * 0.45)

# Clipped to a vest at chest height (marshals): always visible, always quiet.
static func clip_to_chest(avatar: Node3D, pos: Vector3) -> Node3D:
	var radio = create()
	avatar.add_child(radio)
	radio.position = pos
	radio.rotation = Vector3(0, PI, 0.12)
	return radio

static func set_on_air(radio: Node3D, on: bool) -> void:
	var led: MeshInstance3D = radio.get_node("Led")
	if bool(led.get_meta("on")) == on:
		return
	led.set_meta("on", on)
	led.material_override = _material(LED_ON, true) if on else _material(LED_OFF)

static func on_air(radio: Node3D) -> bool:
	return bool(radio.get_node("Led").get_meta("on"))
