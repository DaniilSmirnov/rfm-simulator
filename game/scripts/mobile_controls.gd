extends Control
class_name RallyMobileControls
const StageRegistry = preload("res://scripts/stage_registry.gd")
const UiKit = preload("res://scripts/ui_kit.gd")
const Loc = preload("res://scripts/loc.gd")
# Touch layout in canvas units (960×540 landscape, inside the safe area).
const EDGE = 24.0
const GAP = 8.0
const TILE = Vector2(72, 64)
const TOP = Vector2(64, 60)
const STICK_FILL = Color("1d2b23aa")
const STICK_LINE = Color("d7b479aa")
const SHORT_LABELS = {"Вернуть коробку в багажник": "Вернуть", "Собрать казан с подставкой": "Убрать казан", "Потушить и собрать костёр": "Убрать костёр", "Сесть в машину": "В машину", "Сесть к другу": "К другу", "Сесть на стул": "На стул", "Встать со стула": "Встать", "Собрать гриб": "Собрать", "Собрать ягоды": "Собрать", "Собрать виноград": "Виноград", "Насадить гриб": "Насадить", "Съесть шашлык": "Шашлык", "Съесть гриб": "Есть гриб", "Выпить пиво": "Пиво", "Потушить и собрать мангал": "Убрать мангал", "Поставить казан на костёр": "На костёр", "Добавить ингредиенты и готовить плов": "Готовить плов", "Съесть плов": "Плов"}

var game: Node
var fingers: Dictionary = {}
var held: Dictionary = {}
var stick = Vector2.ZERO
var buttons: Array[Dictionary] = []
var layout_state: Array = []
var layout_revision = 0
var last_size = Vector2.ZERO
var last_in_car = true
var map_open = false
var gear_open = false
var gear_rect = Rect2()
var styles: Dictionary = {}
var stick_center = Vector2.ZERO
const STICK_RADIUS = 62.0
const LOOK_RADIUS = STICK_RADIUS
var look_center = Vector2.ZERO
var look = Vector2.ZERO
var icons: Dictionary = {}
const ICON_NAMES = {"forward": "gas", "brake": "brake", "back": "reverse", "interact": "hand", "sprint": "run", "jump": "jump", "map": "map", "pause_demo": "pause", "gear": "bag", "recover": "recover", "table": "table", "chairs": "chair", "grill": "grill", "firewood": "wood", "cauldron": "pot", "flag": "flag", "eat_berries": "berries", "tow": "tow", "placement_confirm": "check", "placement_rotate": "rotate", "placement_cancel": "cancel"}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(reset_input)
	for name in ICON_NAMES.values() + ["door", "eye"]:
		icons[name] = load("res://textures/ui/mobile/" + name + ".svg")
	var tile = func(color: Color, border: Color) -> StyleBoxFlat:
		var style = UiKit.box(color, border, 14, Vector2.ZERO)
		style.set_border_width_all(2 if border.a > 0 else 0)
		return style
	styles = {"normal": tile.call(Color("1d2b23d9"), Color("d7b47966")), "primary": tile.call(Color(UiKit.ACCENT, 0.94), Color.TRANSPARENT), "pressed": tile.call(UiKit.ACCENT_HOVER, Color.TRANSPARENT), "drawer": UiKit.box(Color("16221be6"), Color("d7b47966"), 16, Vector2.ZERO)}

func active() -> bool:
	return game != null and game.playing and not game.paused and not game.dead and not game.finished

func world_blocked() -> bool:
	return game.room.is_guest() and game.room.world_paused

func _process(_delta: float) -> void:
	game.fit_mobile_dialogs()
	if not active() or world_blocked() or last_in_car != game.in_car or last_size != size or not landscape():
		reset_input()
	last_in_car = game.in_car
	last_size = size
	_layout()
	game.mobile_sidebar.visible = active() and map_open
	if active() and landscape() and not world_blocked() and not map_open and not gear_open:
		game.view_yaw -= look.x * 2.4 * _delta
		game.view_pitch = clampf(game.view_pitch - look.y * 1.8 * _delta, -1.15, 1.1)
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_EXIT_TREE:
		reset_input()

func landscape() -> bool:
	return size.x >= size.y

func add_button(label: String, action: String, hold: bool, rect: Rect2) -> void:
	buttons.append({"label": Loc.t(label), "action": action, "hold": hold, "rect": rect})

# Tile in the action grid above the right stick: columns count from the right
# edge, rows from the bottom; span 2 makes the wide main action.
func grid_rect(column: int, row: int, span: int = 1) -> Rect2:
	var bottom = look_center.y - LOOK_RADIUS - 14
	var width = TILE.x * span + GAP * (span - 1)
	var right = size.x - EDGE - column * (TILE.x + GAP)
	return Rect2(Vector2(right - width, bottom - TILE.y - row * (TILE.y + GAP)), Vector2(width, TILE.y))

