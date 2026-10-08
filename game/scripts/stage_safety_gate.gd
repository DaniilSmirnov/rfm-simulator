extends CanvasLayer
## Full-screen stage-entry gate based on the safety memo from rfm-pwa.
## Deliberately native Godot UI so desktop, mobile web and VK share one flow.

signal accepted

var panel: Control
var scroll: ScrollContainer
var accept_button: Button
var user_scrolled = false

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
	var outer = MarginContainer.new()
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
	var margins = MarginContainer.new()
	margins.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margins.add_theme_constant_override("margin_left", 24)
	margins.add_theme_constant_override("margin_right", 24)
	margins.add_theme_constant_override("margin_top", 24)
	margins.add_theme_constant_override("margin_bottom", 24)
	scroll.add_child(margins)
	var text_column = VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.add_theme_constant_override("separation", 16)
	margins.add_child(text_column)
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
	layout.add_child(accept_button)
	scroll.resized.connect(_update_accept)
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
	var reached_end = user_scrolled and bar.max_value > bar.page and bar.value + bar.page >= bar.max_value - 8.0
	accept_button.disabled = not reached_end
	accept_button.text = "ПРОЧИТАЛ(А), ВОЙТИ НА СУ" if reached_end else "ПРОКРУТИ ПАМЯТКУ ДО КОНЦА"

func _accept() -> void:
	if accept_button.disabled:
		return
	accepted.emit()
	queue_free()
