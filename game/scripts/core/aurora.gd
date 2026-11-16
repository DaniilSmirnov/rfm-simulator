extends Node3D
# Northern lights over stages marked "aurora" in data/stages.json (Поречье):
# on a clear night they come at a random moment, glow for a few minutes,
# fade out and may return later. Three curtains of light hang far away in the
# northern sky (-Z) and follow the camera like the sky does; the folds, rays
# and colours move in shaders/aurora.gdshader. While they glow the snow takes a
# faint green tint from them through the ambient light.
# In a room the host decides when they show: sky_weather.gd sends "aurora" in
# the sky section and guests fade them in and out on their own.
const StageRegistry = preload("res://scripts/stages/stage_registry.gd")
const SHADER = preload("res://shaders/aurora.gdshader")
# Curtains in metres around the camera: distance north, half length, how far
# the line wanders north and south, lower edge and top above the camera. They
# stay inside the play camera's far plane (draw_distance.gd, 1100 m).
const CURTAINS = [
	{"z": -260.0, "half": 600.0, "wander": 90.0, "low": 140.0, "high": 620.0, "seed": 1.3},
	{"z": -430.0, "half": 640.0, "wander": 110.0, "low": 130.0, "high": 520.0, "seed": 2.9},
	{"z": -570.0, "half": 560.0, "wander": 70.0, "low": 120.0, "high": 450.0, "seed": 4.7},
]
const COLUMNS = 160
# Seconds: before the first display, between displays, how long one lasts,
# fading in and out.
const FIRST_WAIT = Vector2(20.0, 110.0)
const PAUSE = Vector2(90.0, 240.0)
const SHOW = Vector2(120.0, 300.0)
const FADE_IN = 25.0
const FADE_OUT = 15.0
# Bursts while they glow: calm spells, short bright surges.
const CALM = Vector2(20.0, 60.0)
const BURST = Vector2(6.0, 14.0)
# The green the snow catches at full display (share of the ambient colour).
const TINT = Color("63e6a4")
const TINT_SHARE = 0.2

var game: Node3D
var material: ShaderMaterial
var curtains: MeshInstance3D
# Night, a clear sky and a stage with northern lights.
var possible = false
# Whether they are showing now (fading in) or not (fading out), and how bright.
var shown = false
var level = 0.0
var surge = 0.0
var _surging = false
var _clock = 0.0
var _surge_clock = 0.0
var _environment: Environment
var _ambient = Color.WHITE
var rng = RandomNumberGenerator.new()

static func on_stage(variant: int) -> bool:
	return StageRegistry.value(variant, "aurora") == true

func setup(owner: Node3D) -> void:
	game = owner
	name = "Aurora"
	rng.randomize()
	material = ShaderMaterial.new()
	material.shader = SHADER
	curtains = MeshInstance3D.new()
	curtains.name = "Curtains"
	curtains.mesh = curtain_mesh()
	curtains.material_override = material
	curtains.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	curtains.custom_aabb = AABB(Vector3(-900, 0, -900), Vector3(1800, 800, 1000))
	add_child(curtains)
	visible = false

# Called by sky_weather.gd whenever the sky is rebuilt: a new environment, and
# maybe a new stage or new conditions.
func configure(time: String, weather: String, variant: int, environment: Environment) -> void:
	_environment = environment
	_ambient = environment.ambient_light_color
	var now = time == "night" and weather == "sun" and on_stage(variant)
	if now != possible:
		possible = now
		shown = false
		level = 0.0
		_clock = _between(FIRST_WAIT)
	_apply()

# A guest follows the host's sky.
func set_shown(on: bool) -> void:
	shown = on and possible

func _guest() -> bool:
	return game.room != null and game.room.is_guest()

func _process(delta: float) -> void:
	if game == null or not possible:
		return
	if not _guest():
		_clock -= delta
		if _clock <= 0.0:
			shown = not shown
			_clock = _between(SHOW if shown else PAUSE)
	level = move_toward(level, 1.0 if shown else 0.0, delta / (FADE_IN if shown else FADE_OUT))
	_surge_clock -= delta
	if _surge_clock <= 0.0:
		_surging = not _surging and shown
		_surge_clock = _between(BURST if _surging else CALM)
	surge = move_toward(surge, 1.0 if _surging else 0.0, delta / 4.0)
	_apply()

func _apply() -> void:
	var lit = possible and level > 0.001
	visible = lit
	material.set_shader_parameter("level", level if possible else 0.0)
	material.set_shader_parameter("surge", surge)
	var camera: Camera3D = game.camera if game != null else null
	if lit and camera != null and camera.is_inside_tree():
		global_position = camera.global_position
	if _environment != null:
		var share = TINT_SHARE * (level if possible else 0.0) * (0.75 + 0.25 * surge)
		_environment.ambient_light_color = _ambient.lerp(TINT, share)

func _between(span: Vector2) -> float:
	return rng.randf_range(span.x, span.y)

# Every curtain as a ribbon of columns, a bottom and a top vertex each: UV.x
# runs along the curtain, UV.y up it; UV2 holds its length and seed; the
# normal points sideways, where the shader folds it.
static func curtain_mesh() -> ArrayMesh:
	var points = PackedVector3Array()
	var normals = PackedVector3Array()
	var uvs = PackedVector2Array()
	var uv2s = PackedVector2Array()
	var indices = PackedInt32Array()
	for spec in CURTAINS:
		var first = points.size()
		var length = 2.0 * float(spec.half)
		for i in range(COLUMNS + 1):
			var s = float(i) / COLUMNS
			var x = -float(spec.half) + length * s
			var phase = x * 0.0035 + float(spec.seed)
			var z = float(spec.z) + float(spec.wander) * sin(phase)
			var along = Vector3(1.0, 0.0, float(spec.wander) * 0.0035 * cos(phase)).normalized()
			var side = Vector3(-along.z, 0.0, along.x)
			for row in [0, 1]:
				points.append(Vector3(x, float(spec.high if row == 1 else spec.low), z))
				normals.append(side)
				uvs.append(Vector2(s, row))
				uv2s.append(Vector2(length, float(spec.seed)))
			if i > 0:
				var a = first + (i - 1) * 2
				indices.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
