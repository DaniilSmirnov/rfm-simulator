extends HBoxContainer
# Basic controls work in the mini engine where OptionButton / PopupMenu are absent.
signal item_selected(index: int)
var items: Array[String] = []
var selected = 0
var caption: Label
var item_count: int:
	get:
		return items.size()
func _init() -> void:
	add_theme_constant_override("separation", 8)
	var previous = Button.new()
	previous.text = "‹"
	previous.custom_minimum_size = Vector2(42, 40)
	previous.add_theme_font_size_override("font_size", 24)
	previous.tooltip_text = "Предыдущий вариант"
	add_child(previous)
	caption = Label.new()
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.clip_text = true
	caption.add_theme_font_size_override("font_size", 18)
	add_child(caption)
	var next = Button.new()
	next.text = "›"
	next.custom_minimum_size = Vector2(42, 40)
	next.add_theme_font_size_override("font_size", 24)
	next.tooltip_text = "Следующий вариант"
	add_child(next)
	previous.pressed.connect(func(): cycle(-1))
	next.pressed.connect(func(): cycle(1))
func add_item(title: String) -> void:
	items.append(title)
	select(selected)
func select(index: int) -> void:
	if items.is_empty():
		return
	selected = posmod(index, items.size())
	caption.text = items[selected]
	caption.tooltip_text = caption.text
func cycle(direction: int) -> void:
	if items.is_empty():
		return
	select(selected + direction)
	item_selected.emit(selected)
