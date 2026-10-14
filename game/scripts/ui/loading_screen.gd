extends CanvasLayer
# Full-screen progress while the stage is built on entry.
const UiKit = preload("res://scripts/ui/ui_kit.gd")
var game: Node3D
var overlay: ColorRect
var caption: Label
var bar: ProgressBar
var history: Array[String] = []
func _ready() -> void:
	layer = 20
	overlay = ColorRect.new()
	overlay.color = Color("131d17")
	overlay.theme = UiKit.theme()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var box = UiKit.vbox(center, 18)
	box.custom_minimum_size = Vector2(360, 0)
	var brand = UiKit.brand(box, 52)
	brand.alignment = BoxContainer.ALIGNMENT_CENTER
	var title = UiKit.label(box, "ГОТОВИМ ВЫЕЗД", "heading")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar = ProgressBar.new()
	bar.custom_minimum_size.y = 10
	bar.show_percentage = false
	box.add_child(bar)
	caption = UiKit.label(box, "Подготовка", "muted")
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