# Short caption for the contextual action ("Сесть в машину" → "В машину").
func action_caption(target: Dictionary) -> String:
	if target.is_empty():
		return Loc.t("Действие")
	var text = str(target.label)
	for long_text in SHORT_LABELS:
		text = text.replace(Loc.t(long_text), Loc.t(SHORT_LABELS[long_text]))
	return text.replace(Loc.t("Собрать "), Loc.t("Убрать "))

func tow_caption() -> String:
	game.injuries.play.injuries = game.injuries
	var owner = str(game.room.player_id) if game.room.connected else "local"
	var person = game.injuries.play.grips.has(owner) or game.injuries.play.nearest(game.walker, game.injuries.local_key()) != ""
	return "Тащить" if not game.in_car and person else "Трос"

func _layout() -> void:
	if not _has_role("stick"):
		stick_center = Vector2(EDGE + 84, size.y - EDGE - 80)
	var target: Dictionary = {}
	if active() and not game.in_car:
		target = game.hud_target if game.hud_target_frame == Engine.get_process_frames() else game.interaction.current()
	var state: Array = [size, active(), landscape(), world_blocked(), game.in_car, game.placement_kind,
		gear_open, game.seated, game.injuries.down, game.beers < 30, game.packing.active(), game.flag_count(),
		game.foraging.can_eat("berries"), game.tow_target != null, game.nearby_tow_target(), target.get("label", ""),
		game.rides.ride, game.rides.hitch, game.rides.hitch_candidate() != "", tow_caption()]
	if state == layout_state:
		return
	layout_state = state
	layout_revision += 1
	buttons.clear()
	gear_rect = Rect2()
	if not active() or not landscape():
		return
	look_center = Vector2(size.x - EDGE - 84, size.y - EDGE - 80)
	var gear: Array = []
	if not world_blocked():
		if game.placement_kind != "":
			var actions = [["Поставить", "placement_confirm"], ["Повернуть", "placement_rotate"], ["Отмена", "placement_cancel"]]
			for i in range(actions.size()):
				add_button(actions[i][0], actions[i][1], false, Rect2(Vector2(size.x / 2 - 148 + i * 100, size.y - EDGE - 168), Vector2(92, TILE.y)))
		elif game.in_car:
			gear = _layout_driving()
		else:
			gear = _layout_walking(target)
		if not gear.is_empty():
			add_button("Лагерь", "gear", false, Rect2(Vector2(size.x - EDGE - 3 * TOP.x - 2 * GAP, EDGE), TOP))
		if gear_open and game.placement_kind == "":
			_layout_drawer(gear)
	add_button("Пауза", "pause_demo", false, Rect2(Vector2(size.x - EDGE - TOP.x, EDGE), TOP))
	add_button("Карта", "map", false, Rect2(Vector2(size.x - EDGE - 2 * TOP.x - GAP, EDGE), TOP))

# Two tall pedals under the right thumb; reverse and exit beside them, the
# tow rope above. A passenger only gets out.
func _layout_driving() -> Array:
	var bottom = look_center.y - LOOK_RADIUS - 14
	var pedal = Vector2(88, 120)
	var side = size.x - EDGE - 2 * pedal.x - 2 * GAP - TILE.x
	if game.rides.riding():
		add_button("Выйти", "interact", false, Rect2(Vector2(side, bottom - 56), Vector2(TILE.x, 56)))
		return []
	add_button("Газ", "forward", true, Rect2(Vector2(size.x - EDGE - pedal.x, bottom - pedal.y), pedal))
	add_button("Тормоз", "brake", true, Rect2(Vector2(size.x - EDGE - 2 * pedal.x - GAP, bottom - pedal.y), pedal))
	add_button("Назад", "back", true, Rect2(Vector2(side, bottom - pedal.y), Vector2(TILE.x, 56)))
	add_button("Выйти", "interact", false, Rect2(Vector2(side, bottom - 56), Vector2(TILE.x, 56)))
	if game.rides.hitch != "" or game.rides.hitch_candidate() != "":
		add_button("Трос", "tow", true, Rect2(Vector2(side, bottom - pedal.y - 56 - GAP), Vector2(TILE.x, 56)))
	return [["Вернуть", "recover"]]

