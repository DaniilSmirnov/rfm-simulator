extends RefCounted
# The drunk view from the third can on, in the manner of GTA IV: the head
# reels in a slow, heavy figure-eight (roll, yaw and pitch on related periods),
# lurches from side to side, the lens breathes, and the picture doubles into a
# ghost image that swims around the real one, darker at the edges.
# game.drunk_strength (0..1: +0.45 a can from the third, fading out over
# DRUNK_FADE_SECONDS, sauna_steam.gd sweats it out faster) scales all of it;
# game.drunk_phase (wraps at TAU) drives it, so only whole multiples of it are
# used and nothing jumps at the wrap.
const ROLL = 9.0 # degrees at full strength
const YAW = 5.0
const PITCH = 2.5
const LURCH = 0.14 # metres, on foot
const FOV = 6.0 # degrees, on foot
const GHOST = 0.02 # screen fraction between the picture and its double
const GHOST_MIX = 0.45
const SHADER = """shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform vec2 ghost = vec2(0.0);
uniform float amount = 0.0;
void fragment() {
	vec3 base = texture(screen_texture, SCREEN_UV).rgb;
	vec3 double_image = (texture(screen_texture, SCREEN_UV + ghost).rgb + texture(screen_texture, SCREEN_UV - ghost * 0.5).rgb) * 0.5;
	vec3 color = mix(base, double_image, amount);
	color *= 1.0 - smoothstep(0.35, 0.85, distance(SCREEN_UV, vec2(0.5))) * amount;
	COLOR = vec4(color, 1.0);
}"""

var overlay: ColorRect

# Adds the reel to the view update_camera() just set up.
func apply(game, collapse: float) -> void:
	var s: float = game.drunk_strength
	var p: float = game.drunk_phase
	var camera: Camera3D = game.camera
	camera.rotation.z += sin(p) * deg_to_rad(ROLL) * s + PI / 2 * collapse
	camera.rotation.y += sin(p + 1.2) * deg_to_rad(YAW) * s
	camera.rotation.x += sin(p * 2.0) * deg_to_rad(PITCH) * s
	# The chase camera eases from where it was last frame: only the fan's own
	# eyes lurch and breathe, or the car view would drift away for good.
	if not game.in_car and s > 0.0:
		camera.position += camera.global_basis.x * sin(p + 0.4) * LURCH * s
		camera.fov += sin(p * 3.0) * FOV * s

# The double image, below the HUD; shown only while the beer is felt.
func update(game) -> void:
	var s: float = game.drunk_strength
	if overlay == null:
		if s <= 0.0:
			return
		_setup(game)
	overlay.visible = s > 0.01 and not game.capture_mode
	if overlay.visible:
		var p: float = game.drunk_phase
		overlay.material.set_shader_parameter("ghost", Vector2(cos(p), sin(p * 2.0) * 0.5) * GHOST * s)
		overlay.material.set_shader_parameter("amount", GHOST_MIX * s)

func _setup(game) -> void:
	var layer = CanvasLayer.new()
	layer.layer = 0
	game.add_child(layer)
	overlay = ColorRect.new()
	overlay.name = "DrunkDoubleVision"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader = Shader.new()
	shader.code = SHADER
	var mat = ShaderMaterial.new()
	mat.shader = shader
	overlay.material = mat
	layer.add_child(overlay)
