extends HBoxContainer
# Basic controls work in the mini engine where OptionButton / PopupMenu are absent.
signal item_selected(index: int)
# Long names shrink to fit between the arrows, down to MIN_FONT_SIZE; past
# that they wrap onto a second line instead of being cut off.
const FONT_SIZE = 18
const MIN_FONT_SIZE = 15
var items: Array[String] = []
var selected = 0
# Items the arrows step over (still selectable by index).
var skipped: Dictionary = {}
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
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.clip_text = true
	caption.add_theme_font_size_override("font_size", FONT_SIZE)
	caption.resized.connect(fit)
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
	fit()
func cycle(direction: int) -> void:
	if items.is_empty():
		return
	var index = selected
	for step in range(items.size()):
		index = posmod(index + direction, items.size())
		if not skipped.has(index):
			break
	select(index)
	item_selected.emit(selected)

func set_skipped(index: int, value: bool) -> void:
	if value:
		skipped[index] = true
	else:
		skipped.erase(index)
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and caption != null:
		fit.call_deferred()
func fit() -> void:
	var width = caption.size.x
	if width <= 0.0:
		return
	var font = caption.get_theme_font("font")
	var text = caption.atr(caption.text)
	var size = FONT_SIZE
	while size > MIN_FONT_SIZE and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
		size -= 1
	caption.add_theme_font_size_override("font_size", size)
	var fits = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width
	caption.autowrap_mode = TextServer.AUTOWRAP_OFF if fits else TextServer.AUTOWRAP_WORD_SMART
	# A clipped label hides a line that does not fit its height: two lines
	# grow the row instead, set close together.
	caption.clip_text = fits
	caption.add_theme_constant_override("line_spacing", 0 if fits else -4)