func _layout_walking(target: Dictionary) -> Array:
	add_button(action_caption(target), "interact", false, grid_rect(0, 0, 2))
	if not game.seated and game.beers < 30:
		add_button("Встать" if game.injuries.down else "Прыжок", "jump", false, grid_rect(2, 0))
		add_button("Бег", "sprint", true, grid_rect(2, 1))
	if game.tow_target != null or game.nearby_tow_target() or tow_caption() == "Тащить":
		add_button(tow_caption(), "tow", true, grid_rect(0, 1))
	var gear: Array = []
	if not game.packing.active():
		gear = [["Стол", "table"], ["Стул", "chairs"], ["Мангал", "grill"], ["Дрова", "firewood"], ["Казан", "cauldron"]]
		if game.flag_count() < game.FLAGS_PER_PLAYER:
			gear.append(["Флаг", "flag"])
	if game.foraging.can_eat("berries"):
		gear.append([str(StageRegistry.value(game.stage.variant, "berries")), "eat_berries"])
	return gear

# The camp drawer opens above the status card, between the two sticks.
func _layout_drawer(gear: Array) -> void:
	var tile = Vector2(88, TILE.y)
	var columns = mini(3, gear.size())
	var rows = ceili(gear.size() / 3.0)
	var extent = Vector2(columns * tile.x + (columns - 1) * GAP, rows * tile.y + (rows - 1) * GAP)
	var origin = Vector2(size.x / 2 - extent.x / 2, size.y - EDGE - 100 - extent.y)
	gear_rect = Rect2(origin - Vector2(GAP, GAP), extent + Vector2(GAP, GAP) * 2)
	for i in range(gear.size()):
		add_button(gear[i][0], gear[i][1], false, Rect2(origin + Vector2((i % 3) * (tile.x + GAP), (i / 3) * (tile.y + GAP)), tile))

