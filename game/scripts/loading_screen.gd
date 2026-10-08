extends CanvasLayer
var game: Node3D
var overlay: ColorRect
var caption: Label
var bar: ProgressBar
var history: Array[String] = []
func _ready() -> void:
	layer = 20
	overlay = ColorRect.new()
	overlay.color = Color("17241bf5")
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var box = VBoxContainer.new()
	box.custom_minimum_size = Vector2(320, 0)
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)
	var title = game._label(box, "ГОТОВИМ ВЫЕЗД", 26, Color("ffe4a5"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption = game._label(box, "Подготовка", 20)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar = ProgressBar.new()
	bar.custom_minimum_size.y = 24
	box.add_child(bar)
	overlay.hide()
func show_loading() -> void:
	history.clear()
	bar.value = 0
	overlay.show()
func hide_loading() -> void:
	overlay.hide()
func stage_progress(name: String, percent: int) -> void:
	caption.text = name
	bar.value = percent
	history.append(name)
	# Two frames let layout and drawing complete before the next CPU-heavy stage.
	await get_tree().process_frame
	await get_tree().process_frame
