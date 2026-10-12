extends RefCounted
# «Как играть»: короткий раздел из четырёх вкладок (цель, управление, лагерь,
# ралли). Управление показывается для текущего устройства: клавиши на ПК,
# кнопки сенсорного экрана с их иконками на телефоне.
# В VK раздел один раз открывается перед памяткой безопасности при первом
# входе на СУ (open_first_time). Из паузы его открывает кнопка «Как играть».
const UiKit = preload("res://scripts/ui_kit.gd")
const SETTINGS_PATH = "user://how_to_play.cfg"
const TABS = ["Цель", "Управление", "Лагерь", "Ралли"]
const ICONS = "res://textures/ui/mobile/%s.svg"

signal finished

var game
var settings_path = SETTINGS_PATH
var root: Control
var panel: PanelContainer
var pages: Array[Control] = []
var tab_buttons: Array[Button] = []
var next_button: Button
var close_button: Button
var page = 0
var body: PanelContainer
# Pages are built for one input kind; touch can switch on after startup.
var built_touch = false
# First visit: «Далее» walks the tabs and the last one leads to the memo.
var first_time = false

func build(layer: Control) -> void:
	var modal = UiKit.modal(layer, "HowToPlay", 720)
	root = modal.root
	panel = modal.panel
	var content: VBoxContainer = modal.content
	var header = UiKit.hbox(content, 12)
	UiKit.expand(UiKit.label(header, "Как играть", "heading"))
	var tabs = UiKit.hbox(content, 6)
	tabs.name = "Tabs"
	for i in range(TABS.size()):
		var tab = UiKit.expand(UiKit.button(tabs, TABS[i], "toggle", 38))
		tab.add_theme_font_size_override("font_size", 15)
		tab.pressed.connect(show_page.bind(i))
		tab_buttons.append(tab)
	body = UiKit.card(content, UiKit.SURFACE_SUNKEN, Vector2(18, 14))
	body.name = "Body"
	_build_pages()
	var actions = UiKit.hbox(content, 10)
	actions.name = "Actions"
	close_button = UiKit.expand(UiKit.button(actions, "ЗАКРЫТЬ", "ghost", 46))
	close_button.name = "Close"
	close_button.pressed.connect(close)
	next_button = UiKit.expand(UiKit.button(actions, "ДАЛЕЕ", "primary", 46))
	next_button.name = "Next"
	next_button.pressed.connect(_next)
	show_page(0)

func _build_pages() -> void:
	for old in pages:
		body.remove_child(old)
		old.queue_free()
	pages.clear()
	built_touch = touch()
	for builder in [_goal, _controls, _camp, _rally]:
		var column = UiKit.vbox(body, 9)
		builder.call(column)
		pages.append(column)

func is_open() -> bool:
	return root != null and root.visible

func seen() -> bool:
	var config = ConfigFile.new()
	return config.load(settings_path) == OK and bool(config.get_value("how_to_play", "seen", false))

func mark_seen() -> void:
	var config = ConfigFile.new()
	config.set_value("how_to_play", "seen", true)
	if config.save(settings_path) != OK:
		push_warning("Не удалось сохранить, что раздел «Как играть» просмотрен")

# Before the safety memo on the first VK stage entry. Returns false when the
# section was already seen, so the caller goes straight to the memo.
func open_first_time() -> bool:
	if seen():
		return false
	first_time = true
	_open()
	return true

func open() -> void:
	first_time = false
	_open()

func _open() -> void:
	if built_touch != touch():
		_build_pages()
		body.custom_minimum_size.y = 0
	show_page(0)
	root.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_zero_approx(body.custom_minimum_size.y):
		_hold_height()

# The window keeps the height of its tallest tab, so switching tabs does not
# make it jump. Labels wrap only after layout, hence the measuring frames.
func _hold_height() -> void:
	root.modulate.a = 0.0
	var tallest = 0.0
	for i in range(pages.size()):
		for j in range(pages.size()):
			pages[j].visible = i == j
		await game.get_tree().process_frame
		tallest = maxf(tallest, body.get_combined_minimum_size().y)
	body.custom_minimum_size.y = tallest
	show_page(page)
	root.modulate.a = 1.0

func close() -> void:
	if not is_open():
		return
	root.hide()
	if first_time:
		first_time = false
		mark_seen()
		finished.emit()

func show_page(index: int) -> void:
	page = clampi(index, 0, pages.size() - 1)
	for i in range(pages.size()):
		pages[i].visible = i == page
		tab_buttons[i].set_pressed_no_signal(i == page)
	var last = page == pages.size() - 1
	next_button.visible = first_time or not last
	next_button.text = ("К ПАМЯТКЕ" if first_time else "ГОТОВО") if last else "ДАЛЕЕ"
	close_button.text = "ПРОПУСТИТЬ" if first_time else "ЗАКРЫТЬ"

func _next() -> void:
	if page == pages.size() - 1:
		close()
	else:
		show_page(page + 1)

func touch() -> bool:
	return game.mobile_mode

# ---------------------------------------------------------------- pages