func _input(event: InputEvent) -> void:
	if not active() or not landscape():
		return
	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled:
			var point = get_global_transform().affine_inverse() * event.position
			if not Rect2(Vector2.ZERO, size).has_point(point):
				return
			touch_begin(event.index, point)
		else:
			touch_end(event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		touch_drag(event.index, get_global_transform().affine_inverse() * event.position, event.relative / scale)
		get_viewport().set_input_as_handled()

func touch_begin(index: int, pos: Vector2) -> void:
	_layout()
	if not active() or not landscape():
		return
	if fingers.has(index):
		touch_end(index)
	if map_open and game.mobile_sidebar.get_global_rect().has_point(get_global_transform() * pos):
		return
	for button in buttons:
		if button.rect.has_point(pos):
			fingers[index] = {"kind": "button", "button": button, "pressed": true}
			if button.hold:
				_hold(button.action)
			elif button.action == "map":
				reset_input()
				map_open = not map_open
				gear_open = false
			elif button.action == "gear":
				reset_input()
				gear_open = not gear_open
				map_open = false
			else:
				var action = InputEventAction.new()
				action.action = button.action
				action.pressed = true
				game._unhandled_input(action)
				if not button.hold:
					gear_open = false
			return
	if gear_open:
		# Drawer gaps/outside taps never turn into camera or movement input.
		if not gear_rect.has_point(pos):
			gear_open = false
		return
	if world_blocked():
		return
	if pos.x < size.x * 0.5 and pos.y > size.y * 0.28 and not _has_role("stick"):
		if pos.distance_to(stick_center) > STICK_RADIUS * 1.6:
			stick_center = Vector2(clampf(pos.x, STICK_RADIUS + 24, size.x * 0.5 - STICK_RADIUS), clampf(pos.y, size.y * 0.28 + STICK_RADIUS, size.y - STICK_RADIUS - 24))
		fingers[index] = {"kind": "stick"}
		_move_stick(pos)
	elif not map_open and pos.distance_to(look_center) <= LOOK_RADIUS and not _has_role("look"):
		fingers[index] = {"kind": "look"}
		_move_look(pos)

func touch_drag(index: int, pos: Vector2, _relative: Vector2) -> void:
	if not active() or not landscape() or world_blocked():
		reset_input()
		return
	if not fingers.has(index):
		return
	var finger: Dictionary = fingers[index]
	if finger.kind == "stick":
		_move_stick(pos)
	elif finger.kind == "look":
		_move_look(pos)
	elif finger.button.hold:
		var inside: bool = finger.button.rect.has_point(pos)
		if inside != finger.pressed:
			_hold(finger.button.action) if inside else _release(finger.button.action)
			finger.pressed = inside

func touch_end(index: int) -> void:
	if not fingers.has(index):
		return
	var finger: Dictionary = fingers[index]
	if finger.kind == "stick":
		stick = Vector2.ZERO
		_set_axis("left", "right", 0)
		_set_axis("forward", "back", 0)
	elif finger.kind == "look":
		look = Vector2.ZERO
	elif finger.kind == "button" and finger.button.hold and finger.pressed:
		_release(finger.button.action)
	fingers.erase(index)

func _has_role(role: String) -> bool:
	for finger in fingers.values():
		if finger.kind == role:
			return true
	return false

func _move_look(pos: Vector2) -> void:
	look = ((pos - look_center) / LOOK_RADIUS).limit_length(1.0)
	if look.length() < 0.12:
		look = Vector2.ZERO

func button_icon(button: Dictionary) -> Texture2D:
	var name: String = ICON_NAMES.get(button.action, "hand")
	if button.action == "interact" and (game.in_car or button.label == Loc.t("В машину") or button.label.begins_with(Loc.t("К другу"))):
		name = "door"
	return icons.get(name)

func _move_stick(pos: Vector2) -> void:
	var delta = (pos - stick_center) / STICK_RADIUS
	# Full circular joystick: steering on X, gas and brake on separate buttons.
	stick = delta.limit_length(1.0)
	if stick.length() < 0.12:
		stick = Vector2.ZERO
	_set_axis("left", "right", stick.x)
	if not game.in_car:
		_set_axis("forward", "back", stick.y)

func _set_axis(negative: String, positive: String, value: float) -> void:
	# Stick axes own one reference; pedal buttons can hold a separate action.
	for action in [negative, positive]:
		if held.get("axis_" + action, false):
			_release(action)
			held.erase("axis_" + action)
	if not is_zero_approx(value):
		var action = negative if value < 0 else positive
		_hold(action, absf(value))
		held["axis_" + action] = true

func _hold(action: String, strength: float = 1.0) -> void:
	held[action] = int(held.get(action, 0)) + 1
	Input.action_press(action, strength)

func _release(action: String) -> void:
	var count = int(held.get(action, 0)) - 1
	if count <= 0:
		held.erase(action)
		Input.action_release(action)
	else:
		held[action] = count

func reset_input() -> void:
	for action in held.keys():
		if not str(action).begins_with("axis_"):
			Input.action_release(action)
	held.clear()
	fingers.clear()
	stick = Vector2.ZERO
	look = Vector2.ZERO

func _draw() -> void:
	if not active():
		return
	var font = ThemeDB.fallback_font
	if not landscape():
		draw_string(font, Vector2(0, size.y / 2), Loc.t("Поверните устройство горизонтально"), HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, UiKit.TEXT)
		return
	if gear_open and gear_rect.has_area():
		draw_style_box(styles.drawer, gear_rect)
	_draw_stick(stick_center, stick, null)
	if not map_open and not gear_open and not world_blocked():
		_draw_stick(look_center, look, icons["eye"])
	for button in buttons:
		_draw_button(button, font)

func _draw_stick(center: Vector2, offset: Vector2, icon: Texture2D) -> void:
	draw_circle(center, STICK_RADIUS, STICK_FILL)
	draw_arc(center, STICK_RADIUS, 0, TAU, 48, STICK_LINE, 2.0, true)
	var knob = center + offset * 46
	draw_circle(knob, 26, UiKit.ACCENT)
	if icon != null:
		draw_texture_rect(icon, Rect2(knob - Vector2(13, 13), Vector2(26, 26)), false, UiKit.ON_ACCENT)

# Every touch button is the same tile: icon above, caption below. The main
# action (gas, contextual action) is amber; a held button lights up.
func _draw_button(button: Dictionary, font: Font) -> void:
	var pressed = false
	for finger in fingers.values():
		if finger.kind == "button" and finger.button.action == button.action and finger.pressed:
			pressed = true
	var emphasized = button.action == "forward" or (button.action == "interact" and not game.in_car)
	var rect: Rect2 = button.rect
	draw_style_box(styles.pressed if pressed else (styles.primary if emphasized else styles.normal), rect)
	var color = UiKit.ON_ACCENT if pressed or emphasized else UiKit.TEXT
	var caption_size = 13 if rect.size.x < 80 else 14
	var icon = button_icon(button)
	var extent = 34.0 if rect.size.y >= 100 else 24.0
	var icon_top = rect.position.y + (rect.size.y - extent - caption_size - 6) / 2
	if icon != null:
		draw_texture_rect(icon, Rect2(Vector2(rect.get_center().x - extent / 2, icon_top), Vector2.ONE * extent), false, color)
	var text = String(button.label)
	var width = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, caption_size).x
	while width > rect.size.x - 8 and caption_size > 10:
		caption_size -= 1
		width = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, caption_size).x
	draw_string(font, Vector2(rect.position.x, icon_top + extent + 4 + font.get_ascent(caption_size)), text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, caption_size, color)
