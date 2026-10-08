extends CanvasLayer
## Full-screen stage-entry gate based on the safety memo from rfm-pwa.
## Deliberately native Godot UI so desktop, mobile web and VK share one flow.

signal accepted

var panel: Control
var scroll: ScrollContainer
var accept_button: Button
var previous_mouse_mode = Input.MOUSE_MODE_VISIBLE

const RULES = [
	"Не находись в зоне вылета.",
	"Всегда имей путь отхода.",
	"Слушай маршалов.",
	"Не выходи на трассу во время гонки.",
	"Дождись автомобиля безопасности с зелёной мигалкой.",
]
const DANGERS = [
	"Внешний радиус поворота — машина может не вписаться и вылететь наружу.",
	"Апекс поворота — машина проходит здесь на скорости.",
	"Выход из поворота — автомобиль может потерять контроль.",
	"Слепой поворот или перелом — экипаж может появиться внезапно.",
	"Трамплин или гребёнка — автомобиль может приземлиться непредсказуемо.",
]
const STAGE_GUIDES = [
	"ЗАЕЗД НА УЧАСТОК\nЛучше заезжать со стороны старта. Со стороны финиша — минимум за 1,5 часа до перекрытия. Двигайся по ходу гонки.",
	"КОГДА БЫТЬ НА ТОЧКЕ\nПриезжай минимум за 1 час до перекрытия дороги. После перекрытия движение ограничено.",
	"КАК ВЫЕЗЖАТЬ\nВыезд возможен через 15 минут после «зелёнки». Не мешай «метле» и экстренным службам.",
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
	outer.add_theme_constant_override("margin_left", 16)
	outer.add_theme_constant_override("margin_right", 16)
	outer.add_theme_constant_override("margin_top", 16)
	outer.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(outer)
	var layout = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	outer.add_child(layout)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = false
	scroll.get_v_scroll_bar().value_changed.connect(_update_accept)
	layout.add_child(scroll)
	var centre = CenterContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(centre)
	var text_column = VBoxContainer.new()
	text_column.custom_minimum_size.x = 300
	text_column.add_theme_constant_override("separation", 14)
	centre.add_child(text_column)
	_add_text(text_column, "ЗРИТЕЛЬ — ЧАСТЬ РАЛЛИ", 15, Color("#ff8b52"))
	_add_text(text_column, "БЕЗОПАСНОСТЬ", 32, Color.WHITE)
	_add_text(text_column, "Ралли — это скорость и риск. Машина может выйти за пределы трассы. Выбирай безопасные точки и следуй указаниям маршалов.", 18)
	_add_text(text_column, "ГЛАВНОЕ", 25, Color("#ffaf6c"))
	for rule in RULES:
		_add_text(text_column, "• " + rule, 18)
	_add_text(text_column, "АВТОМОБИЛИ БЕЗОПАСНОСТИ", 24, Color("#ffaf6c"))
	_add_text(text_column, "Перед первым боевым экипажем проходят: SAFETY (S1) — 40 минут, 00000 — 25, 0000 — 20, 000 — 15, 00 — 10 и 0 — 5 минут.", 18)
	_add_text(text_column, "60 МИНУТ ДО СТАРТА — передвижение по спецучастку запрещено.", 19, Color("#ffad8b"))
	_add_text(text_column, "ОПАСНЫЕ ЗОНЫ", 24, Color("#ffaf6c"))
	for i in range(DANGERS.size()):
		_add_text(text_column, "%d. %s" % [i + 1, DANGERS[i]], 18)
	_add_text(text_column, "Никогда не стой в зоне вылета и за ограждениями. Выбирай место с хорошим обзором и запасом до дороги.", 18)
	_add_text(text_column, "КАК ВЕСТИ СЕБЯ НА ЭТАПЕ", 24, Color("#ffaf6c"))
	for guide in STAGE_GUIDES:
		_add_text(text_column, guide, 18)
	_add_text(text_column, "«Метла» проходит трассу после экипажей. Дождись разрешения маршалов перед выходом на дорогу.", 18)
	_add_text(text_column, "БУДЬ ЗРИТЕЛЕМ, А НЕ УЧАСТНИКОМ АВАРИИ.", 19, Color("#ffad8b"))
	accept_button = Button.new()
	accept_button.text = "ПРОКРУТИ ПАМЯТКУ ДО КОНЦА"
	accept_button.disabled = true
	accept_button.custom_minimum_size.y = 54
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

func _update_accept(_value: float = 0.0) -> void:
	if scroll == null or accept_button == null:
		return
	var bar = scroll.get_v_scroll_bar()
	var reached_end = bar.value + bar.page >= bar.max_value - 8.0
	accept_button.disabled = not reached_end
	accept_button.text = "ПРОЧИТАЛ(А), ВОЙТИ НА СУ" if reached_end else "ПРОКРУТИ ПАМЯТКУ ДО КОНЦА"

func _accept() -> void:
	if accept_button.disabled:
		return
	accepted.emit()
	queue_free()
