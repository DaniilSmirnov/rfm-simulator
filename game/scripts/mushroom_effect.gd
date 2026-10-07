extends RefCounted
# A local screen effect below the HUD. World snapshots trigger it only for
# the affected player, and repeated snapshots never extend its duration.
const DURATION = 10.0
var remaining = 0.0
var serial = 0
var overlay: ColorRect

func setup(game: Node) -> void:
	var layer = CanvasLayer.new()
	layer.layer = 0
	game.add_child(layer)
	overlay = ColorRect.new()
	overlay.name = "MushroomColorInversion"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader = Shader.new()
	shader.code = "shader_type canvas_item; uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest; void fragment() { vec4 pixel = texture(screen_texture, SCREEN_UV); COLOR = vec4(vec3(1.0) - pixel.rgb, 1.0); }"
	var mat = ShaderMaterial.new()
	mat.shader = shader
	overlay.material = mat
	layer.add_child(overlay)
	overlay.hide()

func trigger(event_serial: int, seconds: float = DURATION) -> void:
	if event_serial <= serial:
		return
	serial = event_serial
	remaining = clampf(seconds, 0, DURATION)
	if overlay != null:
		overlay.visible = remaining > 0

func update(delta: float) -> void:
	remaining = maxf(0, remaining - delta)
	if overlay != null:
		overlay.visible = remaining > 0

func clear() -> void:
	remaining = 0
	if overlay != null:
		overlay.hide()