# One line: a key chip or a touch-button icon, then what it does.
func _row(parent: Control, key: String, text: String) -> void:
	var row = UiKit.hbox(parent, 12)
	if key.begins_with("icon:"):
		var icon = TextureRect.new()
		icon.texture = load(ICONS % key.trim_prefix("icon:"))
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(26, 26)
		icon.modulate = UiKit.ACCENT
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var holder = CenterContainer.new()
		holder.custom_minimum_size = Vector2(64, 30)
		holder.add_child(icon)
		row.add_child(holder)
	else:
		var chip = UiKit.label(row, key, "body")
		chip.add_theme_font_size_override("font_size", 14)
		chip.add_theme_color_override("font_color", UiKit.HIGHLIGHT)
		chip.add_theme_stylebox_override("normal", UiKit.box(UiKit.SURFACE_RAISED, UiKit.LINE, 6, Vector2(8, 3)))
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.custom_minimum_size.x = 64
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var label = UiKit.expand(UiKit.wrap(UiKit.label(row, text, "body")))
	label.add_theme_font_size_override("font_size", 15)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER

func _text(parent: Control, text: String) -> void:
	var label = UiKit.wrap(UiKit.label(parent, text, "body"))
	label.add_theme_font_size_override("font_size", 15)

func _goal(page_box: Control) -> void:
	_text(page_box, "Ты — болельщик на раллийном выезде. Приезжай на спецучасток до открытия, устройся у дороги и смотри гонку.")
	_row(page_box, "icon:table", "Разбей лагерь: стол, стулья и мангал.")
	_row(page_box, "icon:grill", "Разожги мангал, выложи шампуры и съешь шашлык.")
	_row(page_box, "icon:flag", "Посмотри два прохода: в каждом по 10 экипажей.")
	_row(page_box, "icon:tow", "Помогай застрявшим экипажам тросом.")
	_row(page_box, "icon:bag", "В конце верни вещи в багажник и доедь до парка сервиса — на старте или на финише СУ.")

func _controls(page_box: Control) -> void:
	if touch():
		_row(page_box, "Слева", "джойстик: идти или рулить. Коснись левой половины экрана.")
		_row(page_box, "icon:eye", "Правый круг — обзор камеры.")
		_row(page_box, "icon:hand", "Главная кнопка — действие с тем, что перед тобой: сесть, взять, съесть.")
		_row(page_box, "icon:gas", "За рулём: Газ, Тормоз, Назад и Выйти справа.")
		_row(page_box, "icon:bag", "«Лагерь» — стол, стулья, мангал и другие вещи.")
		_row(page_box, "icon:map", "«Карта» — схема СУ и счёт выезда. «Пауза» — меню.")
		return
	var columns = UiKit.hbox(page_box, 24)
	var walk = UiKit.expand(UiKit.vbox(columns, 7))
	UiKit.label(walk, "ПЕШКОМ", "caption")
	_row(walk, "WASD", "идти, мышь — смотреть")
	_row(walk, "Shift", "бег")
	_row(walk, "Space", "прыжок")
	_row(walk, "F", "действие с объектом под прицелом")
	var drive = UiKit.expand(UiKit.vbox(columns, 7))
	UiKit.label(drive, "ЗА РУЛЁМ", "caption")
	_row(drive, "W / S", "газ и назад")
	_row(drive, "A / D", "руль")
	_row(drive, "Space", "тормоз")
	_row(drive, "Home", "вернуть машину на дорогу")
	_row(page_box, "M · R · Esc", "карта · что сейчас на СУ · пауза")

func _camp(page_box: Control) -> void:
	_row(page_box, "icon:bag", "Подойди к багажнику своей машины — он откроется сам.")
	if touch():
		_row(page_box, "icon:table", "«Лагерь» → Стол, Стул, Мангал. Вещь сначала видна призраком: «Повернуть», затем «Поставить».")
	else:
		_row(page_box, "Z · C · G", "стол, стулья, мангал. Вещь сначала видна призраком: Q — повернуть, F — поставить.")
	_row(page_box, "icon:grill", "Мангал: F — разжечь, угли прогорают 20 секунд, потом F — выложить шампуры. Шашлык готов ещё через 35 секунд.")
	_row(page_box, "icon:pot" if touch() else "J · H", "Дрова и казан — костёр и плов на всю компанию.")
	_row(page_box, "icon:flag" if touch() else "V", "Флаг болельщика — можно поставить до трёх.")
	_row(page_box, "icon:berries", "В лесу собирай грибы и ягоды. Мухомор и поганку не ешь.")

func _rally(page_box: Control) -> void:
	_text(page_box, "До открытия СУ — 3 минуты. Машины выезжают из парка сервиса под стартовую арку: сначала полиция открывает СУ, затем три нулевых экипажа и 10 гонщиков. На финише все заезжают в парк сервиса на другом конце. Полиция закрывает СУ, минута перерыва — и обратный проход.")
	_row(page_box, "icon:flag", "Не стой на дороге и на внешней стороне поворота: вылетевшая машина может сбить. Сбитого увозит скорая.")
	_row(page_box, "icon:tow" if touch() else "T", "Застрял экипаж — подойди и держи «Трос». Вместе тянуть быстрее.")
	_row(page_box, "icon:recover" if touch() else "Home", ("Своя машина застряла — «Лагерь» → «Вернуть»." if touch() else "Своя машина застряла — верни её на дорогу."))
