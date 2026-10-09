extends CanvasLayer
## Full-screen stage-entry gate based on the safety memo from rfm-pwa.
## Deliberately native Godot UI so desktop, mobile web and VK share one flow.

signal accepted

var panel: Control
var scroll: ScrollContainer
var accept_button: Button
var user_scrolled = false
var outer: MarginContainer
var content_margins: MarginContainer
var button_margins: MarginContainer
var safe_insets = Vector4.ZERO

const MAX_READING_WIDTH = 760.0
const MIN_SIDE_PADDING = 20.0

const WHERE_TO_STAND = [
	"Стой в специально отведённой зрительской зоне, за ограждениями и на безопасном расстоянии от дороги.",
	"Выбирай место с хорошим обзором и свободным путём отхода.",
	"Избегай внешнего радиуса и апекса поворота, выхода из поворота, слепых перегибов и зон приземления после трамплинов.",
	"Даже вдали от дороги держись выше возможной траектории вылета автомобиля и не стой там, куда он может скатиться.",
]
const ALLOWED = [
	"Наблюдай за гонкой только из безопасной зрительской зоны.",
	"Слушай маршалов и выполняй их указания.",
	"Держи проходы и пути эвакуации свободными.",
	"Помогай другим зрителям отойти от опасного места, не подвергая себя риску.",
]
const FORBIDDEN = [
	"Не выходи на трассу, пока её не откроют организаторы и маршалы.",
	"Не стой в зоне вылета, перед автомобилем или за внешней стороной поворота.",
	"Не пересекай ограждения и не заходи в закрытые зоны.",
	"Не подходи к остановившемуся или аварийному автомобилю без разрешения маршалов.",
	"Не препятствуй работе маршалов, спасателей и экипажей.",
]

func _ready() -> void:
	layer = 100
	panel = Control.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	var background = ColorRect.new()
	background.color = Color("#14212a")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_child(background)
	outer = MarginContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("margin_left", 0)
	outer.add_theme_constant_override("margin_right", 0)
	outer.add_theme_constant_override("margin_top", 0)
	outer.add_theme_constant_override("margin_bottom", 0)
	panel.add_child(outer)
	var layout = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 0)
	outer.add_child(layout)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = false
	scroll.get_v_scroll_bar().value_changed.connect(_on_scroll_changed)
	layout.add_child(scroll)
	content_margins = MarginContainer.new()
	content_margins.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_margins.add_theme_constant_override("margin_left", 24)
	content_margins.add_theme_constant_override("margin_right", 24)
	content_margins.add_theme_constant_override("margin_top", 24)
	content_margins.add_theme_constant_override("margin_bottom", 24)
	scroll.add_child(content_margins)
	var text_column = VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.add_theme_constant_override("separation", 16)
	content_margins.add_child(text_column)
	_add_text(text_column, "ЗРИТЕЛЬ — ЧАСТЬ РАЛЛИ", 15, Color("#ff8b52"))
	_add_text(text_column, "БЕЗОПАСНОСТЬ НА СУ", 32, Color.WHITE)
	_add_text(text_column, "Выбирай безопасное место, не мешай проведению гонки и выполняй указания маршалов.", 19)
	_add_text(text_column, "ГДЕ СТОЯТЬ", 26, Color("#ffaf6c"))
	for rule in WHERE_TO_STAND:
		_add_text(text_column, "• " + rule, 19)
	_add_text(text_column, "ЧТО МОЖНО ДЕЛАТЬ", 26, Color("#ffaf6c"))
	for rule in ALLOWED:
		_add_text(text_column, "• " + rule, 19)
	_add_text(text_column, "ЧТО НЕЛЬЗЯ ДЕЛАТЬ", 26, Color("#ffaf6c"))
	for rule in FORBIDDEN:
		_add_text(text_column, "• " + rule, 19)
	_add_text(text_column, "БУДЬ ЗРИТЕЛЕМ, А НЕ УЧАСТНИКОМ АВАРИИ.", 19, Color("#ffad8b"))
	accept_button = Button.new()
	accept_button.text = "ПРОКРУТИ ПАМЯТКУ ДО КОНЦА"
	accept_button.disabled = true
	accept_button.custom_minimum_size.y = 64
	accept_button.pressed.connect(_accept)
	button_margins = MarginContainer.new()
	layout.add_child(button_margins)
	button_margins.add_child(accept_button)
	panel.resized.connect(_update_layout)
	_update_layout()
	scroll.resized.connect(_update_accept)
	_update_accept()

# The mini engine has no JavaScript eval. The game's existing browser-local
# viewport transport supplies hardware/VK/visual viewport insets in UI units.
func set_safe_insets(value: Vector4) -> void:
	var next = Vector4(maxf(0, value.x), maxf(0, value.y), maxf(0, value.z), maxf(0, value.w))
	if next == safe_insets:
		return
	safe_insets = next
	_update_layout()

func _update_layout() -> void:
	if panel == null or outer == null or content_margins == null or button_margins == null:
		return
	var insets = safe_insets
	var content_width = maxf(1.0, panel.size.x - insets.x - insets.z)
	# Keep a readable, centered column on desktop and modest gutters on phones.
	var gutter = maxf(MIN_SIDE_PADDING, (content_width - MAX_READING_WIDTH) * 0.5)
	for item in [content_margins, button_margins]:
		item.add_theme_constant_override("margin_left", roundi(gutter))
		item.add_theme_constant_override("margin_right", roundi(gutter))
	content_margins.add_theme_constant_override("margin_top", 24)
	content_margins.add_theme_constant_override("margin_bottom", 24)
	outer.add_theme_constant_override("margin_left", roundi(insets.x))
	outer.add_theme_constant_override("margin_right", roundi(insets.z))
	outer.add_theme_constant_override("margin_top", roundi(insets.y))
	outer.add_theme_constant_override("margin_bottom", roundi(insets.w + 12))
	_update_accept()

func _add_text(parent: VBoxContainer, value: String, font_size: int, color: Color = Color("#f6ead1")) -> void:
	var label = Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)

func _on_scroll_changed(value: float) -> void:
	if value > 0.0:
		user_scrolled = true
	_update_accept()

func _update_accept() -> void:
	if scroll == null or accept_button == null:
		return
	var bar = scroll.get_v_scroll_bar()
	var fits = bar.page > 0.0 and bar.max_value <= bar.page
	var reached_end = fits or (user_scrolled and bar.value + bar.page >= bar.max_value - 8.0)
	accept_button.disabled = not reached_end
	accept_button.text = "ПРОЧИТАЛ(А), ВОЙТИ НА СУ" if reached_end else "ПРОКРУТИ ПАМЯТКУ ДО КОНЦА"

func _accept() -> void:
	if accept_button.disabled:
		return
	accepted.emit()
	queue_free()
